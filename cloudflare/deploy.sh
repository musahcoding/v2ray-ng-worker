#!/bin/bash
# Deploys the Cloudflare Worker, sets the UUID secret, and attaches
# the custom domain. Run from the project root: bash cloudflare/deploy.sh

set -e

source .credentials
CUSTOM_DOMAIN="cf-$DOMAIN_SUFFIX"

if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$UUID" ] || [ -z "$DOMAIN_SUFFIX" ]; then
  echo "Missing CLOUDFLARE_API_TOKEN, UUID or DOMAIN_SUFFIX in .credentials"
  exit 1
fi

# ── wrangler.toml ────────────────────────────────────────────────────────────
if [ ! -f cloudflare/wrangler.toml ]; then
  echo "=== Creating cloudflare/wrangler.toml from dist ==="
  sed "s|your-subdomain.yourdomain.com|$CUSTOM_DOMAIN|g" \
    cloudflare/wrangler.toml.dist > cloudflare/wrangler.toml
fi

# ── Deploy ───────────────────────────────────────────────────────────────────
echo "=== Deploying Cloudflare Worker ==="
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN \
  npx wrangler deploy --config cloudflare/wrangler.toml

# ── UUID secret ──────────────────────────────────────────────────────────────
echo "=== Setting UUID secret ==="
echo "$UUID" | CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN \
  npx wrangler secret put UUID --config cloudflare/wrangler.toml

echo ""
echo "=== Done! ==="
echo ""
echo "Connection info page:"
echo "  https://$CUSTOM_DOMAIN/$UUID"
