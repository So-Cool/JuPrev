#!/bin/zsh
# Build JuPrev (Release, ad-hoc signed), install it to ~/Applications and register the
# Quick Look extension. Usage: scripts/install-dev.sh
set -euo pipefail
cd "$(dirname "$0")/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
BUILT=build/Build/Products/Release/JuPrev.app
DEST="$HOME/Applications/JuPrev.app"

xcodegen generate --quiet
xcodebuild -project JuPrev.xcodeproj -scheme JuPrev -configuration Release -derivedDataPath build build \
  | grep -E '^(error|warning: |\*\* BUILD)' || true
[[ -d "$BUILT" ]] || { echo "build failed"; exit 1; }

# Keep only the installed copy registered, so Quick Look doesn't pick the build folder's.
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
pkill -x JuPrev 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
"$LSREGISTER" -f "$DEST"
open -g "$DEST"   # first launch registers the extension
sleep 2
qlmanage -r >/dev/null 2>&1
qlmanage -r cache >/dev/null 2>&1
pluginkit -m -i ch.usi.kacper.juprev.quicklook
