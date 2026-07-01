#!/bin/sh
set -eu

APP_PATH=${1:?"usage: create-dmg.sh APP_PATH BACKGROUND_PATH OUTPUT_DIRECTORY"}
BACKGROUND_PATH=${2:?"usage: create-dmg.sh APP_PATH BACKGROUND_PATH OUTPUT_DIRECTORY"}
OUTPUT_DIRECTORY=${3:?"usage: create-dmg.sh APP_PATH BACKGROUND_PATH OUTPUT_DIRECTORY"}
OUTPUT_NAME=${4:-}

for tool in hdiutil ditto osascript; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing required macOS tool: $tool" >&2
        exit 1
    }
done

[ -d "$APP_PATH" ] || {
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
}
[ -f "$BACKGROUND_PATH" ] || {
    echo "DMG background not found: $BACKGROUND_PATH" >&2
    exit 1
}

INFO_PLIST="$APP_PATH/Contents/Info.plist"
[ -f "$INFO_PLIST" ] || {
    echo "App Info.plist not found: $INFO_PLIST" >&2
    exit 1
}

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
APP_NAME=$(basename "$APP_PATH")
VOLUME_NAME=MeetingAudioCapture
mkdir -p "$OUTPUT_DIRECTORY"
if [ -n "$OUTPUT_NAME" ]; then
    FINAL_DMG="$OUTPUT_DIRECTORY/$OUTPUT_NAME"
else
    FINAL_DMG="$OUTPUT_DIRECTORY/MeetingAudioCapture-$VERSION.dmg"
fi

WORK_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/MeetingAudioCapture.dmg.XXXXXX")
STAGING_DIRECTORY="$WORK_DIRECTORY/staging"
MOUNT_POINT="/Volumes/$VOLUME_NAME"
WRITABLE_DMG="$WORK_DIRECTORY/MeetingAudioCapture-rw.dmg"
MOUNTED=0

cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGING_DIRECTORY"
[ ! -e "$MOUNT_POINT" ] || {
    echo "DMG mount point is already in use: $MOUNT_POINT" >&2
    exit 1
}
ditto "$APP_PATH" "$STAGING_DIRECTORY/$APP_NAME"
ln -s /Applications "$STAGING_DIRECTORY/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIRECTORY" \
    -fs HFS+ \
    -format UDRW \
    -size 100m \
    -ov \
    "$WRITABLE_DMG" >/dev/null

hdiutil attach \
    "$WRITABLE_DMG" \
    -mountpoint "$MOUNT_POINT" \
    -nobrowse \
    -noverify \
    -noautoopen >/dev/null
MOUNTED=1

mkdir -p "$MOUNT_POINT/.background"
ditto "$BACKGROUND_PATH" "$MOUNT_POINT/.background/DMGBackground.png"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {140, 120, 800, 540}
        set sidebar width of container window to 0
        set arrangement of icon view options of container window to not arranged
        set icon size of icon view options of container window to 112
        set text size of icon view options of container window to 13
        set background picture of icon view options of container window to file ".background:DMGBackground.png"
        set position of item "$APP_NAME" of container window to {170, 210}
        set position of item "Applications" of container window to {490, 210}
        update without registering applications
        delay 2
        close
        open
        delay 1
    end tell
end tell
APPLESCRIPT

sync
if ! hdiutil detach "$MOUNT_POINT" >/dev/null; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null
fi
MOUNTED=0

rm -f "$FINAL_DMG"
hdiutil convert \
    "$WRITABLE_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG" >/dev/null

echo "$FINAL_DMG"
