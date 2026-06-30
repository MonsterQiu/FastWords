#!/usr/bin/env bash
# Build a release .zip of FastWords.app for distribution and optionally upload a GitHub release.
# Usage: ./Scripts/release.sh [--publish]
set -euo pipefail

APP_NAME="FastWords"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/Scripts/VERSION"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
VERSION="$(cat "$VERSION_FILE")"
TAG="v$VERSION"
PUBLISH=0
if [[ "${1:-}" == "--publish" ]]; then
  PUBLISH=1
fi

cd "$ROOT_DIR"

# 1. Build & package the .app (writes dist/FastWords.app).
"$ROOT_DIR/Scripts/package_app.sh"

# 2. Build a zip named from the single source-of-truth version file.
ZIP_PATH="$DIST_DIR/$APP_NAME-v$VERSION.zip"

# 3. Zip with ditto so the .app bundle (symlinks, resource bundles, perms) is
#    preserved exactly — plain `zip` can mangle bundle structure.
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Release archive: $ZIP_PATH"
ls -lh "$ZIP_PATH" | awk '{print "Size: "$5}'
echo
echo "Next: gh release create $TAG \"$ZIP_PATH\" --title \"FastWords $TAG\" --notes-file <notes>"
