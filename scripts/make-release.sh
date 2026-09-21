#!/bin/zsh
# Genera los binarios publicables en dist/: un DMG y un ZIP.
#
# Se firman SIEMPRE ad-hoc, a propósito. Un certificado personal incrusta el nombre
# y el correo del desarrollador en el binario, y macOS los muestra en Elementos de
# inicio a todo el que lo instale. Para un tercero una firma autofirmada no aporta
# nada frente a ad-hoc: sin notarización de Apple, Gatekeeper avisa igual.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${1:-1.0}"

mkdir -p dist
rm -f "dist/KeyBoost-$VERSION.dmg" "dist/KeyBoost-$VERSION.zip"

echo "▸ Compilando versión publicable (ad-hoc)"
KEYBOOST_ADHOC=1 ./build.sh >/dev/null 2>&1 || { echo "falló la compilación"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/KeyBoost.app" "$STAGE/KeyBoost.app"

echo "▸ ZIP"
(cd "$STAGE" && zip -qry "$ROOT/dist/KeyBoost-$VERSION.zip" KeyBoost.app)

echo "▸ DMG"
ln -s /Applications "$STAGE/Applications"       # el clásico arrastrar-y-soltar
hdiutil create -quiet -volname "KeyBoost" -srcfolder "$STAGE" \
  -ov -format UDZO "dist/KeyBoost-$VERSION.dmg"

echo "▸ Restaurando la compilación local (con tu identidad de firma)"
./build.sh >/dev/null 2>&1 || { echo "falló la recompilación local"; exit 1; }

echo
echo "✓ Listo:"
ls -lh dist/ | tail -n +2 | awk '{printf "   %-28s %s\n", $9, $5}'
echo
AUTH=$(codesign -dvv "dist/KeyBoost-check" 2>/dev/null || true)
echo "Firma de lo publicado:"
hdiutil attach -quiet -nobrowse -mountpoint "$STAGE/mnt" "dist/KeyBoost-$VERSION.dmg"
codesign -dvv "$STAGE/mnt/KeyBoost.app" 2>&1 | grep -E "Signature|TeamIdentifier" | sed 's/^/   /'
hdiutil detach -quiet "$STAGE/mnt"
