"""Copy Pi customizations from Git or a local checkout and update packages."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


DEFAULT_REPOSITORY = "https://github.com/pineapplehunter/pi-customizations"
FILES = (
    "package.json", "settings.json", "AGENTS.md", "README.md", "LICENSE",
    "NOTICE", "CREDITS.md", "upstream.json",
)
DIRECTORIES = ("extensions", "skills", "references", "prompts", "themes")


def read_json(path: Path, default=None):
    if not path.exists():
        if default is not None:
            return default
        raise ValueError(f"missing required file: {path}")
    return json.loads(path.read_text())


def write_file(path: Path, text: str) -> None:
    """Replace files instead of following Home Manager instruction links."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent,
    )
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(text)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def write_json(path: Path, value) -> None:
    write_file(path, json.dumps(value, indent=2) + "\n")


def source(entry) -> str:
    value = entry.get("source") if isinstance(entry, dict) else entry
    if not isinstance(value, str) or not value:
        raise ValueError("package entries need a nonempty source string")
    return value


def package_key(entry) -> str:
    value = source(entry)
    if value.startswith("npm:"):
        return re.match(r"npm:(?:@[^/]+/)?[^@]+", value).group()
    if value.startswith(("https://", "git:")):
        return value.split("@", 1)[0].removesuffix(".git")
    return value


def legacy_package(entry) -> bool:
    """Retire only this module's two old Nix-store resource packages."""
    value = source(entry)
    return value.startswith("/nix/store/") and Path(value).name.endswith(
        ("-pineapplehunter", "-anthropic-skills")
    )


def reconcile(
    settings: dict, desired: list, previous: list,
) -> tuple[dict, list]:
    existing = settings.get("packages", [])
    if not isinstance(existing, list):
        raise ValueError("settings packages must be a list")
    # The old activation replaced the entire package list. Its resource
    # paths identify that migration; adopt matching declarations only then.
    migrating = any(legacy_package(entry) for entry in existing)
    # Otherwise keep pre-existing packages and manual filters/version edits.
    retained = [
        entry for entry in existing
        if entry not in previous and not legacy_package(entry)
        and not (migrating and entry in desired)
    ]
    owned = []
    for entry in desired:
        match = next(
            (old for old in retained
             if package_key(old) == package_key(entry)),
            None,
        )
        if match is None:
            retained.append(entry)
            owned.append(entry)
    return {**settings, "packages": retained}, owned


def profile_settings(home: Path) -> list[Path]:
    personal = home / ".pi/agent/settings.json"
    paths = [personal]
    for profile in ("agent-work", "agent-auto"):
        candidate = home / ".pi" / profile / "settings.json"
        if candidate.exists() or candidate.is_symlink():
            if candidate.is_symlink() and candidate.resolve() == personal:
                continue  # Shared settings already follow personal.
            paths.append(candidate)
    for path in paths:
        if path.is_symlink():
            raise ValueError(f"unexpected settings symlink: {path}")
    return paths


def install(checkout: Path, home: Path, root: Path, pi: str) -> None:
    manifest = read_json(checkout / "package.json")
    if manifest.get("name") != "pi-customizations":
        raise ValueError("expected the pi-customizations package")
    if manifest.get("dependencies"):
        raise ValueError("snapshot extensions must be dependency-free")
    declared = read_json(checkout / "settings.json")
    if set(declared) != {"packages"} or not isinstance(
        declared["packages"], list,
    ):
        raise ValueError("repository settings must contain only packages")
    for entry in declared["packages"]:
        if not source(entry).startswith(("npm:", "git:", "https://")):
            raise ValueError("repository packages must use npm or Git sources")
    instructions = (checkout / "AGENTS.md").read_text()
    snapshot = root / "package"
    previous_snapshot = root / "previous"
    state_path = root / "managed-packages.json"
    state = read_json(state_path, {})
    desired = [*declared["packages"], str(snapshot)]
    updates = []
    for path in profile_settings(home):
        settings = read_json(path, {})
        profile = path.parent.name
        updated, owned = reconcile(settings, desired, state.get(profile, []))
        updates.append((path, updated))
        state[profile] = owned

    for path in (snapshot, previous_snapshot):
        if path.is_symlink():
            raise ValueError(f"refusing to replace a snapshot symlink: {path}")
    with tempfile.TemporaryDirectory(prefix=".stage-", dir=root) as staging:
        staged = Path(staging) / "package"
        staged.mkdir()
        for name in FILES:
            if (checkout / name).is_file():
                shutil.copy2(checkout / name, staged / name)
        for name in DIRECTORIES:
            if (checkout / name).is_dir():
                shutil.copytree(checkout / name, staged / name)
        if previous_snapshot.exists():
            shutil.rmtree(previous_snapshot)
        if snapshot.exists():
            snapshot.rename(previous_snapshot)
        staged.rename(snapshot)

    for path, settings in updates:
        write_json(path, settings)
    write_json(state_path, state)
    write_file(home / ".pi/agent/AGENTS.md", instructions)
    print(f"Installed copied resources at {snapshot}", flush=True)
    # Never use the sandbox wrapper or update Pi itself. Do not load project
    # settings, and ignore whichever profile the caller happens to be using.
    for path, _settings in updates:
        environment = {**os.environ, "PI_CODING_AGENT_DIR": str(path.parent)}
        subprocess.run(
            [pi, "update", "--extensions", "--no-approve"],
            cwd=root, env=environment, check=True,
        )
    print("Pi packages updated. Reload or restart Pi to load new resources.")


def main() -> int:
    cli = argparse.ArgumentParser(prog="pi-update", description=__doc__)
    cli.add_argument(
        "--local", type=Path,
        help="copy from this checkout; still update external packages",
    )
    cli.add_argument(
        "--repo",
        default=os.environ.get("PI_CUSTOMIZATIONS_REPO", DEFAULT_REPOSITORY),
    )
    cli.add_argument(
        "--branch", default=os.environ.get("PI_CUSTOMIZATIONS_BRANCH", "main"),
    )
    args = cli.parse_args()
    home = Path.home()
    root = home / ".pi/customizations"
    if root.is_symlink():
        cli.error(f"expected a real installation directory: {root}")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    pi = os.environ.get("PI_UPDATE_PI", "pi")
    with (root / "update.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            if args.local is not None:
                checkout = args.local.expanduser().resolve(strict=True)
                if checkout == root or root in checkout.parents:
                    raise ValueError("--local must not be an installed copy")
                install(checkout, home, root, pi)
            else:
                with tempfile.TemporaryDirectory(prefix="pi-custom-") as tmp:
                    checkout = Path(tmp) / "checkout"
                    subprocess.run(
                        ["git", "clone", "--depth", "1", "--single-branch",
                         "--branch", args.branch, "--", args.repo,
                         str(checkout)],
                        check=True,
                    )
                    install(checkout, home, root, pi)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(f"pi-update: {error}", file=sys.stderr)
            print(
                "External updates are not transactional; "
                "fix the error and retry pi-update.", file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
