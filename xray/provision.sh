#!/bin/bash
# Provisions a DigitalOcean droplet and runs setup.sh on it.
# Run this from the project root.
#
# Usage:
#   bash xray/provision.sh
#
# Reads from .credentials:
#   DIGITALOCEAN_TOKEN  - DO API token
#   UUID                - VLESS UUID (shared with Cloudflare worker)
#   XRAY_DOMAIN         - subdomain pointing to the droplet
#                         e.g. proxy.yourdomain.com

set -e

source .credentials

DOMAIN=${XRAY_DOMAIN}
SSH_KEY_FILE="xray/.do_ssh_key"
SSH_KEY_NAME="v2ray-do-server"
REGION="fra1"
SIZE="s-1vcpu-1gb"
IMAGE="ubuntu-24-04-x64"
DROPLET_NAME="v2ray-xray"

if [ -z "$DIGITALOCEAN_TOKEN" ] || [ -z "$UUID" ] || [ -z "$DOMAIN" ]; then
  echo "Missing DIGITALOCEAN_TOKEN, UUID or XRAY_DOMAIN in .credentials"
  exit 1
fi

# ── 1. SSH key ──────────────────────────────────────────────────────────────
if [ ! -f "$SSH_KEY_FILE" ]; then
  echo "=== Generating SSH key ==="
  ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -C "$SSH_KEY_NAME"
fi

PUB_KEY=$(cat "$SSH_KEY_FILE.pub")
KEY_ID=$(curl -s "https://api.digitalocean.com/v2/account/keys" \
  -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
  | jq -r ".ssh_keys[] | select(.public_key==\"$PUB_KEY\") | .id")

if [ -z "$KEY_ID" ]; then
  echo "=== Registering SSH key with DigitalOcean ==="
  KEY_ID=$(curl -s -X POST "https://api.digitalocean.com/v2/account/keys" \
    -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$SSH_KEY_NAME\",\"public_key\":\"$PUB_KEY\"}" \
    | jq -r '.ssh_key.id')
fi
echo "SSH key ID: $KEY_ID"

# ── 2. Create droplet ───────────────────────────────────────────────────────
echo "=== Creating droplet in $REGION ==="
DROPLET_ID=$(curl -s -X POST "https://api.digitalocean.com/v2/droplets" \
  -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$DROPLET_NAME\",
    \"region\": \"$REGION\",
    \"size\": \"$SIZE\",
    \"image\": \"$IMAGE\",
    \"ssh_keys\": [$KEY_ID],
    \"tags\": [\"v2ray\"]
  }" | jq -r '.droplet.id')
echo "Droplet ID: $DROPLET_ID"

# ── 3. Wait for IP ──────────────────────────────────────────────────────────
echo "Waiting for droplet to get an IP..."
IP=""
while [ -z "$IP" ] || [ "$IP" = "null" ]; do
  sleep 5
  IP=$(curl -s "https://api.digitalocean.com/v2/droplets/$DROPLET_ID" \
    -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
    | jq -r '.droplet.networks.v4[] | select(.type=="public") | .ip_address')
done
echo "Droplet IP: $IP"

# ── 4. Create DNS A record ──────────────────────────────────────────────────
echo "=== Creating DNS A record: $DOMAIN -> $IP ==="
SUBDOMAIN=$(echo "$DOMAIN" | cut -d. -f1)
ZONE=$(echo "$DOMAIN" | cut -d. -f2-)
ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=$ZONE" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | jq -r '.result[0].id')

curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"A\",
    \"name\": \"$SUBDOMAIN\",
    \"content\": \"$IP\",
    \"ttl\": 60,
    \"proxied\": false
  }" | jq '{success: .success, name: .result.name, content: .result.content}'

# ── 5. Wait for SSH ─────────────────────────────────────────────────────────
echo "Waiting for SSH to become available..."
sleep 30
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    -i "$SSH_KEY_FILE" root@"$IP" echo "SSH ready" 2>/dev/null; do
  sleep 5
done

# ── 6. Run setup.sh ─────────────────────────────────────────────────────────
echo "=== Running setup on server ==="
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_FILE" root@"$IP" \
  "bash -s $DOMAIN $UUID" < xray/setup.sh
