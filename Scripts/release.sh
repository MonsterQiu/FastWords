#!/usr/bin/env bash
# Build a release .zip of FastWords.app for distribution.
# Usage: ./Scripts/release.sh            -> builds dist/FastWords-v<version>.zip
set -euo pipefail

APP_NAME="FastWords"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"

# 1. Build & package the .app (writes dist/FastWords.app).
"$ROOT_DIR/Scripts/package_app.sh"

# 2. Read the version from the packaged Info.plist.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist")"
ZIP_PATH="$DIST_DIR/$APP_NAME-v$VERSION.zip"

# 3. Zip with ditto so the .app bundle (symlinks, resource bundles, perms) is
#    preserved exactly — plain `zip` can mangle bundle structure.
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Release archive: $ZIP_PATH"
ls -lh "$ZIP_PATH" | awk '{print "Size: "$5}'
echo
echo "Next: gh release create v$VERSION \"$ZIP_PATH\" --title \"FastWords v$VERSION\" --notes-file <notes>"
