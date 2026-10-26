#!/bin/bash
# 构建 Release .app 并打包为 .dmg，方便分享给其他 Mac 用户。
# 产物：.build/最近下载.dmg
#
# 注意：此应用未签名、未公证，首次打开时需右键 → 打开。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="最近下载"
DMG_NAME="${APP_NAME}.dmg"
APP_PATH=".build/app/${APP_NAME}.app"
DMG_PATH=".build/${DMG_NAME}"
STAGING=".build/dmg-staging"

# 1. 构建 .app
echo "==> 构建 ${APP_NAME}.app"
bash Scripts/build-app.sh

# 2. 清理旧的 dmg
rm -f "$DMG_PATH"
rm -rf "$STAGING"

# 3. 准备 staging 目录：.app + /Applications 快捷方式
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"

# 4. 创建 .dmg
echo "==> 创建 ${DMG_NAME}"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1 | tail -2

# 5. 清理
rm -rf "$STAGING"

echo "==> 完成: $(pwd)/${DMG_PATH}"
echo "==> 大小: $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
echo "💡 对方收到后，右键 → 打开 即可运行（未签名应用）"