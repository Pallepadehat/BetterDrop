#!/bin/zsh
# Makes a release: builds BetterDrop.dmg (the Mac app) and BetterDrop.ipa (the iPhone app, unsigned, for
# sideloading), and publishes them as a GitHub release with appcast.xml, where the Mac app finds updates (Sparkle).
# The version comes from MARKETING_VERSION in project.yml.
#
# Releases aren't signed with an Apple Developer ID, so what proves an update came from us is the EdDSA signature
# in the appcast, made with the private key in the maintainer's keychain (account "betterdrop", made once with
# Sparkle's `generate_keys --account betterdrop`; its public half is SUPublicEDKey in project.yml). Keep a backup:
# `generate_keys --account betterdrop -x sparkle-key.txt` exports it. Without it, copies already out there can't
# update.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=Pallepadehat/BetterDrop
VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first, so the release matches the code."; exit 1; }
git fetch --tags --quiet
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already exists. Bump MARKETING_VERSION in project.yml first."
  exit 1
fi

./scripts/make-dmg.sh
./scripts/build-ipa.sh

# The appcast: one entry for this version, signed with our EdDSA key, pointing at this release's disk image.
GENERATE_APPCAST=$(find build/DerivedData/SourcePackages/artifacts -name generate_appcast -type f -perm -u+x | head -1)
[[ -n "$GENERATE_APPCAST" ]] || { echo "Couldn't find Sparkle's generate_appcast. Build once so Swift packages are fetched."; exit 1; }
rm -rf build/appcast
mkdir -p build/appcast
cp build/BetterDrop.dmg build/appcast/
"$GENERATE_APPCAST" --account betterdrop \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$REPO/releases/tag/$TAG" --maximum-versions 1 build/appcast
[[ -f build/appcast/appcast.xml ]] || { echo "No appcast was made."; exit 1; }

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" build/BetterDrop.dmg build/BetterDrop.ipa build/appcast/appcast.xml \
  --repo "$REPO" --title "BetterDrop $VERSION" --generate-notes
echo "Released $TAG. Anyone can now install the Mac app with:"
echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
