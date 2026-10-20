#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build.sh"
DESTINATION="$HOME/Applications/Usage Rings.app"
if [[ -e "$DESTINATION" ]]; then
  test "$(plutil -extract CFBundleIdentifier raw "$DESTINATION/Contents/Info.plist")" = "work.hayashigoto.UsageRings"
  python3 - "$DESTINATION/Contents/Info.plist" "$ROOT_DIR/dist/Usage Rings.app/Contents/Info.plist" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

def version(path):
    metadata = plistlib.loads(Path(path).read_bytes())
    if not isinstance(metadata, dict):
        raise ValueError()
    release = metadata.get("CFBundleShortVersionString", "")
    build = str(metadata.get("CFBundleVersion", ""))
    if not isinstance(release, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", release) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError()
    return tuple(map(int, release.split("."))), int(build)

try:
    installed, incoming = map(version, sys.argv[1:])
except (OSError, ValueError, plistlib.InvalidFileException):
    raise SystemExit("Cannot compare app versions; nothing changed.")
if incoming[0] < installed[0]:
    raise SystemExit("The new app version must not be older than the installed version; nothing changed.")
# Sparkle and WidgetKit use build numbers to distinguish updates.
if incoming[1] <= installed[1]:
    raise SystemExit("The new app build must be greater than the installed build; nothing changed.")
PY
fi
APPLICATIONS_DIR="$(dirname "$DESTINATION")"
mkdir -p "$APPLICATIONS_DIR"
INSTALL_WORK_DIR="$(mktemp -d "$APPLICATIONS_DIR/.usage-rings-XXXXXX")"
trap 'rm -rf "$INSTALL_WORK_DIR"' EXIT
STAGED_APP="$INSTALL_WORK_DIR/Usage Rings.app"
ditto "$ROOT_DIR/dist/Usage Rings.app" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
CLAUDE_SETUP=("$ROOT_DIR/script/claude-statusline-setup.py" --helper "$DESTINATION/Contents/Helpers/UsageRingsStatusline" --skip-existing)
python3 "${CLAUDE_SETUP[@]}" --check
GEMINI_SETUP=("$ROOT_DIR/script/antigravity-statusline-setup.py" --helper "$DESTINATION/Contents/Helpers/UsageRingsStatusline" --skip-existing)
python3 "${GEMINI_SETUP[@]}" --check
pkill -x UsageRings >/dev/null 2>&1 || true
rm -rf "$DESTINATION"
mv "$STAGED_APP" "$DESTINATION"
# WidgetKit can keep the previous executable alive after the app is replaced.
# Stop only this installation's widget after replacement, so its next launch uses
# the new bundle and its timeline passes WidgetKit's bundle-version validation.
WIDGET_EXECUTABLE="$DESTINATION/Contents/PlugIns/UsageRingsWidget.appex/Contents/MacOS/UsageRingsWidget"
while IFS= read -r widget_pid; do
  if [[ "$(ps -p "$widget_pid" -o comm=)" == "$WIDGET_EXECUTABLE" ]]; then
    kill -TERM "$widget_pid" 2>/dev/null || true
  fi
done < <(pgrep -x UsageRingsWidget || true)
CLAUDE_SETUP_STATUS=0
python3 "${CLAUDE_SETUP[@]}" || CLAUDE_SETUP_STATUS=$?
GEMINI_SETUP_STATUS=0
python3 "${GEMINI_SETUP[@]}" || GEMINI_SETUP_STATUS=$?
/usr/bin/open "$DESTINATION" --args -SUEnableAutomaticChecks NO
echo "Installed: $DESTINATION"
if [[ "$CLAUDE_SETUP_STATUS" != 0 ]]; then
  echo "ato? opened, but its Claude status line could not be configured." >&2
fi
if [[ "$GEMINI_SETUP_STATUS" != 0 ]]; then
  echo "ato? opened, but its Antigravity status line could not be configured." >&2
fi
if [[ "$CLAUDE_SETUP_STATUS" != 0 ]]; then exit "$CLAUDE_SETUP_STATUS"; fi
exit "$GEMINI_SETUP_STATUS"
