#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="File Converter.app"
APP_BUNDLE_ID="com.alanlucena.FileConverter"
EXT_BUNDLE_ID="com.alanlucena.FileConverter.FinderSync"
TARGET="arm64-apple-macos13.0"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p build

echo "Compiling host..."
swiftc -sdk "$SDK" -target "$TARGET" \
    -framework AppKit -framework Foundation \
    -framework PDFKit -framework ImageIO -framework UniformTypeIdentifiers \
    -o build/FileConverter \
    src/Host/main.swift

echo "Compiling extension..."
swiftc -sdk "$SDK" -target "$TARGET" \
    -module-name FileConverterExt \
    -framework FinderSync -framework AppKit -framework Foundation \
    -o build/FinderSync \
    src/Ext/main.swift src/Ext/FinderSyncController.swift

echo "Assembling bundle..."
APP_PATH="build/$APP_NAME"
APPEX_PATH="$APP_PATH/Contents/PlugIns/FinderSync.appex"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
mkdir -p "$APPEX_PATH/Contents/MacOS"
mkdir -p "$APPEX_PATH/Contents/Resources"

cp build/FileConverter "$APP_PATH/Contents/MacOS/FileConverter"
cp src/Host/Info.plist "$APP_PATH/Contents/Info.plist"
cp build/FinderSync "$APPEX_PATH/Contents/MacOS/FinderSync"
cp src/Ext/Info.plist "$APPEX_PATH/Contents/Info.plist"

echo "Copying localized resources..."
for lproj in src/Resources/*.lproj; do
    name="$(basename "$lproj")"
    cp -R "$lproj" "$APP_PATH/Contents/Resources/$name"
    cp -R "$lproj" "$APPEX_PATH/Contents/Resources/$name"
done

echo "Code-signing (ad-hoc)..."
codesign --force --sign - --entitlements src/Ext/Ext.entitlements --timestamp=none "$APPEX_PATH"
codesign --force --sign - --entitlements src/Host/Host.entitlements --timestamp=none "$APP_PATH"

echo "Verifying signature..."
codesign --verify --verbose=4 "$APP_PATH"

if [[ "${1:-}" == "--install" ]]; then
    echo "Installing to /Applications..."
    osascript -e 'tell app "File Converter" to quit' >/dev/null 2>&1 || true
    osascript -e 'tell app "Convertir archivo" to quit' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/$APP_NAME"
    cp -R "$APP_PATH" /Applications/
    /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "/Applications/$APP_NAME"
    killall -KILL pkd 2>/dev/null || true
    sleep 2
    pluginkit -e use -i "$EXT_BUNDLE_ID"
    echo "Installed and enabled."
    echo "Try: right-click on an image in Finder > Convert File (or your locale) > pick a format."
fi

echo "Done. Bundle: $APP_PATH"
