#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/build-metadata.sh"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT_DIR/dist/Usage Rings.app"
WIDGET="$APP/Contents/PlugIns/UsageRingsWidget.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WIDGET/Contents/MacOS" "$WIDGET/Contents/Resources"
cp "$BIN_DIR/UsageRings" "$APP/Contents/MacOS/UsageRings"
cp "$BIN_DIR/UsageRingsStatusline" "$APP/Contents/Helpers/UsageRingsStatusline"
cp "$BIN_DIR/UsageRingsWidget" "$WIDGET/Contents/MacOS/UsageRingsWidget"
usage_embed_sparkle "$ROOT_DIR" "$APP"
cp -R "$BIN_DIR/UsageRings_UsageCore.bundle" "$APP/Contents/Resources/"
cp -R "$BIN_DIR/UsageRings_UsageCore.bundle" "$WIDGET/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
"$ROOT_DIR/script/icon.sh" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>work.hayashigoto.UsageRings</string>
<key>CFBundleExecutable</key><string>UsageRings</string>
<key>CFBundleName</key><string>Usage Rings</string>
<key>CFBundleDisplayName</key><string>Usage Rings</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>work.hayashigoto.UsageRings.usage</string>
<key>CFBundleURLSchemes</key><array><string>usagerings</string></array>
</dict></array>
</dict></plist>
PLIST
cat > "$WIDGET/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>work.hayashigoto.UsageRings.Widget</string>
<key>CFBundleExecutable</key><string>UsageRingsWidget</string>
<key>CFBundleName</key><string>Usage Rings</string>
<key>CFBundleDisplayName</key><string>Usage Rings</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict></plist>
PLIST
for BUNDLE in "$APP" "$WIDGET"; do
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$APP_BUILD" "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert UsageRingsSourceRevision -string "$SOURCE_REVISION" "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert UsageRingsSourceDirty -bool "$SOURCE_DIRTY" "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert UsageRingsBuildConfiguration -string "$CONFIGURATION" "$BUNDLE/Contents/Info.plist"
done
/usr/bin/plutil -insert SUFeedURL -string "$SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/bin/plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
else
  /usr/bin/plutil -insert SUEnableAutomaticChecks -bool false "$APP/Contents/Info.plist"
fi
usage_sign_sparkle "$APP"
codesign "${SIGNING_ARGS[@]}" --entitlements "$ROOT_DIR/Assets/Widget.entitlements" "$WIDGET"
codesign "${SIGNING_ARGS[@]}" "$APP/Contents/Helpers/UsageRingsStatusline"
codesign "${SIGNING_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
