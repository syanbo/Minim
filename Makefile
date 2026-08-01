.PHONY: build app run test cli clean dmg

build:
	swift build

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
