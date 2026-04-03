#!/bin/bash
# Xray VLESS server setup script.
# Installs Xray-core on a fresh Ubuntu 24.04 server and configures
# VLESS over TCP with HTTP obfuscation and TLS.
#
# Usage (run from project root):
#   bash xray/setup.sh <domain> <uuid> [config-name]
#
# If config-name is omitted, a random name is generated.
#
# Requirements:
#   - Ubuntu 24.04
#   - Domain DNS A record already pointing to this server's IP
#   - Ports 22, 80, and 5050 open

set -e

DOMAIN=$1
UUID=$2
PORT=5050
CONFIG_NAME=${3:-xray-$(openssl rand -hex 3)}

if [ -z "$DOMAIN" ] || [ -z "$UUID" ]; then
  echo "Usage: bash xray/setup.sh <domain> <uuid> [config-name]"
  exit 1
fi

echo "=== Installing dependencies ==="
apt-get update -y
apt-get install -y curl ufw certbot

echo "=== Configuring firewall ==="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow $PORT/tcp
ufw --force enable

echo "=== Installing Xray ==="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo "=== Obtaining TLS certificate ==="
systemctl stop xray 2>/dev/null || true
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
  --register-unsafely-without-email

echo "=== Writing Xray config ==="
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
            }
          ],
          "alpn": ["h2", "http/1.1"]
        },
        "tcpSettings": {
          "header": {
            "type": "http",
            "request": {
              "version": "1.1",
              "method": "GET",
              "path": ["/"],
              "headers": {
                "Host": ["cloudflare.com"],
                "User-Agent": [
                  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                ],
                "Accept-Encoding": ["gzip, deflate"],
                "Connection": ["keep-alive"],
                "Pragma": "no-cache"
              }
            },
            "response": {
              "version": "1.1",
              "status": "200",
              "reason": "OK",
              "headers": {
                "Content-Type": ["application/octet-stream"],
                "Transfer-Encoding": ["chunked"],
                "Connection": ["keep-alive"],
                "Pragma": "no-cache"
              }
            }
          }
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
EOF

echo "=== Setting cert permissions for Xray (runs as nobody) ==="
chmod 755 /etc/letsencrypt/live /etc/letsencrypt/archive
chmod -R a+rX /etc/letsencrypt/live/$DOMAIN/
chmod -R a+rX /etc/letsencrypt/archive/$DOMAIN/

cat > /etc/letsencrypt/renewal-hooks/deploy/xray-reload.sh << 'HOOK'
#!/bin/bash
chmod 755 /etc/letsencrypt/live /etc/letsencrypt/archive
chmod -R a+rX /etc/letsencrypt/live/
chmod -R a+rX /etc/letsencrypt/archive/
systemctl reload xray
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/xray-reload.sh

echo "=== Starting Xray ==="
systemctl enable xray
systemctl restart xray
sleep 2
systemctl status xray --no-pager

echo ""
echo "=== Done! ==="
echo ""
echo "v2rayNG connection link:"
echo "vless://$UUID@$DOMAIN:$PORT?type=tcp&encryption=none&path=%2F&host=cloudflare.com&headerType=http&security=tls&fp=chrome&alpn=h2%2Chttp%2F1.1&sni=$DOMAIN#$CONFIG_NAME"
echo ""