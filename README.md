# v2ray-ng-worker

Two VLESS proxy setups for v2rayNG to bypass internet censorship.

| Setup        | Transport                    | Port | Folder        |
|--------------|------------------------------|------|---------------|
| Cloudflare   | WebSocket + TLS              | 443  | `cloudflare/` |
| DigitalOcean | TCP + HTTP obfuscation + TLS | 5050 | `xray/`       |

Both use the same UUID — stored in `.credentials`, never hardcoded.

---

## How each method works

### Cloudflare Worker

Your device connects to a Cloudflare edge server over a standard HTTPS
WebSocket. Cloudflare forwards the traffic to the target site. Because
the connection looks like ordinary HTTPS to port 443, it passes through
most firewalls.

The weakness: some regions block specific Cloudflare IP ranges. If the
IP your domain resolves to is blocked, connections will time out.

### DigitalOcean + Xray

Your device connects directly to a VPS you control. The traffic is
wrapped in TCP with HTTP header obfuscation — it looks like a plain
HTTP request to `cloudflare.com`, which firewalls tend to avoid
blocking to prevent collateral damage. A non-standard port (5050)
also reduces deep packet inspection scrutiny compared to port 443.

The weakness: if the server IP gets blocked, you need to reprovision
or reassign the IP.

### Why a custom domain is required

Cloudflare's default `*.workers.dev` domain is blocked in several
regions. A custom domain on your own zone resolves to different
Cloudflare IPs that are more likely to be reachable. For the
DigitalOcean setup, a domain is required to obtain a TLS certificate
from Let's Encrypt (which needs a valid DNS record).

---

## API tokens

### Cloudflare API token

1. Go to [dash.cloudflare.com](https://dash.cloudflare.com) →
   **My Profile** → **API Tokens** → **Create Token**
2. Use **Create Custom Token**
3. Add these permissions:

   | Resource                  | Permission |
   |---------------------------|------------|
   | Account / Workers Scripts | Edit       |
   | Zone / Workers Routes     | Edit       |
   | Zone / DNS                | Edit       |

4. Under **Zone Resources** select your domain
5. Click **Continue to summary** → **Create Token**
6. Copy the token into `.credentials` as `CLOUDFLARE_API_TOKEN`

To find your **Account ID**: go to Workers & Pages — it is listed in
the right sidebar.

### DigitalOcean API token

1. Go to [cloud.digitalocean.com](https://cloud.digitalocean.com) →
   **API** → **Tokens** → **Generate New Token**
2. Give it a name (e.g. `v2ray-provisioner`)
3. Select **Full Access** (needs read + write to create droplets and
   SSH keys)
4. Click **Generate Token**
5. Copy the token into `.credentials` as `DIGITALOCEAN_TOKEN`

---

## Credentials file

Copy `.credentials-dist` to `.credentials` and fill in all fields.
This file is gitignored and never committed.

| Field                   | Description                                  |
|-------------------------|----------------------------------------------|
| `CLOUDFLARE_API_TOKEN`  | Cloudflare API token (see above)             |
| `CLOUDFLARE_ACCOUNT_ID` | Found on Workers & Pages sidebar             |
| `UUID`                  | Your VLESS UUID (shared by both setups)      |
| `DOMAIN_SUFFIX`         | Base domain; scripts prepend `cf-` or `do-` |
| `DIGITALOCEAN_TOKEN`    | DigitalOcean API token (see above)           |

Generate a UUID at [uuidgenerator.net](https://www.uuidgenerator.net/).

---

## Cloudflare Worker

### Deploy

```bash
npx wrangler login        # one-time browser login
bash cloudflare/deploy.sh
```

### Get the connection link

```bash
bash cloudflare/get-link.sh              # uses domain as address
bash cloudflare/clean-ips.sh             # find clean IP for friend's ISP
bash cloudflare/get-link.sh <clean-ip>   # use clean IP (if domain is blocked)
```

The config name in v2rayNG defaults to `cf-<domain>`. Pass a second
argument to override it.

The browser link (`https://<CUSTOM_DOMAIN>/<UUID>`) always uses the
domain — browsers cannot use a different address and SNI separately.

### Destroy

```bash
bash cloudflare/destroy.sh
```

### Deploy via dashboard (manual alternative)

1. Go to [Cloudflare Workers](https://dash.cloudflare.com) →
   Workers & Pages → Create Worker
2. Paste `cloudflare/worker.js` into the editor
3. Make sure the format is set to **ES Module** (not Service Worker)
4. Deploy
5. Worker → **Settings** → **Variables and Secrets** → **Add Secret**
   Name: `UUID`, Value: your UUID → Deploy
6. Worker → **Settings** → **Domains & Routes** → **Add** →
   **Custom domain** → enter your subdomain → Save

---

## Xray / DigitalOcean Server

### Provision

Creates the droplet, DNS record, installs Xray, and gets a TLS cert:

```bash
bash xray/provision.sh
```

### Get the connection link

```bash
bash xray/get-link.sh
```

The config name in v2rayNG defaults to `do-<domain>`. Pass an argument
to override it.

### Destroy all resources

Deletes the droplet, SSH key, DNS record, and local key files:

```bash
bash xray/destroy.sh
```

---

## Connect with v2rayNG

### Android

1. Install [v2rayNG](https://github.com/2dust/v2rayNG/releases) from
   GitHub or Google Play
2. Run `bash cloudflare/get-link.sh` or `bash xray/get-link.sh`
3. Copy the `vless://` link
4. In v2rayNG tap **+** → **Import config from clipboard**
5. Tap the config to select it
6. Tap the connect button (bottom right)

### iPhone (iOS)

v2rayNG is not available on iOS. Use **Shadowrocket** instead:

1. Install [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)
   from the App Store (paid app, requires an account in a supported
   region)
2. Run `bash cloudflare/get-link.sh` or `bash xray/get-link.sh`
3. Copy the `vless://` link
4. In Shadowrocket tap **+** (top right) → the link is auto-detected,
   tap **Done**
5. Enable the toggle next to the config and tap **Connect**

---

## Security

| What             | Detail                                              |
|------------------|-----------------------------------------------------|
| Auth             | UUID validated on every connection                  |
| CF config page   | Only accessible at `/<UUID>`, everything else → 404 |
| UUID             | Keep it private — it is the only credential         |
| Credentials file | Gitignored — never committed                        |
