#!/usr/bin/env bash
# Build dist/FastWords.app, then quit any running instance and open the new one
# so you can try the latest build without manually restarting.
#
#   ./Scripts/package_app.sh           # package + relaunch (default)
#   SKIP_RELAUNCH=1 ./Scripts/package_app.sh
#   ./Scripts/package_app.sh --no-relaunch
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

RELAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --no-relaunch|-n) RELAUNCH=0 ;;
  esac
done
if [[ "${SKIP_RELAUNCH:-0}" == "1" ]]; then
  RELAUNCH=0
fi

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
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>加入 FastWords</string>
      </dict>
      <key>NSMessage</key>
      <string>addWordFromService</string>
      <key>NSPortName</key>
      <string>FastWords</string>
      <key>NSSendTypes</key>
      <array>
        <string>public.utf8-plain-text</string>
        <string>NSStringPboardType</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "Packaged $APP_DIR"

relaunch_app() {
  # Prefer a graceful quit (saves state via applicationWillTerminate).
  if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -f "/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    echo "Quitting running ${APP_NAME}..."
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    # Wait up to ~3s for a clean exit; then force-kill leftovers.
    for _ in 1 2 3 4 5 6; do
      if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 \
         && ! pgrep -f "/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        break
      fi
      sleep 0.5
    done
    killall "$APP_NAME" 2>/dev/null || true
    # Also stop copies launched from dist/ or .build/ that share the binary name.
    pkill -f "/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 0.3
  fi

  echo "Opening $APP_DIR"
  open "$APP_DIR"
}

if [[ "$RELAUNCH" == "1" ]]; then
  relaunch_app
else
  echo "Skipped relaunch (SKIP_RELAUNCH=1 or --no-relaunch)."
fi
