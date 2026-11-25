#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/build"
APP_PATH="$DIST_DIR/SandBridge.app"
DMG_PATH="$DIST_DIR/SandBridge-${VERSION}.dmg"
ZIP_PATH="$DIST_DIR/SandBridge-${VERSION}-macOS.zip"
STAGE_DIR="$BUILD_DIR/dmg_stage"

rm -rf "$DIST_DIR" "$BUILD_DIR"
mkdir -p "$DIST_DIR" "$STAGE_DIR"

echo "==> 1. 编译 Release 版 SandBridge.app (v${VERSION})..."
xcodebuild \
  -project "$ROOT/SandBridge.xcodeproj" \
  -scheme SandBridge \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CONFIGURATION_BUILD_DIR="$DIST_DIR" \
  MARKETING_VERSION="$VERSION" \
  build

echo "==> 2. 检查架构..."
lipo -info "$APP_PATH/Contents/MacOS/SandBridge"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> 3. 使用证书签名: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  echo "==> 3. 使用 Ad-Hoc 签名"
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "==> 4. 生成 ZIP 和 DMG..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "SandBridge" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

echo ""
echo "打包完成："
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo "  ZIP: $ZIP_PATH"
