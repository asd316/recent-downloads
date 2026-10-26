#!/bin/bash
# 本地发布新版本脚本（需要 gh CLI）。
# 用法:  bash Scripts/release.sh v1.1.0
#
# 依赖:  brew install gh && gh auth login
# 效果:  构建 DMG → 打 tag → 推送 → 创建 GitHub Release 并上传
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "用法: bash Scripts/release.sh <tag>"
  echo "示例: bash Scripts/release.sh v1.1.0"
  exit 1
fi

VERSION="$1"
cd "$(dirname "$0")/.."

if ! command -v gh &>/dev/null; then
  echo "❌ 需要 gh CLI。安装:  brew install gh && gh auth login"
  exit 1
fi

# 检查 gh 登录态
if ! gh auth status &>/dev/null; then
  echo "❌ gh 未登录。运行:  gh auth login"
  exit 1
fi

echo "==> 构建 DMG"
bash Scripts/build-dmg.sh

echo "==> 创建 tag $VERSION"
git tag "$VERSION"

echo "==> 推送 tag"
git push origin "$VERSION"

echo "==> 创建 GitHub Release 并上传 DMG"
gh release create "$VERSION" \
  ".build/最近下载.dmg" \
  --title "$VERSION" \
  --generate-notes

echo "✅ 完成: https://github.com/asd316/recent-downloads/releases/tag/$VERSION"