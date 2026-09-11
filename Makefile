.PHONY: build app icon install uninstall run dev test clean

# /Applications is writable by admin users, so installing needs no sudo. Falls back to
# ~/Applications when it is not. Override with: make install APP_DIR=~/Applications
APP_DIR ?= $(shell [ -w /Applications ] && echo /Applications || echo $(HOME)/Applications)

# Swift Testing ships with the command-line tools but is not on the default search paths.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

build:
	swift build

app:
	Scripts/build-app.sh release

# Re-renders Resources/AppIcon.icns from Scripts/make-icon.swift. Only needed when
# changing the artwork; the .icns is checked in.
icon:
	swift Scripts/make-icon.swift
	iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns

install: app
	mkdir -p "$(APP_DIR)"
	pkill -x BoseMenuControl 2>/dev/null || true
	rm -rf "$(APP_DIR)/BoseMenuControl.app"
	cp -R .build/BoseMenuControl.app "$(APP_DIR)/"
	@echo "Installed $(APP_DIR)/BoseMenuControl.app"

uninstall:
	pkill -x BoseMenuControl 2>/dev/null || true
	rm -rf "$(APP_DIR)/BoseMenuControl.app"
	@echo "Removed $(APP_DIR)/BoseMenuControl.app"

run: app
	open .build/BoseMenuControl.app

dev:
	swift run BoseMenuControl

test:
	swift test $(TEST_FLAGS)

clean:
	swift package clean
	rm -rf .build/BoseMenuControl.app
