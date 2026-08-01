.PHONY: build app run test cli clean dmg install uninstall

# 默认装到用户目录，不需要 sudo。装系统级：make install PREFIX=/usr/local（需 sudo）
PREFIX ?= $(HOME)/.local

build:
	swift build

# 把命令行工具装进 PATH。注意：这样装的 minim-cli 依赖 Homebrew 的
# pngquant/oxipng/gifsicle（.app 才会把它们打进 bundle）
install:
	swift build -c release
	install -d "$(PREFIX)/bin"
	install -m 755 .build/release/minim-cli "$(PREFIX)/bin/minim-cli"
	@echo "✓ 已安装 $(PREFIX)/bin/minim-cli"

uninstall:
	rm -f "$(PREFIX)/bin/minim-cli"
	@echo "✓ 已移除 $(PREFIX)/bin/minim-cli"

app:
	bash scripts/bundle-app.sh release

dmg: app
	bash scripts/make-dmg.sh

run: app
	open "dist/轻图.app"

test:
	swift test

clean:
	swift package clean
	rm -rf dist
