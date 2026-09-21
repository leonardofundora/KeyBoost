#!/bin/zsh
# Compila KeyBoost: el motor (sin Dock) y la interfaz (con Dock).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD="$ROOT/.build"
rm -rf "$BUILD"; mkdir -p "$BUILD"

SHARED=(Sources/Shared/*.swift)

# Firmar con una identidad estable es lo que hace que TCC (el permiso de Bluetooth)
# sobreviva a las recompilaciones. Con firma ad-hoc, macOS no puede reconocer la app
# entre compilaciones y vuelve a preguntar cada vez.
# 1) Preferimos un certificado propio llamado "KeyBoost" (scripts/make-signing-cert.sh).
#    Es estable Y anónimo: macOS muestra "KeyBoost" en Elementos de inicio, no tu nombre.
# 2) Si no existe, cualquier identidad de firma. Estable, pero expone el nombre y el
#    correo del certificado en el aviso de segundo plano y en Elementos de inicio.
# 3) Si tampoco, ad-hoc: sin datos personales, pero macOS volverá a pedir el permiso
#    de Bluetooth después de cada recompilación.
IDENTITY=$(security find-certificate -c "KeyBoost" -Z 2>/dev/null \
             | awk '/SHA-1 hash:/ {print $3; exit}')
if [[ -n "$IDENTITY" ]]; then
  echo "▸ Firmando con el certificado propio «KeyBoost»"
else
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/[0-9A-F]{40}/ {print $2; exit}')
  if [[ -n "$IDENTITY" ]]; then
    NAME=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
    echo "▸ Firmando con: $NAME"
    echo "  Aviso: macOS mostrará ese nombre en Elementos de inicio."
    echo "  Ejecuta scripts/make-signing-cert.sh para firmar como «KeyBoost» en su lugar."
  else
    IDENTITY="-"
    echo "▸ Sin identidad: firma ad-hoc (macOS repetirá el permiso de Bluetooth al recompilar)"
  fi
fi

# Permite forzar ad-hoc para los binarios que se publican: KEYBOOST_ADHOC=1 ./build.sh
if [[ "${KEYBOOST_ADHOC:-0}" == "1" ]]; then
  IDENTITY="-"
  echo "▸ KEYBOOST_ADHOC=1 -> firma ad-hoc forzada"
fi

bundle() {           # bundle <nombre> <bundle-id> <LSUIElement true|false> <directorio>
  local name=$1 ident=$2 agent=$3 dest=$4
  local app="$dest/$name.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                    <string>$name</string>
    <key>CFBundleDisplayName</key>             <string>$name</string>
    <key>CFBundleExecutable</key>              <string>$name</string>
    <key>CFBundleIdentifier</key>              <string>$ident</string>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleShortVersionString</key>      <string>1.0</string>
    <key>CFBundleVersion</key>                 <string>1</string>
    <key>LSMinimumSystemVersion</key>          <string>14.0</string>
    <key>CFBundleIconFile</key>                <string>AppIcon</string>
    <key>LSUIElement</key>                     <$agent/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>KeyBoost necesita Bluetooth para mantener tu teclado en baja latencia.</string>
    <key>NSHumanReadableCopyright</key>        <string>Uso personal</string>
</dict>
</plist>
PLIST
  cp "$ROOT/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  mv "$BUILD/$name" "$app/Contents/MacOS/$name"
  codesign --force --sign "$IDENTITY" --timestamp=none "$app" >/dev/null 2>&1 \
    && echo "  firmado" || echo "  AVISO: no se pudo firmar"
}

echo "▸ Interfaz (KeyBoost)"
swiftc -O -swift-version 5 \
  -framework AppKit -framework SwiftUI \
  -o "$BUILD/KeyBoost" "${SHARED[@]}" Sources/App/*.swift
bundle KeyBoost com.keyboost.app false "$ROOT"

echo "▸ Motor (KeyBoostAgent), anidado como login item"
swiftc -O -swift-version 5 \
  -framework AppKit -framework CoreBluetooth -framework CoreGraphics \
  -o "$BUILD/KeyBoostAgent" "${SHARED[@]}" Sources/Agent/*.swift
LOGIN_ITEMS="$ROOT/KeyBoost.app/Contents/Library/LoginItems"
mkdir -p "$LOGIN_ITEMS"
bundle KeyBoostAgent com.keyboost.agent true "$LOGIN_ITEMS"

# El anidado invalida la firma del contenedor: hay que refirmar de fuera a dentro.
codesign --force --sign "$IDENTITY" --timestamp=none "$ROOT/KeyBoost.app" >/dev/null 2>&1 \
  && echo "  contenedor refirmado" || echo "  AVISO: no se pudo refirmar el contenedor"

rm -rf "$BUILD"
echo "✓ Listo: $ROOT/KeyBoost.app (motor incluido dentro)"
