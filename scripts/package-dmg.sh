#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export DEVELOPER_DIR
fi

./scripts/package-app.sh

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/steambridge-dmg.XXXXXX")
STAGE="$TEMP_ROOT/stage"
RW_DMG="$TEMP_ROOT/SteamBridge-rw.dmg"
OUTPUT_DMG="$PROJECT_ROOT/dist/SteamBridge.dmg"
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$PROJECT_ROOT/Resources/Info.plist")
VOLUME_NAME="SteamBridge $APP_VERSION"
MOUNT_POINT=""

cleanup() {
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGE/.background"
ditto "$PROJECT_ROOT/dist/SteamBridge.app" "$STAGE/SteamBridge.app"
ln -s /Applications "$STAGE/Applications"
cp "$PROJECT_ROOT/Resources/Branding/dmg-background.png" "$STAGE/.background/background.png"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)
MOUNT_POINT=$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '/Apple_HFS/ {print $3; exit}')

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo "Could not locate mounted DMG volume" >&2
    exit 1
fi

SetFile -a C "$MOUNT_POINT"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {120, 120, 780, 542}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 112
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "SteamBridge.app" of container window to {150, 245}
        set position of item "Applications" of container window to {510, 245}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""

hdiutil convert \
    "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$OUTPUT_DMG" >/dev/null

codesign --force --sign - "$OUTPUT_DMG"
echo "$OUTPUT_DMG"
