#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FastWords"
BUNDLE_ID="com.fastworld.FastWords"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/Scripts/VERSION"
BUILD_FILE="$ROOT_DIR/Scripts/BUILD_NUMBER"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
VERSION="$(cat "$VERSION_FILE")"
BUILD_NUMBER="$(cat "$BUILD_FILE")"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# App icon: copy the .icns into Resources/ and reference it from Info.plist.
RESOURCES_DIR="$CONTENTS_DIR/Resources"
mkdir -p "$RESOURCES_DIR"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Copy SPM-generated resource bundles (ECDICT dictionary, Maple fonts) to the
# .app bundle ROOT — next to Contents/, NOT inside Resources/ or MacOS/. The
# SwiftPM `Bundle.module` accessor resolves them via `Bundle.main.bundleURL`,
# which for an .app is the bundle root; putting them anywhere else makes the
# app fall back to an absolute build-dir path that breaks once moved/renamed.
for bundle in "$ROOT_DIR"/.build/release/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP_DIR/"
done

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Packaged $APP_DIR"
