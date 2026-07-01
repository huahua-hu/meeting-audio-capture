APP_NAME := MeetingAudioCapture
BUILD_DIR := .build/release
APP_DIR := .build/$(APP_NAME).app
MACOS13_BUILD_DIR := .build/arm64-apple-macosx/release
MACOS13_APP_DIR := .build/macos13/$(APP_NAME).app
MACOS13_DMG := MeetingAudioCapture-0.1.0-macos13-arm64.dmg

.PHONY: test build app dmg build-macos13 app-macos13 dmg-macos13 run clean

test:
	swift test

build:
	swift build -c release

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	cp Config/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp Config/AppIcon.icns "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	codesign --force --deep --sign - --entitlements Config/MeetingAudioCapture.entitlements "$(APP_DIR)"

dmg: app
	Scripts/create-dmg.sh "$(APP_DIR)" "Config/DMGBackground.png" ".build"

build-macos13:
	swift build -c release --triple arm64-apple-macosx13.0

app-macos13: build-macos13
	rm -rf "$(MACOS13_APP_DIR)"
	mkdir -p "$(MACOS13_APP_DIR)/Contents/MacOS"
	mkdir -p "$(MACOS13_APP_DIR)/Contents/Resources"
	cp Config/Info.plist "$(MACOS13_APP_DIR)/Contents/Info.plist"
	cp Config/AppIcon.icns "$(MACOS13_APP_DIR)/Contents/Resources/AppIcon.icns"
	cp "$(MACOS13_BUILD_DIR)/$(APP_NAME)" "$(MACOS13_APP_DIR)/Contents/MacOS/$(APP_NAME)"
	codesign --force --deep --sign - --entitlements Config/MeetingAudioCapture.entitlements "$(MACOS13_APP_DIR)"

dmg-macos13: app-macos13
	Scripts/create-dmg.sh "$(MACOS13_APP_DIR)" "Config/DMGBackground.png" ".build" "$(MACOS13_DMG)"

run: app
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf "$(APP_DIR)"
	rm -rf "$(MACOS13_APP_DIR)"
