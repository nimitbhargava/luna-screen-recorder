#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Ensure AppIcon.icns exists
if [ ! -f "$DIR/assets/AppIcon.icns" ]; then
    echo "==> Generating iconset..."
    "$DIR/scripts/generate_icons.sh"
fi

echo "==> Building Luna for macOS..."
mkdir -p .build/cache
env CLANG_MODULE_CACHE_PATH="$DIR/.build/cache" SWIFT_MODULE_CACHE_PATH="$DIR/.build/cache" \
swiftc -sdk "$(xcrun --show-sdk-path)" \
  -O \
  -target arm64-apple-macosx14.0 \
  Sources/ScreenRecorder/*.swift \
  -o .build/Luna

APP_NAME="Luna - Screen Recorder"
APP_DIR="$DIR/$APP_NAME.app"

echo "==> Packaging into $APP_NAME.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/Luna "$APP_DIR/Contents/MacOS/Luna"
chmod +x "$APP_DIR/Contents/MacOS/Luna"

# Copy Icon and Mascot Assets
if [ -f "$DIR/assets/AppIcon.icns" ]; then
    cp "$DIR/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
if [ -f "$DIR/assets/luna_mascot.png" ]; then
    cp "$DIR/assets/luna_mascot.png" "$APP_DIR/Contents/Resources/luna_mascot.png"
fi

cat << EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Luna</string>
    <key>CFBundleIdentifier</key>
    <string>com.luna.screenrecorder</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Luna requires screen capture access to record displays, windows, or selected regions.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Luna uses on-device speech recognition to transcribe voice narration for AI prompts.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Luna requires microphone access to record and transcribe voice narration.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Luna uses AppleScript to detect active browser URLs for context logging.</string>
</dict>
</plist>
EOF

echo "==> Code signing $APP_NAME.app with stable identifier..."
codesign --force --deep -s - -r="designated => identifier \"com.luna.screenrecorder\"" "$APP_DIR"

echo "==> Packaging distribution zip..."
mkdir -p "$DIR/dist"
rm -f "$DIR/dist/Luna.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIR/dist/Luna.zip"

echo "==> Successfully created $APP_DIR and dist/Luna.zip"
