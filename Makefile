APP := build/Flaran.app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
# Universal binary: Apple Silicon and Intel Macs on macOS 26.
ARCHS := --arch arm64 --arch x86_64
BIN = $(shell swift build -c release $(ARCHS) --show-bin-path)

.PHONY: app test run install dmg dist screenshots clean

app:
	swift build -c release $(ARCHS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN)/Flaran $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

test:
	swift test

run: app
	open $(APP)

install: app
	rm -rf /Applications/Flaran.app
	cp -R $(APP) /Applications/

# Drag-to-Applications disk image.
dmg: app
	./scripts/make-dmg.sh

# Release assets: the DMG plus a zip. Ad-hoc signed only, see README.
dist: dmg
	rm -f build/Flaran-$(VERSION).zip
	ditto -c -k --keepParent $(APP) build/Flaran-$(VERSION).zip
	@echo "build/Flaran-$(VERSION).zip"

# README images, from the debug build's showcase mode.
screenshots:
	./scripts/screenshots.sh

clean:
	rm -rf build .build
