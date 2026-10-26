#!/bin/bash
# 构建 Release 并组装 .app 包。
# 产物：.build/app/最近下载.app（非沙盒、未签名、未公证）。
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

APP_DIR=".build/app/最近下载.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

BIN=".build/arm64-apple-macosx/release/RecentDownloads"
if [ ! -f "$BIN" ]; then
    BIN=".build/release/RecentDownloads"
fi
cp "$BIN" "$MACOS/RecentDownloads"
cp Resources/Info.plist "$CONTENTS/Info.plist"
chmod +x "$MACOS/RecentDownloads"

echo "==> 完成: $(pwd)/$APP_DIR"
ls -la "$MACOS"
