---
title: Run a public mining pool
description: How Script 07 deploys GRINIUM, a self-hosted PPLNS Grin pool with no miner accounts, Tor and slatepack payouts, an admin panel and optional regional gateways.
section: Scripts
order: 7.5
label: Script 07
covers: 2026-09-20
updated: 2026-09-20
---

The public pool is the second half of the mining hub (the first half, [solo mining](07-mining-services.html), has its own page). It turns your node into a **mining pool** that other people point their rigs at: a stratum server on a public port, a website with live stats, a per-miner account page, and an admin panel where you set the fee and watch the money. The toolkit's job is the infrastructure — Node.js app, database, systemd, nginx and SSL, the pool wallet, backups. Every business decision (name, fee, payout floor) is made in the web admin panel after setup, not in a config file.

You need a synced **mainnet node** from [Script 01](01-build-node.html) (pruned is fine), a domain, and a passphrase for the pool wallet the setup creates. Testnet works the same way with a testnet node, and is where you should start.

> **Warning:** Status — the mining hub is marked **(DEV)** in the main menu, and the reference pool at grinium.com is *in development*. The first real miners connected to it on 2026-09-20 and found two display bugs the same day (every hashrate read 0.00 G/s and *miners online* read 0 — both fixed since). The regional-gateway path has carried live hashrate on testnet. Most of what was added on top — pairing from the admin panel, encrypted backups, the account page and its payout rails, the incentive features — is written and reviewed but has **not** been exercised on a server. Rehearse the whole flow on **testnet** first, with a tGRIN node and a test rig, and read [Fees and payouts](#fees-and-payouts) before you announce a fee. Nothing on this page should be read as "proven in production".

## What you get

**For a miner**, the pool works like the large Grin pools: there is no sign-up. The rig logs in to `pool.yourdomain.com:3333` with its **Grin slatepack address** as the username (optionally `address.rigname`), and that address *is* the account. A public account page shows its hashrate, workers, share quality, balance and payout history; the pool pays to that same address, so a miner can be paid without ever having had a login. There is nothing to hijack.

**For you**, the operator:

- a **stratum proxy** in front of the node's built-in stratum that counts every share, on your own public port;
- **PPLNS** reward sharing, block maturity tracking, orphan detection with exact reversal;
- payouts to miners over **Tor** (the pool's wallet talks straight to the miner's wallet) or by **slatepack** (copy-paste), plus an off-by-default Goblin rail;
- a **website** (dashboard, blocks, miners, payments, network map, blog, pages) with a white-label branding system and 14 themes (two enabled out of the box);
- an **admin panel** with a full money statement, a payout kill-switch, sessions, regions, ads, incentives, CMS;
- **regional gateways**: thin stratum forwarders on other continents that tunnel miners to this box, added later without a rebuild;
- an encrypted **backup** of everything that cannot be regenerated, and a JSON **API** documented at `/api-docs.html` on your domain.

The deep design — why address-as-identity, why SQLite, why Tor — is in the toolkit's [script07_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script07_design.md); this page is the operator's manual.

## What it does

The pool server install (the *Pool server* mode) puts these on the box:

1. **Node.js 24** from NodeSource (the pool uses Node's built-in SQLite, so 24 is a hard minimum), `logrotate`, `sqlite3` and `fail2ban`. The pool app is copied to `/opt/grin/pubpool/mainnet/`, its dependencies installed with `npm ci`.
2. A **systemd service** `grin-pool-manager` running as the unprivileged `grinpool` user under a hardened unit, plus a logrotate rule for `/opt/grin/logs/grin-pool.log`, a fail2ban jail on the admin login, and the `grin-gateway-ctl` helper the multi-region path uses.
3. A **config file** `/opt/grin/conf/grin_pubpool.json` seeded with defaults (fee 1 %, payout floor 25 GRIN, ports) and a random JWT secret.
4. The **website** in `/var/www/grin-pool/` with the admin panel under `/admin/`.
5. An **nginx vhost** for your domain — HTTP first, then a Let's Encrypt certificate, then the full HTTPS vhost with rate-limit zones, security-header snippets, Cloudflare real-IP support if you want it, and an optional IP allowlist on `/admin/`.
6. A **pool wallet** in `/opt/grin/pubpoolwallet/mainnet/`: its own `grin-wallet` binary, a new or recovered seed, and one *combined* listener on port **3420** that serves both wallet APIs — the node's stratum calls it to build the coinbase of every block template, and the pool backend calls it to send payouts. The passphrase is saved to a mode-600 file owned by the service user and the listener is unlocked over the encrypted Owner API; it is never on a long-running command line.
7. The **first admin account**, created from the box over loopback; the public registration route closes as soon as one admin exists.

One thing the menu does *not* do for you: the node's own stratum server has to be switched on and the node restarted. See [Wire the node and restart it](#wire-the-node-and-restart-it) — skip it and the pool has no work to hand out.

## Before you start

| Need | Why |
|------|-----|
| A synced **mainnet node** from Script 01 (testnet node for a testnet pool). Pruned or full, either is fine | The pool's stratum proxy feeds from the node's built-in stratum on `127.0.0.1:3416` (testnet 13416) and reads the node's API on 3413 (13413). Nothing in the pool needs old block bodies |
| A **domain or subdomain** with an A record pointing at this server (and `www.` too, if you want the redirect) | The site and the admin panel are served over HTTPS; Configure refuses to continue without a domain, and it is the one setting you cannot change from the admin panel |
| **80, 443 and 3333** (testnet 13333) open in your provider's firewall | Website, certificate issuance, and the public stratum port miners connect to. Add **51820/udp** (51821 testnet) only when you pair a regional gateway |
| **Tor** on the box | Script 01 installs it in step 2. The wallet uses it to reach miners' wallets, and the payout pre-flight check dials the local SOCKS port 9050 |
| **No solo mining** on this server | One mining setup per box. The pool script refuses to install next to a solo setup, and the hub refuses the other way round — they collide on the stratum port, nginx zones and `/opt/grin` |
| A **wallet passphrase**, written down somewhere safe | The setup creates the pool wallet and stores the passphrase on disk for unattended unlocks; you still need it for a recovery on a new box |

A mainnet pool and a testnet pool **can** share a box — every directory, port, service and vhost is suffixed per network. Only solo mining collides.

## Choices you will make

### Mainnet or testnet

Pick the network on the mining hub's menu, before the pool script even starts. **Testnet** is a fully independent install — `grin-pool-manager-testnet`, `/opt/grin/pubpool/testnet/`, config `grin_pubpool_testnet.json`, API port 8090, stratum **13333**, wallet port 13420, a `tgrin1…` address, and a block maturity of 100 instead of 1440 — so you can exercise found block → maturity → reward → payout in an afternoon on worthless tGRIN, then repeat the same steps on mainnet. It needs its own domain (or subdomain) and its own testnet node.

### One server, or a pool server plus regional gateways

A single **Pool server** serves every miner in the world on its own port 3333 as region `main`. That is the normal pool and the only thing you need. If you later want lower latency for miners on another continent, you add a **regional gateway** — a separate small VPS that runs a stratum forwarder and a WireGuard tunnel back to the pool server, and nothing else — without rebuilding anything. See [Regional gateways](#regional-gateways-multi-region). An advanced third mode, *Central Hub* (a brain with no local stratum, all mining arriving through gateways), is not on the menu; it is started with `bash 07_grin_mining_public_pool.sh hub`.

### Behind Cloudflare?

Setup nginx asks once, default **yes**. Most public pools front their site with Cloudflare's proxy, and behind it every visitor arrives from a Cloudflare IP — so the toolkit restores the real visitor address from `CF-Connecting-IP`, otherwise the rate limiter and fail2ban would treat all visitors as one. Answer `n` if your DNS points straight at the box. If you *are* behind Cloudflare, the script also prints a `ufw` recipe to allow 80/443 only from Cloudflare's ranges, so nobody can talk to the origin directly.

### Who may open the admin panel

By default the admin panel is reachable from **any IP** — the login form, captcha, per-account lockout, IP auto-ban, optional two-factor and fail2ban are the only gate. The script tells you so twice. Once the pool is live, put your own IP (or VPN range) into `admin_allowlist` in the pool config and re-run *Setup nginx*: `/admin/` and `/api/admin/` then answer 403 to everyone else, with localhost always allowed as the break-glass path. The guided setup prints a one-line command that adds an IP for you.

## The menus

The hub (main menu 7) picks the mining type and the network:

```text
  Grin Mining Services

  Active type: none yet — pick one below

  Pick ONE option only — a server runs a single mining setup.

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
  9) Deploy new code       (refresh js/html/media from checkout + restart)
  A) Admin recovery        (locked out: clear 2FA / reset password — break-glass)
  W) Multi-region          (WireGuard server + add regional gateways)
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
| `9` | After a `git pull` in the toolkit checkout: copies the new backend and frontend into place, re-runs `npm ci` only when the dependency files changed, and restarts the service |
| `A` | [Break-glass recovery](#the-admin-panel) for a locked-out admin: list accounts, clear two-factor, set a new password, new recovery codes, unlock |
| `W` | [Regional gateways](#regional-gateways-multi-region): WireGuard server, add or remove a gateway, list, DNS name for the endpoint |
| `B`, `C` | [Backups and scheduled tasks](#backups-and-scheduled-tasks) |
| `S` | Opens the config JSON in your editor — for the few keys the admin panel does not own, such as `admin_allowlist` |
| `DEL` | Deletes `pool.db` — every balance, share, block and withdrawal — after typing `RESET POOL DATABASE` and then `YES`. The service is stopped, the file removed, and a fresh empty schema created on the next start |

## Guided setup, step by step

`G` runs the seven steps without pausing between them; it stops only for real input. Steps already marked `✓` offer to be skipped, so an aborted run resumes where it left off. Everything not asked here is a default you change later in the admin panel.

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | Refuses to start if solo mining or a gateway is on the box. Installs packages and Node.js 24, copies the app to `/opt/grin/pubpool/mainnet/`, runs `npm ci`, generates the JWT secret and default config, creates the `grinpool` user and the hardened service unit, logrotate, the fail2ban jail (10 failed admin logins in 15 minutes → a 10-day firewall ban) | Wait |
| 2 | Asks for the pool's domain and validates it; then the optional region label, country and ISO code for the connect card | Type `pool.yourdomain.com`; Enter through the location fields or fill them in |
| 3 | Copies the website to `/var/www/grin-pool/`, the admin panel to `/admin/`, writes `js/pool-config.js` with the pool name, fixes ownership for nginx | Nothing |
| 4 | Writes the five rate-limit zones and the header snippets; asks about Cloudflare; writes an HTTP-only vhost, tests and reloads nginx; runs certbot for the domain **and** its `www.` alias with `admin@<domain>` as the account email; then writes the full HTTPS vhost and reloads again. Warns loudly if the admin panel is open to all IPs | Answer the Cloudflare question; answer `Y` to issue the certificate (or `n` and re-run step 4 later) |
| 5 | Asks for the wallet directory (default `/opt/grin/pubpoolwallet/mainnet`), downloads and verifies `grin-wallet`, asks for a passphrase twice (at least 3 characters — use many more), initialises a **new** wallet, checks the passphrase actually opens it, saves it to `/opt/grin/pubpool/mainnet/.wallet_pass`, patches the wallet's config (ports, combined listener, the node's foreign secret) and the node's `wallet_listener_url`, starts the listener in a tmux session, unlocks it, and records the wallet's address as `pool_address` in the pool config. If a wallet already exists it asks: use it, create a new one (the old directory is archived, not deleted), or recover from a seed phrase | Enter the passphrase; for a recovery, type the 24 words when `grin-wallet` itself asks for them. **Write down the seed** a new wallet prints |
| 6 | Starts `grin-pool-manager` and waits for port 8080 (the first start creates the database schema, so it takes a moment) | Nothing |
| 7 | Asks for the admin username (3+ characters), password (8+, twice) and an optional email, and registers the account over loopback — no captcha, nothing on the command line | Choose them; keep the password in a password manager |

The run ends by printing your URLs: the pool site, `https://<domain>/login.html` for the admin panel, `https://<domain>/api-docs.html`, and the feed URL to hand to miningpoolstats.stream if you want to be listed there (they poll it; nothing is pushed).

If step 5 does not end with the listener up **and unlocked**, the script says so and asks whether to continue anyway. Say no: a pool whose wallet is locked cannot build coinbases and hands out **no work at all** — miners connect and sit idle. Fix the cause and re-run `5`.

## Wire the node and restart it

Script 01 deliberately leaves the node's built-in stratum server switched **off** — mining is Script 07's business. The pool relies on the toolkit's secret-sync timer to flip it on: every 5 minutes `grin-secret-sync` checks `grin-server.toml` and sets `enable_stratum_server = true`, `stratum_server_addr = "127.0.0.1:3416"` and the `wallet_listener_url` that step 5 also patched. Those keys are read only at node start-up, so **the node must be restarted once** after the wallet setup. Do it right away rather than waiting for the timer:

```bash
grin-secret-sync                        # applies the stratum keys now; says RESTART if it changed them
gtmux attach -t grin_pruned_mainnet    # Ctrl+C stops the node, then Ctrl+B D to detach
```

Then start it again from **Script 01 → `S`** (or wait for the [sync watchdog](07-mining-services.html#watchdogs-and-autostart), if installed, to bring it back within 5 minutes). Confirm the node's stratum is listening before you announce the pool:

```bash
ss -tlnp | grep 3416                    # the node's stratum, localhost only
cd /opt/grin/node/mainnet-prune
grep -E 'enable_stratum|stratum_server_addr|wallet_listener_url' grin-server.toml
```

> **Note:** The guided setup prints "complete" before this step, and nothing in the menu says the node needs restarting except the wallet step's one-line warning. Until you do it, the pool's own log shows it failing to log in to the node stratum and every miner sees no jobs. This is a gap in the script, not in your setup.

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

A bare worker name without the address is rejected: the address *is* the identity. The **password** is not an account password — it is captured (hashed) from the rig's first accepted shares, together with its IP, and later serves as proof of ownership when that address requests a payout. Trivial passwords (`x`, `123`, the miner defaults) are ignored for that purpose, so tell your miners to set a real one.

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

Testnet uses the same layout with `testnet` in place of `mainnet`, `-testnet` on the service, vhost and helper names, and `/var/www/grin-pool-testnet/`.

## The admin panel

Sign in at `https://<domain>/login.html`; it redirects to `/admin/`. There are **no default credentials**: the only admin is the one step 7 created on the box, and registration closed the moment it existed. The session is an httpOnly cookie with an idle timeout and a hard maximum lifetime, both set under *Access Control*. Money-moving and destructive actions ask for your password again in an in-page dialog (step-up), and you can require two-factor for every admin.

The left rail has two groups. **Dashboard** is the live data: *Miners*, *Payouts* (with the full money statement: what the wallet holds versus what the ledger owes, and the payout **freeze**), *Blocks*, *Sessions*, *Regions*, *System Health*. **Settings** is one page per section:

| Section | What it sets |
|---------|--------------|
| Pool Info | Pool name, tagline, description, the **pool fee %** (0–50, default 1) |
| Branding | Logo, colours, which of the 14 public themes visitors may pick, social links — the white-label layer |
| SEO / Analytics | Meta tags, sitemap, an analytics provider (GA4, Plausible, Umami or Matomo); with GA4 a miner's address is scrubbed from the page URL before it is reported |
| Pages / Blog / Announcements / Ads | The built-in CMS: static pages, posts, a site-wide banner, and promo slots you sell or fill yourself |
| Payout | **Minimum withdrawal** (default 25 GRIN), the flat **withdrawal fee** (default 0.04), the Tor pre-flight check, the retry ladder, the post-failure cooldown, the Goblin rail switch (off), the dormant-balance policy (off) |
| Incentives | Prize pool, join bonus, streaks, jackpot draws and contests, miner donations — all optional, all funded from the pool's own fee bucket or top-ups |
| Access Control | Admin IP allow/deny lists at the app layer, session timeouts, require-2FA, the password blocklist |
| Database | Retention windows for shares, per-miner hashrate history, resolved alerts, the raw ledger and the audit log |

Changing the fee, the payout floor or the retention windows takes effect on save (a few keys say *applied at restart* on the page).

**The payout freeze** is a kill-switch on the *Payouts* page. Engaged, the pool stops every outbound send — Tor, slatepack, Goblin — while still refunding expired slates to miners. The alert monitor engages it on its own when the money checks trip (wallet balance below what miners are owed, a balance that moved without a ledger row); you engage it by hand when a wallet or box looks compromised, or before you swap the wallet. Miners see a *payouts paused* chip on their account page, never the reason. Resume from the same place once you understand what happened.

**Locked out?** `A) Admin recovery` on the pool menu needs a root shell on the box and nothing else: list the admin accounts, clear a lost authenticator, set a new password (prompted, never on the command line), mint new recovery codes, or clear a failed-login lockout. Every action writes an audit row.

## Fees and payouts

The pool fee is a percentage of each **block reward**, taken when the block **matures** — 1440 confirmations on mainnet (about a day), 100 on testnet — never at withdrawal time. Rewards are shared **PPLNS** over the shares submitted in the last **60 blocks**, so a miner who leaves just before a block is found still gets their share of it, and pool hopping does not pay. A block that turns out to be an orphan has its exact credits reversed from every account it paid, fee included. Balances are the miner's to withdraw once they reach the **minimum withdrawal**, 25 GRIN by default (each payout is an interactive transaction that leaves a permanent kernel on chain, hence the high floor); a flat **0.04 GRIN** covers the network fee the pool pays as sender.

**Payouts are requested by the miner**, not sent on a schedule. On their account page the miner proves they own the address — by giving the IP one of their rigs has mined from recently, or the rig's stratum password — enters an amount, and picks a rail:

| Rail | How it works |
|------|--------------|
| **Tor** (the default) | The pool wallet sends straight to the miner's wallet over Tor, the miner's wallet signs automatically, the pool finalises and broadcasts. On failure it retries after 6, 12, 24 and 48 hours; if the miner's wallet is still unreachable, the payout becomes slatepack-claimable instead of being lost. *The miner needs* a wallet with its Tor listener running at the moment of payout (Grim, grin-wallet `listen`, Fidelius…) |
| **Slatepack** | The pool prepares the transaction and shows it as a slatepack, **encrypted to the miner's address** so nobody else can read it; the miner pastes it into their wallet, pastes the response back, the pool finalises. *The miner needs* any wallet that can receive a slatepack, and has 24 hours to answer before the funds go back to their balance |
| **Goblin** | Delivery as a Nostr direct message to a registered Goblin name — this pays a *third party*, so it is off unless you switch it on, and comes with a 48-hour registration cooldown and a domain allowlist. *The miner needs* a Goblin wallet |

Only one payout per address can be in flight, and after a failed or expired one the address waits 30 minutes before trying again. The account page also lets a miner fetch a signed **payment proof** for every confirmed payout.

> **Note:** As read in the code, the Tor rail spawns `grin-wallet` by name, which means the binary must be on the service's `PATH` — and the toolkit installs it only inside the wallet directory. If a Tor payout fails at once with an error that mentions `ENOENT` or *spawn*, that is the cause, and a symlink from the wallet directory into `/usr/local/bin` is the workaround. This has not been verified on a server; rehearse a small payout on testnet before you rely on it.

```bash
ln -s /opt/grin/pubpoolwallet/mainnet/grin-wallet /usr/local/bin/grin-wallet
```

**What you, the operator, do with the money:** the fee accrues in an internal `pool_fee` account and stays in the pool wallet. Sweep it to a cold wallet regularly and keep the **hot balance low** — the pool wallet is unlocked 24/7 by design (it must be, to sign coinbases), so treat it as a cash register, not a vault. The *Payouts* page's reconciliation shows, at any moment, whether the wallet's spendable balance covers what the ledger owes miners; a shortfall freezes payouts automatically.

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

`8` is the runbook for a compromised or corrupted wallet: because every miner's balance lives in `pool.db` and not in the wallet, you can swap in a fresh wallet without losing any accounting — sweep the old one first if you still can, remember that coinbases younger than 1440 blocks cannot move yet, and re-run the node restart above. `9` updates or rolls back the `grin-wallet` binary from the toolkit's shared store; the seed and the database are untouched.

## Regional gateways (multi-region)

Optional, and the `W` menu says so in capitals: a normal pool never needs it. A **regional gateway** is a small VPS near a group of distant miners that runs exactly two things — HAProxy forwarding raw stratum TCP, and a WireGuard tunnel to your pool server. It has no Grin node, no wallet, no database, no Node.js, and holds no keys but its own tunnel key. Miners connect to *its* port 3333; their traffic arrives at the pool server on a private per-region port (3391, 3392… on the tunnel interface only) with the miner's real IP carried in a PROXY-protocol header, and the pool stamps those shares with the region so the connect page can show per-region status and latency.

Pairing is a two-box dance. The pool server assigns everything; the gateway only pastes:

| Step | What happens |
|------|--------------|
| 1 | **Pool server, once** — `W` → `1` *Setup WireGuard server*: installs `wireguard-tools`, generates the hub key pair, brings up `wg-grinpool` (10.66.66.1, udp **51820**) and opens the port. The admin panel's *Regions* page has an *Enable multi-region* button that does the same |
| 2 | **Gateway box** — mining hub → public pool → `2) Regional gateway` → `1` *Install*: installs `haproxy` and `wireguard-tools`, generates the gateway key pair, prints its **public key** and tells you to stop |
| 3 | **Pool server** — `W` → `2` *Add a gateway peer* (or admin *Regions* → new region, paste the key, Save): assigns a tunnel IP, a region port and a region key, and hands back **one line** starting `GRINGW1` that carries all of it, including the pool's public stratum port. `W` → `3` reprints it any time |
| 4 | **Gateway box** — `2` *Configure*: paste the `GRINGW1` line (Enter to type each value by hand instead); `3` *Bring up tunnel*; `4` start the forwarder; `5` *Status* — look for a fresh handshake, `:3333 listening`, and *On reboot: forwarder and tunnel start automatically* |
| 5 | **Pool server** — admin *Regions* shows the new region with its tunnel age; the public connect page shows it green once a miner has submitted a share through it, blue while idle, red when the tunnel is down |

Open **udp 51820** (51821 for a testnet pool) in the pool server's firewall, and **3333** on the gateway. A gateway cannot share a box with a pool server — both want port 3333 — and the script refuses the combination. To replace a gateway box, remove the old peer first (`W` → `4`) and pair again; the region keeps its port. `W` → `5` puts a DNS name instead of an IP into pairing strings, so a later change of the pool server's address is one DNS edit rather than a re-pair. Pull the toolkit on **both** boxes together: a pairing string from a newer pool server is rejected by an older gateway.

> **Warning:** A gateway is fully **trusted**. It reads every miner's login in clear (their address *and* rig password) and it asserts each miner's IP — the two things the pool accepts as proof of ownership at payout time. Run gateways only on servers you control as tightly as the pool server; do not let a partner operate one. The reasoning and alternatives are in the security audit's §J16-2.

## Backups and scheduled tasks

`B` opens the backup menu: *Backup now*, *Restore*, *Schedule daily backup*, *Settings* (your personal key and how many archives to keep — 14 by default), and an optional *Offsite push* over `scp`. One encrypted archive per network per day lands in `/opt/grin/backups/`, named `grin_pubpool_backup_` plus the date and `.tar.gz.enc`, holding everything a fresh install cannot regenerate: a consistent snapshot of `pool.db` (taken with SQLite's online-backup API, never a raw copy of a live file), the pool config with its JWT secret and region map, the wallet directory (seed and config, not the binary), `.wallet_pass`, uploaded media, the WireGuard identity, and the nginx vhost. The archive password is your **personal key** followed by the date in the file name — the key is set in *Settings* and must be kept **off the box**, or the backup is worthless when you need it. The same engine and key scheme serve the toolkit's other products — see [Back up and restore](089-backup-restore.html).

Restoring onto a fresh server, in order: Script 01 node → pool `1) Install` → `B` → `2) Restore` → `grin-secret-sync` → repoint DNS → certbot re-issues on the next *Setup nginx*. Because the WireGuard identity is in the archive, every regional gateway reconnects on its own — no re-pairing.

`C` toggles two cron jobs: the **daily backup at 02:00 UTC**, and a **weekly VACUUM on Sunday 03:00 UTC** that compacts the database. The vacuum **stops the pool** for as long as it takes (the honest cost of a VACUUM — it holds an exclusive lock, and a share or a found block written into that window would be lost); miners reconnect on their own afterwards. The script it installs, `/usr/local/bin/grin-pool-manager-vacuum`, can be run by hand at a quiet hour.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| See whether the pool is healthy | Pool menu `8`, or the admin *System Health* page; `journalctl -u grin-pool-manager -f` for the live log |
| Change the fee, payout floor, name, theme | Admin panel → *Settings* |
| Stop paying out while I investigate something | Admin *Payouts* → freeze; resume from the same place |
| Update the pool after a toolkit release | `git pull` in the toolkit checkout, then pool menu `9`. Re-run `1) Install` too when the release notes mention the service unit |
| Restrict the admin panel to my IP | Add the IP to `admin_allowlist` in the config (the guided setup prints the one-liner), then pool menu `4` |
| Add a region on another continent | [Regional gateways](#regional-gateways-multi-region) |
| Move the pool to a new server | Backup on the old box, restore on the new one — the runbook above |
| Get listed on miningpoolstats.stream | Give them `https://<domain>/api/pool/poolstats`; check it with the `curl` above first |
| Swap a compromised wallet | Freeze payouts, then wallet submenu `8` |
| Recover a locked-out admin | Pool menu `A` |
| Start over | Mode menu `Z` — [below](#removing-the-pool) |

## Removing the pool

`Z` on the mode-selector menu previews what is present, asks for one master confirmation and then confirms **each group**: services and units, the app directory with `pool.db` and `.wallet_pass`, gateway files and tunnels, web root, vhost, zones and snippets, cron and logrotate and the helpers, the JSON configs, logs, the fail2ban jail. It never touches the node, its chain data or `grin-server.toml` (the stratum keys stay as they are and the next install reuses them), the **wallet directory and seed**, or the backups in `/opt/grin/backups/`. Take a backup first if there is any balance in the database — the app directory group deletes every miner's ledger. The same `Z` also removes a *legacy satellite* install, the multi-region role the toolkit used before gateways (deleted in June 2026); nothing else in the menu knows that name any more.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| "Solo PRIVATE mining is already set up on this server" | One mining type per box. [Remove solo mining](07-mining-services.html#removing-solo-mining) from its own menu, or run the pool on another VPS |
| Miners connect but get no work; the log shows the node-stratum login failing | The node's stratum is off or the pool has no `pool_address`. Run `grin-secret-sync`, **restart the node**, check `ss -tlnp` for 3416; check `pool_address` in the config (step 5 writes it) |
| Miners *Alive*, **GetWorks = 0**, everything else green | The pool wallet is **locked** — typically after a reboot or a crash. Wallet submenu `2` restarts and unlocks it; then enable autostart (`6`) and the watchdog (`7`) so it does not recur |
| "Pool manager is not running on port 8080" during step 7 | The service is down or still starting. Pool menu `6` to start it; `journalctl -u grin-pool-manager -n 50` if it will not |
| "An admin already exists — registration is closed" | Step 7 was already done. Sign in, or use `A` to reset the password |
| `certbot failed` in step 4 | DNS for the domain **and** `www.` does not point here yet, or port 80 is closed. The pool stays on HTTP; fix and re-run `4` |
| 403 on `/admin/` | Your browsing IP is not in `admin_allowlist` (it can differ from your SSH IP). Add it and re-run `4` |
| `nginx config test failed` in step 4 | Usually a typo in `admin_allowlist` spliced into an `allow` line. The script disables the new vhost again so nginx keeps serving; fix the value and re-run |
| Uploaded logo or CMS images 404 | A re-run of `1) Install` tightens the app directory; re-run `3` or `4` (both restore the two served folders) |
| A Tor payout fails immediately with `spawn` / `ENOENT` in the log | `grin-wallet` is not on the service's `PATH` — see the note under [Fees and payouts](#fees-and-payouts). Not verified on a server |
| Payouts show *paused* on every account page | The freeze is engaged — by you, or by the alert monitor after a money check tripped. Admin *Payouts* shows the reason |
| Gateway miner shows *Dead* but the tunnel handshakes | `hub_endpoint` on the gateway points at the wrong port (the node's 3416 instead of the assigned region port 3391). Paste the `GRINGW1` string instead of typing values |
| Gateway tunnel handshakes but nothing passes | AllowedIPs mismatch from a duplicate pairing. Remove the peer on the pool server (`W` → `4`) and pair again |
| Gateway *Status* says `:3333 listening` but the pool's port check fails | The gateway's public stratum port was typed wrong once and stuck. Re-paste a current `GRINGW1` string (it now carries the port), or pull the toolkit on both boxes if the gateway rejects it |
| Region stays red on the connect page though the gateway is fine | Wildcard DNS or a stale probe; verify with `nc -vz <region host> 3333`. Deactivate unbuilt regions in admin *Regions* rather than leaving them red |
| Panel pairing "saves" nothing while *Regions* still lists fine | The service unit predates the `/etc/wireguard` write permission. Re-run `1) Install` once; `W` on the CLI works meanwhile |
| Service refuses to start after editing the config | `jwt_secret` missing or shorter than 32 characters — the backend fails loudly on purpose. Restore it from a backup or re-run `1` |
| Every hashrate reads 0.00 G/s, *miners online* 0 with rigs connected | The two day-one bugs from 2026-09-20; `git pull` and pool menu `9`. The database migrates old shares once |

## Related

- [Script 01](01-build-node.html) — the node the pool feeds from, and how to restart it
- [Solo mining](07-mining-services.html) — the other half of the mining hub, including the node-sync watchdog that restarts a stuck node
- [Ports and paths](reference-ports-and-paths.html#public-mining-pool-script-07) — every pool port, and the 51820/udp clash with Fidelius private access
- [Fidelius](051-fidelius.html) — a wallet that can receive pool payouts over Tor
- [Script 06](06-global-health.html) — the Tiny Explorer that the pool's block and payout pages deep-link to
- [Back up and restore](089-backup-restore.html) — the shared engine and personal key the pool's `B` menu uses
- Deeper reading in the toolkit repository: [script07_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script07_design.md) (architecture, reward pipeline, payments, multi-region), [script07_implementation.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script07_implementation.md) (runbooks, scheduler jobs, smoke tests) and [script07_security_audit.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script07_security_audit.md); the pool's own API reference is served at `/api-docs.html` on your domain
