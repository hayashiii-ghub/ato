#!/usr/bin/env python3
"""Connect ato? to Antigravity's status line while preserving custom settings."""
import argparse
import json
import os
from pathlib import Path
import shlex
import tempfile


def configure(settings, helper, uninstall=False, skip_existing=False):
    command = shlex.quote(str(helper)) + " --provider gemini"
    current = settings.get("statusLine")
    owned = isinstance(current, dict) and current.get("command") == command
    result = dict(settings)
    if uninstall:
        if owned:
            result.pop("statusLine", None)
        return result
    if "statusLine" in settings and not owned:
        if skip_existing:
            return result
        raise ValueError("Existing Antigravity status line preserved. Compose it with ato? before connecting.")
    if not owned:
        result["statusLine"] = {"type": "command", "command": command, "stack_with_default": True}
    return result


def make_config_directory(config):
    missing = []
    current = config
    while not current.exists():
        missing.append(current)
        current = current.parent
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)


def write_settings(path, original, updated):
    make_config_directory(path.parent)
    descriptor, temporary = tempfile.mkstemp(prefix=".usage-rings-", dir=path.parent)
    backup = None
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            json.dump(updated, file, ensure_ascii=False, indent=2)
            file.write("\n")
        current = path.read_bytes() if path.exists() else None
        if current != original:
            raise OSError("Settings changed while connecting.")
        if original is not None:
            descriptor, backup = tempfile.mkstemp(prefix=path.name + ".ato-backup-", dir=path.parent)
            with os.fdopen(descriptor, "wb") as file:
                file.write(original)
        os.replace(temporary, path)
    except OSError:
        if backup is not None and os.path.exists(backup):
            os.unlink(backup)
        raise
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return backup


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--skip-existing", action="store_true", help="Leave a custom status line unchanged.")
    parser.add_argument("--check", action="store_true", help="Check settings without writing or requiring an installed helper.")
    parser.add_argument("--helper", type=Path, default=Path.home()/"Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline")
    parser.add_argument("--settings", type=Path, default=Path.home()/".gemini/antigravity-cli/settings.json")
    args = parser.parse_args()
    path = args.settings
    try:
        if path.is_symlink():
            raise OSError("Settings is a symbolic link.")
        original = path.read_bytes() if path.exists() else None
        settings = json.loads(original) if original is not None else {}
    except (OSError, ValueError):
        raise SystemExit("Could not read valid Antigravity settings; nothing changed.") from None
    if not isinstance(settings, dict):
        raise SystemExit("Antigravity settings must be an object; nothing changed.")
    try:
        updated = configure(settings, args.helper, args.uninstall, args.skip_existing)
    except ValueError as error:
        raise SystemExit(str(error))
    if args.check:
        print("Antigravity status line settings checked.")
        return
    if updated == settings:
        print("Antigravity status line unchanged.")
        return
    if not args.uninstall and not args.helper.is_file():
        raise SystemExit("Install ato? before connecting Antigravity.")
    try:
        backup = write_settings(path, original, updated)
    except OSError:
        raise SystemExit("Could not update Antigravity settings; nothing changed.") from None
    print("Antigravity status line disconnected." if args.uninstall else "Antigravity status line connected.")
    if backup is not None:
        print("Previous settings backed up to: " + str(backup))


if __name__ == "__main__":
    main()
