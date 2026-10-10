#!/bin/zsh
# macOS ties permissions to the signing identity, so every build is signed with this one.
set -euo pipefail
name="Hark Dev"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$keychain" | grep -q "\"$name\""; then
  echo "$name already exists"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$work/cert.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name "$name" -passout pass:hark \
  -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/hark.p12"
security import "$work/hark.p12" -k "$keychain" -P hark -T /usr/bin/codesign
echo "created $name"
