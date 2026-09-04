#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

SRC="$DIR/assets/luna_mascot.png"
if [ ! -f "$SRC" ]; then
    echo "Error: $SRC does not exist"
    exit 1
fi

ICONSET="$DIR/assets/Luna.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

echo "==> Resizing mascot into iconset (preserving alpha transparency)..."
TMP_PNG="$SRC"

sips -z 16 16     "$TMP_PNG" --out "$ICONSET/icon_16x16.png" > /dev/null
sips -z 32 32     "$TMP_PNG" --out "$ICONSET/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$TMP_PNG" --out "$ICONSET/icon_32x32.png" > /dev/null
sips -z 64 64     "$TMP_PNG" --out "$ICONSET/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$TMP_PNG" --out "$ICONSET/icon_128x128.png" > /dev/null
sips -z 256 256   "$TMP_PNG" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$TMP_PNG" --out "$ICONSET/icon_256x256.png" > /dev/null
sips -z 512 512   "$TMP_PNG" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$TMP_PNG" --out "$ICONSET/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$TMP_PNG" --out "$ICONSET/icon_512x512@2x.png" > /dev/null

echo "==> Compiling into AppIcon.icns via iconutil..."
iconutil -c icns "$ICONSET" -o "$DIR/assets/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Successfully created $DIR/assets/AppIcon.icns"
