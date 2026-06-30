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

if [[ "$PUBLISH" -eq 1 ]]; then
  NOTES_FILE="$DIST_DIR/release-notes-$TAG.md"
  "$ROOT_DIR/Scripts/generate_release_notes.sh" > "$NOTES_FILE"
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release edit "$TAG" --title "FastWords $TAG" --notes-file "$NOTES_FILE" "$ZIP_PATH"
  else
    gh release create "$TAG" "$ZIP_PATH" --title "FastWords $TAG" --notes-file "$NOTES_FILE"
  fi
  echo "Published GitHub release: $TAG"
else
  echo "Next: gh release create $TAG \"$ZIP_PATH\" --title \"FastWords $TAG\" --notes-file <notes>"
fi
