#!/bin/zsh
# Builds and runs the offscreen renderer. Run from anywhere. Output: design/shots/*.png
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/design/.build"; mkdir -p "$BUILD"
cp "$ROOT/design/render.swift" "$BUILD/main.swift"   # top-level code must live in main.swift
swiftc -swift-version 5 "$ROOT"/Sources/RingGeometry.swift "$ROOT"/Sources/RingModel.swift \
  "$ROOT"/Sources/RingView.swift "$BUILD/main.swift" -o "$BUILD/render"
"$BUILD/render" "$ROOT/design/shots"
