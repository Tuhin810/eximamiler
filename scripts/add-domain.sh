#!/usr/bin/env sh
# Enable DKIM signing for an ADDITIONAL sender domain on a running node.
# Delivery already works for any domain; this just adds a DKIM key so
# mail From that domain is signed (better inbox placement). No restart
# needed — Exim reads the key per-message from the mounted volume.
#
# Usage (inside the container):
#   docker compose exec exim /opt/exim/add-domain.sh yourdomain.com
set -eu

DOMAIN="${1:?usage: add-domain.sh <domain>}"
SELECTOR="${DKIM_SELECTOR:-proxymail}"
DKIM_DIR=/etc/exim4/dkim

if [ -f "$DKIM_DIR/$DOMAIN.private" ]; then
  echo "[add-domain] key for $DOMAIN already exists — DNS record below:"
else
  /opt/exim/gen-dkim.sh "$DOMAIN" "$SELECTOR" "$DKIM_DIR"
fi

EXIM_USER=$(getent passwd Debian-exim >/dev/null 2>&1 && echo Debian-exim || echo exim)
chown "$EXIM_USER" "$DKIM_DIR/$DOMAIN.private" 2>/dev/null || true
chmod 600 "$DKIM_DIR/$DOMAIN.private"

echo "[add-domain] '$DOMAIN' will now be DKIM-signed. Add the TXT record above at your DNS host,"
echo "             plus SPF (v=spf1 a mx ip4:<vps-ip> ~all) and DMARC for the domain."
