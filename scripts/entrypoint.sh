#!/usr/bin/env sh
# Renders exim4.conf from the template using env vars, ensures TLS +
# DKIM material exist, then execs Exim in the foreground.
set -eu

: "${DELIVERY_MODE:=submission}"          # submission | direct-mx
: "${SMARTHOST:=smtp-relay.brevo.com::587}"
: "${SMARTHOST_USER:=}"
: "${SMARTHOST_PASS:=}"
: "${PRIMARY_HOSTNAME:=mail.example.com}"
: "${DKIM_SELECTOR:=proxymail}"
: "${DKIM_DOMAINS:=example.com}"
: "${SUBMISSION_PORT:=587}"

CONF_DIR=/etc/exim4
TLS_DIR="$CONF_DIR/tls"
DKIM_DIR="$CONF_DIR/dkim"

echo "[entrypoint] mode=$DELIVERY_MODE host=$PRIMARY_HOSTNAME port=$SUBMISSION_PORT"

# 1. Render config
export DELIVERY_MODE SMARTHOST SMARTHOST_USER SMARTHOST_PASS \
       PRIMARY_HOSTNAME DKIM_SELECTOR DKIM_DOMAINS SUBMISSION_PORT
# CRITICAL: pass an explicit variable list so envsubst only substitutes
# OUR macros. Without it, envsubst blanks every $word — including Exim's
# own runtime variables ($auth1, $value, $dkim_domain, ...) — silently
# breaking auth and DKIM.
envsubst '$DELIVERY_MODE $SMARTHOST $SMARTHOST_USER $SMARTHOST_PASS $PRIMARY_HOSTNAME $DKIM_SELECTOR $DKIM_DOMAINS $SUBMISSION_PORT' \
  < /opt/exim/exim4.conf.template > "$CONF_DIR/exim4.conf"

# 2. Self-signed TLS if no cert mounted (replace with real certs in prod)
mkdir -p "$TLS_DIR"
if [ ! -f "$TLS_DIR/fullchain.pem" ]; then
  echo "[entrypoint] no TLS cert mounted — generating self-signed (dev only)"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TLS_DIR/privkey.pem" -out "$TLS_DIR/fullchain.pem" \
    -days 825 -subj "/CN=$PRIMARY_HOSTNAME" >/dev/null 2>&1
fi

# 3. Ensure a DKIM key exists for each signing domain
mkdir -p "$DKIM_DIR"
for d in $(echo "$DKIM_DOMAINS" | tr ':' ' '); do
  d=$(echo "$d" | xargs)
  [ -z "$d" ] && continue
  if [ ! -f "$DKIM_DIR/$d.private" ]; then
    echo "[entrypoint] generating DKIM key for $d"
    /opt/exim/gen-dkim.sh "$d" "$DKIM_SELECTOR" "$DKIM_DIR"
  fi
done

# The Debian exim4 package runs the daemon as the "Debian-exim" user;
# fall back to "exim" for other distros.
EXIM_USER=$(getent passwd Debian-exim >/dev/null 2>&1 && echo Debian-exim || echo exim)

# 4. Provision the app submission account if credentials were passed
if [ -n "${APP_SMTP_USER:-}" ] && [ -n "${APP_SMTP_PASS:-}" ]; then
  CRYPT=$(openssl passwd -6 "$APP_SMTP_PASS")
  echo "$APP_SMTP_USER:$CRYPT" > "$CONF_DIR/passwd"
  # Must be readable by the exim runtime user for the lsearch lookup.
  chown "$EXIM_USER" "$CONF_DIR/passwd" 2>/dev/null || true
  chmod 640 "$CONF_DIR/passwd"
  echo "[entrypoint] provisioned app submission user '$APP_SMTP_USER'"
fi

# Exim refuses to run if the MAIN config isn't root-owned, so only the
# runtime-read material (DKIM keys, TLS, passwd) is handed to the exim
# user — exim4.conf itself stays root:root (world-readable).
chown root:root "$CONF_DIR/exim4.conf" 2>/dev/null || true
chmod 644 "$CONF_DIR/exim4.conf"
chown -R "$EXIM_USER" "$DKIM_DIR" "$TLS_DIR" 2>/dev/null || true
# The spool is a bind-mounted volume owned by the host user; Exim runs as
# EXIM_USER and must own it to create the input/ queue dirs (else 421).
mkdir -p /var/spool/exim4
chown -R "$EXIM_USER" /var/spool/exim4 2>/dev/null || true
chmod 750 /var/spool/exim4

# 5. Validate config, then run
exim -C "$CONF_DIR/exim4.conf" -bV >/dev/null
echo "[entrypoint] config OK — starting Exim on :$SUBMISSION_PORT"
exec exim -C "$CONF_DIR/exim4.conf" -bdf -oX "$SUBMISSION_PORT" ${EXIM_DEBUG:-}
