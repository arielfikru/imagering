#!/bin/bash
# Builds ImageRing.app and packs it into dist/ImageRing-<version>.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
STAGE=$(mktemp -d)
cp -R build/ImageRing.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f "dist/ImageRing-$VER.dmg"
hdiutil create -volname "ImageRing $VER" -srcfolder "$STAGE" -ov -format UDZO "dist/ImageRing-$VER.dmg" >/dev/null
rm -rf "$STAGE"
shasum -a 256 "dist/ImageRing-$VER.dmg"
