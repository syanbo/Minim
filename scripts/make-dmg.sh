#!/bin/bash
# 打包 dist/轻图.app 为可分发的 DMG（含拖入 Applications 的快捷方式）
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/轻图.app"
[[ -d "$APP" ]] || { echo "请先执行 make app"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# 文件名用 ASCII：GitHub Release 上传时会过滤掉非 ASCII 字符，
# 「轻图-1.0.0.dmg」会变成「-1.0.0.dmg」。挂载后的卷名仍是中文
DMG="dist/Minim-${VERSION}.dmg"
STAGING="dist/dmg-staging"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "轻图" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov "$DMG" >/dev/null

rm -rf "$STAGING"
hdiutil verify "$DMG" >/dev/null
echo "✓ 已生成 $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
