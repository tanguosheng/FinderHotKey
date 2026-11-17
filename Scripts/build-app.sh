#!/bin/bash
# Builds a universal (Intel + Apple Silicon) FinderHotKey.app in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$ROOT/dist/FinderHotKey.app"
SOURCE="$ROOT/Sources/FinderHotKey/main.swift"
DEPLOYMENT_TARGET="12.0"

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD/x86_64" "$BUILD/arm64" \
         "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling x86_64..."
xcrun --sdk macosx swiftc -O \
    -target "x86_64-apple-macos${DEPLOYMENT_TARGET}" \
    -o "$BUILD/x86_64/FinderHotKey" "$SOURCE"

echo "Compiling arm64..."
xcrun --sdk macosx swiftc -O \
    -target "arm64-apple-macos${DEPLOYMENT_TARGET}" \
    -o "$BUILD/arm64/FinderHotKey" "$SOURCE"

lipo -create "$BUILD/x86_64/FinderHotKey" \
             "$BUILD/arm64/FinderHotKey" \
             -output "$APP/Contents/MacOS/FinderHotKey"
chmod 755 "$APP/Contents/MacOS/FinderHotKey"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"

# Ad-hoc signature. Rebuilding changes the cdhash, so Accessibility permission
# must be approved again after every build.
codesign --force --deep --sign - "$APP"

echo "Built: $APP"