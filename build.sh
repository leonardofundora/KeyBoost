#!/bin/zsh
# Builds KeyBoost: the interface (with a Dock icon) and the engine nested inside it.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD="$ROOT/.build"
rm -rf "$BUILD"; mkdir -p "$BUILD"

SHARED=(Sources/Shared/*.swift)

# Signing with a stable identity is what makes the Bluetooth permission survive rebuilds.
# With an ad-hoc signature macOS cannot recognise the app between builds and asks again.
#   1) Prefer a self-signed certificate named "KeyBoost" (scripts/make-signing-cert.sh).
#      Stable AND anonymous: macOS shows "KeyBoost" in Login Items, not your name.
#   2) Otherwise any signing identity. Stable, but it puts the certificate's name and
#      email in the background-item notice and in Login Items.
#   3) Otherwise ad-hoc: no personal data, but macOS re-asks for Bluetooth after rebuilds.
IDENTITY=$(security find-certificate -c "KeyBoost" -Z 2>/dev/null \
             | awk '/SHA-1 hash:/ {print $3; exit}')
if [[ -n "$IDENTITY" ]]; then
  echo "▸ Signing with the self-signed “KeyBoost” certificate"
else
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/[0-9A-F]{40}/ {print $2; exit}')
  if [[ -n "$IDENTITY" ]]; then
    NAME=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
    echo "▸ Signing with: $NAME"
    echo "  Heads-up: macOS will show that name in Login Items."
    echo "  Run scripts/make-signing-cert.sh to sign as “KeyBoost” instead."
  else
    IDENTITY="-"
    echo "▸ No identity: ad-hoc signature (macOS will re-ask for Bluetooth after rebuilds)"
  fi
fi

# Force ad-hoc for the binaries you publish: KEYBOOST_ADHOC=1 ./build.sh
if [[ "${KEYBOOST_ADHOC:-0}" == "1" ]]; then
  IDENTITY="-"
  echo "▸ KEYBOOST_ADHOC=1 -> forcing an ad-hoc signature"
fi

bundle() {           # bundle <name> <bundle-id> <LSUIElement true|false> <directory>
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
    <key>CFBundleDevelopmentRegion</key>       <string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>es</string></array>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleShortVersionString</key>      <string>1.0</string>
    <key>CFBundleVersion</key>                 <string>1</string>
    <key>LSMinimumSystemVersion</key>          <string>14.0</string>
    <key>CFBundleIconFile</key>                <string>AppIcon</string>
    <key>LSUIElement</key>                     <$agent/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>KeyBoost needs Bluetooth to keep your keyboard on a low-latency link.</string>
    <key>NSHumanReadableCopyright</key>        <string>MIT licensed</string>
</dict>
</plist>
PLIST
  cp "$ROOT/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  # Translations. English is the base language, Spanish sits alongside it, and macOS picks
  # by system language. Both bundles get a copy, because each process reads its own.
  # InfoPlist.strings is what localises the Bluetooth permission dialog.
  for lproj in "$ROOT"/Resources/*.lproj; do
    cp -R "$lproj" "$app/Contents/Resources/"
  done
  mv "$BUILD/$name" "$app/Contents/MacOS/$name"
  codesign --force --sign "$IDENTITY" --timestamp=none "$app" >/dev/null 2>&1 \
    && echo "  signed" || echo "  WARNING: could not sign"
}

echo "▸ Interface (KeyBoost)"
swiftc -O -swift-version 5 \
  -framework AppKit -framework SwiftUI \
  -o "$BUILD/KeyBoost" "${SHARED[@]}" Sources/App/*.swift
bundle KeyBoost com.keyboost.app false "$ROOT"

echo "▸ Engine (KeyBoostAgent), nested as a login item"
swiftc -O -swift-version 5 \
  -framework AppKit -framework CoreBluetooth -framework CoreGraphics \
  -o "$BUILD/KeyBoostAgent" "${SHARED[@]}" Sources/Agent/*.swift
LOGIN_ITEMS="$ROOT/KeyBoost.app/Contents/Library/LoginItems"
mkdir -p "$LOGIN_ITEMS"
bundle KeyBoostAgent com.keyboost.agent true "$LOGIN_ITEMS"

# Nesting invalidates the container's signature, so re-sign it outside-in.
codesign --force --sign "$IDENTITY" --timestamp=none "$ROOT/KeyBoost.app" >/dev/null 2>&1 \
  && echo "  container re-signed" || echo "  WARNING: could not re-sign the container"

rm -rf "$BUILD"
echo "✓ Done: $ROOT/KeyBoost.app (engine bundled inside)"
