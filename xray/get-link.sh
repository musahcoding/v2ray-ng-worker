#!/bin/bash
# Prints the v2rayNG connection link for the Xray/DigitalOcean server.
# Usage: bash xray/get-link.sh [config-name]
# If config-name is omitted, a random name is generated.

set -e

CONFIG_NAME=${1:-xray-$(openssl rand -hex 3)}

source .credentials

if [ -z "$UUID" ] || [ -z "$XRAY_DOMAIN" ]; then
  echo "Missing UUID or XRAY_DOMAIN in .credentials"
  exit 1
fi

LINK="vless://$UUID@$XRAY_DOMAIN:5050?type=tcp&encryption=none&path=%2F&host=cloudflare.com&headerType=http&security=tls&fp=chrome&alpn=h2%2Chttp%2F1.1&sni=$XRAY_DOMAIN#$CONFIG_NAME"

echo "=== v2rayNG Connection Info (DigitalOcean + TLS) ==="
echo ""
echo "Import this link (tap + -> Import from clipboard):"
echo ""
echo "$LINK"
echo ""
echo "--- Manual settings ---"
echo "  Address    : $XRAY_DOMAIN"
echo "  Port       : 5050"
echo "  UUID       : $UUID"
echo "  Encryption : none"
echo "  Transport  : TCP"
echo "  Header     : HTTP obfuscation (host: cloudflare.com)"
echo "  Security   : TLS"
echo "  SNI        : $XRAY_DOMAIN"
echo "  Fingerprint: chrome"
