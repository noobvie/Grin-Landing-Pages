---
title: Run a public mining pool
description: How Script 07 deploys GRINIUM, a self-hosted PPLNS Grin pool with no miner accounts, Tor and slatepack payouts, an admin panel and optional regional gateways.
section: Scripts
order: 7.5
short: Public pool
label: Script 07
covers: 2026-10-23
updated: 2026-10-24
---

The public pool is the second half of the mining hub (the first half, [solo mining](07-mining-services.html), has its own page). It turns your node into a **mining pool** that other people point their rigs at: a [stratum server](reference-glossary.html#stratum) on a public port, a website with live stats, a per-miner account page, and an admin panel where you set the fee and watch the money. The toolkit's job is the infrastructure — Node.js app, database, systemd, nginx and SSL, the pool wallet, backups. Every business decision (name, fee, payout floor) is made in the web admin panel after setup, not in a config file.

You need a synced **mainnet node** from [Script 01](01-build-node.html) (pruned is fine), a domain, and a passphrase for the pool wallet the setup creates.

> **Warning:** Status — the main menu does not mark the mining hub **(DEV)**, but this product is still being built. The reference pool, grinium.com, runs on mainnet with real miners, and that is where the toolkit's pool is tested. Its first [Tor](reference-glossary.html#tor-and-onion-addresses) payout, in September 2026, failed because the pool could not find `grin-wallet` (fixed since). Much of what is on this page was built after that and has **not** run on a server yet: Tor payouts as they work now (one attempt per payout), the [stratum pause](reference-glossary.html#stratum-pause), the hub move (*Migrate OUT / IN*), operator revenue withdrawals, the `/play/` games service, the gateway latency probe and the [Goblin](reference-glossary.html#goblin) rail. Make your first payouts small, and read [Fees and payouts](#fees-and-payouts) before you announce a fee. Nothing on this page should be read as "proven in production".

## What you get

**For a miner**, the pool works like the large Grin pools: there is no sign-up. The rig logs in to `pool.yourdomain.com:3333` with its **[Grin slatepack address](reference-glossary.html#slatepack-address)** as the username (optionally `address.rigname`), and that address *is* the account. A public account page shows its hashrate, workers, share quality, balance and payout history; the pool pays to that same address, so a miner can be paid without ever having had a login. There is no login to steal.

**For you**, the operator:

- a **stratum proxy** in front of the node's built-in stratum that counts every share, on your own public port;
- **[PPLNS](reference-glossary.html#pplns)** reward sharing, block [maturity](reference-glossary.html#coinbase-and-maturity) tracking, [orphan](reference-glossary.html#orphan-block) detection with exact reversal;
- payouts to miners over **Tor** (the pool's wallet talks straight to the miner's wallet) or by **slatepack** (copy-paste), plus a Goblin rail that is off by default;
- a **stratum pause**: close every stratum port for a set time from the admin panel, with a notice on the public site;
- a **website** (dashboard, blocks, miners, payments, network map, blog, pages) with a white-label branding system and 14 themes (two enabled out of the box);
- an **admin panel** with a full money statement, a payout kill-switch, operator revenue withdrawals, sessions, regions, ads, incentives, CMS;
- **regional gateways**: thin stratum forwarders on other continents that tunnel miners to this box, added later without a rebuild;
- an encrypted **backup**, a guided **move to a new server**, and a JSON **API** documented at `/api-docs.html` on your domain;
- optionally, **Play & chat**: a `/play/` games and chat service for your miners, run as its own process beside the pool.

The deep design — why address-as-identity, why SQLite, why Tor — is in the toolkit's [script07_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/reference/script07_design.md); this page is the operator's manual.

## What it does

The pool server install (the *Pool server* mode) puts these on the box:

1. **Node.js 24** from NodeSource (the pool uses Node's built-in SQLite, so 24 is a hard minimum), `logrotate`, `sqlite3`, `wireguard-tools` (only used if you add gateways later) and `fail2ban`. The pool app is copied to `/opt/grin/pubpool/mainnet/`, its dependencies installed with `npm ci`.
2. A **systemd service** `grin-pool-manager` running as the unprivileged `grinpool` user under a hardened unit, plus a logrotate rule for `/opt/grin/logs/grin-pool.log`, a fail2ban jail on the admin login, and the `grin-gateway-ctl` helper the multi-region path uses.
3. A **config file** `/opt/grin/conf/grin_pubpool.json` seeded with defaults (fee 1 %, payout floor 25 GRIN, ports) and a random JWT secret.
4. The **website** in `/var/www/grin-pool/` with the admin panel under `/admin/`.
5. An **nginx vhost** for your domain — HTTP first, then a Let's Encrypt certificate, then the full HTTPS vhost with rate-limit zones, security-header snippets, Cloudflare real-IP support if you want it, and an optional IP allowlist on `/admin/`. If nginx or certbot is missing, this step offers to install them.
6. A **pool wallet** in `/opt/grin/pubpoolwallet/mainnet/`: its own `grin-wallet` binary, a new or recovered seed, and one *combined* listener on port **3420** that serves both wallet APIs — the node's stratum calls it to build the coinbase of every block template, and the pool backend calls it to send payouts. The passphrase is saved to a mode-600 file owned by the service user and the listener is unlocked over the encrypted Owner API; it is never on a long-running command line. This step also installs the toolkit's `grin-secret-sync` timer.
7. The **first admin account**, created from the box over loopback; the public registration route closes as soon as one admin exists.

One thing the menu does *not* do for you: the node's own stratum server has to be switched on and the node restarted. See [Wire the node and restart it](#wire-the-node-and-restart-it) — skip it and the pool has no work to hand out.

## Before you start

| Need | Why |
|------|-----|
| A synced **mainnet node** from Script 01. Pruned or full, either is fine | The pool's stratum proxy feeds from the node's built-in stratum on `127.0.0.1:3416` and reads the node's API on 3413. Nothing in the pool needs old block bodies |
| A **domain or subdomain** with an A record pointing at this server (and `www.` too — the certificate covers both) | The site and the admin panel are served over HTTPS; Configure refuses to continue without a domain, and it is the one setting you cannot change from the admin panel |
| **80, 443 and 3333** open in your provider's firewall | Website, certificate issuance, and the public stratum port miners connect to. Add **51820/udp** only when you pair a regional gateway |
| **Tor** on the box | Script 01 installs it in step 2. The wallet uses it to reach miners' wallets, and the payout pre-flight check dials the local SOCKS port 9050 |
| **No solo mining** on this server | One mining setup per box. The pool script refuses to install next to a solo setup, and the hub refuses the other way round — they collide on the stratum port, nginx zones and `/opt/grin` |
| A **wallet passphrase**, written down somewhere safe | The setup creates the pool wallet and stores the passphrase on disk for unattended unlocks; you still need it for a recovery on a new box |

## Choices you will make

### Mainnet or testnet

Pick the network on the mining hub's menu, before the pool script even starts. **Mainnet** is the real pool, with real GRIN. The hub also offers a **testnet** pool: a fully independent install — `grin-pool-manager-testnet`, `/opt/grin/pubpool/testnet/`, config `grin_pubpool_testnet.json`, API port 8090, stratum **13333**, wallet port 13420, a `tgrin1…` address, block maturity 100 instead of 1440 — that needs its own domain and a testnet node, and can share a box with a mainnet pool. The toolkit's own pool is tested on mainnet only, so nothing on this page has been checked against the testnet mode.

### One server, or a pool server plus regional gateways

A single **Pool server** serves every miner in the world on its own port 3333 as region `main`. That is the normal pool and the only thing you need. If you later want lower latency for miners on another continent, you add a **[regional gateway](reference-glossary.html#wireguard)** — a separate small VPS that runs a stratum forwarder and a WireGuard tunnel back to the pool server, and nothing else — without rebuilding anything. See [Regional gateways](#regional-gateways-multi-region). An advanced third mode, *Central Hub* (a brain with no local stratum, all mining arriving through gateways), is not on the menu; it is started with `bash 07_grin_mining_public_pool.sh hub`.

### Behind Cloudflare?

Setup nginx asks once, default **yes**. Most public pools front their site with Cloudflare's proxy, and behind it every visitor arrives from a Cloudflare IP — so the toolkit restores the real visitor address from `CF-Connecting-IP`, otherwise the rate limiter and fail2ban would treat all visitors as one. Answer `n` if your DNS points straight at the box. If you *are* behind Cloudflare, the script also prints a `ufw` recipe to allow 80/443 only from Cloudflare's ranges, so nobody can talk to the origin directly.

### Who may open the admin panel

By default the admin panel is reachable from **any IP** — the login form, captcha, per-account lockout, IP auto-ban, optional two-factor and fail2ban are the only gate. The script tells you so twice. Once the pool is live, put your own IP (or VPN range) into `admin_allowlist` in the pool config and re-run *Setup nginx*: `/admin/` and `/api/admin/` then answer 403 to everyone else, with localhost always allowed as the break-glass path. Once the list holds at least one entry, the summary at the end of the guided setup prints a one-line `node -e …` command that adds a further IP for you; the first entry you type into the config yourself (`S` on the pool menu).

## The menus

The hub (main menu 7) picks the mining type and the network:

```text
  Grin Mining Services

  Active type: none yet — pick one below

  Pick ONE option only — a server runs a single mining setup.
  All three clash on the stratum port, nginx zones, and /opt/grin, so only
  one can be installed per server (the others are blocked once one is set up).

  ─── Solo Mining Pool (private — yourself + friends)─────────
  1) Solo PRIVATE mining — Internet  (public domain + Let's Encrypt SSL · reachable anywhere)
  2) Solo PRIVATE mining — LAN       (internal network · plain HTTP stats page · no domain/SSL)

  ─── Public Mining Pool (open to anyone)──────────────────
  3) Public mining pool — Mainnet   (real GRIN · PPLNS, Tor payouts, web dashboard)
  4) Public mining pool — TESTNET   (independent test install · fast blocks · tGRIN, no real value)

  0) Back to main menu
```

The pool script then asks *what* you are installing on this box:

```text
  Public Mining Pool Deployment Mode — Mainnet
  ● MAINNET — real GRIN (8080 / grin1 wallet / mainnet node). Live funds.

  What are you installing?

  1) Pool server      The pool itself — runs everything. Start here.
                     Serves local miners as region "main"; accepts
                     regional gateways from other zones later — no rebuild.

  2) Regional gateway A thin stratum forwarder on ANOTHER box: no node,
                     no wallet — tunnels miners to your pool server (Model C).

  Z) Cleanup public pool  (remove pool/hub/gateway infra · keeps node + wallet + backups)
  0) Back to mining hub

  Run a Gateway on a DIFFERENT box from the pool server (they share
  port 3333). Advanced — a mining-less central hub:
  `bash 07_grin_mining_public_pool.sh hub`.
```

Pick the pool server and you land on the pool menu. The `·` next to setup steps turns into a `✓` as each one's artefacts appear on disk, so a re-run knows what is already done:

```text
  GRINIUM — Grin Public Mining Pool (Mainnet)

  Service: not installed

  ─── First-Time Setup ────────────────────────────
  G) Guided Full Setup    (runs all setup steps 1→7)

  ─── Manual Setup Steps ───────────────────────────
  1) · Install             (nodejs ≥24, npm, sqlite3, systemd, fail2ban)
  2) · Configure           (pool name, domain, fee, stratum port)
  3) · Deploy web files    (frontend → /var/www/grin-pool)
  4) · Setup nginx         (vhost + SSL + rate limits)
  5) · Set up wallet       (combined coinbase + payout, Owner+Foreign 3420)
  6) · Service control     (start / stop — start before creating admin)
  7) · Create admin account (first admin user — needs service running)

  ─── Administration ───────────────────────────────
  8) Pool status           (service, port, DB, recent logs)
  9) Deploy new code       (refresh from checkout · restarts only what changed)
  A) Admin recovery        (locked out: clear 2FA / reset password — break-glass)
  W) Multi-region          (WireGuard server + add regional gateways)
  P) Play & chat (games)   (/play/ service: not installed · never restarts the pool)
  B) Backup & Restore      (encrypted: DB + wallet + WG identity · offsite push)
  C) Cron tasks            (backup schedule, VACUUM)
  L) View logs             (tail -50 | less)
  S) Edit config           (/opt/grin/conf/grin_pubpool.json)

  ─── Danger Zone ──────────────────────────────────
  DEL) Reset database    (⚠ permanently wipes all data)

  0) Back to deployment mode menu
```

| Key | Action |
|-----|--------|
| `G` | The [guided setup](#guided-setup-step-by-step): steps 1–7 in a row, asking only for real inputs |
| `1–7` | The same steps one at a time. Every step is safe to re-run: Install refreshes the code and the service unit without touching the database or the wallet password |
| `2` | Despite its label, Configure asks for **the domain** and, optionally, where this server is (a region name, country and two-letter code shown as a flag on the connect card). Name, fee and everything else are set in the admin panel |
| `5` | Opens the [wallet submenu](#the-pool-wallet) — setup, listener start/stop, address, node patch, autostart, watchdog, replace wallet, binary update |
| `8` | Service state, listening port, database size and URL, plus the last 15 log lines |
| `9` | After you update the toolkit checkout: copies the new backend and frontend into place, re-runs `npm ci` only when the dependency files changed, and restarts the service **only if** code it runs changed (a change to web pages alone does not restart it). If an earlier deploy was never loaded, it restarts for that too. Also deploys the games service when it is installed |
| `A` | [Break-glass recovery](#the-admin-panel) for a locked-out admin: list accounts, clear two-factor, set a new password, new recovery codes, unlock |
| `W` | [Regional gateways](#regional-gateways-multi-region): WireGuard server, add or remove a gateway, list, DNS name for the endpoint |
| `P` | [Play and chat](#play-and-chat-games): the `/play/` games service — install, deploy, nginx, status, uninstall |
| `B` | [Backups](#backups-and-scheduled-tasks) and the [hub move](#move-the-pool-to-a-new-server) |
| `C` | [Scheduled tasks](#backups-and-scheduled-tasks): daily backup, weekly VACUUM, run a VACUUM now |
| `S` | Opens the config JSON in your editor — for the few keys the admin panel does not own, such as `admin_allowlist` |
| `DEL` | Deletes `pool.db` — every balance, share, block and withdrawal — after typing `RESET POOL DATABASE` and then `YES`. The service is stopped, the file removed, and the service started again at once with a fresh empty schema |

> **Danger:** `DEL` takes no backup first and cannot be undone. Every miner's balance is in `pool.db` and nowhere else; the coins stay in the pool wallet, but the record of who is owed what is gone. Run `B` → `1` *Backup now* before you use it on a pool that has ever had a miner.

## Guided setup, step by step

`G` runs the seven steps without pausing between them; it stops only for real input. Steps already marked `✓` offer to be skipped, so an aborted run resumes where it left off. Everything not asked here is a default you change later in the admin panel.

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | Refuses to start if solo mining or a gateway is on the box. Installs packages and Node.js 24, copies the app to `/opt/grin/pubpool/mainnet/`, runs `npm ci`, generates the JWT secret and default config, creates the `grinpool` user and the hardened service unit, logrotate, the fail2ban jail (10 failed admin logins in 15 minutes → a 10-day firewall ban) | Wait |
| 2 | Asks for the pool's domain and validates it; then the optional region label, country and ISO code for the connect card | Type `pool.yourdomain.com`; Enter through the location fields or fill them in |
| 3 | Copies the website to `/var/www/grin-pool/`, the admin panel to `/admin/`, writes `js/pool-config.js` with the pool name, fixes ownership for nginx | Nothing |
| 4 | Offers to install nginx and certbot if either is missing. Writes the five rate-limit zones and the header snippets; asks about Cloudflare; writes an HTTP-only vhost, tests and reloads nginx; runs certbot for the domain **and** its `www.` alias with `admin@<domain>` as the account email; then writes the full HTTPS vhost and reloads again. Warns loudly if the admin panel is open to all IPs | Answer the Cloudflare question; answer `Y` to issue the certificate (or `n` and re-run step 4 later) |
| 5 | Asks for the wallet directory (default `/opt/grin/pubpoolwallet/mainnet`), downloads and verifies `grin-wallet`, asks for a passphrase twice, initialises a **new** wallet, checks the passphrase actually opens it, saves it to `/opt/grin/pubpool/mainnet/.wallet_pass`, patches the wallet's config (ports, combined listener, the node's foreign secret) and the node's `wallet_listener_url`, starts the listener in a tmux session, unlocks it, and records the wallet's address as `pool_address` in the pool config. If a wallet already exists it asks: use it, create a new one (the old directory is archived, not deleted), or recover from a seed phrase | Enter the passphrase (use a long one); for a recovery, type the 24 words when `grin-wallet` itself asks for them. **Write down the seed** a new wallet prints |
| 6 | Starts `grin-pool-manager` and waits for port 8080 (the first start creates the database schema, so it takes a moment) | Nothing |
| 7 | Asks for the admin username (3+ characters), password (8+, twice) and an optional email, and registers the account over loopback — no captcha, nothing on the command line | Choose them; keep the password in a password manager |

The run ends by printing your URLs: the pool site, `https://<domain>/login.html` for the admin panel, `https://<domain>/api-docs.html`, and the feed URL to hand to miningpoolstats.stream if you want to be listed there (they poll it; nothing is pushed).

If step 5 does not end with the listener up **and unlocked**, the script says so and asks whether to continue anyway. Say no: a pool whose wallet is locked cannot build coinbases and hands out **no work at all** — miners connect and sit idle. Fix the cause and re-run `5`.

## Wire the node and restart it

Script 01 deliberately leaves the node's built-in stratum server switched **off** — mining is Script 07's business. The pool relies on the toolkit's `grin-secret-sync` timer (step 5 installs it) to flip it on: every 5 minutes it checks `grin-server.toml` and sets `enable_stratum_server = true`, `stratum_server_addr = "127.0.0.1:3416"` and the `wallet_listener_url` that step 5 also patched. It only rewrites keys already in the file, which a toolkit-built node has. Those keys are read only at node start-up, so **the node must be restarted once** after the wallet setup. Do it right away rather than waiting for the timer:

```bash
grin-secret-sync                        # applies the stratum keys now; says RESTART if it changed them
```

Then restart the node from **Script 01 → Stop a node**, followed by **Start a node** (or, if the [sync watchdog](07-mining-services.html#watchdogs-and-autostart) is installed, stop it and let the watchdog bring it back within 5 minutes). Confirm the node's stratum is listening before you announce the pool:

```bash
ss -tlnp | grep 3416                    # the node's stratum, localhost only
cd /opt/grin/node/mainnet-prune
grep -E 'enable_stratum|stratum_server_addr|wallet_listener_url' grin-server.toml
```

> **Note:** The guided setup prints "complete" before this step, and nothing in the menu says the node needs restarting except the wallet step's one-line warning. Until you do it, the pool's own log shows it failing to log in to the node stratum and every miner sees no jobs. This is a gap in the script, not in your setup.

The same timer puts the three keys back after a Script 01 rebuild regenerates `grin-server.toml`, and prints `RESTART the mainnet node` when it did; restart the node again after any rebuild.

## After it finishes

Two more things the setup leaves to you, both in the wallet submenu (`5`): enable **Auto-restart on boot** (`6` → `e`) and install the **watchdog** (`7` → `i`). After a reboot the wallet's decrypted seed is gone from memory; without these, the listener stays down or locked and the pool issues no work until you log in and fix it by hand. The watchdog runs every 5 minutes and relaunches or re-unlocks the listener.

Now check the parts:

```bash
systemctl status grin-pool-manager --no-pager      # active (running), User=grinpool
ss -tlnp | grep -E ':(3333|8080|3420|3416) '       # stratum, API, wallet, node stratum
tail -n 30 /opt/grin/logs/grin-pool.log            # should show the node-stratum login succeeding
tmux attach -t grin_pubpoolwallet                   # the wallet listener; Ctrl+B D to leave
curl -s https://pool.yourdomain.com/api/pool/poolstats | python3 -m json.tool
```

The last one is the public stats feed; a JSON document with your pool name, hashrate and block count proves nginx, the API and the database are all talking. Open `https://pool.yourdomain.com` and its `/login.html`; sign in with the admin account you created.

Then point a rig at it. Any Grin miner that speaks stratum works (iPollo G1 and G1-Mini, lolMiner, GMiner…); the connect card on the homepage shows the exact endpoint and a mock of a miner's *Pool Setting* form:

```text
Pool URL   pool.yourdomain.com:3333        (bare host:port; no stratum+tcp:// prefix needed)
Worker     grin1…your 62-character slatepack address….rig1
Password   anything but a trivial one — see below
```

A bare worker name without the address is rejected: the address *is* the identity. The **password** is not an account password — the pool keeps a hash of it, and of the rig's IP, from the rig's first accepted shares (up to ten of each per address), and they later serve as proof of ownership when that address requests a payout. Trivial passwords (`x`, `123`, the miner defaults) are ignored for that purpose, so tell your miners to set a real one.

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/pubpool/mainnet/` | The pool app. `pool.db` (every balance, share, block and withdrawal — the money) and `.wallet_pass` live here too, with the admin panel's `uploads/` and `custom_assets/` |
| `/opt/grin/conf/grin_pubpool.json` | Pool config: domain, ports, `pool_address`, `jwt_secret`, `admin_allowlist`, `cloudflare_proxy`. The admin panel's own settings are stored in the database |
| `/opt/grin/pubpoolwallet/mainnet/` | The pool wallet: `grin-wallet` binary, seed, `grin-wallet.toml`, the listener launcher and the unlock helper |
| `/var/www/grin-pool/` | The website and `/admin/` |
| `grin-public-pool-mainnet` in `/etc/nginx/sites-available/` | The vhost; the security-header snippets it includes are under `/etc/nginx/snippets/` |
| `grin-pool-manager.service` in `/etc/systemd/system/` | The service (runs as `grinpool`) |
| `grin-pool.conf` in `/etc/fail2ban/jail.d/` and its filter | The `grin-pool-login` jail: 10 failed admin logins in 15 minutes → a 10-day ban |
| `/usr/local/bin/grin-gateway-ctl` | The one root helper the service may call (through `/etc/sudoers.d/grin-pool-gwctl`), for WireGuard pairing |
| `grin-pool-admin-reset-mainnet` in `/usr/local/bin/` | The break-glass admin recovery CLI |
| `/opt/grin/logs/grin-pool.log` | The service log (rotated daily, 10 kept); `grinium_<date>.log` beside it is each menu run's log |

The five rate-limit zones live in `/etc/nginx/conf.d/` as `script07-grin-pool-manager.conf`.

A testnet pool uses the same layout with `testnet` in place of `mainnet`, `-testnet` on the service, vhost and helper names, and `/var/www/grin-pool-testnet/`.

## The admin panel

Sign in at `https://<domain>/login.html`; it redirects to `/admin/`. There are **no default credentials**: the only admin is the one step 7 created on the box, and registration closed the moment it existed. The session is an httpOnly cookie with an idle timeout and a hard maximum lifetime, both set under *Access Control*. Money-moving and destructive actions ask for your password again in an in-page dialog (step-up), and you can require two-factor for every admin. Every admin page has a search box that finds a page, a section or a single setting.

The left rail has four groups:

| Group | Pages |
|-------|-------|
| **Dashboard** | *Miners*, *Donors*, *Blocks*, *Security* (login security, admin sessions, payout request audit), *Regions*, *System Health*, *Node Availability* |
| **Payouts** | *Queue* (payout requests, manual payouts, operator revenue), *Treasury* (the money statement: what the wallet holds against what the ledger owes; the wallet-send audit; switching the pool wallet), *Dormant balances* |
| **Games** | The `/play/` service's own pages, shown whether it is on or not: overview, chat moderation, players, events, nicknames |
| **Settings** | One page per section, below |

| Settings page | What it sets |
|---------|--------------|
| Pool Info | Pool name, tagline, description, the **pool fee %** (0–50, default 1) |
| Branding | Logo, colours, which of the 14 public themes visitors may pick, social links, which chain explorer block and payout links open — the white-label layer |
| SEO / Analytics | Meta tags, sitemap, an analytics provider (GA4, Plausible, Umami or Matomo); with GA4 a miner's address is scrubbed from the page URL before it is reported |
| Pages / Blog / Announcements / Ads | The built-in CMS: static pages, posts, a site-wide banner, and promo slots you sell or fill yourself. *Announcements* also holds Maintenance Mode and the [stratum pause](#pause-the-stratum) |
| Payout | **Minimum withdrawal** (default 25 GRIN), the flat **withdrawal fee** (default and minimum 0.04), the cooldown after a reversed payout, the slatepack response window, the Tor pre-flight check, block confirmation depth, the Goblin rail switch (off), the dormant-balance policy (off) |
| Incentives | Prize pool, join bonus, streaks, jackpot draws and contests, miner donations — all optional, all funded from the pool's own fee bucket or top-ups |
| Games / Names | The `/play/` switch (off, preview or on) and chat, and the blocked-word list for player names |
| Access Control | Admin IP allow/deny lists at the app layer, session timeouts, require-2FA, the password blocklist |
| Database | Retention windows for shares, per-miner hashrate history, resolved alerts, the raw ledger and the audit log |

Changing the fee, the payout floor or the retention windows takes effect on save (a few keys say *applied at restart* on the page).

**The payout freeze** is a kill-switch on the *Payouts* pages (*Queue* and *Treasury*). Engaged, the pool stops every outbound send — Tor, slatepack, Goblin — while still refunding expired slates to miners. The alert monitor engages it on its own when the money checks trip (wallet balance below what miners are owed, a balance that moved without a ledger row); a restore engages it too; you engage it by hand when a wallet or box looks compromised, or before you swap the wallet. Miners see a *payouts paused* chip on their account page, never the reason. Resume from the same place once you understand what happened.

**Locked out?** `A) Admin recovery` on the pool menu needs a root shell on the box and nothing else: list the admin accounts, clear a lost authenticator, set a new password (prompted, never on the command line), mint new recovery codes, or clear a failed-login lockout. Every action writes an audit row.

## Fees and payouts

The pool fee is a percentage of each **block reward**, taken when the block **matures** — 1440 confirmations on mainnet (about a day) — never at withdrawal time; 0 % is allowed, for a promotion. Rewards are shared **PPLNS** over the shares submitted in the last **60 blocks**, so a miner who leaves just before a block is found still gets their share of it, and pool hopping does not pay. A block that turns out to be an orphan has its exact credits reversed from every account it paid, fee included. Balances are the miner's to withdraw once they reach the **minimum withdrawal**, 25 GRIN by default (each payout is an interactive transaction that leaves a permanent kernel on chain, hence the high floor). A flat **withdrawal fee**, 0.04 GRIN by default and never less, is deducted from each payout to cover the network fee the pool pays as sender.

**Payouts are requested by the miner**, not sent on a schedule — there is no automatic payout. On their account page the miner proves they own the address — by giving the IP one of their rigs has mined from, or a rig's stratum password — enters an amount, and picks a rail:

| Rail | How it works |
|------|--------------|
| **Tor** (the default) | The pool wallet sends straight to the miner's wallet over Tor, the miner's wallet signs automatically, the pool finalises and broadcasts. A pre-flight check refuses the request at once if the miner's wallet does not answer over Tor. The send is tried **once** and ends *Paid*, *Failed* (balance returned at once, and the page offers Slatepack instead) or *Held* (see below). It is never re-sent. *The miner needs* a wallet with its Tor listener running at the moment of payout (Grim, grin-wallet `listen`, Fidelius…) |
| **Slatepack** | The pool prepares the transaction and shows it as a slatepack, **encrypted to the miner's address** so nobody else can read it; the miner pastes it into their wallet, pastes the response back, the pool finalises. *The miner needs* any wallet that can receive a slatepack, and has **30 minutes** by default (the *Slatepack Response Window*) to answer before the funds go back to their balance |
| **Goblin** | Delivery as a Nostr direct message to a registered Goblin name — this pays a *third party*, so it is off unless you switch it on, and comes with a domain allowlist, a 48-hour cooldown on a newly registered name, and registration needs both proofs (IP and password), each at least an hour old. *The miner needs* a Goblin wallet |

Only one payout per address can be in flight, and after a reversed payout (an expired slatepack, a failed Goblin send, an admin cancel) the address waits 30 minutes before trying again; a failed Tor payout does not start that wait. After five failed Tor payouts in 24 hours, Tor is paused for that address for 24 hours. The account page also lets a miner fetch a signed **payment proof** for every confirmed payout.

**[Held payouts](reference-glossary.html#held-payout).** When the pool genuinely cannot tell whether a Tor send went out (it timed out, say), the amount stays locked and the row is *Held*. The pool reads its wallet's transaction log every pass and settles the row by itself: confirmed on chain → *Paid*; absent on two reads at least 10 minutes apart → refunded. Both reads must be taken while payouts are **unfrozen**, so after a restore or a Migrate IN a held row waits until you unfreeze. A payout held for more than 24 hours raises a critical alert. The *Queue* page has **Re-check** and, after a password and typing the payout id back, **Forced refund**; neither ever sends money.

**What you, the operator, do with the money:** the fee accrues in an internal `pool_fee` account and stays in the pool wallet. Withdraw it from **Payouts → Queue → Operator revenue → your wallet**: save a revenue address once (a change to it waits 24 hours and raises an alert), then withdraw; these withdrawals are listed publicly on the Payments page. Do not move the fee with a raw `grin-wallet send`: the ledger would not know, the wallet would no longer cover what it owes, and the reconciliation would freeze payouts. Keep the **hot balance low** — the pool wallet is unlocked 24/7 by design (it must be, to sign coinbases), so treat it as a cash register, not a vault.

## The pool wallet

`5` on the pool menu opens the wallet submenu:

```text
  1) Set up wallet        (install + init/recover + save pass/address + start)
  2) Start listener       (owner_api + include_foreign, Owner+Foreign 3420, auto-unlock)
  3) Stop listener
  4) Show pool address
  5) Patch node wallet_listener_url
  6) Auto-restart on boot (enable / disable)
  7) Watchdog */5        (install / remove)
  8) Replace pool wallet  (compromise/corruption runbook — balances live in pool.db)
  9) grin-wallet binary   (update · roll back · verify — seed and pool.db untouched)
  0) Back
```

Two facts make the pool wallet different from a personal one. It runs **one** listener that serves both wallet APIs on port 3420: the node's stratum calls it to build the coinbase of every block template it sends to miners (a *local signing operation* — the seed must be decrypted in memory), and the pool backend calls it to check balances and send payouts. And **a locked wallet stops the pool**, not just the rewards: no coinbase, no block template, no jobs. That is why the passphrase lives on disk and why autostart and the watchdog matter.

The listener runs `grin-wallet owner_api` only and never publishes a Tor onion of its own. If the status line warns that a Tor hidden service or a `grin-wallet listen` points at the pool wallet, remove it: a miner's wallet could then finalise a payout behind the backend's back.

`8` is the runbook for a compromised or corrupted wallet: because every miner's balance lives in `pool.db` and not in the wallet, you can swap in a fresh wallet without losing any accounting — freeze payouts first, sweep the old one if you still can, remember that coinbases younger than 1440 blocks cannot move yet, and re-run the node restart above. `9` updates or rolls back the `grin-wallet` binary from the toolkit's shared store; the seed and the database are untouched.

## Pause the stratum

*Settings → Announcements → Stratum* in the admin panel closes **every** stratum port — the public 3333 and every gateway's region port — so that during a restore, a move or database trouble no share is accepted that the pool cannot credit. Pausing waits up to 30 seconds for shares already in flight (a block found in that moment is still credited), then drops every miner. The website, the API and payouts keep running.

- **Pause** for 15, 30, 60 or 120 minutes, with a reason (admin-only, never published). Every pause ends on its own; **Extend** sets a new end time, and **Resume** ends it early.
- **Schedule a window** for later: 5 minutes to 6 hours long, starting at least 15 minutes ahead and at most 30 days ahead. Times are entered in UTC.
- While paused, the public site shows a maintenance notice with the expected time back ("Mining is paused until about 05 Oct 14:30 UTC"), and a banner announces a scheduled window from 24 hours before it. The notice text is set in the *Maintenance Mode* card on the same page.
- A red strip on every admin page says the stratum is paused, or **degraded** if a port failed to open again on resume (the strip names the port and offers **Re-bind**).

Every action asks for your password again. A pause survives a restart of the service: the pool comes back paused until the same time. A restore and a Migrate IN start the pool paused for up to 2 hours.

## Regional gateways (multi-region)

Optional, and the `W` menu says so in capitals: a normal pool never needs it. A **regional gateway** is a small VPS near a group of distant miners that runs exactly two things — HAProxy forwarding raw stratum TCP, and a WireGuard tunnel to your pool server. It has no Grin node, no wallet, no database, no Node.js, and holds no keys but its own tunnel key. Miners connect to *its* port 3333; their traffic arrives at the pool server on a private per-region port (3391, 3392… on the tunnel interface only) with the miner's real IP carried in a PROXY-protocol header, and the pool stamps those shares with the region so the connect page can show per-region status and latency.

The `W` menu on the pool server:

```text
  1) Setup WireGuard server   (install, keys, tunnel, firewall, pairing helper)
  2) Add a gateway peer       (assign tunnel IP + region port)
  3) List gateways / regions
  4) Remove a gateway        (revoke wg key, free port mapping, drop admin card)
  5) Hub endpoint DNS name   (survive a provider/IP change without re-pairing)
```

The gateway box's own menu (mining hub → public pool → `2) Regional gateway`):

```text
  1) Install            (haproxy + wireguard; generate keypair)
  2) Configure          (region, central endpoint, tunnel keys)
  3) Bring up tunnel    (wg-quick up wg-grinpool + hub re-resolve timer; re-run once to add it)
  4) Service control    (start / stop / restart forwarder)
  5) Status
  6) Latency probe      (HTTPS /ping so the pool's connect page can time this gateway)
```

Pairing is a two-box dance. The pool server assigns everything; the gateway only pastes. The admin panel's *Regions* page does the pool-server half too, and is the better path: it opens the new region's listener without restarting the pool, while `W` → `2` needs a service restart (it asks).

| Step | What happens |
|------|--------------|
| 1 | **Pool server, once** — `W` → `1` *Setup WireGuard server*: generates the hub key pair, brings up `wg-grinpool` (10.66.66.1, udp **51820**) and opens the port. The admin panel's *Regions* page has an *Enable multi-region* button that does the same |
| 2 | **Gateway box** — `1` *Install*: installs `haproxy` and `wireguard-tools`, generates the gateway key pair, prints its **public key** and tells you to stop |
| 3 | **Pool server** — admin *Regions* → new region, paste the key, Save (or `W` → `2`): assigns a tunnel IP, a region port and a region key (an airport-style code such as `nyc`), and hands back **one line** starting `GRINGW1` that carries all of it, including the pool's public stratum port. Adding the same key again reprints that line and changes nothing |
| 4 | **Gateway box** — `2` *Configure*: paste the `GRINGW1` line (Enter to type each value by hand instead); `3` *Bring up tunnel* (it also installs the timer that follows a DNS change of the pool server); `4` start the forwarder; `5` *Status* — look for a fresh handshake, `:3333 listening`, and *On reboot: forwarder and tunnel start automatically* |
| 5 | **DNS** — point the hostname miners will dial for this region (for example `nyc.yourdomain.com`) at the **gateway box's** public IP, not the pool server's, DNS only (no Cloudflare proxy: it cannot carry stratum). Then enter that hostname on the region's card in admin *Regions* and tick *Active*. A region paired with `W` → `2` gets a **hidden** card that stays off the connect page until you do this. Until DNS resolves, the panel's port check shows the region unreachable even when the tunnel is healthy |
| 6 | **Pool server** — admin *Regions* shows the new region with its tunnel age; the public connect page shows it green once a miner has submitted a share through it, blue while idle, red when the tunnel is down |

Open **udp 51820** in the pool server's firewall, and **3333** on the gateway. A gateway cannot share a box with a pool server — both want port 3333 — and the script refuses the combination.

**Replacing a gateway box:** do **not** remove the old peer first. Install the new box, then add its public key under the **same region key** (`W` → `2`, or the region's card in admin *Regions*): the pool swaps the key in place, keeps the region's tunnel IP and port, and hands back a pairing line for the new box. DNS and the region card do not change; only the A record moves if the new box has a new IP.

**Removing a gateway** (`W` → `4`) asks you to type the region key twice, revokes its key, deletes its port mapping and its card in admin *Regions*, and then **restarts the pool service straight away**, without asking, which drops every miner on every region for a few seconds. The freed port is never reused: pairing that gateway again later gives it a new tunnel IP and port. `W` → `5` puts a DNS name instead of an IP into pairing strings, so a later change of the pool server's address is one DNS edit rather than a visit to every gateway. Update the toolkit on **both** boxes together: a pairing string from a newer pool server is rejected by an older gateway.

**Latency probe (optional).** The connect page can time each gateway from the visitor's browser. Gateway `6` → `1` asks for the gateway's public hostname — the same name miners use for that region — gets a certificate for it with `certbot --standalone`, and answers `https://<host>/ping` on port 443 with an empty reply and nothing else. It needs TCP **80** (at issue and at every renewal) and **443** open on the gateway. The stratum forwarder is a separate process and is not restarted. The pool's website may only time hosts **under its own domain name**: with the pool at `pool.yourdomain.com` it can time `nyc.pool.yourdomain.com` but not `nyc.yourdomain.com`. For the second kind, set `latency_probe_domain` in the pool config to the parent domain you own (`yourdomain.com`) and re-run pool menu `4`; until then the browser blocks the probe and the connect page keeps its estimate.

> **Warning:** A gateway is fully **trusted**. It reads every miner's login in clear (their address *and* rig password) and it asserts each miner's IP — the two things the pool accepts as proof of ownership at payout time. Run gateways only on servers you control as tightly as the pool server; do not let a partner operate one. The reasoning and alternatives are in the security audit's §J16-2.

## Backups and scheduled tasks

`B` opens the backup menu:

```text
  1) Backup now            (encrypted archive)
  2) Restore from backup   (one-shot extract to original paths + runbook)
  3) Schedule daily backup (cron · 14-archive retention)
  4) Settings              (personal key · retention · list)
  5) Offsite push (scp)    (auto-copy each archive to a remote server)

  6) Migrate OUT           (this hub → a new box: freeze, stop, final archive)
  7) Migrate IN            (NEW box: CHECK first · restore, verify, start)
```

One encrypted archive per network per day lands in `/opt/grin/backups/`, named `grin_pubpool_backup_` plus the date and `.tar.gz.enc`, holding everything a fresh install cannot regenerate: a consistent snapshot of `pool.db` (taken with SQLite's online-backup API, never a raw copy of a live file), the pool config with its JWT secret and region map, the wallet directory (seed and config, not the binary), `.wallet_pass`, uploaded media, the WireGuard identity, the nginx vhost, and the games database when `/play/` is installed. The TLS certificate is not in it. The archive password is your **personal key** followed by the date in the file name — the key is set in *Settings* and must be kept **off the box**, or the backup is worthless when you need it. The same engine and key scheme serve the toolkit's other products — see [Back up and restore](089-backup-restore.html).

**Restoring** (`2`) asks you to type `RESTORE` (and, when `/play/` is installed, separately whether to restore the games database, default yes), then stops the service and the wallet listener, extracts the archive over the original paths, **freezes payouts** on the restored ledger and **pauses the stratum** for 2 hours. It then prints the steps to finish, in order: `grin-secret-sync`; bring the restored WireGuard tunnel up (`W` → `1`); wallet submenu `2` to start the listener; `4) Setup nginx` on a fresh box (certbot re-issues once DNS points here); **reconcile before resuming payouts** (admin *Payouts → Treasury*) — the restored ledger is older than the chain, and a payout made after the snapshot would otherwise be sent again; start the service; then resume the stratum in the admin panel. On a fresh server the order is Script 01 node → pool `1) Install` → `B` → `2`, then those steps.

No gateway needs re-pairing after a restore, because the WireGuard identity is in the archive. Whether they reconnect on their own depends on the pool server's address:

| The pool server… | Gateways |
|---|---|
| kept its IP | reconnect by themselves |
| has a new IP, and gateways were paired to a DNS name (`W` → `5`) | update the A record; gateways follow within about 2–3 minutes |
| has a new IP, and gateways were paired to a raw IP | on each gateway: `2` *Configure* the new endpoint, then `3` *Bring up tunnel* |

The old pool server's tunnel must be down, or the gateways keep talking to it.

`C` opens the scheduled tasks: **1** toggles the **daily backup at 02:00 UTC**, **2** a **weekly VACUUM on Sunday 03:00 UTC** that compacts the database, and **V** runs a VACUUM now. A VACUUM **stops the pool** for as long as it takes (it holds an exclusive lock, and a share or a found block written into that window would be lost); miners reconnect on their own afterwards. *Run now* shows the database size and the free disk space first (a VACUUM needs up to twice the database size). With `/play/` installed, **3** and **G** do the same for the games database on Sunday 03:30 UTC, stopping only the games.

## Move the pool to a new server

`B` → `6` *Migrate OUT* and `B` → `7` *Migrate IN* move a live pool to a new box with every balance, share, hashrate history, audit row, the wallet seed, the WireGuard identity **and** the TLS certificate, and as little downtime as possible. Both refuse to start until you type `MIGRATE`.

1. **Days before, on the new box:** build the node with Script 01, run **only** pool `1) Install` (not `5) Set up wallet`: it would mint a seed the restore replaces, and `CHECK` warns about it), then `B` → `7` and type `CHECK`. It is read-only: it checks the node is synced, nginx and certbot, the firewall, Tor, and prints a fingerprint of the backend code. The old box's Migrate OUT prints the same fingerprint, and the two must match (update whichever box is behind). If the pool takes a new region tag at its new home, create that region's DNS record now (DNS only, no proxy, TTL 60). Fix every ✗ while the old pool still serves.
2. **On the old box,** optionally pause the stratum for 60 minutes and wait for "settled". Then `B` → `6` *Migrate OUT*: freezes payouts first; stops the wallet listener and removes its watchdog and boot autostart; turns off the VACUUM cron; stops and disables the pool service, the games service and the WireGuard tunnel; turns off the daily backup; writes a manifest of the ledger figures; takes a final encrypted archive (with the certificate — the only archive that carries one) and verifies it; and copies it to the new box with `scp`, or prints the command. **Miners disconnect now**, and this box will not start the pool again, not even after a reboot. The node keeps running.
3. **On the new box,** `B` → `7`, type `MIGRATE`: checks again, and that the **old pool is dark** (it must not answer on its stratum port or its API); restores with payouts frozen; asks for a new region tag if the pool moved; brings up node secrets, wallet, web files, WireGuard and nginx; then compares every balance, count and highest id with the manifest — any ✗ stops here, before anything starts. Then it starts the wallet and the pool with the stratum **paused** (up to 2 hours) and prints the DNS records to change.
4. Change DNS, **resume the stratum on the new pool** as soon as the continuity check is all ✓ (waiting for the automatic resume is pure downtime), watch the gateways come back, reconcile, and unfreeze payouts. Never start the old pool again.

> **Note:** Migrate OUT and IN have not been run on a server yet. A failed step is safe to repeat: fix the cause and run the same menu item again. Nothing in either half ever unfreezes payouts.

## Play and chat (games)

`P` installs an optional **`/play/`** section on your pool's site: games miners play against each other by address (chess ships today), competitions between addresses, and a moderated chat. It runs as its own service, `grin-games`, under its own user `grinplay` and its own database (`/opt/grin/pubgames-data/mainnet/grinium-games.db`), listening on `127.0.0.1:8081` behind your existing vhost. Nothing under `P` ever stops, restarts or reloads the pool service; nginx is only reloaded.

```text
  1) Install / repair       (user, dirs, link secret, code, unit, start)
  2) Deploy games code      (refresh from checkout, restart games only if needed)
  3) Nginx                  (write /play/ locations + reload + route check)
  4) Service control        (start / stop / restart games)
  5) Status                 (unit, listener, DB, mode, internal auth)
  6) Logs                   (tail -50 | less)
  7) Rotate link secret     (atomic replace, no restarts)
  8) Uninstall              (keeps the database unless you confirm twice)
  9) Restore games DB       (from a pool archive — games DB only, pool untouched)
```

Run `1`, then `3`. Installing does not make the section public: switch it in the admin panel under *Settings → Games* (off, preview or on) and *Games → Overview* (*Go live*). `5` also prints how many times the pool service has restarted, so you can see for yourself that the games did not touch it. Pool menu `9` deploys new games code along with the pool's.

> **Note:** The games service has been built and reviewed but has not run on a server yet.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| See whether the pool is healthy | Pool menu `8`, or the admin *System Health* page; `journalctl -u grin-pool-manager -f` for the live log |
| Change the fee, payout floor, name, theme | Admin panel → *Settings* |
| Stop paying out while I investigate something | Admin *Payouts* → freeze; resume from the same place |
| Stop accepting miners for maintenance | Admin *Settings → Announcements → Stratum* → pause, or schedule a window |
| Take my fee revenue | Admin *Payouts → Queue* → *Operator revenue → your wallet* |
| Update the pool after a toolkit release | Update the toolkit checkout, then pool menu `9`. Re-run `1) Install` too when the release notes mention the service unit |
| Restrict the admin panel to my IP | Add the IP to `admin_allowlist` in the config (pool menu `S`), then pool menu `4` |
| Add a region on another continent | [Regional gateways](#regional-gateways-multi-region) |
| Move the pool to a new server | [Migrate OUT / IN](#move-the-pool-to-a-new-server) |
| Get listed on miningpoolstats.stream | Give them `https://<domain>/api/pool/poolstats`; check it with the `curl` above first |
| Swap a compromised wallet | Freeze payouts, then wallet submenu `8` |
| Recover a locked-out admin | Pool menu `A` |
| Start over | Mode menu `Z` — [below](#removing-the-pool) |

## Removing the pool

> **Danger:** Every question in `Z` defaults to **yes** (`[Y/n]`): pressing Enter through it deletes `pool.db`, every miner's balance, along with the rest. Take a backup (`B` → `1`) first, and answer `n` to each group you want to keep. Only the games database question defaults to no.

`Z` on the mode-selector menu previews what is present, asks for one master confirmation and then confirms **each group**: services and units, the games service and (separately) its database, the app directory with `pool.db` and `.wallet_pass`, gateway files and tunnels, web root, vhost, zones and snippets, cron and logrotate and the helpers, the JSON configs, logs, the fail2ban jail. It never touches the node, its chain data or `grin-server.toml` (the stratum keys stay as they are and the next install reuses them), the **wallet directory and seed**, or the backups in `/opt/grin/backups/`. Take a backup first if there is any balance in the database — the app directory group deletes every miner's ledger. The TLS certificate stays in `/etc/letsencrypt` (`certbot delete` removes it). The same `Z` also removes a *legacy satellite* install, the multi-region role the toolkit used before gateways (deleted in June 2026); nothing else in the menu knows that name any more.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| "Solo PRIVATE mining is already set up on this server" | One mining type per box. [Remove solo mining](07-mining-services.html#removing-solo-mining) from its own menu, or run the pool on another VPS |
| Miners connect but get no work; the log shows the node-stratum login failing | The node's stratum is off or the pool has no `pool_address`. Run `grin-secret-sync`, **restart the node**, check `ss -tlnp` for 3416; check `pool_address` in the config (step 5 writes it) |
| Miners *Alive*, **GetWorks = 0**, everything else green | The pool wallet is **locked** — typically after a reboot or a crash. Wallet submenu `2` restarts and unlocks it; then enable autostart (`6`) and the watchdog (`7`) so it does not recur |
| Miners cannot connect at all (connection refused on 3333), or were dropped with "Pool paused" | The stratum is paused: while paused no stratum port is open, and "Pool paused" is only sent to rigs caught in the moment the pause starts. It was paused — by you, by a scheduled window, or because the pool was just restored or migrated. Resume in *Settings → Announcements → Stratum*, or wait for the end time shown there |
| A red *degraded* strip on every admin page after a resume | A stratum port could not open again. `EADDRNOTAVAIL` on a region port means the WireGuard tunnel is not up — bring it up, then press **Re-bind** |
| "Pool manager is not running on port 8080" during step 7 | The service is down or still starting. Pool menu `6` to start it; `journalctl -u grin-pool-manager -n 50` if it will not |
| "An admin already exists — registration is closed" | Step 7 was already done. Sign in, or use `A` to reset the password |
| `certbot failed` in step 4 | DNS for the domain **and** `www.` does not point here yet, or port 80 is closed. The pool stays on HTTP; fix and re-run `4` |
| 403 on `/admin/` | Your browsing IP is not in `admin_allowlist` (it can differ from your SSH IP). Add it and re-run `4` |
| `nginx config test failed` in step 4 | Usually a typo in `admin_allowlist` spliced into an `allow` line. nginx keeps serving the old config. On a first run the script disables the new vhost again; on a re-run (the vhost was already enabled, the usual case when you edit the allowlist) it **leaves the broken vhost enabled** and says so — fix the value and re-run `4` before any reboot or nginx restart, or nginx will refuse to start and take every site on the box down |
| Uploaded logo or CMS images 404 | nginx cannot reach the app's `custom_assets/` or `uploads/` folder (a hand `chmod`, or an install from before this was fixed). Re-run `4` (or `1`): both re-open the two served folders. `3` does not |
| A miner's Tor payout ends *Failed* | Their wallet's Tor listener was not reachable when the pool sent; the balance is already back on their account page, which offers Slatepack instead. Five failures in 24 hours pause Tor for that address for 24 hours |
| A payout stays *Held* | The pool could not tell whether the send went out, so it keeps the amount locked and checks its wallet log every pass. Wait; after 24 hours an alert fires. Use **Re-check** on *Payouts → Queue*; **Forced refund** only when you are sure the coins did not move |
| Payouts show *paused* on every account page | The freeze is engaged — by you, by a restore or migration, or by the alert monitor after a money check tripped. *Payouts → Treasury* shows the reason |
| Payouts froze right after I sent coins from the pool wallet by hand | The ledger does not know about a raw `grin-wallet send`, so the wallet no longer covers what it owes. Use *Operator revenue* for your fee instead; reconcile on *Treasury* before resuming |
| Gateway miner shows *Dead* but the tunnel handshakes | `hub_endpoint` on the gateway points at the wrong port (the node's 3416 instead of the assigned region port 3391). Paste the `GRINGW1` string instead of typing values |
| Gateway tunnel handshakes but nothing passes | AllowedIPs mismatch from a duplicate pairing. Remove the peer on the pool server (`W` → `4`) and pair again |
| Gateway *Status* says `:3333 listening` but the pool's port check fails | The gateway's public stratum port was typed wrong once and stuck. Re-paste a current `GRINGW1` string (it carries the port), or update the toolkit on both boxes if the gateway rejects it |
| A paired region does not take miners after `W` → `2` | The CLI path opens the region's listener only after a pool service restart, and you answered no. Restart the service, or pair from the admin *Regions* page next time |
| Region stays red on the connect page though the gateway is fine | Wildcard DNS or a stale probe; verify with `nc -vz <region host> 3333`. Deactivate unbuilt regions in admin *Regions* rather than leaving them red |
| Panel pairing "saves" nothing while *Regions* still lists fine | The service unit predates the `/etc/wireguard` write permission (pool menu `9` warns about it). Re-run `1) Install` once; `W` on the CLI works meanwhile |
| Migrate IN stops at "old hub" | The old pool still answers on its stratum port or API. Finish Migrate OUT on the old box first; nothing on the new box has started |
| Service refuses to start after editing the config | `jwt_secret` missing or shorter than 32 characters — the backend fails loudly on purpose. Restore it from a backup or re-run `1` |

## Related

- [Script 01](01-build-node.html) — the node the pool feeds from, and how to restart it
- [Solo mining](07-mining-services.html) — the other half of the mining hub, including the node-sync watchdog that restarts a stuck node
- [Ports and paths](reference-ports-and-paths.html#public-mining-pool-script-07) — every pool port, and the 51820/udp clash with Fidelius private access
- [Fidelius](051-fidelius.html) — a wallet that can receive pool payouts over Tor
- [Script 06](06-global-health.html) — the Tiny Explorer that the pool's block and payout pages can deep-link to
- [Back up and restore](089-backup-restore.html) — the shared engine and personal key the pool's `B` menu uses
- Deeper reading in the toolkit repository: [script07_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/reference/script07_design.md) (architecture, reward pipeline, payments, multi-region, stratum pause), [script07_implementation.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/reference/script07_implementation.md) (as built: runbooks, scheduler jobs, hub move), [script07_implementation_games.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/reference/script07_implementation_games.md) (the `/play/` service) and [script07_security_audit.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/reference/script07_security_audit.md); the pool's own API reference is served at `/api-docs.html` on your domain
