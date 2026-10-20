#!/bin/zsh
# Quick compile check of both apps, signed ad hoc, for development. Prints only errors and warnings in our code.
#   ./scripts/dev-build.sh [macos|ios|all]
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --quiet

build() {
  local scheme=$1 destination=$2
  echo "▸ $scheme"
  xcodebuild -project BetterDrop.xcodeproj -scheme "$scheme" -configuration Debug -derivedDataPath build/DerivedData \
    -destination "$destination" -skipMacroValidation -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build 2>&1 \
    | grep -E "error:|warning: .*(Apps|Packages)/|BUILD (SUCCEEDED|FAILED)" | sort -u
}

case "${1:-all}" in
  macos) build "BetterDrop macOS" "platform=macOS" ;;
  ios) build "BetterDrop iOS" "generic/platform=iOS Simulator" ;;
  *) build "BetterDrop macOS" "platform=macOS"; build "BetterDrop iOS" "generic/platform=iOS Simulator" ;;
esac
