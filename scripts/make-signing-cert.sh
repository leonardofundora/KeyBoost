#!/bin/zsh
# Creates a self-signed certificate named "KeyBoost" and imports it into your keychain.
#
# Why: signing with a stable identity stops macOS from re-asking for Bluetooth permission
# after every rebuild. And because the certificate is called "KeyBoost" rather than
# carrying your name, that is what macOS shows in Login Items and in the "wants to run in
# the background" notice — instead of your legal name, which is what appears if you sign
# with an Apple developer certificate.
set -euo pipefail

NAME="KeyBoost"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "A certificate named “$NAME” already exists. Nothing to do."
  exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 7300 -nodes -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Deliberately old algorithms: the macOS keychain cannot read modern PKCS#12 files.
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -passout pass:keyboost -name "$NAME" \
  -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null

security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
  -P keyboost -T /usr/bin/codesign -A

echo "Done. Run ./build.sh again and it will sign with “$NAME”."
