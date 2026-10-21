#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:?Usage: icon.sh output.icns}"
ICON_WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK_DIR"' EXIT
COMPILED_RESOURCES="$ICON_WORK_DIR/Resources"
PARTIAL_INFO="$ICON_WORK_DIR/AppIcon-info.plist"
mkdir -p "$COMPILED_RESOURCES" "$(dirname "$OUTPUT")"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT")" && pwd)"
OUTPUT="$OUTPUT_DIR/$(basename "$OUTPUT")"
xcrun actool "$ROOT_DIR/Assets/AppIcon.icon" \
  --compile "$COMPILED_RESOURCES" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --standalone-icon-behavior all \
  --output-partial-info-plist "$PARTIAL_INFO" \
  --output-format human-readable-text
python3 - "$PARTIAL_INFO" "$COMPILED_RESOURCES" <<'PY'
from pathlib import Path
import plistlib
import sys

try:
    metadata = plistlib.loads(Path(sys.argv[1]).read_bytes())
    resources = Path(sys.argv[2])
    if not isinstance(metadata, dict) or metadata.get("CFBundleIconName") != "AppIcon" or metadata.get("CFBundleIconFile") not in ("AppIcon", "AppIcon.icns"):
        raise ValueError()
    for filename in ("Assets.car", "AppIcon.icns"):
        path = resources / filename
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError()
except (OSError, ValueError, plistlib.InvalidFileException):
    raise SystemExit("App icon compilation did not produce valid AppIcon metadata, Assets.car, and AppIcon.icns.") from None
PY
cp "$COMPILED_RESOURCES/Assets.car" "$OUTPUT_DIR/Assets.car"
cp "$COMPILED_RESOURCES/AppIcon.icns" "$OUTPUT"
