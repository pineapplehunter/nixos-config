"""Install Pi customizations from Git or a local checkout."""

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
PACKAGE = "pi-customizations"
FILES = (
    "package.json", "package-lock.json", "settings.json", "AGENTS.md",
    "README.md", "LICENSE",
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


def pack(checkout: Path, archive_dir: Path) -> Path:
    with tempfile.TemporaryDirectory(prefix=".pack-", dir=archive_dir) as temp:
        staged = Path(temp)
        for name in FILES:
            if (checkout / name).is_file():
                shutil.copy2(checkout / name, staged / name)
        for name in DIRECTORIES:
            if (checkout / name).is_dir():
                shutil.copytree(checkout / name, staged / name)
        packed = subprocess.run(
            ["npm", "pack", "--json", "--ignore-scripts",
             "--pack-destination", str(archive_dir)],
            cwd=staged, check=True, text=True, stdout=subprocess.PIPE,
        )
    return archive_dir / Path(json.loads(packed.stdout)[0]["filename"]).name


def install(checkout: Path, home: Path, root: Path, pi: str) -> None:
    manifest = read_json(checkout / "package.json")
    if manifest.get("name") != PACKAGE:
        raise ValueError("expected the pi-customizations package")
    declared = read_json(checkout / "settings.json")
    if set(declared) != {"packages"} or not isinstance(
        declared["packages"], list,
    ):
        raise ValueError("repository settings must contain only packages")
    for entry in declared["packages"]:
        if not source(entry).startswith(("npm:", "git:", "https://")):
            raise ValueError("repository packages must use npm or Git sources")
    instructions = (checkout / "AGENTS.md").read_text()
    agent = root.parent
    settings_path = agent / "settings.json"
    if settings_path.is_symlink():
        raise ValueError(f"unexpected settings symlink: {settings_path}")
    legacy = home / ".pi/customizations"
    state_path = root / "managed-packages.json"
    state = read_json(state_path, {})
    if not state_path.exists() and not legacy.is_symlink():
        state = read_json(legacy / "managed-packages.json", {})
    # Validate declarations before asking Pi to install anything.
    desired = declared["packages"]
    previous = state.get("agent", [])
    reconcile(read_json(settings_path, {}), desired, previous)

    archives = root / "archives"
    archives.mkdir(exist_ok=True, mode=0o700)
    archive_dir = Path(tempfile.mkdtemp(prefix="build-", dir=archives))
    environment = {**os.environ, "PI_CODING_AGENT_DIR": str(agent)}
    try:
        archive = pack(checkout, archive_dir)
        package_source = f"npm:{PACKAGE}@{archive.as_uri()}"
        subprocess.run(
            [pi, "install", package_source, "--no-approve"],
            cwd=root, env={**environment, "npm_config_ignore_scripts": "true"},
            check=True,
        )
    except (OSError, ValueError, subprocess.CalledProcessError):
        shutil.rmtree(archive_dir)
        raise

    settings = read_json(settings_path)
    settings["packages"] = [
        entry for entry in settings["packages"]
        if Path(os.path.abspath(agent / Path(source(entry)).expanduser()))
        != legacy / "package"
    ]
    settings, state["agent"] = reconcile(settings, desired, previous)
    write_json(settings_path, settings)
    write_json(state_path, state)
    write_file(agent / "AGENTS.md", instructions)
    subprocess.run(
        [pi, "update", "--extensions", "--no-approve"],
        cwd=root, env=environment, check=True,
    )

    # Only delete old snapshots after the managed installation succeeds.
    if not legacy.is_symlink():
        for path in (legacy / "package", legacy / "previous"):
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
    # Pi needs the current archive for reinstalls, but not older builds.
    for path in archives.glob("build-*"):
        if path != archive_dir and path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
    print("Pi packages updated. Reload or restart Pi to load new resources.")


def main() -> int:
    cli = argparse.ArgumentParser(prog="pi-update", description=__doc__)
    cli.add_argument(
        "--local", type=Path,
        help="install a package built from this working tree instead of Git",
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
    root = home / ".pi/agent/pi-update"
    if root.is_symlink():
        cli.error(f"expected a real installation directory: {root}")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    pi = os.environ.get("PI_UPDATE_PI", "pi")
    with (root / "update.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            if args.local is not None:
                checkout = args.local.expanduser().resolve(strict=True)
                if any(checkout.is_relative_to(path) for path in (
                    root.parent, home / ".pi/customizations",
                )):
                    raise ValueError("--local must be a source checkout")
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
