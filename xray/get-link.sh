#!/bin/bash
# Prints the v2rayNG connection link for the Xray/DigitalOcean server.
# Usage: bash xray/get-link.sh [config-name]
# If config-name is omitted, a random name is generated.

set -e

CONFIG_NAME=${1:-}

source .credentials
CUSTOM_DOMAIN="do-$DOMAIN_SUFFIX"

if [ -z "$UUID" ] || [ -z "$DOMAIN_SUFFIX" ]; then
  echo "Missing UUID or DOMAIN_SUFFIX in .credentials"
  exit 1
fi

CONFIG_NAME=${CONFIG_NAME:-do-$DOMAIN_SUFFIX}

LINK="vless://$UUID@$CUSTOM_DOMAIN:5050?type=tcp&encryption=none&path=%2F&host=cloudflare.com&headerType=http&security=tls&fp=chrome&alpn=h2%2Chttp%2F1.1&sni=$CUSTOM_DOMAIN#$CONFIG_NAME"

echo "=== v2rayNG Connection Info (DigitalOcean + TLS) ==="
echo ""
echo "Import this link (tap + -> Import from clipboard):"
echo ""
echo "$LINK"
echo ""
echo "--- Manual settings ---"
echo "  Address    : $CUSTOM_DOMAIN"
echo "  Port       : 5050"
echo "  UUID       : $UUID"
echo "  Encryption : none"
echo "  Transport  : TCP"
echo "  Header     : HTTP obfuscation (host: cloudflare.com)"
echo "  Security   : TLS"
echo "  SNI        : $CUSTOM_DOMAIN"
echo "  Fingerprint: chrome"
