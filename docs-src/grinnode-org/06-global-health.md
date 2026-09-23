---
title: Network dashboard, peer map and a tiny explorer
description: How Script 06 deploys a self-hosted Grin network dashboard with a peer map and charts, the Tiny Explorer with its wallet tools, and the grincoin.org explorer.
section: Scripts
order: 6
short: Dashboard
label: Script 06
covers: 2026-09-20
updated: 2026-09-23
---

Script 06 — *Global Grin Health* in the main menu — is the hub for everything that **shows the network to the public**. Every product in it reads from your own node and is served by nginx over HTTPS on a subdomain you own. Nothing here touches wallets or money; the worst a misconfiguration can do is show stale numbers.

It holds four products, each with its own sub-menu and status line:

| Key | Product | What it is |
|-----|---------|------------|
| `A` | **Network Stats + Peer Map** | A three-page dashboard: a world map of Grin nodes, charts of hashrate, difficulty, transactions, fees, price and supply, and an ecosystem status page. Built with a Python collector, SQLite and static HTML — [world.grin.money](https://world.grin.money). Needs a mainnet node; **pruned is enough** |
| `B` | **GrinScan** | A block explorer for mainnet and testnet — [grinscan.org](https://grinscan.org). It has its own page: [GrinScan](06b-grinscan.html). Pruned works; an archive node adds old blocks |
| `C` | **Grin Explorer by Grincoin.org** | The upstream Rust explorer ([aglkm/grin-explorer](https://github.com/aglkm/grin-explorer)) built from source and put behind nginx. Needs an **archive** node (`mainnet-full`) or a remote one |
| `D` | **Tiny Explorer** | A stateless single-block explorer with a toolbox: slatepack inspector, payment-proof verifier, wallet and node checkers, emission and mining calculators — [scan.grin.money](https://scan.grin.money). Mainnet; archive is best, pruned runs |

Plus `N`, which installs nginx, certbot and `whois` for all of them.

This page covers `A`, `C` and `D`. GrinScan is on [its own page](06b-grinscan.html).

## Before you start

| Need | Why |
|------|-----|
| A synced **mainnet** node from [Script 01](01-build-node.html), running on port 3413 | Every product reads the node's Foreign API (`/v2/foreign`), and the dashboard's peer data comes from its Owner API. Testnet peer data is thin, so the dashboard is mainnet-first — a testnet node next to it only adds testnet peers to the map |
| nginx + certbot | Press `N` in this menu if you have not installed them (Scripts 02 and 04 install the same packages) |
| One subdomain per product, with a DNS **A record** pointing at the server | `stats.yourdomain.com`, `explorer.yourdomain.com`, `scan.yourdomain.com` — created in your DNS provider's panel *before* the nginx step, or certbot fails. Cloudflare users: set the record to **DNS only**, not Proxied |
| Python 3 (dashboard) · Node.js 18+ (Tiny Explorer) · Rust toolchain (grincoin explorer) | The scripts install what is missing: Python from apt, Node.js 20 from NodeSource, Rust with `rustup` |
| Disk | Dashboard: about 110 MB of SQLite for the complete chain history plus 12 MB a year, under 20 MB for prices, 5 MB of map geometry in the web root. Grincoin explorer: about 2 GB for the Rust toolchain and build. Tiny Explorer: a few MB |

> **Tip:** Install **GrinScan before Tiny Explorer** if you want both on one server. GrinScan needs Node.js 24 and its installer removes an older Node.js first; Tiny Explorer is happy with anything from 18 up, so it runs fine on 24 — but the other way round, GrinScan's install swaps the binary under a running Tiny Explorer.

## The menu

```text
  06) Global Grin Health

  Requirements:
  [OK]   Grin node running  (A requires mainnet · B needs pruned or full · C & D require archive)
  [OK]   Nginx installed    (use option N to install)
  [--]   DNS A-records — confirm via A→4 or C→4 before nginx setup (B: see DNS hint in menu)

  N)   Install Nginx + Certbot + Whois

  A)   Network Stats + Peer Map
       Hashrate · Difficulty · Transactions · Fees · Versions · 2D Peer Map
  B)   GrinScan
       Lightweight block explorer — testnet + mainnet, mobile friendly, pruned node OK
  C)   Grin Explorer by Grincoin.org
       Rust + Rocket — archive node required
  D)   Tiny Explorer
       Stateless single-block explorer for pool deep-links — mainnet, archive node

  0) Back to main menu
```

The requirement lines are live: the node check looks for something listening on 3413, the nginx check for the binary. The keys `A`–`D` open a sub-menu each; the sub-menus below are numbered, and every one of them reads `0` as back and a bare Enter as "refresh the status labels".

> **Note:** The menu says `C & D require archive`. For `C` that is true. Tiny Explorer's own installer only *recommends* an archive node and lets you continue on a pruned one — old block permalinks then return 404 (see [Tiny Explorer](#tiny-explorer)).

## Network Stats + Peer Map

### What visitors see

Three static pages, served from `/var/www/grin-stats/` and refreshed by a background collector:

| Page | Shows |
|------|-------|
| `/` — **Peer map** | A world map with one dot per location where Grin nodes run, sized by how many nodes share that spot; click a dot for the list. A side panel with the peer list, a network snapshot (total peers, mainnet/testnet, nodes running both, nodes with no location) and the public JSON API. The map's land, borders and city labels are drawn from geometry the toolkit ships, not from a third-party tile service |
| `/stats.html` — **Network stats** | Price strip (market cap, 24 h volume and change, price), then charts: hashrate, difficulty, block activity (transactions and fees per block), mempool, kernels and outputs since genesis with a live UTXO count, active peers, node versions and top countries with week/month/year/all-time toggles, and an inflation comparison of Grin against USD M2 and gold |
| `/ecosystem.html` — **Ecosystem status** | Whether the Grin DNS seeds answer, a list of public wallet-API nodes and their domain expiry dates, the status of community sites and services, and a "submit your node" form |

Every chart has a matching JSON file under `/api/…` that anyone may fetch (rate-limited, CORS-open, cached 5 minutes) — the pages list them. The peer list itself (`peers.json`) is **not** on that API: it is served only to the page's own scripts, and it masks every address (last octet of an IPv4, last group of an IPv6) and adds a short salted id so two nodes in one masked range can still be told apart.

### The pieces on the server

- **`grin-stats-collector`** (`/usr/local/bin/`, a Python script) — talks to the node, keeps `/opt/grin/grin-stats/stats.db` and writes the JSON files. Every 5 minutes it fetches new block headers, samples the mempool, samples the unspent-output count every 20 minutes, fills in transaction and fee stats for recent blocks (at most 60 blocks and 2 minutes per run, so a slow node can never delay the export), refreshes the peer list, and rewrites all JSON. It runs under `flock`, so a run that overruns is skipped rather than stacked.
- **`grin-price-collector`** — its own script and database (`/opt/grin/grin-price/grin-price.db`). GRIN/USDT comes from Gate.io, with daily candles back to 2019 imported once at install; GRIN/BTC comes from CoinGecko, or is derived from Gate.io's USDT prices when CoinGecko is unavailable. Also every 5 minutes.
- **`grin-ecosystem-checker`** — TCP-checks the DNS seeds, HTTP-checks the listed sites and services (GitHub and Gitea repositories included), probes the community-submitted nodes, and looks up domain expiry over RDAP (refreshed daily). Hourly.
- **`grin-submit`** — a small systemd service on `127.0.0.1:5060` behind the "submit your node" form. It hands out a challenge token, probes the submitted node before accepting it (through Tor when the URL is an `.onion`, which is why `tor` is installed), accepts at most two submissions per hour per visitor, and stores the result in `community_nodes.json`. A node that fails 168 consecutive hourly checks (a week) is dropped automatically.
- **nginx** — the vhost `grin-stats`: static files, gzip (the map geometry is 740 KB raw, 240 KB compressed), a 30-day cache on the geometry, a referer check on `/data/`, and the whitelisted `/api/…` endpoints.

**Smart sampling** keeps the database small without losing detail where it matters: every block for the last 24 hours, one block per hour for the last 30 days, one per day before that — and full transaction and fee rows for every block since genesis (about 23 bytes each, 85 MB for the whole chain).

**Hashrate** is derived the way the reference explorers do it — the difficulty added by a block times 42, divided by the real seconds since the previous block, divided by 16 384 — not "difficulty ÷ 60", which reads about 366 times too high.

### Setup, step by step

The sub-menu `A`:

```text
  6A) Network Stats + Peer Map

  1)   Install          collector + ecosystem checker + Chart.js + Leaflet   [✗ not installed]
  2)   Import Data      stats: init / backfill / update  |  price: init / update  |  ecosystem: run / whois
  3)   Start Updates    stats+price every 5 min · ecosystem hourly  [stats: inactive · eco: inactive]
  4)   Check DNS        confirm A-record before nginx setup
  5)   Setup Nginx      HTTPS subdomain  [not configured]
  6)   Status
  7)   Google Analytics  inject GA tag into all three pages  [not set]
  Z)   Stop Updates     disable cron
```

| Step | What happens | What you do |
|------|--------------|-------------|
| `1` Install | Creates `/opt/grin/grin-stats/` and `/var/www/grin-stats/`; installs the three collectors and their JSON sidecars (DNS seeds, ecosystem sites, external nodes, exceptions) into `/usr/local/bin/`; installs `python-whois`, `tor` and the Python SOCKS packages; copies the three pages, the shared header and the map geometry; downloads Chart.js and Leaflet; detects the running node and its secret paths and writes `config.env`; installs the secret self-heal timer; creates both databases; imports the Gate.io price history (about 30 s); generates the inflation chart; starts the submit server | Optionally paste a Google Analytics `G-…` ID, or Enter to skip |
| `2` Import Data → `b` | **Full history import** — samples headers across the whole chain (fast), then walks every block since genesis for transaction and fee stats, then peers, then exports. This is the one run that seeds the block table; the other import keys refuse to run before it | Answer `Y`, and run it inside `tmux` — it takes **6 hours or more**. On a pruned node, blocks older than the pruning horizon have no body, so their transaction rows stay empty |
| `3` Start Updates | Adds four cron lines to root's crontab: stats and price every 5 minutes, ecosystem hourly, RDAP expiry refresh daily at 03:00. Each stats run first re-syncs the node secret paths (`grin-secret-sync`) so a node rebuild cannot break it | Enter. Re-running offers to replace the existing lines |
| `4` Check DNS | Prints this server's IP addresses and the A record you need — it does **not** query DNS; it asks you to confirm you set it | Confirm |
| `5` Setup Nginx | Asks for the subdomain (the labels `fullmain`, `prunemain` and `prunetest` are refused — Script 02 owns them) and an email for Let's Encrypt; stamps the domain into the pages' canonical and Open Graph tags and writes `robots.txt` and `sitemap.xml`; writes the HTTP vhost, creates the rate-limit zones and the `/etc/nginx/snippets/grin-api.conf` snippet, tests, reloads, then runs certbot and reloads again | Subdomain, email |
| `6` Status | Collectors, databases with sizes, the age of every JSON export, cron state, nginx domain, node, submit server with community node counts, analytics | Read it |
| `7` Google Analytics | Set, change or remove the measurement ID; re-copies the pages from the toolkit source and injects the tag | Paste an ID, Enter to remove, `0` to cancel |
| `Z` Stop Updates | Removes all four cron lines. Nothing else is touched | — |

> **Warning:** Do not press `3` before `2b` has finished. The 5-minute updater starts from the last height it knows, and on an empty table that is genesis — the first cron run would try to fetch every header since 2019 in one go.

The other keys under `2` are for later: `c`/`d`/`e` re-walk the last 180 days, 90 days or the whole chain for transaction rows and **skip blocks that already have them** — the way to finish an interrupted full import. `f` is one updater run by hand, `g` refreshes only the peer map, `n` back-fills the kernel/output counts (headers only, fast), `k` re-fetches the M2 and gold series without touching the node, `h`–`j` re-initialise or re-export the price data, `l`/`m` run the ecosystem check or force the expiry lookups.

> **Note:** Changing the Analytics ID (`7`) copies the pristine pages back, which also resets the canonical and Open Graph URLs to their placeholder; the pages fix that in the browser, but the raw HTML a crawler downloads keeps the placeholder until you run `5` again. Certbot on a domain that already has a certificate is harmless.

### After it finishes

```bash
curl -s https://stats.yourdomain.com/api/summary | head -c 400   # tip height, hashrate, supply…
crontab -l | grep grin-node-toolkit                              # the four cron lines
tail -n 20 /opt/grin/logs/grin_stats_cron.log                    # "[OK] Update complete."
systemctl status grin-submit --no-pager                          # the node-submit service
```

A healthy dashboard shows a tip height within a block or two of your node's, the *Status* screen shows every JSON file "N m ago" with N under 6, and the peer map has dots. The map needs one collector run with peers before it shows anything, and the country and version rankings grow over the first days — the year and all-time views are built forward from install day, not reconstructed.

#### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/grin-stats/config.env` | Node URLs and secret paths, the analytics ID, the domain, the submit-server token (mode 600) |
| `…/stats.db` | Headers, transaction stats, peers, ecosystem checks — the database |
| `…/community_nodes.json` | Nodes submitted through the ecosystem page |
| `/opt/grin/grin-price/config.env`, `grin-price.db` | The price collector's config and database |
| `/var/www/grin-stats/` | The web root: the three pages, `_header.html`, `assets/` (map geometry, flag font), Chart.js and Leaflet, `data/*.json` |
| `/usr/local/bin/grin-stats-collector`, `…/grin-price-collector`, `…/grin-ecosystem-checker`, `…/grin-node-submit` | The four programs, with their `06_*.json` data files beside them |
| `/etc/systemd/system/grin-submit.service` | The submit server |
| `/etc/nginx/sites-available/grin-stats` | The vhost; `/etc/nginx/snippets/grin-api.conf` is the shared API snippet, the zones live in `/etc/nginx/conf.d/grin-rate-limit.conf` and `script06-submit.conf` |
| `/etc/logrotate.d/grin-stats` | Rotates the vhost's access and error logs |
| `/opt/grin/logs/grin_stats_cron.log`, `…/price_cron.log`, `…/grin_ecosystem.log` | The cron jobs' output |

> **Note:** The `grin_api` rate-limit zone (300 requests a minute per visitor, burst 10) is **shared** with [Script 04](04-publish-node-api.html#setting-up-the-https-proxy-step-by-step): on a server that runs both, a visitor's dashboard API calls and node API calls draw from one budget. The submit endpoints have their own, tighter zone.

### Privacy

The map exists to show where nodes run, so the collector sends the peer addresses it learns from your node to **ip-api.com** (their free batch endpoint, over plain HTTP) for city-level coordinates. What it publishes afterwards is masked as described above, and nothing is kept longer than 30 days in the live peer table; a separate registry keeps one row per node (first seen, last seen, country, version) so the year and all-time counts are counts of distinct nodes rather than node-days. If that trade-off is not for you, this product is not for your server — the map cannot be turned off separately.

## Grin Explorer by Grincoin.org

Option `C` builds the explorer that powers [grincoin.org](https://grincoin.org) from its upstream source and puts it behind nginx. It is a Rust application that reads block bodies straight from the node's `chain_data` on disk as well as through the API, so it **needs a mainnet archive node on the same server** — or a remote archive node reached over HTTPS. The toolkit deploys it as-is, with one patch: upstream hard-codes a `main/` path segment under the node directory that a toolkit node does not have.

```text
  C) Grin Explorer by Grincoin.org

  1)   Install & Build  clone + cargo build --release  [✗ not built]
  2)   Configure        patch Explorer.toml
  3)   Start            launch in tmux  [stopped]
  4)   Check DNS        confirm A-record before nginx setup
  5)   Setup Nginx      HTTPS subdomain → proxy :8000  [not configured]
  6)   Auto-Start on Boot  @reboot cron via tmux  [inactive]
  7)   Status
  Z)   Stop             kill tmux session
  X)   Nuke             remove service, nginx, crontab, data dir (clean rebuild)
```

| Step | What happens | What you do |
|------|--------------|-------------|
| `1` | Installs the build packages, then the Rust toolchain if `cargo` is missing, clones into `/opt/grin/grin-explorer/` (or pulls if already there), applies the path patch and runs `cargo build --release`, streaming the build log | Confirm; wait **10–30 minutes** on a small VPS. About 2 GB of disk |
| `2` | Local node: refuses unless `/opt/grin/node/mainnet-full` exists, then patches `Explorer.toml` with `127.0.0.1:3413`, the archive node's secret paths and `grin_dir`. Remote node: asks host, port (3413) and protocol (https) | `1` local or `2` remote |
| `3` | Starts the binary in a tmux session named `grin-explorer` on `127.0.0.1:8000`; offers to restart if it is already running | Attach with `tmux attach -t grin-explorer` if it exits at once — usually a wrong `grin_dir` |
| `5` | Subdomain + email, HTTP vhost proxying to port 8000, certbot, logrotate | Subdomain, email |
| `6` | An `@reboot` cron entry that sleeps a delay (default 100 s, so the node is up first) and starts the tmux session | Accept or change the delay |

`Z` stops it, `X` removes everything it created after you type `nuke` — the node, its chain data and the Rust toolchain stay.

> **Note:** Key `6` prints a notice if no Script 03 snapshot cron exists and says the explorer "may serve stale or missing data" without one. Publishing snapshots has nothing to do with how fresh the explorer's data is — it reads the running node. Treat the notice as informational.

## Tiny Explorer

Option `D` is the toolkit's own explorer, written for one job first: answering **deep links** — `/block/<height>` on your domain — from mining pools and payout pages, without a database or a crawler. It is a thin Node.js proxy in front of the node with small in-memory caches, so it is light enough for any VPS and needs no import step. Around that core it has grown a **toolbox** — six tools that a Grin user needs sooner or later and that no wallet provides:

| URL | Tool | Where the work happens |
|-----|------|------------------------|
| `/`, `/block/…`, `/kernel/…`, `/output/…` | Live tip, hashrate, difficulty, supply, price, the latest blocks, and one page per block, kernel and output, with a search box that tells the three apart. A block is found by height or hash, a kernel by its excess, an output by its commitment | Your node |
| `/slate` | **Slate Inspector** — paste a slatepack and read what is inside: amount, fee, which step of the exchange it is, mainnet or testnet | Entirely in the visitor's browser; nothing is uploaded |
| `/proof` | **Payment Proof Verifier** — checks both signatures of a grin-wallet payment proof, then whether its kernel is on chain | This server (signature checks) and your node |
| `/wallet-check` | **Wallet Address Checker** — validates a slatepack address, says which network it belongs to and derives its Tor `.onion`; optionally asks that wallet over Tor whether it is online right now | Browser for the address; this server for the optional Tor probe |
| `/node-check` | **Node Reachability Checker** — enter a host and port and this server tries the node's Foreign API and P2P port from outside the visitor's network | This server dials the target (with a blocklist against internal addresses) |
| `/emission`, `/mining` | **Emission & Supply** (1 ツ per second, supply = height × 60, live inflation) and a **Mining Calculator** (GRIN per day from your graphs-per-second, power cost, break-even and payback) | Browser, from one stats call |

Kernels resolve on a pruned node too; a spent output whose block has been pruned returns 404, as does any block below the pruning horizon — which is why an archive node is recommended.

### Tiny Explorer setup, step by step

```text
  D) Tiny Explorer — single-block deep-link explorer

  1)   Install         Node.js + npm deps + systemd unit
  2)   Configure       write config.json (prompts domain)  [✗]
  3)   Service Control Start / Stop / Remove  [stopped]
  4)   Setup Nginx     HTTPS reverse proxy + certbot (repoints C's domain if reused)  [not configured]
  5)   Auto-Start      systemctl enable (survive reboots)
  6)   Status
  7)   View Logs
  U)   Update App      redeploy server.js + web files, refresh npm deps
  Z)   Nuke            stop + remove service, data dir, nginx config
```

| Step | What happens | What you do |
|------|--------------|-------------|
| `1` Install | Checks for an archive node (warns and lets you continue without one); installs Node.js 20 if nothing from 18 up is present; copies the app to `/opt/grin/tiny-explorer/app/`, runs `npm install`, writes the `grin-tiny-explorer` systemd unit (runs as `www-data`, log at `/opt/grin/tiny-explorer/tiny-explorer.log`). Re-running it on a live install redeploys the files and restarts the service | Confirm the archive warning if it appears |
| `2` Configure | Finds the live mainnet node and tests it; asks the questions below; copies the node's two secrets into `/opt/grin/tiny-explorer/` for `www-data`; writes `config.json`; registers with the secret self-heal timer; restarts the service if it is running | Answer the prompts |
| `3` Service Control | `S` start (waits for port 8471), `T` stop, `R` remove the unit | — |
| `4` Setup Nginx | Domain (defaults to the configured one — and if you type a different one, offers to update `config.json` so page titles and canonical tags match), email on the first certbot run; writes the vhost proxying everything to `127.0.0.1:8471` with two rate-limit zones, tests, reloads, runs certbot, writes logrotate | Domain, maybe email |
| `5` Auto-Start | `systemctl enable` | — |
| `6` Status | Service, port, config, nginx, Tor probe state — and a warning when the app files or `config.json` are newer than the running process, which means a restart is owed | Read it |

The Configure prompts, in order:

| Prompt | Meaning |
|--------|---------|
| Node Foreign URL | `http://127.0.0.1:3413/v2/foreign` — change only for a remote archive node |
| Public domain | Baked into every page title, canonical link and share tag — so it must be the domain nginx will serve |
| Slogan | The line under the logo; blank keeps the default |
| GA4 Measurement ID | Optional analytics |
| Peers-stats source URL | Where the "Node peers · 30 d" card on the home page gets its count. Defaults to `https://world.grin.money`; point it at your own dashboard if you run one. When unreachable, the card falls back to your node's own live peer count |
| Enable the Wallet Checker Tor liveness probe? | The optional second half of the wallet checker. **Yes** needs a Tor SOCKS proxy on `127.0.0.1:9050`; if none is listening the script offers to install and start `tor` for you, and if that fails it asks whether to leave the probe on anyway. The prompt says `(installs tor)` when that is what a yes would do. New installs default to yes; an existing choice in `config.json` is kept |

### After the Tiny Explorer install

```bash
curl -s http://127.0.0.1:8471/healthz          # {"status":"ok","node_mode":"archive"} or "pruned"
curl -s https://scan.yourdomain.com/api/tip     # the node's tip through nginx
# then open, in a browser:  https://scan.yourdomain.com/block/<a recent height>
```

The nginx step prints the three deep-link forms to try.

#### Tiny Explorer files

| Path | Purpose |
|------|---------|
| `/opt/grin/tiny-explorer/app/` | The application (`tiny-explorer-server.js`, `public/`, `lib/`) |
| `…/config.json` | Every setting: node URLs, domain, caches, the probe switch, Tor SOCKS host and port |
| `…/.foreign_api_secret`, `…/.api_secret` | Copies of the node's secrets, owned by `www-data`, refreshed by the self-heal timer after a node rebuild |
| `…/tiny-explorer.log` | The service log, rotated 14 days |
| `/etc/systemd/system/grin-tiny-explorer.service` | The service |
| `/etc/nginx/sites-available/tiny-explorer` | The vhost. Zones: `tinyx_api` (30 requests a minute, `/api/…`) in `script06d-rate-limit.conf` and `tinyx_probe` (10 a minute, the two probe routes) in `script06d-probe-rate-limit.conf` |

### The two probes and abuse

Two routes make this server contact **other machines** on a visitor's request: `/api/node-check` (an HTTP request and a TCP connect to the host the visitor typed) and `/api/wallet-check` (a Tor circuit to a wallet's `.onion`). Both are rate-limited at 10 requests a minute per visitor, the node checker refuses private and loopback addresses, and the wallet probe runs only while `config.json` says so — Configure asks, and a config that has lost the key counts as off. Everything else the explorer does is a read of your own node.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| See whether the dashboard is up to date | `A` → `6`. Every export should be a few minutes old; `Stats cron ✓ active` |
| Refresh the peer map right now | `A` → `2` → `g` |
| Finish an interrupted full import | `A` → `2` → `e` — it skips blocks already stored |
| Fill the kernels/outputs chart back to genesis | `A` → `2` → `n` (headers only, fast on a pruned node) |
| Remove a submitted community node | A `DELETE` to the submit server on the box itself, with the admin token from `config.env` — the command is below the table, and the install step prints it too |
| Pause everything without uninstalling | `A` → `Z` (cron off); `systemctl stop grin-submit` |
| Change the dashboard's domain | `A` → `5` again with the new name — SEO tags, robots and sitemap are re-stamped, certbot issues the new certificate |
| Ship a new Tiny Explorer build after `git pull` | `D` → `U` (or `1` again) — redeploys and restarts; check `6` for the "newer than the running process" warnings |
| Turn the wallet Tor probe on or off | `D` → `2` and answer the probe question; the service restarts with the new value |
| Reuse the grincoin explorer's subdomain for Tiny Explorer | `D` → `4` with that domain — the vhost takes it over; stop `C` with `Z` |
| Start over | `C` → `X` or `D` → `Z`, type `nuke`. For the dashboard there is no nuke: `A` → `Z`, then remove `/opt/grin/grin-stats`, `/opt/grin/grin-price`, `/var/www/grin-stats`, the vhost and `grin-submit` by hand |

```bash
# remove one community-submitted node (run on the server)
TOKEN=$(grep GRIN_SUBMIT_TOKEN /opt/grin/grin-stats/config.env | cut -d= -f2-)
curl -X DELETE "http://127.0.0.1:5060/remove-node?url=<the node URL>&token=$TOKEN"
```

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `No Grin node detected. Stats will fail until a node is running.` | Nothing listens on 3413 or 13413. Start the node ([Script 01](01-build-node.html) → `S`) and re-run the step |
| `Foreign API secret not found` / `Mainnet secret not found` at install | The node's secret files are not where `grin-server.toml` says. Rare on a toolkit node; `grin-secret-sync` from a root shell re-resolves them, or edit `config.env` |
| `[ERROR] No block headers in DB — run --init-history first.` | You chose `c`, `d` or `e` before the full import. Run `2` → `b` |
| `Another --update run is still in progress — skipping` in the cron log | Normal after a slow run; the lock prevents pile-up. If it repeats for an hour, a run is stuck — `pgrep -af grin-stats-collector`, kill it, and check the node |
| Charts stop moving, JSON files age past 10 minutes | Cron is off (`A` → `6`), or every run fails — read `/opt/grin/logs/grin_stats_cron.log`. HTTP `401` there means the node's secrets changed under a running collector; the next run's self-heal fixes it, or run `grin-secret-sync` |
| The price cards read the same value for hours | Gate.io or CoinGecko unreachable from the server; `A` → `2` → `i` shows the error. CoinGecko rejects requests without a browser-like user agent — the collector sends one, a hand-written fetch will not |
| `Certbot failed — verify DNS A-record resolves to this server` | The subdomain does not resolve here yet, or Cloudflare proxying is on. Fix DNS, wait, re-run `5` |
| `'prunemain' is reserved by script 02` | Those labels belong to the chain-data server. Pick another subdomain |
| Peer map shows dots on a blank blue background | The `assets/` folder is missing or empty in the web root — an incomplete toolkit checkout at install time. `git pull` in the toolkit and run `A` → `1` again |
| Explorer `C`: `Full archive node not found at /opt/grin/node/mainnet-full` | Build one with Script 01 (mode *full*), or configure a remote archive node with `2` → `2` |
| Explorer `C` exits right after `3` | Wrong `grin_dir`: `chain_data` must be directly under it. `2` again |
| Tiny Explorer: old block links return 404 | The node is pruned and the block is below its horizon (`/healthz` says `"node_mode":"pruned"`). An archive node fixes it |
| Tiny Explorer: the wallet checker's "is it online" button never appears | The probe is off in `config.json`, or the service was not restarted after turning it on. `D` → `2`, answer `y`; `6` shows the probe state |
| Tiny Explorer: the probe answers "could not check" for every wallet | No Tor SOCKS proxy on `127.0.0.1:9050`. `systemctl status tor`; `grep SocksPort /etc/tor/torrc` |
| `Port :8471 not listening yet — check: journalctl -u grin-tiny-explorer -n 20` | Usually a config error; the log names it |

## Related

- [Script 01](01-build-node.html) — pruned versus archive node, and how to build the archive the explorers want
- [GrinScan](06b-grinscan.html) — option `B` of this menu, on its own page
- [Script 04](04-publish-node-api.html) — the published node API that shares the `grin_api` rate-limit zone with the dashboard
- [Public pool](07-public-pool.html) — Script 07's pool, whose block and payout pages deep-link to a Tiny Explorer
- [Ports and paths](reference-ports-and-paths.html) — 5060, 8000, 8471 and the `/opt/grin` tree
- Deeper reading in the toolkit repository: [script06_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script06_design.md) (the peer map's geometry and grouping, the Tiny Explorer tools) and [script06_security_audit.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script06_security_audit.md)
