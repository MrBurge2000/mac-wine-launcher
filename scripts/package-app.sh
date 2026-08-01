#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export DEVELOPER_DIR
fi

UNIVERSAL_BUILD=".build/universal"
swift build \
    -c release \
    --arch arm64 \
    --arch x86_64 \
    --build-path "$UNIVERSAL_BUILD"

APP="dist/Mac Wine Launcher.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"
cp "$UNIVERSAL_BUILD/apple/Products/Release/MacWineLauncher" "$MACOS/MacWineLauncher"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
codesign --force --sign - "$APP"
echo "$APP"
