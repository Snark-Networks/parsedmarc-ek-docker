FROM nginx:alpine

# certbot for Let's Encrypt, openssl for self-signed bootstrap cert,
# gettext for envsubst (template rendering).
RUN apk add --no-cache certbot openssl gettext

# Remove the default nginx config
RUN rm -f /etc/nginx/conf.d/default.conf

# Config templates
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY nginx-acme-only.conf.template /etc/nginx/nginx-acme-only.conf.template

# Certbot renewal crontab (runs twice daily)
COPY crontab /etc/crontabs/root

# Create webroot used by certbot's webroot authenticator
RUN mkdir -p /var/www/certbot

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
