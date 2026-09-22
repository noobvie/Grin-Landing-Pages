---
title: Mine Grin on your own node (solo)
description: How Script 07 turns your Grin node into a private stratum server for solo mining — reward wallet, publishing the port, pointing a rig, stats, watchdogs, backup.
section: Scripts
order: 7
label: Script 07
covers: 2026-09-20
updated: 2026-09-20
---

A Grin **miner** is a machine that races to solve the *Cuckatoo32* proof-of-work; whoever solves the next block earns its **coinbase**, 60 GRIN, and there is a block about every minute. Today that machine is almost always an ASIC such as the iPollo G1 Mini. Most miners join a **pool** that shares blocks and rewards among many rigs for a fee. **Solo mining** cuts the pool out: your node itself hands work to your rig over the **stratum** protocol, and when your rig finds a block the whole 60 GRIN lands in a wallet on your server — no fee, no account, no Tor, no payout to wait for. The price is luck: a single rig finds blocks rarely and irregularly, so solo suits an owner (or a trusted group) who wants full rewards and full control, not a smooth daily income. Script 07's *Solo private mining* sets it all up on the node you built with [Script 01](01-build-node.html); the live example is [solo.grin.money](https://solo.grin.money).

> **Warning:** Status — the mining hub is marked **(DEV)** in the main menu. The solo product is deployed and in daily use (solo.grin.money had eight rigs connected when this page was checked), but two things to know before you point real hardware at it: the reward wallet's **passphrase is saved on the server** so the wallet can restart unattended (see [the wallet](#step-2-the-reward-wallet)), and this wallet is **not included in the toolkit-wide backup** — only in the solo menu's own encrypted backup (see [Backups](#backups)). The public pool in the same hub is a separate product with [its own page](07-public-pool.html).

## The mining hub — one setup per server

Main menu 7 opens a small hub. It offers the solo product twice and the public pool twice, and enforces one rule: **a server runs one mining setup.** Solo and the public pool both want the node's stratum port (3416), both write nginx rate-limit zones, and both lay out `/opt/grin` their own way, so the hub refuses to start one while it detects the other (it checks for the solo payout config, collector cron, stats password file, collector state or a `grin-solo-*` service; and for the pool's config files, directories or `grin-pool-manager` service). It prints which type is active at the top.

```text
  Grin Mining Services

  Active type: none yet — pick one below

  ─── Solo Mining Pool (private — yourself + friends)─────────
  1) Solo PRIVATE mining — Internet  (public domain + Let's Encrypt SSL · reachable anywhere)
  2) Solo PRIVATE mining — LAN       (internal network · plain HTTP stats page · no domain/SSL)

  ─── Public Mining Pool (open to anyone)──────────────────
  3) Public mining pool — Mainnet   (real GRIN · PPLNS, Tor payouts, web dashboard)
  4) Public mining pool — TESTNET   (independent test install · fast blocks · tGRIN, no real value)

  0) Back to main menu
```

| Row | What it is |
|-----|------------|
| Solo — **Internet** | This page. The stats page is served on a public domain with Let's Encrypt HTTPS and an optional password |
| Solo — **LAN** | The **same** solo setup (same wallet, ports, directories, watchdogs); only the stats page differs — plain HTTP on a private IP, no domain, no certificate, no password. For a home or office network. Switching between Internet and LAN later re-writes the stats vhost; the hub asks before it does |
| Public pool — Mainnet / Testnet | A full PPLNS pool for other people's miners, with Tor payouts and an admin panel. The testnet install is independent and can live next to a mainnet pool, but neither can share a server with solo. [Manual page](07-public-pool.html) |

You can also start the solo script directly: `bash scripts/07_grin_mining_solo.sh` for Internet mode, with `lan` appended for LAN mode. Started that way it performs the same Internet/LAN switch check itself.

## How solo mining works

Three pieces, all on one server, talking over localhost except for the miner:

```text
  your rig (e.g. iPollo G1 Mini)
     │  stratum+tcp://YOUR_SERVER_IP:3416      (13416 on testnet)
     ▼
  grin node — built-in stratum server           enable_stratum_server = true
     │  a block is found                        stratum_server_addr   = "0.0.0.0:3416"
     ▼  build_coinbase, localhost only          wallet_listener_url   = "http://127.0.0.1:3420"
  grin-wallet listener on 3420 (13420 testnet)  → the 60 GRIN coinbase is yours
```

- **The node** already has a stratum server built in; Script 01 leaves it switched off and bound to `127.0.0.1`. Solo setup turns it on, points it at the wallet, and *publishes* it — binds it to all interfaces and opens the firewall — so rigs elsewhere can connect.
- **The wallet** is an ordinary `grin-wallet` in `/opt/grin/solowallet/<network>/`, run as a **listener**: a single process serving grin-wallet's Owner API on port 3420 (13420 testnet) with the Foreign API mounted on the same port. The node calls it to build the coinbase output whenever a block is solved. That call never leaves the box.
- **The miner** logs in with any worker name; there are no accounts. The name is only a label on the stats page — and, if you enable the *payout split*, the part before the first dot groups a friend's rigs (`alpha.01`, `alpha.02` → `alpha`).

A coinbase is locked for **1,440 blocks (about 24 hours)** before it can be spent; the stats page shows how many of your blocks are still maturing. Everything else — stats page, watchdogs, quiet hours, backups, settlement — is optional tooling around those three pieces.

## Before you start

| You need | Notes |
|----------|-------|
| A **synced mainnet node** on this server | [Script 01](01-build-node.html). Pruned or full archive both work; the script finds whichever is running. A testnet node is optional — good for a rehearsal, since the flow is identical and tGRIN is worthless |
| A Cuckatoo32 miner | The **iPollo G1 Mini** and **G1** are the supported, tested rigs; the setup page lists GPU miners as *not yet tested*. Any C32 stratum miner should work in principle |
| Inbound **TCP 3416** (13416 testnet) open at your provider | Stratum is raw TCP straight to the node — it is never proxied through nginx. LAN mode needs it open on the LAN only |
| No other wallet on port 3420 / 13420 | The CMD wallet in `owner_api` mode, Fidelius, Grin Drop and the public pool wallet all use it. The script refuses to start its listener over a foreign process — it never kills one |
| A domain with an **A record** to the server, ports 80 and 443 open | **Internet mode, stats page only.** On Cloudflare the record must be *DNS only* (grey cloud): a proxied record cannot carry stratum, so miners would have to use the raw IP anyway |
| nginx, certbot, python3 | nginx and certbot are installed by the stats-page deploy if missing; the stats collector is Python 3 with no extra packages |

## Choices you will make

- **Network.** The top screen picks mainnet or testnet *once*; everything inside that branch then applies to that network without asking again. Mainnet is real GRIN; the banner turns red to say so.
- **Internet or LAN.** Decided in the hub (or by the `lan` argument). Only the stats page differs.
- **Who may reach the stratum port.** When publishing: open it to all IPs (the default), to one IP or CIDR range, or leave the firewall alone.
- **Payout split** (mainnet, asked during the stats-page deploy). Off if you mine alone. On if friends point rigs at your node: the page then shows what share of the work each nickname did and what they are owed, so you can pay them by hand. It is bookkeeping only — the coinbase still goes to your one wallet.
- **Access lock on the stats page** (Internet mode, recommended and the default). A username and password (HTTP Basic Auth over HTTPS) in front of the whole site, because a solo page shows your income. A sanitised `data/health.json` stays public for uptime monitors; you can also choose to publish the `poolstats` feed that miningpoolstats.stream polls.

## The menu

The solo top screen, as of today, with a mainnet node running and its stratum already published:

```text
  07) Grin Mining Service — Solo Private Pool (Internet mode)

  Node Status:
    Mainnet (3413): RUNNING
    Testnet (13413): OFF     (build/sync in Script 01)

  Stratum Status:
    Mainnet (3416): LISTENING  bind: PUBLIC  (0.0.0.0:3416)
    Testnet (13416): OFF         bind: NOT PUBLIC (127.0.0.1:13416)

  ─── Set up your solo private pool — top to bottom ────────
  A) Start here — node check      (is your node running & synced?)
  1) Configure solo private pool Mainnet  (real GRIN)
  2) Configure solo private pool Testnet  (tGRIN — no monetary value)
  3) Deploy stats web page        (public dashboard, both nets)

  ─── Overview & shared tools ──────────────────────
  4) Node, Wallet & Mining Status  (both networks)
  5) Watchdogs (global)            (node-sync · boot autostart · wallet · stratum)
  6) Maintenance                   (encrypted backup · restore · schedule · seed)
  7) Payouts & settlement          (mainnet running balance · record payments)
  8) Quiet hours (energy saver)    (auto-pause stratum in set hours · miners idle)

  ─── Danger Zone ──────────────────────────────────
  C) Clean up solo mining  (remove solo infra · keeps node + seed + backups)

  ↩  Press Enter to refresh
  0) Back to main menu
```

| Key | Action |
|-----|--------|
| `A` | **Node check** — read-only: is each node running and synced? Offers to start an installed node or to open Script 01 to build one. Do this first |
| `1` / `2` | Enter the **mainnet** or **testnet** branch: *Wallet*, *Stratum* and a *Terminal Stats* view for that network |
| `3` | **Deploy the stats web page** — one page for both networks, plus the collector and its 5-minute cron |
| `4` | Node, wallet and stratum status for both networks, including the values in each `grin-server.toml` |
| `5` | [Watchdogs and autostart](#watchdogs-and-autostart) — node-sync watchdog, node boot autostart, wallet-listener watchdog, stratum watchdog |
| `6` | [Maintenance](#backups) — refresh deployed code, encrypted backup and restore, daily schedule, show the recovery seed, off-site copies |
| `7` | [Payouts and settlement](#payouts-and-settlement) — mainnet balances per nickname |
| `8` | [Quiet hours](#quiet-hours) — pause the stratum port on a daily schedule |
| `C` | [Clean up](#removing-solo-mining) — removes the solo pieces, keeps the node, the seed and the backups |

Inside a network branch:

```text
  07) Solo Private Pool Internet — [MAINNET — REAL GRIN]

  Mainnet:
    Node   : RUNNING  (PID 1234, port 3413)
    Wallet : LISTENING  (PID 2345, Owner+Foreign port 3420)
    Stratum: LISTENING  (port 3416)
    Miners : 2 connected
    toml   : /opt/grin/node/mainnet-prune/grin-server.toml
    enabled: true
    bind   : 0.0.0.0:3416
    wallet : http://127.0.0.1:3420
    burn   : false

  1) Wallet          ▸ setup/recover · listener · auto-restart · address
  2) Stratum         ▸ setup & publish · manual config · restrict
  3) Terminal Stats  (live dashboard for Mainnet)

  ↩  Press Enter to refresh
  0) Back to network select
```

The sub-menus are shown in the steps below. Keys in this hub are positional and may move; the names are what to look for.

## Setting up, step by step

The order the node-check screen itself recommends: check the node, set up the wallet, set up and publish the stratum, point a miner, then add the stats page and the watchdogs.

### Step 1 — Node check

`A` on the top screen. Solo mining needs a **fully synced** node: a coinbase built by a node that is behind the chain is worthless. The screen asks each node for its status over the Owner API and prints *SYNCED* (grin's `no_sync`) or *still syncing — wait*. If a node is installed but stopped it offers to start it; if none exists it opens Script 01 in place and returns here when you leave it. A testnet node is listed as optional — the screen encourages one for practice.

### Step 2 — The reward wallet

Enter the network branch and open **Wallet**:

```text
  07) Solo Private Pool Internet · [MAINNET] · Central Wallet  (coinbase listener)

  Listener:
    [RUNNING] mainnet: session=yes port=3420(yes)
    [DOWN] testnet: session=no port=13420(no)

  Auto-restart: (@reboot + */5 listener watchdog)
    Boot autostart:
      [OK] Mainnet    [--] Testnet
    Listener watchdog:
      [OK]    Wallet-listener watchdog: INSTALLED (/etc/cron.d/grin-wallet-listener-watchdog)

  1) Setup / Recover    (download + init|recover + save pass + start)
  2) Start listener
  3) Stop listener
  4) Show address
    ── Auto-restart ──────────────────────────
  5) Enable boot autostart   (per net)
  6) Disable boot autostart  (per net)
  7) Install listener watchdog (*/5)
  8) Remove listener watchdog
    ── Binary ────────────────────────────────
  9) grin-wallet binary      (update · roll back · verify)
  0) Back
```

**Setup / Recover** does everything in one pass:

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | Downloads the pinned `grin-wallet` release (**v5.4.1**) into `/opt/grin/solowallet/<network>/` and checks its SHA256. The binary is kept in a shared store, so the *grin-wallet binary* screen can later update it or roll it back in one key | Wait |
| 2 | Asks for the setup mode: **new wallet** (`init`) or **recover from seed**. If a wallet already exists it asks before overwriting | `1` or `2`. On mainnet, read the red warning: this wallet receives real GRIN |
| 3 | Asks for a **passphrase** twice (at least 3 characters), then runs `grin-wallet init`. A new wallet prints its **24-word seed** — write it down now; it is the only way to recover the wallet on another machine. In recover mode grin-wallet asks you to type the 24 words itself | Type the passphrase; save the seed. If init prints `get_version: Cannot parse response`, ignore it — the wallet is not yet pointed at the node at that moment; the next step fixes it |
| 4 | **Saves the passphrase** to `.passphrase` in the wallet directory, readable by root only (mode 600). This is what lets the listener open the wallet unattended after a reboot or a crash | Nothing — but understand it: anyone with root on this server can spend this wallet. Keep the balance low and sweep rewards out (see [Day-to-day](#day-to-day-operations)) |
| 5 | Patches `grin-wallet.toml`: `node_api_secret_path` → the node's `.foreign_api_secret`; `log_max_files = 5`; `owner_api_listen_port` = 3420 / 13420; `owner_api_include_foreign = true`. Installs the 5-minute `grin-secret-sync` timer so a future node rebuild re-points the wallet automatically | Nothing |
| 6 | Writes the launcher `listen.sh` and **starts the listener** in a tmux session `grin_solowallet_<network>` (a root session — attach with plain `tmux attach`), then waits for the port and prints a `curl` you can use to prove the wallet is open and building coinbases | Read the summary |

> **Note:** Known item — the launcher reads the passphrase from the saved file, but today it still hands it to grin-wallet on the command line, so it is visible in the process list (`ps`) to any local user for as long as the listener runs. The script's own header records this and the fix (feed it on standard input, as the CMD wallet already does). On a single-owner box it changes little; on a shared box, treat it as one more reason to keep only rewards you are about to sweep in this wallet.

Then, in the same menu, turn on **boot autostart** for this network (a root-crontab `@reboot` line, delayed 40 seconds so the node is up first) and **install the listener watchdog** (a cron every 5 minutes that relaunches a listener whose port has gone quiet, at most once per 10 minutes). Both are also reachable from the global *Watchdogs* menu. *Show address* prints the wallet's `grin1…` slatepack address — not needed for mining, but useful if someone wants to send you GRIN directly.

### Step 3 — Stratum: Setup and Publish

Open **Stratum** in the same network branch:

```text
  07) Solo Private Pool Internet · [MAINNET] · Stratum Server

  1) Setup & Publish  (enable stratum + wallet URL → bind 0.0.0.0 + firewall + restart — all in one)
  2) Manual config    (hand-edit one field: enable / bind / wallet)
  3) Restrict         (revert to 127.0.0.1)
  0) Back
```

**Setup & Publish** finds the running node's `grin-server.toml` (via the process on the API port; otherwise it searches the standard directories and asks if it finds more than one) and walks through:

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | Shows the current `enable_stratum_server` and `wallet_listener_url`, then sets `enable_stratum_server = true` | `Y` |
| 2 | Sets `wallet_listener_url`. The default, `http://127.0.0.1:3420` (13420 testnet), is the listener from step 2. It is a **base URL** — the node appends `/v2/foreign` itself — and an old value on port 3415 or ending in `/v2/foreign` is corrected automatically | Enter for the default |
| 3 | Forces `burn_reward = false`. grin has a testing flag that throws coinbases away; the script never asks about it, so a solo miner cannot burn real rewards by accident | Nothing |
| 4 | **Publish:** explains that the node will bind `0.0.0.0:3416` (13416 testnet) so rigs elsewhere can reach it, then writes `stratum_server_addr` | `Y` |
| 5 | Firewall: open the port to **all IPs** (default), to **one IP or CIDR**, or **skip**. Uses `ufw` when present, otherwise `iptables` (saved with netfilter-persistent when available). Rules are not stacked on re-runs | `1`, `2` or `3` |
| 6 | **Restarts the node** so the new settings take effect: SIGTERM, up to 30 seconds' wait, then a relaunch through the toolkit's standard launcher — as the `grin` user, in its tmux session on the `gtmux` socket, never as root | `Y` (or `n` and restart the node yourself later — the toml is already patched) |
| 7 | Prints the **miner box** — the exact `stratum+tcp://IP:3416` URL to paste into a rig, with the server's public IPv4 cross-checked between the network interface and three public echo services (ipify, icanhazip, ifconfig.me), and a note if they disagree or the box is behind NAT | Copy the URL |
| 8 | Offers to **watch for your first miner**: a screen that counts established connections on the stratum port; Enter re-checks | Configure the rig, then press Enter until it shows *Miner connected* |

In LAN mode the miner box advertises the server's private LAN IP instead of a public one.

*Manual config* edits one of the three toml keys by hand and offers the same node restart. *Restrict* is the undo: binds the stratum back to `127.0.0.1`, removes the all-IPs firewall rule (a per-IP rule you added must be removed by hand) and restarts the node.

### Step 4 — Point a miner at it

For an **iPollo G1 Mini or G1**: open the miner's web panel on its LAN IP, log in, go to *Miners → Pool Configuration* and fill in Pool 1 — *Select Coin* `GRIN`, *Pool 1 URL* the `stratum+tcp://` line from the miner box, *Pool1 worker* a name of the form `nickname.NN` (for example `alpha.01`, a second rig `alpha.02`), *Pool1 password* anything. Set *Pool 2* and *Pool 3* to public pools as failover — there the worker is your own GRIN address, in whatever format that pool asks — so the rig keeps earning if your node goes down. Save, and reboot the rig if you can; it reconnects to Pool 1 within seconds and *CGMiner Status* should show the pool *Alive*. The deployed stats site carries this walkthrough with a screenshot at `/setup-solo-mining.html`, with the URLs pre-filled from your config and, in Internet mode, a live *reachable / unreachable* check of each stratum URL made from an off-box checker.

Prefer the **raw IP** over a domain in Pool 1: stratum is plain TCP to the node, a domain only works when its A record points straight at the server, and a Cloudflare-proxied record silently breaks it. A domain in Pool 1 is at most a convenience for when the IP changes.

> **Tip:** *Alive* alone does not prove the rig is on your node — a rig that cannot reach Pool 1 falls through to the public backup and keeps hashing there. The proof is your worker name appearing in the *Miners* table of your stats page, or `Got share at height …` lines in the node log. If the pool shows Alive and the worker never appears, the node's `file_log_level` in `grin-server.toml` is probably above `Info`: shares are logged at INFO (found blocks at WARN, which always shows). grin's default is Info, so this only bites if it was changed.

### Step 5 — The stats web page

`3` on the top screen deploys **one** static page for both networks at your domain (or LAN address). Nothing else runs for it: nginx proxies two small JSON endpoints per network to the node's Owner API and the wallet listener — injecting the node's API secret server-side so the browser never sees it — and a Python **collector** runs from cron every 5 minutes, parsing the node log for `Solution Found` and `Got share` lines into JSON files the page reads. No Node.js, no database service, no systemd unit. The prompts, in order:

| Prompt | Notes |
|--------|-------|
| *(auto)* Detects which networks have a node (by their `.api_secret`); installs nginx + certbot if missing | A missing network is greyed out on the page rather than failing the deploy |
| Subdomain, e.g. `solo.yourdomain.com` | Internet mode. Warns if the name does not resolve yet and lets you deploy over HTTP first. **LAN mode** asks instead for the LAN IP to bind (default: the box's own) and an HTTP port (default 80) |
| Header slogan | Optional; default *Your node, your keys, your rewards.* |
| Pool display name | Shown in the `poolstats` feed; default *Grin Solo (Node Toolkit)* |
| Public IP for miners | Pre-filled by the same detection as the miner box; feeds the setup page |
| Port-check API | Internet mode. The off-box service the setup page uses for its live reachability pills; defaults to the public Office Tools checker, or `-` to disable. Not offered in LAN mode |
| Google Analytics 4 ID | Internet mode, optional; the page's Content-Security-Policy is widened for Google only when set |
| **Payout split** (mainnet present) | On or off — see [Choices](#choices-you-will-make) |
| *(auto)* Installs the collector, its wrapper and cron, and runs it once | Prints how many block and share lines each node's log matched, and warns if `file_log_level` would hide shares |
| **Access lock** | Internet mode. Username and password; then whether to publish the `poolstats` feed. The password file is written with an `apr1` hash that nginx reads natively |
| *(auto)* Writes the nginx vhost (HTTP first), enables it, tests and reloads | The vhost holds the base64 API credentials, so it is mode 600 |
| Run certbot for SSL? | Internet mode. HTTP → HTTPS redirect included. If certbot fails, the page stays up over HTTP — and the access lock is **switched off**, because the script refuses to send passwords over plain HTTP; fix DNS and deploy again |

The page (see solo.grin.money) shows per network: found blocks in 24 h and how many are still maturing, active miners, whether the wallet listener is up, estimated earnings per day for your hashrate and for one G1 Mini, network difficulty and hashrate, your total hashrate, a miners list with 15-minute to 48-hour hashrates, and every block you found with its maturity or *orphaned* status. Below that: a blocks-found chart with a by-hour heatmap, a hashrate history chart, and — mainnet, when the payout split is on — the split, a GRIN-per-miner-per-day chart and a **Solo Health** card. A clock button switches per-event times between UTC and local; charts can be exported as PNG or CSV. Live tiles refresh every **120 seconds**, collector data every 5 minutes.

The collector keeps its durable state in **SQLite** — `/opt/grin/solo-stats/solo_mining_stats_main.db` and `…_test.db` — and regenerates the JSON files from it on every run. On mainnet, blocks are **chain-verified**: a found block is checked against the node at 60 confirmations and marked *orphaned* if the chain kept a different block at that height, and counted as matured only at 1,440 confirmations, so an orphan never inflates a payout. Testnet keeps no ledger, so its blocks are counted from the log alone.

> **Note:** *Solo Health* answers the question every solo miner asks — why did I earn less than a pool would have paid for the same hashrate? At equal *effective* hashrate you earn the same on average, minus the pool's fee; a real gap is lost effective hashrate. The card breaks it into an **orphan rate** (from the verified ledger; high means slow block propagation or poor peering) and **stale / rejected share rates** parsed from the node log, over daily to all-time windows, per worker where the log names one. Over a short window the rest is variance.

### Step 6 — Watchdogs and autostart

Do not skip this: a solo node that stops mining at 3 a.m. earns nothing until you notice. See [Watchdogs and autostart](#watchdogs-and-autostart) below.

## After it finishes

From a root shell on the server:

```bash
ss -tlnp | grep -E ':(3416|3420) '          # node stratum + wallet listener, both LISTEN
ss -tn  | grep ':3416' | grep -c ESTAB      # rigs connected right now
tail -f /opt/grin/node/mainnet-prune/grin-server.log | grep -iE 'got share|solution found'
```

Every accepted share logs a `Got share at height …, submitted by <worker>` line; a solved block logs `Solution Found for block <height>`. To prove the wallet is open and can build a coinbase:

```bash
curl -s -X POST http://127.0.0.1:3420/v2/foreign -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"build_coinbase",
       "params":{"block_fees":{"fees":0,"height":1,"key_id":null}}}'
```

An answer containing `"Ok"` means the wallet is unlocked and coinbases will land; a `null` or an error about the wallet or seed means the saved passphrase is missing or wrong — re-run *Setup / Recover*. (Use 13420 for testnet.) The *Terminal Stats* view in the network branch shows height, difficulty, network hashrate (computed from the last 60 block headers) and connected miners, refreshed on Enter; `4` on the top screen shows the same for both networks together, and the stats page's `data/health.json` publishes node, wallet and stratum liveness for an external uptime monitor even when the page is locked.

The wallet log repeats `Error calling get_version … 127.0.0.1:3413` when the node is down or busy. That is the wallet's own probe of the node and does not affect rewards: a coinbase is built by the node calling *into* the wallet, which needs no node connection. It only matters when you want to check a balance or spend.

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/solowallet/<network>/` | The reward wallet: `grin-wallet` binary, `wallet_data/` (the seed), `grin-wallet.toml`, `.owner_api_secret` / `.foreign_api_secret`, the saved `.passphrase`, the `listen.sh` launcher |
| `/opt/grin/node/<network>-<mode>/grin-server.toml` | The node config, with the three stratum keys patched |
| `/var/www/grin-solo-mining-stat/` | The stats site: `index.html`, `setup-solo-mining.html`, the screenshot and logo, and `data/` with `config.json` and the collector's JSON files |
| `/etc/nginx/sites-available/grin-solo-mining-stat` | The vhost — mode 600, because it holds the node API credentials |
| `/etc/nginx/conf.d/script07-solo-*.conf` | The three rate- and connection-limit zones |
| `/etc/nginx/grin-solo-stats.htpasswd` | The access-lock credentials, when set |
| `/usr/local/bin/grin-solo-mining-collector` (+ `.py`) | The collector wrapper and script; cron `/etc/cron.d/grin-solo-mining-collector` every 5 min |
| `/opt/grin/solo-stats/` | Collector state: `solo_mining_stats_main.db` / `_test.db`, watchdog cooldown stamps |
| `/opt/grin/conf/grin_solo_payment.json` | The payout-split switch (`{"enabled":true}`); absent when off |
| `/opt/grin/conf/grin_node_watchdog.json`, `/opt/grin/watchdog/` | Node-sync watchdog config and state |
| `/usr/local/bin/grin-node-sync-watchdog`, `…/grin-wallet-listener-watchdog`, `…/grin-stratum-watchdog` | The three watchdog scripts, each with a matching `/etc/cron.d/` entry and a log under `/opt/grin/logs/` |
| Root crontab `@reboot` lines tagged `grin_autostart_<net>` and `grin_solowallet_autostart_<net>` | Node and wallet boot autostart |
| `/opt/grin/conf/grin_solo_quiet.conf`, `/usr/local/bin/grin-solo-quiet`, `/etc/cron.d/grin-solo-quiet` | Quiet hours, when set |
| `/opt/grin/backups/grin_solo_backup_<DDMMYYYY>.tar.gz.enc` | Encrypted backups; key in `/opt/grin/conf/grin_backup.conf`, schedule in `grin_solo_backup.conf` |
| `/opt/grin/logs/grin_mining_<date>.log` | This run's log |

## Watchdogs and autostart

`5` on the top screen. Four independent guards; the first two protect **any** toolkit node, mining or not — this menu is where they are installed and removed (Super Auto in Script 01 installs them for you; Script 03 → `G` is a second door to the same autostart entry).

```text
  07) Solo Private Pool Internet · Health / Watchdogs

  1) Install node-sync watchdog    (restarts a wedged node)
  2) Remove  node-sync watchdog
  3) Enable  node boot-autostart   (@reboot · per net / both)
  4) Disable node boot-autostart   (per net / both)
  5) Install wallet-listener watchdog
  6) Remove  wallet-listener watchdog
  7) Install stratum watchdog      (alert if stratum drops)
  8) Remove  stratum watchdog
  0) Back
```

| Guard | What it does |
|-------|--------------|
| **Node-sync watchdog** | Cron every 5 minutes. Restarts a node that is down or not answering; and one that is *wedged* — port open, process alive, height not moving — but only when third-party height references confirm the chain has moved on by more than `tolerance_blocks` (10) on two consecutive checks. An unreachable reference never triggers a restart. 20-minute cooldown between restarts and a 20-minute grace after one. Config in `/opt/grin/conf/grin_node_watchdog.json` — **mainnet on, testnet off by default**; set `"testnet": true` there to cover it. The references shipped in the default config are public Grin endpoints; edit them if one goes away |
| **Node boot autostart** | One `@reboot` root-crontab line per network, started as the `grin` user on the `gtmux` socket: mainnet 5 seconds after boot, testnet 1,000 seconds later so two nodes never boot together on a small VPS. The same entry Script 01 Super Auto and Script 03 → `G` write |
| **Wallet-listener watchdog** | Cron every 5 minutes: if a set-up wallet's port (3420 / 13420) is not listening, relaunches its tmux session — at most once per 10 minutes. Covers both networks that have a saved passphrase. Log: `/opt/grin/logs/wallet-watchdog.log` |
| **Stratum watchdog** | Cron every 5 minutes that **only logs**: a warning to `/opt/grin/logs/stratum-watchdog.log` when a node's toml no longer says `enable_stratum_server = true`, or says so but the port is not listening. It does not repair anything — it tells you to |

The **wallet's** boot autostart (the 40-second `@reboot` line) lives in the wallet sub-menu, not here.

> **Warning:** A node **rebuild** in Script 01 (`M`, `T`, `K` or Super Auto — anything that regenerates `grin-server.toml`) drops the three stratum keys, and nothing puts them back for solo: mining stops silently and only the stratum watchdog's log notices. Re-run *Stratum → Setup & Publish* after any rebuild. `R` (chain data only) and `B` (binary update) keep the toml and are safe. *(Read from the code; not reproduced on a server.)*

## Backups

`6` on the top screen, **Maintenance**:

```text
  Maintenance — Deploy, Backup & Restore

  Dir: /opt/grin/backups · key: set · schedule: daily 03:30 · offsite: off

  1) Deploy new code       (refresh collector + web page from checkout · pull via 08→8 first)
  2) Backup now            (encrypted archive of wallets + stats + config)
  3) Restore from backup   (one-shot extract to original paths)
  4) Schedule daily backup (cron · 30-archive retention)
  5) Settings              (personal key · retention · list)
  6) Show recovery seed    (per net — the ultimate wallet backup)
  7) Offsite push (scp)    (auto-copy each archive to a remote server)
  0) Back
```

> **Warning:** The toolkit-wide backup (**[Admin & Maintenance → Backup](089-backup-restore.html)**, Script 089) finds wallets through a registry file that the solo setup does not write to, so it archives the solo *stats databases* but **not the solo wallet's seed**. The backup on this menu is the only one that does. Take one as soon as the wallet exists, and write the 24 words down as well.

- **Backup now** archives `/opt/grin/solowallet/` (every network's wallet, binary included so a restore runs at once), `/opt/grin/solo-stats/` (each SQLite database snapshotted with SQLite's own backup API, so a copy taken mid-write is never torn) and the payout-split file, encrypted with AES-256-CBC (600,000 PBKDF2 rounds) into `/opt/grin/backups/grin_solo_backup_<DDMMYYYY>.tar.gz.enc`, mode 600. The passphrase for an archive is your **personal key followed by that date** (`DDMMYYYY`, read from the file name). The personal key is one secret shared by every toolkit product's backups, stored in `/opt/grin/conf/grin_backup.conf` so the daily job can run unattended, and typed by hand on restore. Lose the key and the archives cannot be opened by anyone, you included — keep it somewhere that is not this server.
- **Schedule daily backup** installs a self-contained cron wrapper (default 03:30 server time, keeps the newest 30 archives); **Offsite push** copies each new archive to another server over `scp` with a dedicated SSH key.
- **Restore** lists the archives, asks for the personal key once, decrypts and validates, stops the wallet listeners, and extracts to the original paths. It restores files only: afterwards build or start the node (Script 01 — the node is **not** in the backup), start the wallet listener (the restored `.passphrase` opens it), re-run *Setup & Publish*, and redeploy the stats page. Autostart and watchdog crons are not in the archive either.
- **Show recovery seed** runs `grin-wallet recover` for one network, which asks for the wallet passphrase and prints the 24 words. Make sure nobody is looking.
- **Deploy new code** is for after a toolkit update ([Admin & Maintenance → Self-update](08-admin-maintenance.html#self-update-key-8)): the menu scripts run in place, but the collector and the stats page are copies, and this re-copies just those two without re-asking anything.

## Payouts and settlement

`7` on the top screen, mainnet only, and only once the stats page has run with the **payout split** on. It is a ledger, not a payment rail: nothing here moves GRIN or stores an address. The collector splits each *matured* block's 60 GRIN across nicknames in proportion to the share-difficulty their rigs submitted that day, and keeps a running balance per nickname — *All time earn*, *Paid*, *To be Paid*. When you have sent a friend their GRIN by hand, **Record a payment** (pick the row, Enter accepts the full amount owed, add a note) lowers their balance, and the page updates at once. **Payment history** lists the last 20. Blocks credit only once they are chain-verified at 1,440 confirmations, so an orphan is never paid out, and attribution of *who found the block* (the winning share's worker) is shown on the page as a leaderboard curiosity only — earnings are always split by work done, never handed to the lucky finder.

## Quiet hours

`8` on the top screen. An energy saver for the hours when electricity is expensive: at the *pause* time a cron inserts a firewall DROP for the stratum port (both networks, or one) and cuts the live connections, so the rigs lose their job feed and idle; at the *resume* time it removes the rule and they reconnect. The node keeps running and the toml is untouched, so the toggle is cheap. Times are the **server's local clock** — the menu prints the timezone — and a window may cross midnight. *Pause now* and *Resume now* act immediately; *Disable schedule* removes the cron **and reopens the port**, so disabling never leaves rigs locked out. The stats page shows the schedule in a banner.

## Removing solo mining

`C` on the top screen prepares the server for the public pool, or just cleans up. It lists what is present and then asks per group: disable stratum in both tomls and close the firewall ports (with an optional node restart so mining actually stops); remove the collector, its cron and `/opt/grin/solo-stats/`; remove the stats site, vhost and password file (the Let's Encrypt certificate is left; `certbot delete` if you want it gone); remove the stratum and wallet-listener watchdogs; remove quiet hours (reopening the port); remove the payout-split file; stop the wallet listener sessions. It **never** touches the node, the node-sync watchdog and boot autostart, the wallet directory with your seed, or the backups and key. For those, [Script 08's *Full cleanup*](08-admin-maintenance.html#full-grin-cleanup-key-del) is the tool.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| See whether everything is up | Top screen `4` — node, wallet and stratum for both networks; or the stats page; or `data/health.json` |
| Add a second rig | Point it at the same URL with a different worker name (`alpha.02`) |
| Let a friend mine here | Give them the URL; they use their own nickname (`bob.01`). Turn on the payout split (deploy the stats page again — it asks) so the page tracks what they are owed |
| Check the wallet balance or move rewards out | The wallet is a normal `grin-wallet`. Stop the listener first (*Wallet → Stop listener*), run `./grin-wallet info` or `send` from `/opt/grin/solowallet/mainnet` (it asks for the passphrase), then *Start listener* again — do it between blocks, the listener must be up when one is found. See the [CMD wallet page](05-wallet-services.html#the-cmd-wallet-quick-setup) for the wallet commands |
| Stop accepting outside miners for a while | *Stratum → Restrict* (back to localhost, node restart) — or *Quiet hours → Pause now* if the node should keep its config |
| Change the stats page's name, slogan or ports | Edit `/var/www/grin-solo-mining-stat/data/config.json`; the next collector run picks it up. Toggling analytics needs a redeploy (the CSP is regenerated) |
| Update grin-wallet, or roll back a bad update | *Wallet → grin-wallet binary* — one-key update to the pinned release, one-key rollback |
| Update the collector or stats page after a toolkit update | *Maintenance → Deploy new code* |
| Move everything to a new server | *Backup now*, copy the archive and note the personal key; on the new box build the node with Script 01, then *Maintenance → Restore* and follow its printed order |
| Run testnet as a rehearsal | Same steps in the testnet branch: ports 13416 / 13420, the same stats page shows both networks side by side |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| The hub says `Cannot start that` — the other mining type is already set up | The one-setup rule. Remove the pool (its own menu) or use another server |
| `Port 3420 is in use` by another process when starting the listener | Another wallet product on this server (CMD wallet in `owner_api` mode, Fidelius, Grin Drop, the pool wallet). Stop it, or run solo on a different box — the script never kills a foreign process |
| `No saved passphrase` — the listener will boot locked | `.passphrase` is missing (deleted, or the wallet was created outside the menu). Keeping the existing wallet in *Setup / Recover* does **not** re-save it: answer *y* to re-initialise and choose *Recover from seed* — the same wallet comes back from its 24 words and the passphrase is saved again. (Or create the file by hand, mode 600, holding just the passphrase) |
| `build_coinbase` returns `null` or a wallet/seed error | The listener is running but the wallet is locked — wrong or missing saved passphrase. Same fix |
| Rig says Alive but never appears in the miners list | It fell through to a backup pool, or the node's `file_log_level` hides shares — see the tip in [Step 4](#step-4-point-a-miner-at-it) |
| `No miner connected yet` for more than a few minutes after publishing | The rig's URL does not match the miner box; the provider firewall still blocks 3416; the node did not restart after publish (`4` shows `bind: 127.0.0.1`); or the domain in Pool 1 is Cloudflare-proxied — use the raw IP |
| Stats page shows a network as *not deployed* / greyed out | That node had no `.api_secret` at deploy time. Build it, then deploy the stats page again |
| Wallet Listener tile says down while the stratum works | The listener crashed and the watchdog is not installed (or is in its 10-minute cooldown). *Wallet → Start listener*, then install the watchdog. Blocks found meanwhile are lost — the node cannot build a coinbase without it |
| `No node .api_secret found` when deploying the stats page | No toolkit node on this box, or its directory is not registered. Build one with Script 01 first |
| certbot failed — page is live over HTTP only, and the password lock is off | DNS does not point here yet (or Cloudflare is proxying). Fix it and run the deploy again; the saved credentials are reused |
| `Access lock NOT active` printed at the end of the deploy | Same cause — deliberate. Get HTTPS working first |
| Mining stopped after a node rebuild | The rebuild regenerated `grin-server.toml`. Re-run *Setup & Publish* (see the warning under [Watchdogs](#watchdogs-and-autostart)) |
| Miners idle at the same time every day | Quiet hours are scheduled. `8` shows the window; *Resume now* or *Disable schedule* |
| A found block shows *orphaned* | Another miner's block at the same height won the race; yours is worthless and excluded from earnings. A high orphan rate on the Solo Health card points at slow block propagation — check the node's peer count and the server's bandwidth |
| `Wrong key or corrupt backup` on restore | The personal key differs from the one the archive was made with, or the file name's date was changed. The key is `grin_backup.conf` on the old box |

## Related

- [Script 01](01-build-node.html) — the node this mines on; rebuilds and the `S` start key
- [Script 03](03-share-chain-data.html#g-and-h-start-the-node-on-reboot) — the other door to node boot autostart
- [Wallet hub](05-wallet-services.html) — what a Grin wallet is; the CMD wallet commands for moving rewards
- [Ports and paths](reference-ports-and-paths.html) — 3416 / 13416 and the solo directories in context
- [Public pool](07-public-pool.html) — the other half of this hub: a PPLNS pool for other people's miners
- [Back up and restore](089-backup-restore.html) — the toolkit-wide backup (089), which covers the solo stats but not the solo wallet; [Full cleanup](08-admin-maintenance.html#full-grin-cleanup-key-del)
