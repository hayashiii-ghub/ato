#!/usr/bin/env bash

usage_load_sparkle_configuration() {
  local root_dir="$1"
  local configuration="$2"
  local values
  values="$(python3 - "$root_dir/script/sparkle-config.json" "$configuration" <<'PY'
import base64
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

try:
    config = json.loads(Path(sys.argv[1]).read_text())
    feed = os.environ.get("SPARKLE_FEED_URL", config["feed_url"])
    key = os.environ.get("SPARKLE_PUBLIC_ED_KEY", config["public_ed_key"])
    account = config["keychain_account"]
    url = urlsplit(feed)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
        raise ValueError("Sparkle feed must be an HTTPS URL without credentials or a fragment.")
    if not isinstance(account, str) or not account or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for c in account):
        raise ValueError("Sparkle keychain account is invalid.")
    if key:
        if len(base64.b64decode(key, validate=True)) != 32:
            raise ValueError("Sparkle public key must be a base64 Ed25519 public key.")
    elif sys.argv[2] == "release":
        raise ValueError("Sparkle public key is not configured; release builds are disabled.")
    print(feed)
    print(key)
except (OSError, KeyError, TypeError, ValueError) as error:
    print(f"Build metadata: {error}", file=sys.stderr)
    sys.exit(1)
PY
)" || return 1
  SPARKLE_FEED_URL="$(printf '%s\n' "$values" | sed -n '1p')"
  SPARKLE_PUBLIC_ED_KEY="$(printf '%s\n' "$values" | sed -n '2p')"
}

usage_sparkle_framework_path() {
  local framework="$1/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
  [[ -d "$framework" ]] || { echo "Sparkle.framework is missing; resolve the package dependency first." >&2; return 1; }
  printf '%s\n' "$framework"
}

usage_embed_sparkle() {
  local root_dir="$1"
  local app="$2"
  local binary="$app/Contents/MacOS/UsageRings"
  local source
  source="$(usage_sparkle_framework_path "$root_dir")" || return 1
  mkdir -p "$app/Contents/Frameworks"
  ditto "$source" "$app/Contents/Frameworks/Sparkle.framework"
  if ! otool -l "$binary" | grep -Fq '@executable_path/../Frameworks'; then
    codesign --remove-signature "$binary" >/dev/null 2>&1 || true
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$binary"
  fi
}

usage_sign_sparkle() {
  local app="$1"
  local framework="$app/Contents/Frameworks/Sparkle.framework"
  local version="$framework/Versions/Current"
  local component
  [[ -d "$framework" ]] || { echo "Embedded Sparkle.framework is missing." >&2; return 1; }
  # Official Sparkle code is already signed. Preserve those signatures for
  # ad-hoc builds, while Developer ID builds re-sign every nested component.
  if [[ "$CODE_SIGN_IDENTITY" != - ]]; then
    for component in "$version/XPCServices/Downloader.xpc" "$version/XPCServices/Installer.xpc" \
        "$version/Updater.app" "$version/Autoupdate"; do
      [[ -e "$component" ]] || { echo "Sparkle component is missing: $component" >&2; return 1; }
      codesign "${SIGNING_ARGS[@]}" --preserve-metadata=entitlements "$component"
    done
    codesign "${SIGNING_ARGS[@]}" --preserve-metadata=entitlements "$framework"
  fi
  codesign --verify --deep --strict "$framework"
}
