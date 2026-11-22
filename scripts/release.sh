#!/bin/zsh
# Build a release zip for GitHub Releases and print the values for the Homebrew cask.
# Used locally and by .github/workflows/release.yml.
#
# Usage: scripts/release.sh
#   VERSION       defaults to MARKETING_VERSION in project.yml (CI passes the tag's version)
#   BUILD_NUMBER  defaults to 1 (CI passes the run number)
set -euo pipefail
cd "$(dirname "$0")/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
VERSION="${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD=build/release
APP="$BUILD/Build/Products/Release/JuPrev.app"
ZIP="dist/JuPrev-$VERSION.zip"

[[ -n "$VERSION" ]] || { echo "No version: set VERSION or MARKETING_VERSION in project.yml"; exit 1; }
echo "==> JuPrev $VERSION ($BUILD_NUMBER)"

echo "==> Tests"
mkdir -p build
if ! swift test >build/test.log 2>&1; then
  tail -60 build/test.log
  echo "tests failed (full log: build/test.log)"
  exit 1
fi
grep -E '^✔ Test run' build/test.log

echo "==> Build (universal, ad-hoc signed)"
rm -rf "$BUILD"
xcodegen generate --quiet
xcodebuild build \
  -project JuPrev.xcodeproj -scheme JuPrev -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  | grep -E '^(error|warning: |\*\* BUILD)' | grep -v 'appintents' || true
[[ -d "$APP" ]] || { echo "build failed"; exit 1; }

echo "==> Verify"
codesign --verify --deep --strict "$APP"
for binary in "$APP/Contents/MacOS/JuPrev" "$APP"/Contents/PlugIns/*.appex/Contents/MacOS/*; do
  echo "  $(basename "$binary"): $(lipo -archs "$binary")"
done
for bundle in "$APP" "$APP"/Contents/PlugIns/*.appex; do
  # A debugging entitlement has no place in a release build.
  if codesign -d --entitlements - "$bundle" 2>/dev/null | grep -q get-task-allow; then
    echo "$(basename "$bundle") has get-task-allow"
    exit 1
  fi
done

echo "==> Package"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# Don't leave the build copy registered: it would show up twice under Open With.
"$LSREGISTER" -u "$APP" 2>/dev/null || true
rm -rf "$APP"
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "ZIP=$ZIP" >> "$GITHUB_ENV"
  echo "SHA256=$SHA256" >> "$GITHUB_ENV"
fi

cat <<EOF

$ZIP
  sha256 $SHA256

To release, push a tag (the Release workflow builds, publishes and updates the cask):
  git tag v$VERSION && git push origin v$VERSION
EOF
