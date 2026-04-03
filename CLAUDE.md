# CLAUDE.md

## Writing style

- Max line length: **80 characters** for prose, no limit for tables/code
- Tables: pad all columns so pipe characters align vertically; every
  cell must have at least one space before the closing `|`
- No trailing whitespace

## Project

Cloudflare Worker (`cloudflare/worker.js`) implementing VLESS over
WebSocket for use with v2rayNG. A separate Xray server setup lives in
`xray/` for a DigitalOcean droplet.

## Key facts

- **Format**: ES Module — required for `import`/`export` syntax
- **No build step**: plain JS, deployable via `npx wrangler deploy`
- `connect()` must be imported:
  `import { connect } from 'cloudflare:sockets'`
- `compatibility_date = "2024-01-01"` is required in `wrangler.toml`
  for `cloudflare:sockets` to be available
- The UUID is read from `env.UUID` — set as a Cloudflare Worker Secret,
  never hardcoded in source

## Endpoints

| Path          | Purpose                                      |
|---------------|----------------------------------------------|
| `/<UUID>`     | Returns the v2rayNG connection link (secret) |
| `/vless`      | VLESS WebSocket proxy endpoint               |
| anything else | 404                                          |

## VLESS protocol (in `parseVless`)

Header layout:

```
version(1) + uuid(16) + addonLen(1) + addons(n)
  + cmd(1) + port(2) + addrType(1) + addr(n)
```

| Field      | Value                                    |
|------------|------------------------------------------|
| `cmd`      | `1`=TCP, `2`=UDP (DNS forwarded via DoH) |
| `addrType` | `1`=IPv4, `2`=domain, `3`=IPv6           |
| Response   | `[0x00, 0x00]` sent back to client       |

## Write serialisation

Concurrent WebSocket message handlers can cause `WritableStreamDefaultWriter`
errors. All writes go through a promise chain
(`writeQueue = writeQueue.then(...)`) to serialise them.

## Deployment

Scripts (run from project root):

| File                     | Purpose                               |
|--------------------------|---------------------------------------|
| `cloudflare/deploy.sh`   | Deploy worker + set UUID secret       |
| `cloudflare/get-link.sh` | Print v2rayNG connection link         |
| `cloudflare/destroy.sh`  | Delete worker and custom domain route |

`deploy.sh` auto-creates `cloudflare/wrangler.toml` from the dist
template if it doesn't exist. Config in `cloudflare/wrangler.toml`
(gitignored — contains custom domain). Use `wrangler.toml.dist` as
the template.

```bash
npx wrangler deploy                 # deploy code
npx wrangler secret put UUID        # set/update UUID secret
```

Credentials for CI/scripted deploys go in `.credentials` (gitignored).
Use `.credentials-dist` as the template. Load with:

```bash
export $(grep CLOUDFLARE_API_TOKEN .credentials | xargs)
cd cloudflare && npx wrangler deploy
```

A custom domain is required — the default `workers.dev` domain is
blocked in the target region.

## Xray / DigitalOcean server

Lives in `xray/`. VLESS over TCP with HTTP obfuscation on port 5050.
Used when Cloudflare IPs are blocked in the target region.

| File                      | Purpose                                  |
|---------------------------|------------------------------------------|
| `setup.sh`                | Installs Xray + TLS cert on the server   |
| `provision.sh`            | Creates DO droplet + DNS, runs setup.sh  |
| `destroy.sh`              | Tears down droplet, DNS, local SSH keys  |
| `get-link.sh`             | Prints the v2rayNG connection link       |
| `server-config.json.dist` | Xray config template                     |

All scripts are run from the project root. They read from `.credentials`.

## Credentials

`.credentials` fields (gitignored — use `.credentials-dist` as template):

| Field                   | Used by                         |
|-------------------------|---------------------------------|
| `CLOUDFLARE_API_TOKEN`  | wrangler, provision, destroy    |
| `CLOUDFLARE_ACCOUNT_ID` | wrangler                        |
| `UUID`                  | both setups                     |
| `CUSTOM_DOMAIN`         | Cloudflare Worker custom domain |
| `DIGITALOCEAN_TOKEN`    | provision, destroy              |
| `XRAY_DOMAIN`           | provision, destroy, get-link    |

The CF API token needs: Workers:Edit + Zone:DNS:Edit permissions.
