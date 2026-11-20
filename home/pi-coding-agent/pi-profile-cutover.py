"""Plan (and optionally stage) a Work/Auto to canonical Pi profile merge."""

import argparse
from collections import Counter, defaultdict
from contextlib import ExitStack, contextmanager
from dataclasses import dataclass
import errno
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile


PROFILES = ("agent", "agent-work", "agent-auto")
LIMIT = 1024 * 1024
MISSING = object()


def choice(*choices):
    return lambda value: type(value) is str and value in choices


def boolean(value):
    return type(value) is bool


def unsigned(value):
    return type(value) is int and 0 <= value <= (1 << 53) - 1


# Values must be of the documented type; refuse free-form strings and lists.
SAFE_SETTINGS = {
    "defaultThinkingLevel": choice("off", "minimal", "low", "medium", "high", "xhigh", "max"),
    "steeringMode": choice("all", "one-at-a-time"),
    "followUpMode": choice("all", "one-at-a-time"),
    "doubleEscapeAction": choice("tree", "fork", "none"),
    "treeFilterMode": choice("default", "no-tools", "no-tool-results", "user-only", "labeled-only", "all"),
    "theme": choice("system", "light", "dark"),
    "quietStartup": lambda value: boolean(value) or (type(value) is str and value == "header"),
    "hideThinkingBlock": boolean,
    "showCacheMissNotices": boolean,
    "tuiMode": choice("regular", "fullscreen"),
    "fullscreenExitOutput": choice("transcript", "resume-hint", "hidden"),
    "fullscreenScrollbar": choice("auto", "always", "hidden"),
    "editorPaddingX": unsigned,
    "outputPad": unsigned,
    "autocompleteMaxVisible": unsigned,
    "collapseChangelog": boolean,
    "compaction": {"enabled": boolean, "reserveTokens": unsigned, "keepRecentTokens": unsigned},
    "branchSummary": {"reserveTokens": unsigned, "skipPrompt": boolean},
    "terminal": {
        "showImages": boolean,
        "imageWidthCells": unsigned,
        "clearOnShrink": boolean,
        "showTerminalProgress": boolean,
        "hyperlinks": boolean,
        "trueColor": boolean,
    },
    "images": {"autoResize": boolean, "blockImages": boolean},
    "markdown": {"mermaid": choice("off", "final", "streaming")},
}


class UnsafeEntry(Exception):
    pass


@contextmanager
def directory(parent, name):
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY, dir_fd=parent)
    except OSError as e:
        if e.errno in {errno.ELOOP, errno.ENOTDIR}:
            raise UnsafeEntry from None
        raise
    try:
        if os.fstat(fd).st_uid != os.getuid():
            raise UnsafeEntry
        yield fd
    finally:
        os.close(fd)


@contextmanager
def regular(parent, name):
    def check(info):
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid():
            raise UnsafeEntry

    check(os.stat(name, dir_fd=parent, follow_symlinks=False))
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    with os.fdopen(fd, "rb") as file:
        info = os.fstat(file.fileno())
        check(info)
        yield file, info


def reject_constant(_):
    raise ValueError  # NaN/Infinity are not JSON.


def read_settings(parent, profile):
    try:
        with regular(parent, "settings.json") as (file, _):
            data = file.read(LIMIT + 1)
        if len(data) > LIMIT:
            raise ValueError
        settings = json.loads(data, parse_constant=reject_constant)
        if not isinstance(settings, dict):
            raise ValueError
        return settings
    except FileNotFoundError:
        return {}
    except (UnsafeEntry, ValueError, RecursionError):
        print(f"{profile}: settings skipped (link, unsafe file or invalid JSON).")
        return None


def merge_settings(schema, canonical, old, prefix=""):
    additions = {}
    for key, spec in schema.items():
        label = prefix + key
        present = canonical.get(key, MISSING)
        found = [p.get(key, MISSING) for p in old]
        if isinstance(spec, dict):
            sources = [obj if isinstance(obj, dict) else {} for obj in found]
            if present is MISSING or isinstance(present, dict):
                nested = merge_settings(spec, {} if present is MISSING else present, sources, label + ".")
                if nested:
                    additions[key] = nested
            elif any(sources):
                print(f"Settings conflict: {label}; canonical kept.")
        else:
            values = [value for value in found if spec(value)]
            if not values:
                continue
            if present is not MISSING:
                if any(type(present) is not type(value) or present != value for value in values):
                    print(f"Settings conflict: {label}; canonical kept.")
            elif any(type(values[0]) is not type(value) or values[0] != value for value in values[1:]):
                print(f"Settings conflict: {label}; Work and Auto disagree, not added.")
            else:
                additions[key] = values[0]
                print(f"Settings addition: {label}.")
    return additions


@dataclass(frozen=True)
class Session:
    profile: str
    path: Path
    id: str
    digest: str
    mtime_ns: int


def fingerprint(file, dest=None):
    digest = hashlib.sha256()
    for block in iter(lambda: file.read(LIMIT), b""):
        digest.update(block)
        if dest is not None:
            dest.write(block)
    return digest.hexdigest()


def scan_sessions(parent, profile):
    sessions = []
    skipped = 0

    def scan_files(fd, group):
        nonlocal skipped
        for name in sorted(os.listdir(fd)):
            if not name.endswith(".jsonl") or name.startswith("."):
                continue
            try:
                with regular(fd, name) as (file, info):
                    line = file.readline(LIMIT + 1)
                    header = json.loads(line) if len(line) <= LIMIT else None
                    if (not isinstance(header, dict) or header.get("type") != "session"
                            or not isinstance(header.get("id"), str) or not header["id"]
                            or not isinstance(header.get("cwd"), str) or not header["cwd"]):
                        raise ValueError
                    file.seek(0)
                    sessions.append(Session(profile, group / name, header["id"],
                                            fingerprint(file), info.st_mtime_ns))
            except (UnsafeEntry, ValueError, RecursionError):
                skipped += 1

    try:
        with directory(parent, "sessions") as fd:
            scan_files(fd, Path())  # Explicit --session-dir / wrapper's env override.
            for name in sorted(os.listdir(fd)):
                if name.startswith("--") and name.endswith("--") and len(name) >= 4:
                    try:
                        with directory(fd, name) as group:
                            scan_files(group, Path(name))
                    except UnsafeEntry:
                        skipped += 1
    except FileNotFoundError:
        # Only a missing sessions root is ordinary. A tree changing mid-scan
        # should not be treated as empty.
        try:
            os.stat("sessions", dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise
    except UnsafeEntry:
        skipped += 1
    if skipped:
        print(f"{profile}: {skipped} unsafe/invalid session entries or directories skipped.")
    return sessions, skipped


def merge_sessions(canonical, old):
    ids = defaultdict(set)
    paths = {session.path for session in canonical}
    for session in canonical:
        ids[session.id].add(session.digest)
    variants = defaultdict(list)
    candidate_ids = defaultdict(set)
    for session in old:
        variants[session.id].append(session)
        candidate_ids[session.path].add(session.id)

    copies = []
    counts = Counter()
    for id_, group in variants.items():
        if id_ in ids:
            for session in group:
                counts["already canonical" if session.digest in ids[id_] else "canonical ID conflict"] += 1
        elif len({session.digest for session in group}) > 1:
            counts["Work/Auto ID conflict"] += len(group)
        else:
            available = [s for s in group if s.path not in paths and len(candidate_ids[s.path]) == 1]
            if available:
                copies.append(available[0])  # Work and Auto are byte-identical here.
                counts["duplicate legacy copies"] += len(available) - 1
            counts["session path conflict"] += len(group) - len(available)
    for reason, count in sorted(counts.items()):
        if count:
            print(f"Sessions: {count} {reason}.")
    return copies


def private_file(path, flags):
    return os.open(path, flags, 0o600)


def stage(home, pi, additions, sessions):
    root = Path(tempfile.mkdtemp(prefix="pi-cutover-", dir=home))
    (root / "sessions").mkdir(mode=0o700)
    for session in sessions:
        target = root / "sessions" / session.path
        target.parent.mkdir(exist_ok=True, mode=0o700)
        with ExitStack() as stack:
            source = stack.enter_context(directory(pi, session.profile))
            source = stack.enter_context(directory(source, "sessions"))
            if len(session.path.parts) == 2:
                source = stack.enter_context(directory(source, session.path.parts[0]))
            file, _ = stack.enter_context(regular(source, session.path.name))
            with open(target, "xb", opener=private_file) as dest:
                if fingerprint(file, dest) != session.digest:
                    raise ValueError
        os.utime(target, ns=(session.mtime_ns, session.mtime_ns))
    with open(root / "settings-additions.json", "x", encoding="utf-8", opener=private_file) as dest:
        json.dump(additions, dest, indent=2)
        dest.write("\n")
    # Only use a bundle whose name was printed by a successful invocation.
    return root.name


def migrate(home, stage_changes=False):
    settings = {}
    sessions = {}
    skipped_canonical = False
    with directory(None, home / ".pi") as pi:
        # Most installs already share the canonical session directory. If no
        # legacy files are candidates, don't read canonical transcripts.
        for profile in (*PROFILES[1:], PROFILES[0]):
            with ExitStack() as stack:
                try:
                    parent = stack.enter_context(directory(pi, profile))
                except FileNotFoundError:
                    settings[profile], sessions[profile] = {}, []
                    continue
                except UnsafeEntry:
                    if profile == PROFILES[0]:
                        raise
                    print(f"{profile}: unsafe profile directory skipped.")
                    settings[profile], sessions[profile] = {}, []
                    continue
                settings[profile] = read_settings(parent, profile)
                if profile != PROFILES[0] or any(sessions.values()):
                    sessions[profile], skipped = scan_sessions(parent, profile)
                    if profile == PROFILES[0]:
                        skipped_canonical = bool(skipped)
                else:
                    sessions[profile] = []

        if settings["agent"] is None:
            print("Settings: no additions planned (canonical settings cannot be compared safely).")
            additions = {}
        else:
            additions = merge_settings(SAFE_SETTINGS, settings["agent"],
                                       [settings[p] or {} for p in PROFILES[1:]])
        if skipped_canonical:
            print("Sessions: no copies planned (canonical sessions cannot all be compared safely).")
            copies = []
        else:
            copies = merge_sessions(sessions["agent"], sessions["agent-work"] + sessions["agent-auto"])
        print(f"Sessions: {len(copies)} to copy. No profiles changed.")
        if stage_changes and (copies or additions):
            print(f"Private staging bundle under home: {stage(home, pi, additions, copies)}")
        elif stage_changes:
            print("Nothing to stage.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, help="home root (default: current host home)")
    parser.add_argument("--stage", action="store_true", help="write a private review bundle, not into .pi")
    args = parser.parse_args()
    if (os.environ.get("PI_WRAPPER_PROFILE") or os.environ.get("PI_CODING_AGENT")
            or Path("/.flatpak-info").exists() or Path("/run/pi-subagent").exists()):
        parser.exit(1, "Run the profile cutover utility in a host terminal, outside Pi.\n")
    os.umask(0o077)
    try:
        migrate((args.home or Path.home()).resolve(strict=True), args.stage)
    except (OSError, UnsafeEntry, ValueError):
        # Do not echo exceptions: paths and parser diagnostics may contain private data.
        parser.exit(1, "Cutover aborted: missing, inaccessible, unsafe or changing inputs. "
                       "No profiles changed. Do not use partial staging bundles.\n")


if __name__ == "__main__":
    main()
