#!/bin/zsh
# Pure geometry self-test. No GUI, no AppKit.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/design/.build"; mkdir -p "$BUILD"
swiftc -swift-version 5 -parse-as-library "$ROOT"/Sources/RingGeometry.swift "$ROOT"/Sources/RingModel.swift \
  "$ROOT"/design/geometry_test.swift -o "$BUILD/geometry_test"
"$BUILD/geometry_test"
