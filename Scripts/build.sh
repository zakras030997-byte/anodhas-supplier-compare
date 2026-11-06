#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
BUILD_DIR="$PROJECT_ROOT/.build"
RELEASE_DIR="$PROJECT_ROOT/releases/1.0.0"
APP_NAME="Сравнение поставщиков.app"
APP="$RELEASE_DIR/$APP_NAME"
SDK_PATH="${SUPPLIER_COMPARE_SDK:-$(xcrun --show-sdk-path)}"
mkdir -p "$BUILD_DIR/module-cache" "$RELEASE_DIR" "$PROJECT_ROOT/Verification"

xcrun swiftc -O -parse-as-library -sdk "$SDK_PATH" -module-cache-path "$BUILD_DIR/module-cache" Sources/Model.swift Sources/Engine.swift Sources/Transfer.swift Sources/Demo.swift Tests/Suite.swift -o "$BUILD_DIR/CoreTests"
"$BUILD_DIR/CoreTests" > Verification/tests.json

for ARCH in arm64 x86_64; do
  mkdir -p "$BUILD_DIR/$ARCH"
  xcrun swiftc -O -parse-as-library -sdk "$SDK_PATH" -target "$ARCH-apple-macos13.0" \
    -module-cache-path "$BUILD_DIR/module-cache" Sources/Model.swift Sources/Engine.swift Sources/Transfer.swift Sources/Demo.swift Sources/Store.swift Sources/ImportView.swift Sources/App.swift \
    -o "$BUILD_DIR/$ARCH/SupplierCompare"
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun lipo -create "$BUILD_DIR/arm64/SupplierCompare" "$BUILD_DIR/x86_64/SupplierCompare" -output "$APP/Contents/MacOS/SupplierCompare"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xcrun swift -sdk "$SDK_PATH" -module-cache-path "$BUILD_DIR/module-cache" Scripts/MakeIcon.swift "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements Resources/App.entitlements "$APP"
else
  codesign --force --options runtime --sign - --entitlements Resources/App.entitlements "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
xcrun lipo -archs "$APP/Contents/MacOS/SupplierCompare"
echo "Application: $APP"
