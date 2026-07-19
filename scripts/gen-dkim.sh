#!/usr/bin/env sh
# Generate a DKIM keypair for a domain and print the DNS TXT record.
# Usage: gen-dkim.sh <domain> <selector> [out_dir]
set -eu

DOMAIN="${1:?domain required}"
SELECTOR="${2:-proxymail}"
OUT_DIR="${3:-./dkim}"

mkdir -p "$OUT_DIR"
PRIV="$OUT_DIR/$DOMAIN.private"
PUB="$OUT_DIR/$DOMAIN.public"

openssl genrsa -out "$PRIV" 2048 >/dev/null 2>&1
openssl rsa -in "$PRIV" -pubout -out "$PUB" >/dev/null 2>&1
chmod 600 "$PRIV"

# Strip PEM header/footer/newlines to build the p= value
P=$(grep -v '^-' "$PUB" | tr -d '\n')

echo ""
echo "=== DKIM DNS record for $DOMAIN ==="
echo "Host:  ${SELECTOR}._domainkey.${DOMAIN}"
echo "Type:  TXT"
echo "Value: v=DKIM1; k=rsa; p=${P}"
echo "==================================="
