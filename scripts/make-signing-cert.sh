#!/bin/zsh
# Crea un certificado autofirmado llamado "KeyBoost" y lo importa al llavero.
#
# Por qué: firmar con una identidad estable evita que macOS vuelva a pedir el permiso
# de Bluetooth en cada recompilación. Y al llamarse "KeyBoost" en vez de llevar tu
# nombre, es eso lo que macOS muestra en Elementos de inicio y en el aviso de
# "quiere ejecutarse en segundo plano" — en vez de tu nombre legal, que es lo que
# aparece si firmas con un certificado de desarrollador de Apple.
set -euo pipefail

NAME="KeyBoost"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Ya existe un certificado «$NAME». Nada que hacer."
  exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 7300 -nodes -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Algoritmos antiguos a propósito: el llavero de macOS no lee los PKCS#12 modernos.
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -passout pass:keyboost -name "$NAME" \
  -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null

security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
  -P keyboost -T /usr/bin/codesign -A

echo "Listo. Vuelve a ejecutar ./build.sh y usará «$NAME» para firmar."
