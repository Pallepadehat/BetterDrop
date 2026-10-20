#!/bin/zsh
# Builds BetterDrop and packs it into build/BetterDrop.dmg: the app next to a shortcut to Applications, so you can
# drag it across. That's the file a GitHub release carries; install.sh downloads it from there.
#
#   --skip-build   pack the app already in build/
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "${1:-}" == "--skip-build" ]] || ./scripts/build.sh

APP=build/BetterDrop.app
[[ -d "$APP" ]] || { echo "No app at $APP. Run scripts/build.sh first."; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/BetterDrop.app"
ln -s /Applications "$STAGE/Applications"

DMG=build/BetterDrop.dmg
rm -f "$DMG"
hdiutil create -volname "BetterDrop" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
