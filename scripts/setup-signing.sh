#!/bin/bash
# One-time setup: creates a self-signed code signing certificate in its own keychain.
# A stable signature lets macOS keep the Accessibility and Screen Recording grants
# across rebuilds. Nothing is added to the login keychain.
set -euo pipefail

NAME="SwitchTab Local Signing"
KEYCHAIN="$HOME/Library/Keychains/switchtab-signing.keychain-db"
SUPPORT="$HOME/Library/Application Support/SwitchTab"
PWFILE="$SUPPORT/signing-keychain-password"

if [ -f "$KEYCHAIN" ] && [ -f "$PWFILE" ]; then
    echo "Signing keychain already exists"
    exit 0
fi

umask 077
mkdir -p "$SUPPORT"
PW="$(/usr/bin/openssl rand -hex 24)"
printf '%s' "$PW" > "$PWFILE"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cfg" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout "pass:$PW" -name "$NAME"

security create-keychain -p "$PW" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$PW" "$KEYCHAIN"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PW" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KEYCHAIN" >/dev/null

# codesign only finds identities in keychains on the user search list.
EXISTING=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%\"}"
    line="${line#\"}"
    [ -n "$line" ] && EXISTING+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "${EXISTING[@]}" "$KEYCHAIN"

echo "Created signing identity: $NAME"
