#!/bin/zsh
# Draws the app icons and the README's pictures and GIFs with the app's own Metal shaders.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=Apps/Shared/Assets.xcassets/AppIcon.appiconset
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

xcrun -sdk macosx metal -c Packages/BetterDropKit/Sources/BetterDropUI/Shaders/Light.metal -o "$BUILD/Light.air"
xcrun -sdk macosx metallib "$BUILD/Light.air" -o "$BUILD/Light.metallib"
swiftc -O -parse-as-library -o "$BUILD/brand" scripts/brand/Brand.swift
rm -f "$ICONS"/*.png(N)
"$BUILD/brand" "$BUILD/Light.metallib" "$ICONS" docs/images
