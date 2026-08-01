#!/bin/bash
# 组装 轻图.app：swift build 产物 + Info.plist + 外部工具 + ad-hoc 签名
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"

swift build -c "$CONFIG" --arch arm64

BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
APP="dist/轻图.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/MinimApp" "$APP/Contents/MacOS/MinimApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM 打出的资源 bundle（本地化等），有则一并拷入
find "$BIN_PATH" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \; 2>/dev/null || true

bash scripts/fetch-tools.sh "$APP"

# 签名顺序：Frameworks/Helpers 已在 fetch-tools.sh 内签好，最后签主 app（不用 --deep）
codesign --force -s - "$APP"

echo "✓ 已生成 $APP"
