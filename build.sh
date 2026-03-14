#!/bin/bash
set -e

APP_NAME="Mosby"
BUNDLE_ID="com.tommasominuto.mosby"
VERSION="1.0.0"
MIN_MACOS="14.0"
BINARY_NAME="Mosby"

APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "==> Cleaning previous build..."
rm -rf "${APP_BUNDLE}" "${DMG_NAME}" dmg-staging

echo "==> Building release binary..."
swift build -c release

echo "==> Assembling .app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${BINARY_NAME}" "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"

# Copy icon if it exists
if [ -f "Mosby.icns" ]; then
    cp "Mosby.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    ICON_KEY=""
fi

cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    ${ICON_KEY}
</dict>
</plist>
EOF

echo "==> Signing with ad-hoc signature..."
codesign --deep --force --sign - "${APP_BUNDLE}"

echo "==> Creating .dmg..."
mkdir dmg-staging
cp -r "${APP_BUNDLE}" dmg-staging/
ln -s /Applications dmg-staging/Applications

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder dmg-staging \
    -ov \
    -format UDZO \
    -o "${DMG_NAME}"

rm -rf dmg-staging

echo ""
echo "Done!"
echo "  App bundle : ${APP_BUNDLE}"
echo "  Disk image : ${DMG_NAME}"
echo ""
echo "Note: users downloading this will need to run:"
echo "  xattr -rd com.apple.quarantine /Applications/${APP_BUNDLE}"
echo "or right-click > Open on first launch."
