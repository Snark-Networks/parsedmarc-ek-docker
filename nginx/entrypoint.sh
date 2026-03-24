#!/bin/sh
set -e

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
if [ -z "${KIBANA_HOSTNAME}" ]; then
    echo "ERROR: KIBANA_HOSTNAME environment variable is required." >&2
    exit 1
fi

if [ -z "${CERTBOT_EMAIL}" ]; then
    echo "ERROR: CERTBOT_EMAIL environment variable is required." >&2
    exit 1
fi

CERT_PATH="/etc/letsencrypt/live/${KIBANA_HOSTNAME}/fullchain.pem"

# ---------------------------------------------------------------------------
# Render nginx configs from templates (only substitutes ${KIBANA_HOSTNAME},
# leaving nginx's own $variables untouched).
# ---------------------------------------------------------------------------
envsubst '${KIBANA_HOSTNAME}' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/conf.d/default.conf

envsubst '${KIBANA_HOSTNAME}' \
    < /etc/nginx/nginx-acme-only.conf.template \
    > /tmp/acme-only.conf

# ---------------------------------------------------------------------------
# First-run: obtain a real Let's Encrypt certificate
# ---------------------------------------------------------------------------
if [ ! -f "${CERT_PATH}" ]; then
    echo "==> No certificate found for ${KIBANA_HOSTNAME}."
    echo "==> Starting nginx temporarily to serve the ACME challenge..."

    cp /tmp/acme-only.conf /etc/nginx/conf.d/default.conf
    nginx
    sleep 2

    echo "==> Requesting Let's Encrypt certificate..."
    certbot certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --email "${CERTBOT_EMAIL}" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        -d "${KIBANA_HOSTNAME}"

    echo "==> Certificate obtained. Stopping bootstrap nginx..."
    nginx -s stop
    sleep 1

    # Restore full HTTPS config
    envsubst '${KIBANA_HOSTNAME}' \
        < /etc/nginx/nginx.conf.template \
        > /etc/nginx/conf.d/default.conf

    echo "==> Certificate acquisition complete."
fi

# ---------------------------------------------------------------------------
# Start crond for twice-daily renewal, then run nginx in the foreground
# ---------------------------------------------------------------------------
echo "==> Starting crond for automatic certificate renewal..."
crond -b

echo "==> Starting nginx (${KIBANA_HOSTNAME})..."
exec nginx -g 'daemon off;'
