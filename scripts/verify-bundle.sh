#!/bin/bash
# 验证 .app 自带四个压缩工具、不依赖 Homebrew，且签名完好。
# 编译通过不代表工具打进去了——这是本项目最容易翻车的地方，
# ci.yml / release.yml / 发版流程共用这一份，别再各写一遍。
#
# 用法：bash scripts/verify-bundle.sh [.app 路径]（默认 dist/轻图.app）
set -uo pipefail

APP="${1:-dist/轻图.app}"
[[ -d "$APP" ]] || { echo "❌ 找不到 $APP"; exit 1; }

fail=0
for tool in pngquant oxipng gifsicle apngasm; do
    # 用清空的 PATH 运行，确保产物不依赖 Homebrew 环境；
    # 看输出而非退出码：apngasm 即使成功 --version 也返回非 0
    out="$(env -i PATH=/usr/bin:/bin "$APP/Contents/Helpers/$tool" --version 2>&1 | head -1 || true)"
    if [[ -z "$out" ]]; then
        echo "❌ $tool 无输出——可能没被打进 bundle 或缺依赖"
        fail=1
    else
        printf '✓ %-10s %s\n' "$tool" "$out"
    fi
done

if codesign --verify --deep --strict "$APP" 2>&1; then
    echo "✓ 签名校验通过"
else
    echo "❌ 签名校验失败"
    fail=1
fi

exit $fail
