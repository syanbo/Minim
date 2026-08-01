#!/bin/bash
# 从源码静态编译 apngasm（去掉 boost_regex→icu 依赖链，产物只链系统库），
# 输出到 Vendor/tools/apngasm。产物已入库，仅在需要升级 apngasm 时重跑。
# 依赖：cmake、brew 的 boost（静态 .a）与 libpng（静态 .a）
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BREW="$(brew --prefix)"
SRC="$(mktemp -d)/apngasm"

git clone --depth 1 https://github.com/apngasm/apngasm "$SRC"
cd "$SRC"

# 1) boost::regex → std::regex（仅用于 ASCII 参数/文件名匹配）
python3 - <<'EOF'
import re

p = "cli/src/cli.cpp"
s = open(p).read()
s = s.replace("#include <boost/regex.hpp>", "#include <regex>")
s = s.replace('static const regex RE("\\\\Ay(es)?\\\\z", regex::icase);',
              'static const std::regex RE("y(es)?", std::regex::icase);')
s = s.replace('static const boost::regex PNG_RE(".+\\\\.png\\\\z");',
              'static const std::regex PNG_RE(".+\\\\.png");')
# 原正则 [0-9]+[:[0-9]+]? 是病态写法，std::regex 会拒绝，按原意规范化
s = s.replace('static const boost::regex DELAY_RE("[0-9]+[:[0-9]+]?");',
              'static const std::regex DELAY_RE("[0-9]+(:[0-9]+)?");')
s = s.replace("regex_match(", "std::regex_match(").replace("std::std::", "std::")
open(p, "w").write(s)

p = "lib/src/apngasm.cpp"
s = open(p).read()
s = s.replace("#include <boost/regex.hpp>", "#include <regex>")
s = s.replace("boost::regex_replace", "std::regex_replace")
s = s.replace("boost::regex", "std::regex")
s = s.replace('"\\\\\\\\$0"', '"\\\\\\\\$&"')   # boost 的 $0 → std 的 $&
open(p, "w").write(s)

# 2) 去掉 regex/system 组件（boost≥1.90 system 为纯头文件且无 cmake 配置）
for p in ["lib/CMakeLists.txt", "cli/CMakeLists.txt"]:
    s = open(p).read()
    s = s.replace("find_package(Boost REQUIRED COMPONENTS program_options regex system)",
                  "find_package(Boost REQUIRED COMPONENTS program_options)")
    s = re.sub(r"Boost::regex\s*", "", s)
    s = re.sub(r"Boost::system\s*", "", s)
    open(p, "w").write(s)

# 3) CLI 改链静态库 target
p = "cli/CMakeLists.txt"
s = open(p).read()
s = s.replace("target_link_libraries(apngasm-cli\n  apngasm\n",
              "target_link_libraries(apngasm-cli\n  apngasm-static\n")
open(p, "w").write(s)
print("patched")
EOF

cmake -B build -DCMAKE_BUILD_TYPE=Release \
    -DBoost_USE_STATIC_LIBS=ON \
    -DPNG_LIBRARY="$BREW/opt/libpng/lib/libpng16.a" \
    -DPNG_PNG_INCLUDE_DIR="$BREW/opt/libpng/include"
cmake --build build --target apngasm-cli -j8

# 验证：只允许链接系统库
if otool -L build/cli/apngasm | grep -qE "/opt/homebrew|/usr/local|@rpath"; then
    echo "错误: 产物仍有非系统依赖" >&2
    otool -L build/cli/apngasm >&2
    exit 1
fi

mkdir -p "$ROOT/Vendor/tools"
cp -f build/cli/apngasm "$ROOT/Vendor/tools/apngasm"
chmod 755 "$ROOT/Vendor/tools/apngasm"
codesign --force -s - "$ROOT/Vendor/tools/apngasm"
echo "✓ Vendor/tools/apngasm ($(du -h "$ROOT/Vendor/tools/apngasm" | cut -f1 | tr -d ' '))"
