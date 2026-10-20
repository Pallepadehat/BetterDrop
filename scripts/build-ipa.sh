#!/bin/zsh
# Builds an unsigned BetterDrop.ipa into build/, for installing on an iPhone with a sideloading tool (AltStore,
# Sideloadly), which signs it with your own Apple ID as it installs.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --quiet

PRODUCTS=build/DerivedData/Build/Products/Release-iphoneos
rm -rf "$PRODUCTS/BetterDrop.app"
mkdir -p build
if ! xcodebuild -project BetterDrop.xcodeproj -scheme "BetterDrop iOS" -configuration Release \
  -derivedDataPath build/DerivedData -destination 'generic/platform=iOS' \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
  build > build/xcodebuild-ios.log 2>&1; then
  grep -E "error:" build/xcodebuild-ios.log | sort -u | head -20
  echo "Build failed. The whole log is in build/xcodebuild-ios.log"
  exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$PRODUCTS/BetterDrop.app" "$STAGE/Payload/BetterDrop.app"
rm -f build/BetterDrop.ipa
(cd "$STAGE" && zip -qry - Payload) > build/BetterDrop.ipa
echo "Built build/BetterDrop.ipa ($(du -h build/BetterDrop.ipa | cut -f1))"
