#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
swift test
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT_DIR/script" -p 'test_*.py'
for script in script/*.sh; do bash -n "$script"; done
# The settings panel sources are mirrored by hand in cc:. Neither repository depends on the other,
# so this only compares the copies when a cc: checkout sits beside this one.
MIRROR="$ROOT_DIR/../cc/Sources/CC/Shared"
if [[ -d "$MIRROR" ]] && ! diff -r "$ROOT_DIR/Sources/UsageRings/Shared" "$MIRROR"; then
  echo "Sources/UsageRings/Shared differs from cc:'s Sources/CC/Shared. Apply the change to both." >&2
  exit 1
fi
