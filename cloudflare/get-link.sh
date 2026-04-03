#!/bin/bash
# Prints the v2rayNG connection link for the Cloudflare Worker.
# Usage: bash cloudflare/get-link.sh [clean-ip] [config-name]
#
# clean-ip   : unblocked Cloudflare IP for the friend's ISP
#              (see cloudflare/clean-ips.sh to get the list)
#              If omitted, the domain is used as the address.
# config-name: label shown in v2rayNG (random if omitted)

set -e

CLEAN_IP=${1:-}
CONFIG_NAME=${2:-}

source .credentials
CUSTOM_DOMAIN="cf-$DOMAIN_SUFFIX"

if [ -z "$UUID" ] || [ -z "$DOMAIN_SUFFIX" ]; then
  echo "Missing UUID or DOMAIN_SUFFIX in .credentials"
  exit 1
fi

CONFIG_NAME=${CONFIG_NAME:-cf-$DOMAIN_SUFFIX}

if [ -n "$CLEAN_IP" ]; then
  ADDRESS="$CLEAN_IP"
  echo "Using clean IP: $CLEAN_IP (SNI/host will remain $CUSTOM_DOMAIN)"
else
  ADDRESS="$CUSTOM_DOMAIN"
fi

LINK="vless://$UUID@$ADDRESS:443?encryption=none&security=tls&sni=$CUSTOM_DOMAIN&fp=chrome&type=ws&host=$CUSTOM_DOMAIN&path=%2Fvless#$CONFIG_NAME"

echo "=== v2rayNG Connection Info (Cloudflare Worker) ==="
echo ""
echo "Import this link (tap + -> Import from clipboard):"
echo ""
echo "$LINK"
echo ""
echo "--- Manual settings ---"
echo "  Address    : $ADDRESS"
echo "  Port       : 443"
echo "  UUID       : $UUID"
echo "  Encryption : none"
echo "  Transport  : WebSocket"
echo "  Path       : /vless"
echo "  TLS        : TLS"
echo "  SNI        : $CUSTOM_DOMAIN"
echo "  Host header: $CUSTOM_DOMAIN"
echo "  Fingerprint: chrome"
echo ""
echo "--- Or visit in browser ---"
echo "  https://$CUSTOM_DOMAIN/$UUID"
if [ -n "$CLEAN_IP" ]; then
  echo "  (browser always uses the domain — requires $CUSTOM_DOMAIN to be reachable)"
fi
