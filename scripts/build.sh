#!/bin/zsh
# Builds BetterDrop.app (the Mac app) into build/, signed ad hoc.
#
# There's no Apple Developer ID behind BetterDrop yet, so releases are signed ad hoc: macOS can tell the app hasn't
# been changed since it was built, but not who built it. Updates are protected by Sparkle's EdDSA signature instead
# (see scripts/release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

# Regenerate the project if XcodeGen is around, so it matches project.yml.
command -v xcodegen >/dev/null && xcodegen generate --quiet

APP="build/DerivedData/Build/Products/Release/BetterDrop.app"
# A failed build must never leave an older app behind to be picked up below.
rm -rf "$APP"
mkdir -p build
if ! xcodebuild -project BetterDrop.xcodeproj -scheme "BetterDrop macOS" -configuration Release \
  -derivedDataPath build/DerivedData -destination 'generic/platform=macOS' \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build > build/xcodebuild.log 2>&1; then
  grep -E "error:" build/xcodebuild.log | sort -u | head -20
  echo "Build failed. The whole log is in build/xcodebuild.log"
  exit 1
fi
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

# Sign everything again, inside out, the same way, so the app and Sparkle's helpers match.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign() { codesign --force --sign - --options runtime "$@"; }
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Apps/macOS/BetterDrop.entitlements "$APP"
codesign --verify --deep --strict "$APP" || { echo "The app's signature doesn't check out."; exit 1; }

rm -rf build/BetterDrop.app
ditto "$APP" build/BetterDrop.app
echo "Built build/BetterDrop.app"
echo "Run it with: open build/BetterDrop.app"
