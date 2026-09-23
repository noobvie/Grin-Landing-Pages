---
title: Publish your node's API for wallets and explorers
description: How Script 04 puts your Grin node's public (Foreign) API behind nginx and HTTPS, adds a status page, REST endpoints and a Tor onion, and how to test it.
section: Scripts
order: 4
short: Node API
label: Script 04
covers: 2026-09-19
updated: 2026-09-20
---

Your node already answers questions about the chain — but only to programs on the same server. Script 04 opens that up: it puts the node's **public API** behind **nginx** (a web server) with a free HTTPS certificate, so a wallet or an explorer anywhere in the world can use your node at `https://api.yourdomain.com`. Optionally it adds a live status page, simple REST endpoints, and a Tor `.onion` address for people who do not want to reveal where they connect from. The sites [api.grin.money](https://api.grin.money) and [testapi.grin.money](https://testapi.grin.money) are exactly this script's output.

You need a running node from [Script 01](01-build-node.html), a domain name whose **A record** points at the server, and ports **80** and **443** open in your provider's firewall.

## What it does

1. Installs nginx and certbot if they are missing, and makes sure the rate-limit zones the toolkit shares between scripts exist.
2. Writes an nginx site for your domain that forwards **only** `/v2/foreign` to the node on `127.0.0.1:3413` (testnet `13413`). Every other path — including the management API at `/v2/owner` — is answered with **403**.
3. Reads the node's `.foreign_api_secret` and bakes it into the proxy as an `Authorization` header, so callers never need credentials and the secret never leaves the server.
4. Requests a Let's Encrypt certificate for the domain and reloads nginx with HTTPS enabled.
5. On request, deploys a static **status page** at `https://api.yourdomain.com/`, a set of **REST JSON files** under `/rest/` refreshed by cron every minute, and a **Tor hidden service** that reaches the same `/v2/foreign` endpoint over the Tor network.

Nothing here changes how the node itself runs. The node keeps listening on localhost; nginx is the only thing the internet talks to.

## Foreign API and Owner API

A Grin node has one HTTP port (3413) with two APIs on it, told apart by path:

| | Foreign API — `/v2/foreign` | Owner API — `/v2/owner` |
|--|--|--|
| What it answers | Public chain data: the current tip, blocks, headers, kernels, outputs, the mempool size — and `push_transaction`, which broadcasts a finished transaction | Management: node status and peer counts, chain validation and compaction |
| Who calls it | Wallets (to check balances and broadcast), explorers, dashboards, developers | You, and toolkit scripts on the same server |
| Protected by | `.foreign_api_secret` | `.api_secret` |
| Script 04 | **Publishes it**, with the secret injected by nginx | **Blocks it** — 403 from the internet |

Both files were created by Script 01 in the node directory (see [Getting started](getting-started.html#where-things-live-on-the-server)). The Foreign API is read-only apart from broadcasting transactions, which is why it is safe to share.

## Choices you will make

### Which network

The script asks first whether you are publishing the **mainnet** or the **testnet** node, and every later action applies to that network only. Each network gets its own domain (`api.` and `testapi.` are the convention), its own nginx site and, if you enable it, its own `.onion` address. Re-run the script and pick the other network to publish both.

### Mode A or Mode B

The menu offers two exclusive ways to expose the API. **Use Mode B, the nginx HTTPS proxy** — it is the one every other feature builds on, and it is the one this page describes.

> **Warning:** Mode A ("Raw TCP", keys `1`–`3`) should be treated as **not working** in the current code. It is meant to make the node itself listen on all interfaces and open port 3413 in the firewall, but it writes the setting `check_node_api_http_addr` into `grin-server.toml` — that is a grin-*wallet* setting; the node's bind address is called `api_http_addr`. The node keeps listening on localhost, the firewall port is opened anyway, and the menu reports the mode as ACTIVE (its own `3) Status` screen contradicts it with "LISTENING on 127.0.0.1 (localhost only)"). Even once fixed, raw mode would publish the *whole* API port in cleartext, including `/v2/owner` guarded only by `.api_secret` — the known limitation recorded as finding F1 in the toolkit's [Script 04 security audit](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script04_security_audit.md). Nothing on this page needs it. (This was found by reading the code, not on a live server — whether grin also objects to the unknown key at start-up is unverified.)

### Domain and subdomain

One subdomain per network, pointed at the server's IP before you start. The labels `fullmain`, `prunemain` and `prunetest` are refused because [Script 02](02-nginx-fileserver.html) uses them for chain-snapshot hosts. `api.yourdomain.com` and `testapi.yourdomain.com` are the pattern the demo sites follow.

## Before you start

| Need | Why |
|------|-----|
| A running node ([Script 01](01-build-node.html)) | The proxy forwards to it on `127.0.0.1:3413` / `13413`. Script 04 finds the node directory — and its `.foreign_api_secret` — through the instances file Script 01 wrote in `/opt/grin/conf/`, falling back to the standard paths under `/opt/grin/node/`. It warns and lets you continue if the port is not listening, but nothing works until the node is up |
| A domain with an **A record** pointing at this server | Let's Encrypt validates the domain over HTTP on port 80 |
| Ports **80** and **443** open at the provider | 80 for certificate issuance and renewal, 443 for the API itself |
| An email address | Let's Encrypt's expiry notices |
| `tor` installed and running — only for the onion (`T`) | The script asks whether to continue without it; the onion cannot be published until Tor runs |

nginx and certbot are installed by the script itself if absent (the packages `nginx`, `certbot` and `python3-certbot-nginx`).

## The menu

The first screen is the network choice. It shows whether each node is currently listening:

```text
  04) Grin Node API Services Manager

  1) Mainnet API  (node RUNNING, port 3413)
  2) Testnet API  (node down, port 13413)

  0) Back to main menu

Select network [1/2/0]:
```

The second screen is the real menu for that network. It begins with a status block — node, proxy, auth header, status page, REST, Tor — and every key's label changes to reflect what is already installed:

```text
  04) Grin Node API Services  [Mainnet]

Status:

  Grin node   : RUNNING  (port 3413)
  raw TCP     : disabled  (option 1)
  nginx proxy : not configured  (option 4)
  status page : not deployed  (option 6)
  REST API    : not deployed  (option 8)
  Tor onion   : disabled  (option T)

  ╔══════════════════════════════════════════════════╗
  ║  IMPORTANT — Choose ONE mode only.               ║
  ║  Activating both modes will cause port conflicts.║
  ╚══════════════════════════════════════════════════╝

  ─── MODE A: Raw TCP Direct Access ──────────────────
  1) Enable Raw TCP       (opens port 3413, patches grin-server.toml)
  2) Disable Raw TCP      (nothing active)
  3) Status Raw TCP       (show current bind address + firewall rule)

  ─── MODE B: nginx HTTPS Proxy ───────────────────────
  4) Enable via nginx     (/v2/foreign, HTTPS + Let's Encrypt)
  5) Remove nginx proxy

  ─── Live Status Page (requires option 4) ─────────────
  6) Deploy / Update page (requires option 4 first)
  7) Remove status page

  ─── REST API /rest/*.json (requires option 6) ────────
  8) Enable REST API      (requires option 6 first)
  9) Disable REST API      (removes cron + JSON files)

  ─── Tor onion /v2/foreign (requires option 4) ────────
  T) Enable Tor onion     (requires option 4 first)
  U) Disable Tor onion    (removes nginx listener + torrc stanza)
  V) Backup onion identity (→ /opt/grin/backups/grin_tor_onion_<net>.tar.gz)

  ↩  Press Enter to refresh status
  0) Back to network select

Select [1-9 / T / U / V / 0]:
```

| Key | Action |
|-----|--------|
| `4` | **Set up the HTTPS proxy** — the main action, [step by step below](#setting-up-the-https-proxy-step-by-step). Re-running it lets you change the domain; the status page and REST endpoints are re-applied automatically afterwards |
| `5` | Remove the proxy. Also removes the Tor listener and the status page files, because neither can work without it |
| `6` | Deploy the [status page](#the-status-page) at `https://api.yourdomain.com/`, or push the latest page files if it is already deployed |
| `7` | Remove the status page (and the REST endpoints, which depend on it) |
| `8` | Enable the [REST endpoints](#the-rest-endpoints) under `/rest/` |
| `9` | Disable them — removes the cron jobs and the JSON files |
| `T` | Publish the API as a [Tor onion](#the-tor-onion) — first time, choose a new address or recover one from backup |
| `U` | Disable the onion; the identity key stays on disk so `T` brings the same address back |
| `V` | Snapshot the onion identity to `/opt/grin/backups/grin_tor_onion_<network>.tar.gz` |
| `1` / `2` / `3` | Mode A — see the warning above |
| `Enter` | Refresh the status block |
| `0` | Back to the network choice |

The order matters: `4` first, then `6`, then `8`; `T` any time after `4`. Every action is logged under `/opt/grin/logs/` as `grin_node_services_<date>.log`.

## Setting up the HTTPS proxy, step by step

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | A **port guide** explains what port 3413 is, who needs it and who should skip it | `Enter` (or `Y`) to continue, `n` or `0` to cancel |
| 2 | Checks for nginx and certbot; offers to install what is missing | `Y` |
| 3 | Checks that the node is listening on its port | If it is not: `Y` to continue anyway, `n` or `0` to stop and start the node first |
| 4 | Asks for the domain | Type `api.yourdomain.com` (DNS must already point here) |
| 5 | Asks for an email for Let's Encrypt | Type it |
| 6 | Finds the node directory and reads `.foreign_api_secret`; encodes it as the `Authorization` header nginx will send to the node | Nothing. If the file is missing you get a warning and a config **without** the header — see [Troubleshooting](#troubleshooting) |
| 7 | Removes leftovers from older versions of the script, makes sure `sites-enabled` is included by `nginx.conf`, creates the rate-limit zones in `/etc/nginx/conf.d/`, and writes a Cloudflare real-IP snippet (harmless if you do not use Cloudflare) | Nothing |
| 8 | Writes the **HTTP-only** site to `/etc/nginx/sites-available/grin-node-api` (`-testnet` for testnet), a logrotate rule for its log files, enables it, runs `nginx -t` and reloads | Nothing |
| 9 | Installs the 5-minute **secret self-heal** timer (`grin-secret-sync`) so the header in step 6 is re-embedded if the node directory ever moves | Nothing |
| 10 | Runs `certbot --nginx` for the domain. certbot edits the site to add the certificate and the HTTPS listener | Wait — a minute or so. If it fails, the script stops here with the reason (usually DNS or port 80) |
| 11 | If a status page or REST endpoints were active before (a re-run), re-applies them, tests and reloads nginx | Nothing |
| 12 | Prints the endpoint, the config path and two `curl` test commands | Copy the tests — [After it finishes](#after-it-finishes) |

What the site does, in plain terms: a `POST` to `/v2/foreign` on your domain is forwarded to the node with the secret attached; browsers are allowed to call it from any website (**CORS** `*`); each visitor IP is limited to **300 requests per minute** (a burst of 200 is tolerated) and **20 simultaneous connections**; request bodies are capped at **8 KB**; the node has **60 seconds** to answer. Over the limit, nginx refuses the request with an HTTP error (**503**) instead of passing it on. Everything else returns **403** with the message *Access denied. Only /v2/foreign is exposed.*

> **Note:** The rate-limit zone `grin_api` is **shared** with the network dashboard of Script 06 when both run on one server — a visitor's requests to the API and to the dashboard count against the same 300-per-minute budget. Both zones live in `/etc/nginx/conf.d/` — `grin-rate-limit.conf` and `grin-conn-limit.conf`.

## The status page

`6` copies a small static site from the toolkit's `web/04_node_api/public_html/` to `/var/www/grin-node-api/` (`-testnet`) and changes the nginx site so `/` serves it. It costs the server nothing per visitor: the page is plain HTML and JavaScript that calls `/v2/foreign` from the visitor's own browser, refreshing every 60 seconds.

What a visitor sees at `https://api.yourdomain.com/`:

- **Live cards** — block height, total difficulty, latest block hash, circulating supply (height × 60), emission rate, node version, header version, and the round-trip time of the last `get_tip`. Connected peers and chain-data size come from the REST collector, so they fill in once `8` is enabled.
- **Wallet connection cards** with copy buttons — for `grin-wallet.toml`, for the Grim GUI wallet, and for Tor (the Tor card shows the real `.onion` once `T` has run; `T` rewrites `config.js` in the deployed page).
- **A REST section** listing the endpoints with their status.
- **Developer tools** — a "Run Test" button that fires `get_tip` from the browser, a CORS test, and a `fetch()` snippet to paste into any website's console.
- Four themes: dark, light, "Matrix" and "Windows XP".

The nginx patch also adds security headers (`nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy`, a Content-Security-Policy), blocks dotfiles, and tells browsers to re-check HTML and JS on every load so the Tor card never shows a stale address. Run `6` again after updating the toolkit to push a newer page.

## The REST endpoints

Not everything speaks JSON-RPC. `8` adds plain `GET` URLs that return small JSON documents, meant for spreadsheets, widgets, price sites and no-code tools:

| URL | Contents |
|-----|----------|
| `/rest/stats.json` | Height, supply, difficulty, latest hash, node and header versions |
| `/rest/supply.json` | Circulating supply only (height × 60 — Grin emits 1 GRIN per second, forever) |
| `/rest/height.json` | Block height only |
| `/rest/difficulty.json` | Total network difficulty only |
| `/rest/emission.json` | The emission schedule — static |
| `/rest/node.json` | Connected peers, chain-data size in MB, archive mode |

They are static files, rewritten **every minute** by two cron jobs and served with `Cache-Control: max-age=60` and CORS `*`:

- `/etc/cron.d/grin-node-api-rest` runs `rest-collector.py` as the nginx web user (`www-data` on Ubuntu). It calls the node's Foreign API, so the script makes `.foreign_api_secret` readable by that user (`root:www-data`, mode 640).
- `/etc/cron.d/grin-node-api-node` runs `node-collector.py` as **root**, because peers come from the Owner API (`.api_secret`) and chain size from `du` on `chain_data/`. It writes `node.json` with mode 644 so nginx can serve it.

Both collectors are installed to `/opt/grin/grin-api-collector/`; the JSON lands in `/var/www/grin-node-api/rest/`. The script runs each collector once immediately, so the files exist before nginx starts serving them. The status page must be deployed first (`6`) — the REST rules are inserted into the nginx site block that the status page creates.

## The Tor onion

`T` gives the same API a `.onion` address, for wallets that connect through Tor and for anyone who prefers not to show the API host where they are connecting from. It works like this: nginx gets a second, **localhost-only** listener on `127.0.0.1:8413` (testnet `18413`) that proxies `/v2/foreign` with the secret injected, exactly like the public site; a stanza is appended to `/etc/tor/torrc` between `grin-toolkit:mainnet-nginx` marker comments, mapping the hidden service's port 80 to that listener; Tor is reloaded and, within about 30 seconds, publishes the address.

The address is printed with a `main.grin.` prefix (`test.grin.` for testnet) in front of the 56-character `.onion` name, followed by `/v2/foreign`. Tor ignores the prefix — it is only there so you can tell the two networks apart.

**The identity is a key, not a name.** The `.onion` address is derived from an Ed25519 key in `/var/lib/tor/` under `grin-mainnet-nginx/`; lose the key and the address is gone for good. So:

- The first time you run `T` on a network it asks: `1` generate a **new** address, or `2` **recover** from the backup in `/opt/grin/backups/` (`grin_tor_onion_mainnet.tar.gz`) if one exists. A new address is backed up there automatically once Tor has published it.
- `U` disables the onion but **keeps the key directory**, so `T` later brings back the same address.
- `V` re-snapshots the identity on demand. The archive holds the secret key and is **not encrypted** (root-only, mode 600) — copy it off the server and treat it like a wallet seed. **[Admin & Maintenance → Backup](089-backup-restore.html)** includes it.

> **Note:** Script 01 (step 13b) already created a *different* `.onion` per node, in `/var/lib/tor/` under `grin-<network>-raw-tcp/`. That one points straight at the node's port, so a caller must present the Foreign API secret — it is a private mirror for your own use. Script 04's onion is the **public** one: credential-free and limited to `/v2/foreign`. The two identities are independent; backing up one does not back up the other.

A wallet user on the Tor side sets `check_node_api_http_addr` in `grin-wallet.toml` to the onion URL (`http://` plus the address, no path), installs `tor` and `torsocks` on their machine, and runs the wallet as `torsocks ./grin-wallet info`. The status page's Tor card shows these steps with the real address.

## After it finishes

Test from a machine that is **not** the server — your laptop is ideal, because it proves DNS, the certificate and the firewall as well as nginx:

```bash
curl -s -X POST https://api.yourdomain.com/v2/foreign \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"get_tip","params":[],"id":1}'
```

Good output is a JSON-RPC reply with the node's `Ok` result inside it:

```json
{"id":1,"jsonrpc":"2.0","result":{"Ok":{"height":3967196,"last_block_pushed":"…","prev_block_to_last":"…","total_difficulty":…}}}
```

**A parsed `{"Ok":…}` is the proof; an HTTP 200 alone is not.** Any web server, hosting parking page or CDN error page answers 200 — only a Grin node produces that shape. Likewise a plain `GET` on `/v2/foreign` proves nothing: the endpoint is POST-only JSON-RPC. Two more checks worth a minute:

```bash
# Node version and the header version (block format) it runs
curl -s -X POST https://api.yourdomain.com/v2/foreign \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"get_version","params":{},"id":1}'

# The management API must be unreachable — expect 403, not JSON
curl -s https://api.yourdomain.com/v2/owner
```

The second one should print *Access denied. Only /v2/foreign is exposed.* If the status page is deployed, its **Run Test** button does the `get_tip` check from a browser.

### Pointing a wallet at your node

- **grin-wallet** (the command-line wallet): in `grin-wallet.toml` set `check_node_api_http_addr` to `https://api.yourdomain.com` — the domain only; the wallet adds `/v2/foreign` itself — and restart the wallet. `grin-wallet info` now refreshes the balance through your node.
- **Grim** (the desktop GUI wallet): *External Connections → ADD NODE*, paste `https://api.yourdomain.com`, save. The node should show as **Available**.
- **Through Tor:** as in [The Tor onion](#the-tor-onion).
- **From a web page:** `fetch()` a `POST` to `/v2/foreign` with the JSON-RPC body; CORS is open, no key needed. The status page's developer section has a ready snippet.

### What was created

| Path | Purpose |
|------|---------|
| `/etc/nginx/sites-available/grin-node-api` (+ `-testnet`), linked from `sites-enabled/` | The public site: proxy rules, rate limits, the injected auth header, certbot's HTTPS block; later the status-page and REST rules |
| `/etc/nginx/sites-available/grin-node-api-tor` (+ `-testnet`) | The localhost listener behind the onion |
| `/etc/nginx/conf.d/grin-rate-limit.conf`, `grin-conn-limit.conf` | The shared `grin_api` request-rate zone and the `grin_conn` connection zone |
| `/etc/nginx/snippets/cloudflare-realip.conf` | Restores the visitor IP behind Cloudflare so rate limits apply per visitor, not per Cloudflare edge; no effect otherwise |
| `/etc/letsencrypt/live/api.yourdomain.com/` | The certificate; certbot renews it on its own timer |
| `/var/log/nginx/grin-node-api.access.log`, `.error.log` | The site's own logs, rotated daily, 5 kept, 5 MB cap — rule in `/etc/logrotate.d/grin-node-api` |
| `/var/www/grin-node-api/` (+ `-testnet`) | Status page files, `config.js` (network + onion URL), and `rest/` with the JSON files |
| `/opt/grin/grin-api-collector/rest-collector.py`, `node-collector.py` | The two REST collectors |
| `/etc/cron.d/grin-node-api-rest`, `grin-node-api-node` (+ `-testnet`) | Their one-minute cron jobs |
| `/var/lib/tor/grin-mainnet-nginx/` (+ `-testnet-`) | The onion identity — `hs_ed25519_secret_key`, `hostname` |
| `/opt/grin/backups/grin_tor_onion_<network>.tar.gz` | Its backup, mode 600, unencrypted |
| `/etc/tor/torrc` — a marked stanza per network | The hidden-service mapping; only the toolkit's markers are ever touched |
| `/etc/systemd/system/grin-secret-sync.timer`, `/usr/local/bin/grin-secret-sync` | The 5-minute self-heal that keeps the auth header aligned with the node's secret |
| `/opt/grin/logs/grin_node_services_<date>.log` | This run's log |

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Change the domain | Script 04 → network → `4` again with the new domain. The status page and REST rules are re-applied for you; run `T` again if you use the onion (it reuses the same address) |
| Publish the other network too | Script 04 → the other network → `4` with its own subdomain |
| Update the status page after a toolkit update | `6` — it copies the new files and reloads nginx |
| See who is using the API | `tail -f /var/log/nginx/grin-node-api.access.log` |
| Check the certificate | `certbot certificates`. Renewal is automatic; port 80 must stay reachable for it |
| Move the `.onion` to a new server | Copy `/opt/grin/backups/grin_tor_onion_<network>.tar.gz` over, run `4` then `T` and choose `2` (recover) |
| Take the whole thing down cleanly | `9` (REST), `7` (status page), `U` (onion), then `5`. Doing only `5` removes the onion listener and the page too, but leaves the two REST cron jobs in `/etc/cron.d/` — run `9` first |
| Re-check that the secret header is current | `grin-secret-sync` from a root shell (the timer does this every 5 minutes anyway) |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `certbot failed — check /var/log/letsencrypt/letsencrypt.log` | Let's Encrypt could not reach `http://api.yourdomain.com/` on port 80. Check that the A record points at this server (`dig +short api.yourdomain.com`) and that port 80 is open at the provider. If the domain is behind Cloudflare's orange cloud, set it to "DNS only" while `4` runs, then turn the proxy back on |
| `Port 3413 is not listening. Make sure your Grin mainnet node is running.` | The node is down or still starting. Start it from Script 01 → `S`; the proxy can be set up first and will work as soon as the node is up |
| `Foreign API secret not found at: …/.foreign_api_secret` — config written WITHOUT an auth header; the status line says `auth header: MISSING` | The node directory Script 04 found has no secret file, usually because `grin_instances_location.conf` points at an old path. Rebuild or `S`-start the node with Script 01 (it re-creates the file and the conf), then run `4` again |
| A wallet or browser gets **401** from the API | Same cause as above — nginx is not injecting the secret, so the node asks for it. Re-run `4`; if the node was just rebuilt, `grin-secret-sync` fixes it within 5 minutes |
| `'prunemain' is reserved by script 02` | Pick another subdomain — `api.` or `testapi.` |
| `MODE A Raw TCP is currently active … Disable Raw TCP first (option 2)` | Someone enabled Mode A earlier. `2` reverts the toml line and closes the firewall port (it offers to restart the node), then `4` works |
| `nginx config test failed. Check /etc/nginx/sites-available/grin-node-api` | Another site on the box is broken, or an old hand edit conflicts. `nginx -t` prints the offending line; the script never reloads a config that fails the test |
| `curl` from outside hangs or `Connection refused` | Port 443 (or 80) is closed at the provider's firewall or in `ufw`. `ufw status` on the server; the security-group page at the provider |
| HTTP **503** on a burst of requests | The rate limit: 300 per minute and 20 concurrent connections per IP. Back off; for your own bulk jobs, run them on the server against `127.0.0.1:3413` instead |
| `.onion address not yet published — check 'systemctl status tor' and retry.` | Tor was slow to generate keys or is not running. `systemctl status tor`; once `/var/lib/tor/grin-mainnet-nginx/hostname` exists, run `T` (or `6`) again to put the address on the status page |
| `tor service is not running. Install/start it first` | `apt install tor && systemctl start tor`, then `T` |
| `Recovery failed — aborting so a NEW address is not silently generated.` | The backup archive is unreadable or lacks `hs_ed25519_secret_key`. Restore a good copy to `/opt/grin/backups/grin_tor_onion_<network>.tar.gz` and run `T` again |
| `Initial REST collection failed (node may not be running yet)` / `REST cron: MISSING (re-run option 8)` | Harmless if the node was down — cron retries every minute. If `stats.json` never appears, `sudo -u www-data python3 /opt/grin/grin-api-collector/rest-collector.py 3413 /var/www/grin-node-api/rest /opt/grin/node/mainnet-prune/.foreign_api_secret` shows the real error |
| Status page cards for peers and chain size stay empty | They read `/rest/node.json`, which only exists once `8` is enabled |
| The Tor card on the status page still shows a placeholder | The page was deployed before the onion existed. `T` or `6` rewrites `config.js`; the page is served with `no-cache`, so a reload is enough |

## Related

- [Script 01](01-build-node.html) — the node, its `.foreign_api_secret`, and the private `.onion` from step 13b
- [Script 02](02-nginx-fileserver.html) — the other public site nginx may already be serving on this box; its subdomain labels are reserved
- [Getting started](getting-started.html#where-things-live-on-the-server) — what the two secret files are
- [Ports and paths](reference-ports-and-paths.html) — every port the toolkit uses and which must be open
- [Wallet hub](05-wallet-services.html) and [Fidelius](051-fidelius.html) — the toolkit's own wallets, which point at a node exactly like this one
- [Script 06](06-global-health.html) — the network dashboard that shares the `grin_api` rate-limit zone
- [Back up and restore](089-backup-restore.html) — the toolkit-wide backup, which includes the onion identity; [Script 08](08-admin-maintenance.html) is its hub
