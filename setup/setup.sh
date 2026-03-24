#!/bin/sh
set -e

ES_URL="http://elasticsearch:9200"
KIBANA_URL="http://kibana:5601"

# ---------------------------------------------------------------------------
# Step 1: Set the kibana_system user password
# ---------------------------------------------------------------------------
echo "==> Setting kibana_system password..."
until curl -sf -o /dev/null -w "%{http_code}" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -X POST "${ES_URL}/_security/user/kibana_system/_password" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}" | grep -q "^200$"
do
    echo "    Retrying in 5s..."
    sleep 5
done
echo "    kibana_system password set."

# ---------------------------------------------------------------------------
# Step 2: Create ILM policy for 1-year retention
# ---------------------------------------------------------------------------
echo "==> Creating ILM policy (1-year retention)..."
curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    -X PUT "${ES_URL}/_ilm/policy/dmarc-retention-1year" \
    -H "Content-Type: application/json" \
    -d @/setup/ilm-policy.json
echo ""
echo "    ILM policy created."

# ---------------------------------------------------------------------------
# Step 3: Create index templates so new parsedmarc indices get the ILM policy
# ---------------------------------------------------------------------------
echo "==> Creating index templates..."

curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    -X PUT "${ES_URL}/_index_template/dmarc-aggregate" \
    -H "Content-Type: application/json" \
    -d '{
      "index_patterns": ["dmarc_aggregate-*"],
      "template": {
        "settings": {
          "index.lifecycle.name": "dmarc-retention-1year"
        }
      }
    }'
echo ""

curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    -X PUT "${ES_URL}/_index_template/dmarc-forensic" \
    -H "Content-Type: application/json" \
    -d '{
      "index_patterns": ["dmarc_forensic-*"],
      "template": {
        "settings": {
          "index.lifecycle.name": "dmarc-retention-1year"
        }
      }
    }'
echo ""

curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    -X PUT "${ES_URL}/_index_template/dmarc-smtp-tls" \
    -H "Content-Type: application/json" \
    -d '{
      "index_patterns": ["smtp_tls-*"],
      "template": {
        "settings": {
          "index.lifecycle.name": "dmarc-retention-1year"
        }
      }
    }'
echo ""
echo "    Index templates created."

# ---------------------------------------------------------------------------
# Step 4: Wait for Kibana to become available
# ---------------------------------------------------------------------------
echo "==> Waiting for Kibana..."
until curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    "${KIBANA_URL}/api/status" | grep -q '"level":"available"'
do
    echo "    Kibana not ready yet, retrying in 10s..."
    sleep 10
done
echo "    Kibana is available."

# ---------------------------------------------------------------------------
# Step 5: Download and import parsedmarc Kibana dashboards
# ---------------------------------------------------------------------------
echo "==> Downloading parsedmarc Kibana dashboards..."
if curl -sf -L -o /tmp/export.ndjson \
    "https://raw.githubusercontent.com/domainaware/parsedmarc/master/kibana/export.ndjson"; then

    echo "==> Importing dashboards into Kibana..."
    curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
        -X POST "${KIBANA_URL}/api/saved_objects/_import?overwrite=true" \
        -H "kbn-xsrf: true" \
        -F "file=@/tmp/export.ndjson"
    echo ""
    echo "    Dashboards imported successfully."
else
    echo "    WARNING: Could not download parsedmarc dashboards from GitHub."
    echo "    Import manually: Kibana > Stack Management > Saved Objects > Import"
    echo "    File: https://raw.githubusercontent.com/domainaware/parsedmarc/master/kibana/export.ndjson"
fi

echo ""
echo "==> Setup complete!"
