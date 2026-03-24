#!/bin/sh
set -e

echo "Generating parsedmarc config from environment..."
envsubst < /etc/parsedmarc.ini.template > /etc/parsedmarc.ini

echo "Starting parsedmarc..."
exec parsedmarc -c /etc/parsedmarc.ini
