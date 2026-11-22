#!/bin/zsh
# Build a release zip for GitHub Releases and print the values for the Homebrew cask.
# The version comes from MARKETING_VERSION in project.yml.
# Usage: scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
BUILD=build/release
APP="$BUILD/Build/Products/Release/JuPrev.app"
ZIP="dist/JuPrev-$VERSION.zip"

[[ -n "$VERSION" ]] || { echo "MARKETING_VERSION not found in project.yml"; exit 1; }
echo "==> JuPrev $VERSION"

echo "==> Tests"
swift test 2>&1 | grep -E '^(✔|✘) Test run' || true
swift test >/dev/null 2>&1 || { echo "tests failed"; exit 1; }

echo "==> Build (universal, ad-hoc signed)"
rm -rf "$BUILD"
xcodegen generate --quiet
xcodebuild -project JuPrev.xcodeproj -scheme JuPrev -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" build \
  | grep -E '^(error|warning: |\*\* BUILD)' | grep -v 'appintents' || true
[[ -d "$APP" ]] || { echo "build failed"; exit 1; }

codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/JuPrev"
for appex in "$APP"/Contents/PlugIns/*.appex; do
  echo "  $(basename "$appex"): $(lipo -archs "$appex/Contents/MacOS/"*)"
done

echo "==> Package"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# Don't leave the build copy registered: it would show up twice under Open With.
"$LSREGISTER" -u "$APP" 2>/dev/null || true
rm -rf "$APP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

cat <<EOF

$ZIP
  sha256 $SHA

Next:
  git tag v$VERSION && git push origin v$VERSION
  gh release create v$VERSION "$ZIP" --repo So-Cool/JuPrev --title "JuPrev $VERSION"
  In So-Cool/homebrew-tap, Casks/juprev.rb:
    version "$VERSION"
    sha256 "$SHA"
EOF
