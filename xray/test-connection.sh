#!/bin/bash
# Tests whether the Xray/Reality server is reachable.
#
# Run from the project root:
#   bash xray/test-connection.sh
#
# Checks:
#   1. DNS resolves the domain
#   2. TCP port 443 is open
#   3. TLS handshake succeeds (Reality falls back to www.microsoft.com
#      for unauthenticated connections — cert subject should be microsoft.com)
#
# A passing test means the server is up and reachable.
# If it fails from the target region, the IP may be blocked.

set -e

source .credentials

if [ -z "$XRAY_DOMAIN" ]; then
  echo "Missing XRAY_DOMAIN in .credentials"
  exit 1
fi

PASS="[PASS]"
FAIL="[FAIL]"

echo "=== Testing $XRAY_DOMAIN ==="
echo ""

# 1. DNS
echo -n "1. DNS resolution ... "
IP=$(dig +short "$XRAY_DOMAIN" | tail -1)
if [ -z "$IP" ]; then
  echo "$FAIL could not resolve $XRAY_DOMAIN"
  exit 1
fi
echo "$PASS -> $IP"

# 2. TCP
echo -n "2. TCP port 443 ... "
if timeout 5 bash -c "echo >/dev/tcp/$XRAY_DOMAIN/443" 2>/dev/null; then
  echo "$PASS open"
else
  echo "$FAIL port 443 unreachable (IP may be blocked)"
  exit 1
fi

# 3. TLS / Reality fallback
echo -n "3. TLS handshake (Reality fallback) ... "
CERT=$(echo | timeout 5 openssl s_client \
  -connect "$XRAY_DOMAIN:443" \
  -servername www.microsoft.com \
  2>/dev/null | openssl x509 -noout -subject 2>/dev/null || true)
if echo "$CERT" | grep -qi "microsoft"; then
  echo "$PASS Reality is up (fallback cert: $CERT)"
else
  echo "$FAIL unexpected cert or no response: $CERT"
  exit 1
fi

echo ""
echo "=== All checks passed — server is reachable ==="
echo ""
echo "Quick browser test from any device (no app needed):"
echo "  https://$XRAY_DOMAIN"
echo ""
echo "Expected results:"
echo "  Cert warning (www.microsoft.com cert) -> server reachable, Reality"
echo "                                           fallback is working (OK)"
echo "  ERR_EMPTY_RESPONSE       -> server reachable, Reality rejected SNI (OK)"
echo "  ERR_CONNECTION_TIMED_OUT -> IP is blocked"
echo "  ERR_CONNECTION_REFUSED   -> server is down"
