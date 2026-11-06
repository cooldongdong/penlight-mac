#!/bin/sh
# One-time: create a self-signed code-signing identity in the login keychain.
#
# Why: an ad-hoc signed app is identified by its exact binary hash, so every
# rebuild looks like a brand-new app to macOS and loses the Input Monitoring
# permission. Signing with a stable certificate keeps the permission across
# rebuilds. The certificate is only used to sign this app locally; delete
# "Penlight Local Signing" in Keychain Access to remove it.
set -eu
NAME="Penlight Local Signing"

for existing in "$NAME" "Hawk Presenter Local Signing"; do  # older name still works
  if security find-identity -p codesigning | grep -q "$existing"; then
    echo "Already exists: $existing"; exit 0
  fi
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cfg" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/key.pem" -out "$T/cert.pem" -days 3650 -config "$T/cfg" 2>/dev/null
# macOS `security` only understands the old SHA1/3DES PKCS#12 encoding;
# OpenSSL 3 (e.g. Homebrew) defaults to AES/SHA256, so force the legacy one.
openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -out "$T/id.p12" -passout pass:tmp -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import "$T/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P tmp -T /usr/bin/codesign
echo "Created: $NAME"
