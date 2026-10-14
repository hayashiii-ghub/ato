#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build.sh"
DESTINATION="$HOME/Applications/Usage Rings.app"
if [[ -e "$DESTINATION" ]]; then
  test "$(plutil -extract CFBundleIdentifier raw "$DESTINATION/Contents/Info.plist")" = "work.hayashigoto.UsageRings"
fi
pkill -x UsageRings >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$DESTINATION"
ditto "$ROOT_DIR/dist/Usage Rings.app" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
# WidgetKit can keep the previous executable alive after the app is replaced.
# Stop only this installation's widget after copying, so its next launch uses
# the new bundle and its timeline passes WidgetKit's bundle-version validation.
WIDGET_EXECUTABLE="$DESTINATION/Contents/PlugIns/UsageRingsWidget.appex/Contents/MacOS/UsageRingsWidget"
while IFS= read -r widget_pid; do
  if [[ "$(ps -p "$widget_pid" -o comm=)" == "$WIDGET_EXECUTABLE" ]]; then
    kill -TERM "$widget_pid" 2>/dev/null || true
  fi
done < <(pgrep -x UsageRingsWidget || true)
python3 "$ROOT_DIR/script/claude-statusline-setup.py" --helper "$DESTINATION/Contents/Helpers/UsageRingsStatusline"
/usr/bin/open "$DESTINATION"
echo "Installed: $DESTINATION"
