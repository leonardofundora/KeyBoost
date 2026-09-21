#!/bin/zsh
# Produces the publishable binaries in dist/: a DMG and a ZIP.
#
# They are ALWAYS signed ad-hoc, on purpose. A personal certificate embeds the developer's
# name and email in the binary, and macOS shows them in Login Items to everyone who
# installs it. For a third party a self-signed certificate buys nothing over ad-hoc:
# without Apple notarisation, Gatekeeper warns either way.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${1:-1.0}"

mkdir -p dist
rm -f "dist/KeyBoost-$VERSION.dmg" "dist/KeyBoost-$VERSION.zip"

echo "▸ Building the publishable copy (ad-hoc)"
KEYBOOST_ADHOC=1 ./build.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/KeyBoost.app" "$STAGE/KeyBoost.app"

echo "▸ ZIP"
(cd "$STAGE" && zip -qry "$ROOT/dist/KeyBoost-$VERSION.zip" KeyBoost.app)

echo "▸ DMG"
ln -s /Applications "$STAGE/Applications"       # the classic drag-and-drop layout
hdiutil create -quiet -volname "KeyBoost" -srcfolder "$STAGE" \
  -ov -format UDZO "dist/KeyBoost-$VERSION.dmg"

echo "▸ Restoring your local build (signed with your own identity)"
./build.sh >/dev/null 2>&1 || { echo "local rebuild failed"; exit 1; }

echo
echo "✓ Done:"
ls -lh dist/ | tail -n +2 | awk '{printf "   %-28s %s\n", $9, $5}'
echo
echo "Signature of what ships:"
hdiutil attach -quiet -nobrowse -mountpoint "$STAGE/mnt" "dist/KeyBoost-$VERSION.dmg"
codesign -dvv "$STAGE/mnt/KeyBoost.app" 2>&1 | grep -E "Signature|TeamIdentifier" | sed 's/^/   /'
hdiutil detach -quiet "$STAGE/mnt"
