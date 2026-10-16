#!/usr/bin/env python3
"""Install/remove the Usage Rings status line without replacing other customizations."""
import argparse
import json
import os
from pathlib import Path
import shlex
import tempfile


def configure(settings, helper, uninstall=False, skip_existing=False):
    command = shlex.quote(str(helper))
    current = settings.get("statusLine")
    owned = isinstance(current, dict) and current.get("command") == command
    result = dict(settings)
    if uninstall:
        if owned:
            result.pop("statusLine", None)
        return result
    if current is not None and not owned:
        if skip_existing:
            return result
        raise ValueError("Existing Claude status line preserved. Compose it with Usage Rings before connecting.")
    result["statusLine"] = {**(current or {}), "type": "command", "command": command}
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--skip-existing", action="store_true", help="Leave a custom status line unchanged.")
    parser.add_argument("--check", action="store_true", help="Check settings without writing or requiring an installed helper.")
    parser.add_argument("--helper", type=Path, default=Path.home()/"Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline")
    args = parser.parse_args()
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home()/".claude")))
    path = config/"settings.json"
    try:
        settings = json.loads(path.read_text()) if path.exists() else {}
    except (OSError, ValueError):
        raise SystemExit("Could not read valid Claude settings; nothing changed.") from None
    if not isinstance(settings, dict):
        raise SystemExit("Claude settings must be an object; nothing changed.")
    try:
        updated = configure(settings, args.helper, args.uninstall, args.skip_existing)
    except ValueError as error:
        raise SystemExit(str(error))
    if args.check:
        print("Claude status line settings checked.")
        return
    if not args.uninstall and not args.helper.is_file():
        raise SystemExit("Install Usage Rings before connecting Claude.")
    try:
        if updated != settings:
            config.mkdir(parents=True, exist_ok=True)
            descriptor, temp = tempfile.mkstemp(prefix=".usage-rings-", dir=config)
            try:
                with os.fdopen(descriptor, "w") as file:
                    json.dump(updated, file, ensure_ascii=False, indent=2)
                    file.write("\n")
                os.replace(temp, path)
            finally:
                if os.path.exists(temp):
                    os.unlink(temp)
    except OSError:
        raise SystemExit("Could not update Claude settings.") from None
    if args.skip_existing and updated == settings:
        print("Claude status line unchanged.")
    else:
        print("Claude status line disconnected." if args.uninstall else "Claude status line connected.")


if __name__ == "__main__":
    main()
