#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
RELEASE_DIR="$PROJECT_ROOT/releases/1.0.0"
STAGING="$PROJECT_ROOT/.build/installer-image"
APP_NAME="Сравнение поставщиков.app"
APP="$RELEASE_DIR/$APP_NAME"
DMG="$RELEASE_DIR/Supplier-Compare-1.0.0-universal.dmg"
test -f "$APP/Contents/MacOS/SupplierCompare"
codesign --verify --deep --strict "$APP"
mkdir -p "$STAGING" "$PROJECT_ROOT/Verification"
ditto "$APP" "$STAGING/$APP_NAME"
if [ ! -L "$STAGING/Программы" ]; then ln -s /Applications "$STAGING/Программы"; fi
cp Resources/Установка.txt "$STAGING/Установка.txt"
hdiutil create -volname "Сравнение поставщиков" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG" > Verification/dmg-verification.txt
shasum -a 256 "$DMG" "$APP/Contents/MacOS/SupplierCompare" > Verification/SHA256.txt
echo "$DMG"
