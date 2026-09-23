---
title: GrinScan — a self-hosted block explorer
description: Run GrinScan, the toolkit's Node.js block explorer for Grin mainnet and testnet — why an archive node matters, and how to move it without re-crawling.
section: Scripts
order: 6.5
short: GrinScan
label: Script 06b
covers: 2026-09-20
updated: 2026-09-20
---

GrinScan is the block explorer behind [grinscan.org](https://grinscan.org) and [test.grinscan.org](https://test.grinscan.org): a Node.js application with its own small SQLite database that shows the latest blocks, one page per block, kernel and output, hashrate and difficulty charts, price, the node's peers and a JSON API — with live updates pushed to the page as blocks arrive, a mobile layout and light and dark themes. It runs one copy per network, so a single server can serve mainnet and testnet under two subdomains.

It is option `B` of [Script 06](06-global-health.html). Unlike the grincoin.org explorer (option `C`) it needs no Rust build, and unlike the [Tiny Explorer](06-global-health.html#tiny-explorer) it keeps history, so it can draw charts and page through blocks.

## What it does

1. Installs Node.js 24 (it needs the built-in `node:sqlite` module), copies the app to `/opt/grin/grinscan/app/` and writes two systemd services, `grinscan-test` and `grinscan-main`, that run as `www-data`.
2. Writes a `config.json` per network with the node's API URLs, a copy of the node's two API secrets, ports **3010** (testnet) and **3011** (mainnet), and the cache settings.
3. On start, the service asks the node whether it can serve block 1 — that decides `node_mode`, archive or pruned — then caches the last **500 blocks** into its database and from there on polls the node every **30 seconds** for new ones. Old blocks are read from the node on demand when the node is an archive; on a pruned node they are reported as not found.
4. nginx fronts each copy on its own subdomain with HTTPS, a rate limit on the REST endpoints and the special handling the live-update stream needs.

## Pruned or archive node?

A Grin node keeps the full **header** chain forever, but a **pruned** node throws away the *bodies* — the inputs, outputs and kernels — of blocks older than a few weeks. An **archive** node (`mainnet-full`, Script 01's *full* mode) keeps every body since genesis.

GrinScan needs bodies to show a block's transactions, so:

| | Pruned node | Archive node |
|--|-------------|--------------|
| Latest blocks, charts, live updates, price | ✓ | ✓ |
| Any block from the last ~500 (the cache) | ✓ | ✓ |
| Older blocks, the genesis block | *not found* | ✓, read live from the node |
| Kernel lookup by excess | ✓ (kernels are never pruned) | ✓ |
| Output lookup by commitment | ✓ while unspent; a spent, pruned output is *not found* | ✓ |
| Disk and memory on the node | Small | 18 GB and growing; **bulk random reads thrash a 4 GB box** (swap fills, the node stalls) |

GrinScan is written for that last row: it never crawls the chain from genesis unless you ask it to (`backfill_history` in `config.json`, off by default), and even then it goes gently — three requests at a time with pauses. Single on-demand reads of old blocks are fine on a 4 GB archive box; pre-warming charts with deep history wants 8 GB or more.

The installer checks for an archive node and asks before continuing without one. Both choices are legitimate: testnet on a pruned node is the normal case, and a mainnet explorer that only needs recent blocks works fine pruned.

## Before you start

| Need | Why |
|------|-----|
| A synced node from [Script 01](01-build-node.html) for each network you want — mainnet on 3413, testnet on 13413 | GrinScan reads blocks through the node's Foreign API and peers through its Owner API, both on localhost |
| nginx + certbot | `N` in the Script 06 menu |
| A subdomain per network with an A record, e.g. `scan.yourdomain.com` and `test.yourdomain.com` | Set before the nginx step; Cloudflare records on **DNS only** |
| Root shell, a few hundred MB of disk | The database grows with the block cache (500 blocks) plus a compact daily table that never gets pruned — small |

> **Tip:** If Tiny Explorer or another Node.js product is already on the box, install GrinScan first next time — its installer removes any Node.js older than 24 before installing 24 from NodeSource. Everything else in the toolkit runs on 24, so nothing breaks, but a running service keeps the old binary until restarted.

## The menu

```text
  B) GrinScan — Lightweight Block Explorer

  Node.js / Express + SQLite — works with a pruned node
  Testnet port: 3010  ·  Mainnet port: 3011

                        testnet              mainnet
  1)   Install         Node.js + npm deps + systemd units
  2)   Configure       write config.json  [test: ✗ · main: ✗]
  3)   Service Control Start / Stop / Remove  [test: stopped · main: stopped]
  4)   Setup Nginx     HTTPS reverse proxy + certbot  [test: not configured · main: not configured]
  5)   Auto-Start      systemctl enable (survive reboots)
  6)   Status
  7)   View Logs
  8)   Backup / Restore DB  migrate to a new server without re-crawling
  U)   Update App      redeploy server.js + web files from toolkit, refresh npm deps
  Z)   Nuke            stop + remove service, data dir, nginx config (clean rebuild)

  0) Back
  [Enter] Refresh menu
  DNS: ensure A-record points to this server before running Setup Nginx (4)
```

Every key that acts on a network first asks **which network** — `1` testnet, `2` mainnet, `3` both — except Install, which sets up both services at once, and Status, which shows both.

## Setup, step by step

| Step | What happens | What you do |
|------|--------------|-------------|
| `1` Install | Looks for an archive node (`FULLMAIN_GRIN_DIR` in `/opt/grin/conf/grin_instances_location.conf` with `archive_mode = true` in its `grin-server.toml`) and warns if there is none; ensures Node.js 24; copies the app and runs `npm install`; creates `/opt/grin/grinscan/{test,main}/`; writes both systemd units | `y` to continue on a pruned node if asked |
| `2` Configure | Per network: asks the node URL (default `http://127.0.0.1:<port>/v2/foreign`), tests the node through its Owner API, asks for a GA4 ID (mainnet only) and the **sibling URL** — the other network's public address, which powers the mainnet/testnet switch in the header; detects archive mode; copies the node's secrets into the data directory (owned by `www-data`, mode 600); writes `config.json` and a sample `banners.json`; installs the secret self-heal timer | Enter for the default URL; the sibling URL if you will run both |
| `3` Service Control → `S` | Starts the service and waits up to 10 s for the port. The database is created on first start — there is no import step | Watch for `Port :3011 is listening` |
| `4` Setup Nginx | Per network: the domain and, on the first certbot run, an email; creates the `grinscan_api` rate-limit zone and the `grinscan-proxy.conf` snippet; writes the HTTP vhost, tests, reloads, runs certbot with redirect, writes logrotate | Domain, maybe email |
| `5` Auto-Start | `systemctl enable` for the chosen network(s) | — |
| `6` Status | Per network: service, port, config, block count and tip height in the database, last price, nginx domain, certificate | Read it |

The `config.json` written in step 2, with the values you may want to change:

```json
{
  "network":          "mainnet",
  "node_url":         "http://127.0.0.1:3413/v2/foreign",
  "node_owner_url":   "http://127.0.0.1:3413/v2/owner",
  "port":             3011,
  "poll_interval_ms": 30000,
  "blocks_cache":     500,
  "history_days":     50,
  "backfill_history": false,
  "ga4_measurement_id": "",
  "sibling_url":      "https://test.yourdomain.com",
  "archive_mode":     true
}
```

`blocks_cache` is how far back the explorer keeps bodies in its own database; `history_days` (at most 50) only matters when `backfill_history` is `true`, which makes the service import that many days of blocks at start-up to pre-warm the charts. The service reads the file once at start, so restart after editing (`3` → `T`, then `S`).

> **Note:** `archive_mode` in the config is informational — the service decides for itself at start-up by trying to fetch block 1, and reports the result as `node_mode` in `/api/stats` and `/healthz`.

### Partner banners

Configure also writes `/opt/grin/grinscan/<net>/banners.json` with one inactive example. Set `"active": true` and fill in `src`, `href` and `alt` for an image banner (put the image under `app/public/img/partners/`), or `type: "code"` with `html` for an ad-network embed. Banners are spliced into the page by the server, re-read every 5 minutes — no restart, no public endpoint.

## After it finishes

```bash
curl -s http://127.0.0.1:3011/healthz                  # {"status":"ok","network":"mainnet"}
curl -s http://127.0.0.1:3011/api/stats | head -c 300   # tip_height, hashrate_gps, node_mode…
tail -n 20 /opt/grin/grinscan/main/grinscan-main.log    # "Backfilling …" then "Backfill complete."
```

Then open `https://scan.yourdomain.com`. The first start logs `Backfilling <tip−500> → <tip>` and shows blocks as they land — allow a minute or two; the page's live stream fills in the rest. `node_mode` in `/api/stats` tells you which kind of node it found.

### Pages and API

| URL | What it is |
|-----|-----------|
| `/`, `/block.html?h=…`, `/kernel.html?ex=…`, `/output.html?c=…` | Home with the latest blocks and charts; one page per block, kernel and output. The search box takes a height, a block hash, a kernel excess or an output commitment |
| `/info.html`, `/api.html` | About the network, and the API reference |
| `/rest/stats.json`, `supply.json`, `height.json`, `difficulty.json`, `emission.json`, `node.json`, `price.json` | Compact JSON for other sites and scripts — rate-limited to 30 requests a minute per visitor, cached 30 s |
| `/api/tip`, `/api/stats`, `/api/blocks`, `/api/block/<ref>`, `/api/kernel/<excess>`, `/api/output/<commit>`, `/api/history`, `/api/price`, `/api/peers` | The pages' own API |
| `/events` | The live-update stream (server-sent events) the pages subscribe to |

Price comes from Gate.io (GRIN/USDT) and CoinGecko (GRIN/BTC), refreshed every 10 minutes and kept in the database, so the charts can show price alongside hashrate. Hashrate uses the standard Cuckatoo32 formula (difficulty delta × 42 ÷ seconds ÷ 16 384), the same as the dashboard of Script 06 and the grincoin.org explorer.

> **Note:** Two items from the toolkit's [security audit](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script06_security_audit.md) are still open: the `/api/…` routes that reach the node are not rate-limited by nginx (only `/rest/` is), and `/api/peers` and `/rest/node.json` publish your node's connected peers with their addresses. On a public explorer, expect both.

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/grinscan/app/` | The application and its `node_modules` |
| `/opt/grin/grinscan/<net>/config.json` | Settings for that network (`net` = `test` or `main`) |
| `…/grinscan.db` | The database: cached blocks, the daily rollup, prices |
| `…/.foreign_api_secret`, `…/.api_secret` | Copies of the node's secrets for `www-data`; refreshed by the self-heal timer after a node rebuild |
| `…/banners.json` | Partner banners |
| `…/grinscan-<net>.log` | The service log, rotated 14 days by `/etc/logrotate.d/grinscan-<net>` |
| `/opt/grin/grinscan/backups/` | Database snapshots from key `8` |
| `/etc/systemd/system/grinscan-test.service`, `…/grinscan-main.service` | The services |
| `/etc/nginx/sites-available/grinscan-test`, `…/grinscan-main` | The vhosts; `/etc/nginx/snippets/grinscan-proxy.conf` and `/etc/nginx/conf.d/grinscan-rate-limit.conf` are shared by both |

## Moving to a new server

The database is the only part of GrinScan that is slow to rebuild, and key `8` exists so a move never re-crawls the chain:

1. Old server: `8` → `B` **Backup DB** — a consistent snapshot (`sqlite3 .backup`, integrity-checked, gzipped) lands in `/opt/grin/grinscan/backups/` as `grinscan-<net>-<date>.db.gz`. Safe while the service runs.
2. Copy the file down and up with `scp`; the screen prints both commands.
3. New server: `1` Install → `2` Configure.
4. New server: `8` → `R` **Restore DB** — pick the file, confirm. The backup is verified before it replaces anything, the service is stopped for the swap, and the previous database is kept beside it as `grinscan.db.pre-restore.<date>`.
5. `3` → `S`.

The daily chart history goes back only as far as the blocks the database has accumulated; it is not reconstructed from genesis on a new install — which is exactly what the backup preserves.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Restart after editing `config.json` | `3` → pick the network → `T`, then `S` |
| Read the log | `7` (choose the network, `F` to follow) or `journalctl -u grinscan-main -n 50` |
| Ship a new version after `git pull` in the toolkit | `U` — redeploys the app, refreshes `npm` packages, restarts. Config, database and secrets stay |
| Pre-warm the charts with history on an archive node | Set `"backfill_history": true` in `config.json`, restart, watch the log — gentle, but expect it to run a while |
| Add the network switch between mainnet and testnet | `2` again and enter the sibling URL, then restart |
| Remove one network | `3` → `R` removes the service; answer `y` to delete its database and config too. Or `Z` for a full clean |
| Remove everything | `Z` → `3` both → type `nuke`; it also removes the shared nginx snippet and offers to delete the app directory |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Node API port :3011 not listening — is the node running?` at Configure | Wrong network chosen for the node you have, or the node is down. Start it ([Script 01](01-build-node.html) → `S`), or answer `n` and configure the other network |
| `Node not reachable at http://127.0.0.1:3413/v2/owner` | The node is up but rejected the secret — usually a node rebuilt while a stale secret sat in the data dir. `grin-secret-sync` from a root shell, then Configure again |
| `Port :3011 not yet listening after 10s` | The service crashed at start: `journalctl -u grinscan-main -n 20`. Typical causes: a Node.js older than 24 (`node --version`), or a bad `config.json` after a hand edit |
| Old blocks say *not found* | Pruned node — see [Pruned or archive node?](#pruned-or-archive-node). `/api/stats` shows `"node_mode":"pruned"` |
| The node becomes slow or swaps after GrinScan starts | Someone (or a crawler) is pulling many old blocks from an archive node on a small box. Restrict with a firewall or fail2ban for now; the audit item above is the durable fix |
| `Certbot failed — check connectivity and DNS.` | The subdomain does not resolve to this server yet. Fix DNS, then `4` again |
| The mainnet/testnet switch in the header is missing | No sibling URL was given at Configure. `2` again, then restart |
| `Restore aborted — backup failed integrity check` | The file is truncated or not a GrinScan database. Re-copy it; `gzip -t file.db.gz` on the source |

## Related

- [Script 06](06-global-health.html) — the hub this lives in: the network dashboard, the grincoin.org explorer and the Tiny Explorer
- [Script 01](01-build-node.html) — building the archive node that lets GrinScan serve every block
- [Ports and paths](reference-ports-and-paths.html) — 3010/3011 and the `/opt/grin/grinscan` tree
- Deeper reading in the toolkit repository: [script06b_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script06b_design.md) and [script06b_implementation.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script06b_implementation.md)
