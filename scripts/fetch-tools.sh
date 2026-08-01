#!/bin/bash
# 把 brew 安装的压缩工具拷入 app bundle，并把 /opt/homebrew 的动态库依赖
# 重定向到 bundle 内的 Frameworks（依赖链每次动态解析，不硬编码）
set -euo pipefail

APP="$1"                       # dist/轻图.app
HELPERS="$APP/Contents/Helpers"
FRAMEWORKS="$APP/Contents/Frameworks"
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
TOOLS=(pngquant oxipng gifsicle apngasm)

mkdir -p "$HELPERS" "$FRAMEWORKS"

missing=()
for tool in "${TOOLS[@]}"; do
    # 优先用项目内置的静态编译版（无动态库依赖，如 apngasm）
    if [[ -x "Vendor/tools/$tool" ]]; then
        cp -f "Vendor/tools/$tool" "$HELPERS/$tool"
        chmod 755 "$HELPERS/$tool"
        continue
    fi
    src="$BREW_PREFIX/bin/$tool"
    if [[ ! -x "$src" ]]; then
        missing+=("$tool")
        continue
    fi
    cp -fL "$src" "$HELPERS/$tool"
    chmod 755 "$HELPERS/$tool"
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "警告: 未安装 ${missing[*]}，请执行: brew install ${missing[*]}" >&2
fi

# 递归收集非系统 dylib 依赖并修复 install name
# 参数: 目标文件路径, 引用前缀（helper 用 @loader_path/../Frameworks，dylib 用 @loader_path）
fix_deps() {
    local binary="$1" prefix="$2"
    otool -L "$binary" | awk 'NR>1 {print $1}' | { grep -E '^(/opt/homebrew|/usr/local|@rpath)' || true; } | while read -r dep; do
        local name src
        name="$(basename "$dep")"
        if [[ "$dep" == @rpath/* ]]; then
            # @rpath 依赖（如 apngasm 的 libapngasm.dylib）：到 brew opt 下按名查找
            src="$(find -L "$BREW_PREFIX/opt" -maxdepth 3 -name "$name" -path '*/lib/*' 2>/dev/null | head -1)"
            [[ -z "$src" ]] && { echo "警告: 无法解析 $dep" >&2; continue; }
        else
            src="$dep"
        fi
        if [[ ! -f "$FRAMEWORKS/$name" ]]; then
            cp -fL "$src" "$FRAMEWORKS/$name"
            chmod 644 "$FRAMEWORKS/$name"
            install_name_tool -id "@loader_path/$name" "$FRAMEWORKS/$name" 2>/dev/null
            fix_deps "$FRAMEWORKS/$name" "@loader_path"
        fi
        install_name_tool -change "$dep" "$prefix/$name" "$binary" 2>/dev/null
    done
}

for tool in "${TOOLS[@]}"; do
    [[ -x "$HELPERS/$tool" ]] && fix_deps "$HELPERS/$tool" "@loader_path/../Frameworks"
done

# 修复后残留检查
leftover="$(find "$HELPERS" "$FRAMEWORKS" -type f -exec otool -L {} \; 2>/dev/null | grep -E '^\s+(/opt/homebrew|/usr/local)' || true)"
if [[ -n "$leftover" ]]; then
    echo "错误: 仍有未修复的 brew 依赖:" >&2
    echo "$leftover" >&2
    exit 1
fi

# 先签 Frameworks 再签 Helpers（主 app 签名在 bundle-app.sh 末尾）
find "$FRAMEWORKS" -type f -name '*.dylib' -exec codesign --force -s - {} \; 2>/dev/null || true
for tool in "${TOOLS[@]}"; do
    [[ -x "$HELPERS/$tool" ]] && codesign --force -s - "$HELPERS/$tool"
done

# 自验证：每个工具能跑 --version 并产生输出（apngasm 的 --version 退出码非 0，看输出判断）
for tool in "${TOOLS[@]}"; do
    if [[ -x "$HELPERS/$tool" ]]; then
        out="$("$HELPERS/$tool" --version 2>&1 | head -1 || true)"
        if [[ -z "$out" ]]; then
            echo "错误: $tool 打包后无法运行" >&2
            exit 1
        fi
        echo "✓ $tool $out"
    fi
done
