#!/bin/bash
# Destroys all provisioned resources on DigitalOcean and Cloudflare.
# Run from the project root: bash xray/destroy.sh
#
# Removes:
#   - DigitalOcean droplet (v2ray-xray)
#   - DigitalOcean SSH key (v2ray-do-server)
#   - Cloudflare DNS A record (proxy.aboutafg.com)
#   - Local SSH key files (xray/.do_ssh_key*)

set -e

source .credentials

echo "=== This will permanently destroy:"
echo "    - DigitalOcean droplet: v2ray-xray"
echo "    - DigitalOcean SSH key: v2ray-do-server"
echo "    - Cloudflare DNS record: $CUSTOM_DOMAIN"
echo "    - Local SSH keys: xray/.do_ssh_key*"
echo ""
read -p "Type 'yes' to confirm: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# ── Droplet ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Deleting DigitalOcean droplet ==="
DROPLET_ID=$(curl -s "https://api.digitalocean.com/v2/droplets?tag_name=v2ray" \
  -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
  | jq -r '.droplets[] | select(.name=="v2ray-xray") | .id')

if [ -n "$DROPLET_ID" ] && [ "$DROPLET_ID" != "null" ]; then
  curl -s -X DELETE "https://api.digitalocean.com/v2/droplets/$DROPLET_ID" \
    -H "Authorization: Bearer $DIGITALOCEAN_TOKEN"
  echo "Droplet $DROPLET_ID deleted."
else
  echo "No droplet found, skipping."
fi

# ── SSH key ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Deleting DigitalOcean SSH key ==="
KEY_ID=$(curl -s "https://api.digitalocean.com/v2/account/keys" \
  -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
  | jq -r '.ssh_keys[] | select(.name=="v2ray-do-server") | .id')

if [ -n "$KEY_ID" ] && [ "$KEY_ID" != "null" ]; then
  curl -s -X DELETE "https://api.digitalocean.com/v2/account/keys/$KEY_ID" \
    -H "Authorization: Bearer $DIGITALOCEAN_TOKEN"
  echo "SSH key $KEY_ID deleted."
else
  echo "No SSH key found, skipping."
fi

# ── Cloudflare DNS ───────────────────────────────────────────────────────────
echo ""
echo "=== Deleting Cloudflare DNS record: $CUSTOM_DOMAIN ==="
SUBDOMAIN=$(echo "$CUSTOM_DOMAIN" | cut -d. -f1)
ZONE=$(echo "$CUSTOM_DOMAIN" | cut -d. -f2-)
ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=$ZONE" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | jq -r '.result[0].id')

RECORD_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$CUSTOM_DOMAIN" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | jq -r '.result[0].id')

if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
  curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '{success, errors}'
  echo "DNS record $CUSTOM_DOMAIN deleted."
else
  echo "No DNS record found, skipping."
fi

# ── Local SSH keys ───────────────────────────────────────────────────────────
echo ""
echo "=== Removing local SSH keys ==="
rm -f xray/.do_ssh_key xray/.do_ssh_key.pub
echo "Local SSH keys removed."

echo ""
echo "=== Done. All resources destroyed. ==="
