#!/bin/bash
# Compiles Sources/*.swift into build/ImageRing.app and ad-hoc signs it. Does NOT install anywhere.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build/ImageRing.app
mkdir -p build/ImageRing.app/Contents/MacOS build/ImageRing.app/Contents/Resources build/obj
# Universal binary (Apple Silicon + Intel), macOS 13+
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" -o "build/obj/ImageRing-$arch" Sources/*.swift
done
lipo -create build/obj/ImageRing-arm64 build/obj/ImageRing-x86_64 -output build/ImageRing.app/Contents/MacOS/ImageRing
cp Info.plist build/ImageRing.app/Contents/Info.plist
install -m 755 scripts/img-shrink build/ImageRing.app/Contents/Resources/img-shrink
codesign --force -s - build/ImageRing.app
echo "built $(pwd)/build/ImageRing.app"
