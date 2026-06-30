#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/Scripts/VERSION"
PREV_TAG="${1:-v0.2.0}"
CUR_VERSION="$(cat "$VERSION_FILE")"
CUR_TAG="v$CUR_VERSION"

cat <<HDR
# FastWords $CUR_TAG

HDR

echo "## 变化摘要"
echo
if git -C "$ROOT_DIR" rev-parse "$PREV_TAG" >/dev/null 2>&1; then
  git -C "$ROOT_DIR" log --no-merges --pretty=format:'- %s' "$PREV_TAG..HEAD"
else
  git -C "$ROOT_DIR" log --no-merges --pretty=format:'- %s' -n 10
fi

echo

echo
cat <<'FOOT'
## 安装

- 下载下方 zip，解压后把 `FastWords.app` 拖进「应用程序」文件夹。
- 首次打开如被 Gatekeeper 拦截，右键 → 打开。
FOOT
