#!/bin/sh
set -e

# Map the positional arguments passed by qBittorrent
HASH="$1"
NAME="$2"
TAGS="$3"
CONTENT_PATH="$4"

# Define the target n8n webhook URL
WEBHOOK_URL="http://n8n-ui.automation.svc.cluster.local:5678/webhook/$WEBHOOK_ID"

# Ensure the secret was successfully injected from the Kubernetes Secret
if [ -z "$WEBHOOK_SECRET" ]; then
  echo "[ERROR] WEBHOOK_SECRET environment variable is missing!" >&2
  exit 1
fi

if [ -z "$WEBHOOK_ID" ]; then
  echo "[ERROR] WEBHOOK_ID environment variable is missing!" >&2
  exit 1
fi

echo "Sending completion webhook to n8n for: $NAME"

# Fire the request
curl -sS --fail -X POST "$WEBHOOK_URL" \
  -H "X-n8n-Webhook-Secret: $WEBHOOK_SECRET" \
  --form-string "hash=$HASH" \
  --form-string "name=$NAME" \
  --form-string "tags=$TAGS" \
  --form-string "path=$CONTENT_PATH"
