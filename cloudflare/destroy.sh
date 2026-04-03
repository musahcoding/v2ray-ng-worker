#!/bin/bash
# Destroys the Cloudflare Worker and its custom domain route.
# Run from the project root: bash cloudflare/destroy.sh

set -e

source .credentials
CUSTOM_DOMAIN="cf-$DOMAIN_SUFFIX"

if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
  echo "Missing CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID in .credentials"
  exit 1
fi

WORKER_NAME=$(grep '^name' cloudflare/wrangler.toml 2>/dev/null \
  | head -1 | sed 's/name = "\(.*\)"/\1/')
WORKER_NAME=${WORKER_NAME:-vless-proxy}

echo "=== This will permanently destroy:"
echo "    - Cloudflare Worker: $WORKER_NAME"
echo "    - Custom domain route: $CUSTOM_DOMAIN"
echo ""
read -p "Type 'yes' to confirm: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# ── Delete worker ────────────────────────────────────────────────────────────
echo ""
echo "=== Deleting Cloudflare Worker: $WORKER_NAME ==="
RESULT=$(curl -s -X DELETE \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$WORKER_NAME" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | jq '{success, errors}')
echo "$RESULT"

# ── Delete custom domain DNS record ──────────────────────────────────────────
if [ -n "$CUSTOM_DOMAIN" ]; then
  echo ""
  echo "=== Deleting DNS record: $CUSTOM_DOMAIN ==="
  SUBDOMAIN=$(echo "$CUSTOM_DOMAIN" | cut -d. -f1)
  ZONE=$(echo "$CUSTOM_DOMAIN" | cut -d. -f2-)
  ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=$ZONE" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    | jq -r '.result[0].id')

  RECORD_ID=$(curl -s \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$CUSTOM_DOMAIN" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    | jq -r '.result[0].id')

  if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
    curl -s -X DELETE \
      "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '{success, errors}'
    echo "DNS record $CUSTOM_DOMAIN deleted."
  else
    echo "No DNS record found, skipping."
  fi
fi

echo ""
echo "=== Done. Cloudflare Worker destroyed. ==="
