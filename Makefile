APP_NAME := MeetingAudioCapture
BUILD_DIR := .build/release
APP_DIR := .build/$(APP_NAME).app

.PHONY: test build app dmg run clean

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

run: app
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf "$(APP_DIR)"
