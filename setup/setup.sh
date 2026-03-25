#!/bin/sh
set -e

ES_URL="http://elasticsearch:9200"
KIBANA_URL="http://kibana:5601"
DATA_RETENTION_DAYS=${DATA_RETENTION_DAYS:-365}
SNAPSHOT_SCHEDULE=${SNAPSHOT_SCHEDULE:-"0 0 2 * * ?"}
SNAPSHOT_RETENTION_DAYS=${SNAPSHOT_RETENTION_DAYS:-30}

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
# Step 2: Create ILM policy for configurable retention
# ---------------------------------------------------------------------------
echo "==> Creating ILM policy (${DATA_RETENTION_DAYS}-day retention)..."
curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    -X PUT "${ES_URL}/_ilm/policy/dmarc-retention" \
    -H "Content-Type: application/json" \
    -d "{
      \"policy\": {
        \"phases\": {
          \"delete\": {
            \"min_age\": \"${DATA_RETENTION_DAYS}d\",
            \"actions\": { \"delete\": {} }
          }
        }
      }
    }"
echo ""
echo "    ILM policy created."

# ---------------------------------------------------------------------------
# Step 3: Create index templates so new parsedmarc indices get the ILM policy
# ---------------------------------------------------------------------------
echo "==> Creating index templates..."

for template in dmarc-aggregate:dmarc_aggregate dmarc-forensic:dmarc_forensic dmarc-smtp-tls:smtp_tls; do
    name="${template%%:*}"
    pattern="${template##*:}"
    curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
        -X PUT "${ES_URL}/_index_template/${name}" \
        -H "Content-Type: application/json" \
        -d "{
          \"index_patterns\": [\"${pattern}-*\"],
          \"template\": {
            \"settings\": {
              \"index.lifecycle.name\": \"dmarc-retention\"
            }
          }
        }"
    echo ""
done
echo "    Index templates created."

# ---------------------------------------------------------------------------
# Step 4: Create read-only kibana_viewer user (if password is provided)
# ---------------------------------------------------------------------------
if [ -n "${KIBANA_VIEWER_PASSWORD}" ]; then
    echo "==> Creating kibana_viewer user..."
    curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
        -X PUT "${ES_URL}/_security/user/kibana_viewer" \
        -H "Content-Type: application/json" \
        -d "{
          \"password\": \"${KIBANA_VIEWER_PASSWORD}\",
          \"roles\": [\"viewer\"],
          \"full_name\": \"Kibana Viewer\",
          \"email\": \"\"
        }"
    echo ""
    echo "    kibana_viewer user created."
else
    echo "==> Skipping kibana_viewer user (KIBANA_VIEWER_PASSWORD not set)."
fi

# ---------------------------------------------------------------------------
# Step 5: Register snapshot repository and SLM policy
# ---------------------------------------------------------------------------
echo "==> Registering snapshot repository..."
curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    -X PUT "${ES_URL}/_snapshot/dmarc_backup" \
    -H "Content-Type: application/json" \
    -d '{
      "type": "fs",
      "settings": {
        "location": "/usr/share/elasticsearch/snapshots"
      }
    }'
echo ""
echo "    Snapshot repository registered."

echo "==> Creating snapshot lifecycle policy (schedule: ${SNAPSHOT_SCHEDULE}, retention: ${SNAPSHOT_RETENTION_DAYS}d)..."
curl -sf -u "elastic:${ELASTIC_PASSWORD}" \
    -X PUT "${ES_URL}/_slm/policy/dmarc-daily-snapshot" \
    -H "Content-Type: application/json" \
    -d "{
      \"schedule\": \"${SNAPSHOT_SCHEDULE}\",
      \"name\": \"<dmarc-snapshot-{now/d}>\",
      \"repository\": \"dmarc_backup\",
      \"config\": {
        \"indices\": [\"dmarc_aggregate-*\", \"dmarc_forensic-*\", \"smtp_tls-*\"]
      },
      \"retention\": {
        \"expire_after\": \"${SNAPSHOT_RETENTION_DAYS}d\",
        \"min_count\": 5,
        \"max_count\": 50
      }
    }"
echo ""
echo "    Snapshot lifecycle policy created."

# ---------------------------------------------------------------------------
# Step 6: Wait for Kibana to become available
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
# Step 7: Download and import parsedmarc Kibana dashboards
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
