#!/bin/bash
# Creates a self-signed code-signing certificate named "Luik Local" in your login keychain, so
# builds of Luik keep a stable identity and macOS permissions (Screen Recording for evidence
# screenshots) survive rebuilds. Run once; build.sh picks the certificate up automatically.
#
# Nothing leaves your Mac: the certificate is only trusted on this machine, for code signing.
set -euo pipefail

NAME="Luik Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "A \"$NAME\" code-signing identity already exists. Nothing to do."
  exit 0
fi

cat > "$WORK/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF

echo "▶ Generating the certificate (valid 10 years) …"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/luik.p12" \
  -name "$NAME" -passout pass:luik >/dev/null 2>&1

echo "▶ Importing it into the login keychain …"
security import "$WORK/luik.p12" -k "$KEYCHAIN" -P luik -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "▶ Trusting it for code signing (macOS may ask for your password) …"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "✔ \"$NAME\" is ready. Rebuild with ./build.sh --install, then grant Screen Recording once:"
  echo "  System Settings › Privacy & Security › Screen Recording — remove the old Luik entry (−) and add the new one."
else
  echo "The identity was imported but codesign does not see it yet. Open Keychain Access, find"
  echo "\"$NAME\" under My Certificates, double-click it, expand Trust and set Code Signing to Always Trust." >&2
  exit 1
fi
