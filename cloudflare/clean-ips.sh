#!/bin/bash
# Fetches current unblocked Cloudflare IPs per Iranian ISP.
# Source: ircf.space (DNS-based, resolvable from anywhere)
#
# Run from the project root: bash cloudflare/clean-ips.sh
#
# Use the IP for your friend's ISP with get-link.sh:
#   bash cloudflare/get-link.sh <ip>

set -e

if ! command -v dig &>/dev/null; then
  echo "Error: 'dig' is required. Install with: apt install dnsutils"
  exit 1
fi

resolve() {
  dig +short "$1" | grep -E '^[0-9]+\.' | head -1
}

echo "=== Clean Cloudflare IPs by Iranian ISP ==="
echo ""
echo "Cloudflare has thousands of IPs. Iran can only block some of them"
echo "without causing collateral damage to legitimate sites."
echo "ircf.space maintains one subdomain per Iranian ISP, each pointing"
echo "to a Cloudflare IP verified to be unblocked for that carrier."
echo "This script resolves those subdomains via DNS — no direct"
echo "connection to Iran needed. The list is always current."
echo ""

printf "%-20s %-30s %s\n" "ISP" "Subdomain" "IP"
printf "%-20s %-30s %s\n" "---" "---------" "--"

declare -A ISPS=(
  ["MCI (Hamrahe Avval)"]="mci.ircf.space"
  ["Irancell (MTN)"]="mtn.ircf.space"
  ["Mokhbarat / TCI"]="mkh.ircf.space"
  ["RighTel"]="rtl.ircf.space"
  ["Asiatech"]="ast.ircf.space"
  ["Shatel"]="sht.ircf.space"
  ["Shatel Mobile"]="shm.ircf.space"
  ["Pars Online"]="prs.ircf.space"
  ["Mobin Net"]="mbt.ircf.space"
  ["Respina"]="rsp.ircf.space"
  ["Afranet"]="afn.ircf.space"
  ["Pishgaman"]="psm.ircf.space"
  ["Zi-Tel"]="ztl.ircf.space"
  ["Sabanet"]="sbn.ircf.space"
  ["General"]="cname.ircf.space"
)

for ISP in "General" "MCI (Hamrahe Avval)" "Irancell (MTN)" \
           "Mokhbarat / TCI" "RighTel" "Asiatech" "Shatel" \
           "Shatel Mobile" "Pars Online" "Mobin Net" "Respina" \
           "Afranet" "Pishgaman" "Zi-Tel" "Sabanet"; do
  SUBDOMAIN="${ISPS[$ISP]}"
  IP=$(resolve "$SUBDOMAIN")
  printf "%-20s %-30s %s\n" "$ISP" "$SUBDOMAIN" "${IP:-not resolved}"
done

echo ""
echo "Usage: bash cloudflare/get-link.sh <ip>"
echo "Example: bash cloudflare/get-link.sh $(resolve mci.ircf.space)"
