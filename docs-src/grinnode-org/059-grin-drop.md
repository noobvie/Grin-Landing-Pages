---
title: Grin Drop — a giveaway and donation portal
description: How Script 059 deploys Grin Drop — a rate-limited GRIN faucet and donation page on one domain for testnet and mainnet — with its wallet, limits and backups.
section: Scripts
order: 59
label: Script 059
covers: 2026-09-20
updated: 2026-09-20
---

Grin Drop is a small public website that hands GRIN out and takes GRIN in. Visitors can **claim** a little GRIN from a hot wallet on your server — a *faucet*, useful for letting newcomers try a wallet on testnet, for events, or for tips on mainnet — and can **donate** to the same wallet. One domain serves both networks: `https://yourdomain.com/testnet/` and `/mainnet/`, each with its own wallet, service and settings, plus a unified homepage at `/`. The live example is [drop.grin.money](https://drop.grin.money), built with this script. On the wallet hub it is marked ✅ *ready*.

> **Warning:** Status — the portal itself is deployed and in use, but two things in this script are not what they claim. The **passphrase of the giveaway wallet is stored in plain text** on the server so the wallet can restart unattended — the script says so at setup, and it means anyone with root on the box can spend the balance; keep only what you are willing to give away in it. And the **bot protection is off by default and fails open**, so the *global daily cap* — not the per-visitor cooldown — is the real ceiling on what a bad day can cost you (see [Choices](#choices-you-will-make)). Start on testnet.

## What it does

1. **One nginx site for both networks.** *Create / Update domain* writes a vhost for your domain with HTTPS from Let's Encrypt or a Cloudflare origin certificate. `/` is a static homepage (from `web/059_drop/home/`, copied to `/var/www/grin-drop-home/`), `/testnet/` is proxied to `127.0.0.1:3004` and `/mainnet/` to `127.0.0.1:3005`, each with per-IP request limits. Google Analytics and Cloudflare Turnstile keys, when set, are injected into the pages by nginx.
2. **A wallet per network** in `/opt/grin/drop-test/` or `/opt/grin/drop-main/`: its own `grin-wallet` binary, `wallet_data/` with the seed, `grin-wallet.toml` pointed at your node (or a public one), the API secrets, and the saved passphrase. It runs as the `grin` user in **one tmux session** — `drop-test-ownerapi` / `drop-main-ownerapi` — as `grin-wallet owner_api` with the Foreign API mounted on the same port (3420 mainnet / 13420 testnet). The older separate `listen` session on 3415 / 13415 is retired; *Start* and *Stop* clean one up if they find it.
3. **A Node.js/Express app per network** (`grin-drop-test` / `grin-drop-main` systemd services, also as `grin`) that serves the page, talks to the wallet over its Owner API (ECDH-encrypted, opened with the saved passphrase) and Foreign API, and keeps claims, donations, cooldowns and invoices in an SQLite database — `node:sqlite`, no native build step. The database lives in a **separate** directory, `/opt/grin/drop-<net>-data/`, so a wallet reinstall (which wipes the wallet directory) cannot erase the history.
4. **Two modes you toggle independently** in Configure: *giveaway* (the claim flow) and *donation* (three ways to send GRIN in). Either can be off.
5. **Housekeeping:** reboot autostart and a 5-minute watchdog for the wallet session, logrotate for the app and nginx logs, an **encrypted backup** of both networks' wallets and databases with a daily schedule and optional off-site copy, and a *Delete* key that removes everything.

## What a visitor does

### Claiming from the giveaway

The page offers two tabs. **With Address**: the visitor pastes their own Grin slatepack address (`grin1…` on mainnet, `tgrin1…` on testnet) and gets up to the configured amount per claim (defaults: **0.008 GRIN** mainnet, **10 tGRIN** testnet), once per address per cooldown. **Without Address** ✦: no address needed; the visitor is identified by a salted hash of their IP and gets a smaller fixed cap (0.009 mainnet / 2.0 testnet — a constant in the app). Either way the flow is three steps:

| Step | On the page | In the visitor's wallet |
|------|-------------|-------------------------|
| 1 — Choose amount & generate | Pick an amount (or the maximum), pass the Turnstile check if you enabled it, click *Claim*. The page shows a **send slatepack** and starts a countdown (default **30 minutes**) | Paste it: `grin-wallet receive` on the command line, or Grim's *Receive* tab. The wallet prints a **response slatepack** |
| 2 — Finalize | Paste the response into the box and click *Finalize* | Nothing |
| 3 — Confirmed | *Transaction Submitted!* — the server's wallet finalised and broadcast the payment. The visitor's balance updates once it confirms | Wait for the confirmation |

A claim that is not finalised inside the window is cancelled and its locked coins are released (the app sweeps expired claims every 30 seconds, and cancels wallet transactions that are still unfinalised after `wallet_cleanup_hours`, default 1). The page's *How It Works* section walks a first-time user through creating a testnet wallet, so the testnet drop doubles as a tutorial.

### Donating

Three tabs, from simplest to most automatic as advertised — with one caveat:

| Tab | How it works | Status |
|-----|--------------|--------|
| **1. TOR Direct** | Shows the drop wallet's slatepack address and a QR code. The donor's wallet sends to that address over Tor | **Does not work as shipped.** The address is real, but a `grin-wallet owner_api` process never opens a Tor hidden service — only the retired `listen` mode did — so a wallet sending over Tor cannot reach the drop wallet and falls back to producing a slatepack. Point donors at tab 2 |
| **2. Slatepack — You Send** | The donor pastes the slatepack their wallet produced (`grin-wallet send -m …`); the page returns the drop wallet's response slatepack, which the donor pastes back into their wallet to finalise (`grin-wallet finalize -i …`) | Works over HTTPS |
| **3. Invoice — We Request** | The donor enters an amount (0.1 to 10 000 GRIN) and their address; the page creates an **invoice slatepack**; the donor pays it (`grin-wallet pay -i …`) and pastes the response back. Invoices expire after `donation_invoice_timeout` minutes (default 30) | Works over HTTPS. Ignore the page's line about the response arriving *automatically via TOR* — same reason as tab 1 |

The public stats (*total given / received*, counts) can be shown or hidden with `show_public_stats`; they count slatepack and invoice donations only.

## Before you start

| You need | Notes |
|----------|-------|
| A synced Grin node | [Script 01](01-build-node.html). The wallet setup defaults to the local node when it is running, and offers a list of public nodes otherwise (it probes each with `get_tip` before listing it as online) |
| A domain with an **A record** to the server, ports **80 and 443** open | One domain for both networks. Sub-domains starting `fullmain.`, `prunemain.` or `prunetest.` are refused — [Script 02](02-nginx-fileserver.html) owns those |
| nginx and certbot | Installed by the script if missing |
| Node.js 24 | Installed from NodeSource if missing; an older version is replaced only after you say yes |
| `python3`, `tmux` | Installed on any toolkit server; the script uses Python to edit its JSON config and tmux for the wallet session |
| GRIN to give away | Sent to the drop wallet's address after setup — see [Funding the wallet](#funding-the-wallet) |
| Cloudflare Turnstile keys (mainnet) | Free; strongly recommended before enabling the giveaway on mainnet |

## Choices you will make

- **Network.** Testnet first. Each network is set up separately from its own sub-menu; they share the domain and nothing else.
- **HTTPS.** *Let's Encrypt* (needs port 80 reachable and, if you use Cloudflare, the DNS record set to *DNS only* while the certificate is issued) or a *Cloudflare Origin Certificate* pasted in (the domain can stay proxied through Cloudflare).
- **New wallet or recover from seed**, and a passphrase (at least 3 characters). Then two questions: **save the passphrase** (`Y` — needed for the wallet to start on reboot, restart on crash, and for the app to open it; stored in plain text at `/opt/grin/drop-<net>/.temp_<net>`, mode 600) and **save the seed words** to `/opt/grin/drop-<net>/.word_<net>` (`N` by default — write them on paper instead; the encrypted backup captures `wallet_data/`, which contains the seed, either way).
- **Which node** the wallet reads the chain from: the local node (default when running) or a public one from the list.
- **Modes and limits** in Configure — giveaway on/off, donation on/off, public stats; GRIN per claim; cooldown; finalize window; **global daily and hourly caps** (defaults 2000 / 100 claims, `0` = unlimited); invoice expiry; site description and image; maintenance message.
- **Turnstile.** Off until you paste a site key and secret (top-level menu `7`). With it off, the app also lets a claim through when Cloudflare cannot be reached. The [security audit](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script059_security_audit.md) is blunt about it: fresh addresses are free and the anonymous tab's IP check can be fooled on a site not behind Cloudflare, so the **global daily cap × GRIN per claim** is the most a drain can cost you — 2000 × 0.008 = 16 GRIN a day at the mainnet defaults. Set the cap to a number you can lose.

> **Note:** The cooldown default is not what the Configure prompt shows. Setup writes `claim_cooldown_hours: 24` into the config, and the app honours it as **1440 minutes**; the Configure prompt reads a different key and displays `[240 min]` as if that were current. Type the value you want at that prompt and it wins. The live demo runs at 1440.

## The menu

```text
 059) GRIN DROP

  Domain: not configured  (run option 1)
  GA4   : not configured

  ─── Domain & nginx ───────────────────────────────
  1) Create / Update domain  (nginx + SSL for unified drop)
  5) Remove current domain   (delete nginx config + SSL)

  ─── Networks ─────────────────────────────────────
  2) Testnet  (tGRIN — no monetary value)  drop: not running
  3) Mainnet  ⚠ sends/receives real GRIN  drop: not running
  4) Unified Homepage  (aggregated stats for both networks)
  7) Turnstile          (Cloudflare bot protection — optional)
  6) Google Analytics  (GA4 tracking — optional)

  ─── Admin (both networks) ────────────────────────
  B) Backup & Restore (encrypted wallets+seed+DB; daily schedule)
  R) Restore  (decrypt + restore backup — shortcut)
  D) Delete   (wipe all drop data — services, wallets, config, nginx)

  0) Back to main menu
```

| Key | Action |
|-----|--------|
| `1` | Sub-menu: set site name and domain, renew or re-run SSL only, or re-apply the nginx config without changing the domain |
| `2` / `3` | Open a network's own menu (below). Mainnet opens directly — the red *⚠* is the only warning, there is no confirmation prompt |
| `4` | Prints the three URLs the domain serves |
| `5` | Removes the vhost and its symlink, clears the domain from the shared config, and offers to delete the Let's Encrypt certificate (`N` by default) |
| `6` | Set or clear a GA4 measurement ID (`G-…`); nginx is re-applied at once if a domain exists |
| `7` | Set or clear Turnstile site key (`0x…`) and secret; the secret is copied into each installed network's config and the running services are restarted |
| `B` | Backup & Restore sub-menu: backup now, restore, schedule, settings, off-site push |
| `R` | Straight to restore |
| `D` | Remove everything the script ever created, on both networks — after typing `DELETE ALL`. Wallets and their GRIN included; back up first |

Choosing a network shows a status block — domain, mode, node, wallet, and the state of steps 3–6 — above:

```text
  ─── First-time setup (run in order) ─────────────
  1) Setup wallet          (download + 5-step init flow)
  2) Wallet listening      (combined Owner+Foreign · drop-test-ownerapi)
  3) Install               (Node.js + npm + systemd service)
  4) Configure             (modes, wallet API ports/secrets)
  5) Deploy web files      (copy to /opt/grin/drop-test/public_html/)
  6) Start / Stop service  (systemd grin-drop-test)

  ─── Info & maintenance ───────────────────────────
  7) Drop status           (health, balance, claims)
  8) Wallet address        (show + update)
  L) View logs             (activity / journal / nginx)

  ↩  Press Enter to refresh
  0) Back to network select
```

`1) Setup wallet` and `2) Wallet listening` are sub-menus of their own:

```text
  1) Install new wallet      (first-time setup)
  2) Re-install wallet       (clean + full reinstall)
  3) Scan wallet             (recover wallet from seed · balance wrong · after node switch)
  4) Update / roll back binary (change grin-wallet version, keep wallet data)
  5) Switch Grin node        (change node without reinstalling)
  6) View / recover seed     (display seed phrase, optionally save)
```

```text
  1) Start / restart wallet listener   (combined Owner+Foreign, drop-test-ownerapi)
  2) Stop wallet listener
  3) Auto-start wallet @reboot              [not set]
  4) Watchdog: auto-restart wallet on crash [not set]
```

## Setup, step by step

| Step | What happens | What you do |
|------|--------------|-------------|
| Top menu `1` → `1` | Site name and domain are saved to `/opt/grin/conf/drop_shared.conf`. Then the SSL choice: Let's Encrypt writes a temporary port-80 vhost, runs `certbot --nginx`, and only then writes the real vhost; Cloudflare asks you to paste the certificate and key. The vhost is tested and loaded, the homepage files are copied, logrotate is set | Name, domain, `1` or `2`, an email for Let's Encrypt |
| `2` or `3` | Enter the network | |
| `1` → `1` Install new wallet | Creates the `grin` system user; downloads the pinned `grin-wallet` release through the toolkit's shared installer (checksum-verified); runs `grin-wallet init` (new: prints the seed; recover: asks for your words); asks whether to save the passphrase and the seed words; probes the public node list and the local node and lets you pick; patches `grin-wallet.toml` (a public node's address, or the local node's secret path plus the 5-minute secret-sync timer that keeps it valid across node rebuilds; Owner port 3420 / 13420; Foreign API on the same port; absolute secret path; 3 log files); fixes ownership to `grin` | `1` new or `2` recover; passphrase twice; **write the seed down**; `Y` to save the passphrase; pick the node (Enter takes the default) |
| `2` → `1` Start listener | Kills any old session, starts `grin-wallet owner_api` in tmux as `grin`, waits 5 s, fetches the wallet address and saves it to the config. Then `3` and `4` in the same menu to enable the reboot cron (asks for a boot delay, default 300 s so the node is up first) and the 5-minute watchdog | Enter, then `3`, then `4` |
| `3` Install | Node.js 24, `npm` latest; copies `server/` and `public_html/` into `/opt/grin/drop-<net>/`; `npm install`; log file + logrotate; creates the data directory; writes the config defaults; writes `grin-drop-<net>.service` | `Y` to enable at boot, `Y` to start now |
| `4` Configure | Every setting with its current value in brackets; Enter keeps it, `0` cancels. Detects the wallet address from the running app or wallet. Restarts the service at the end | Set amounts and caps; read the Turnstile advice above |
| `5` Deploy web files | Re-copies `public_html/` and `server/` from the toolkit checkout and re-runs `npm install`; writes `robots.txt`. Install already did this once — use it after a toolkit update | Nothing |
| `6` Start / Stop | Start, stop, restart, enable/disable at boot | |
| `7` Drop status | Service, port, URL, wallet session, DB size, balance and claim counts from the app, the last 10 journal lines | Check the balance shows |

## After it finishes

```bash
curl -s http://127.0.0.1:3004/api/status      # 3005 for mainnet
```

You want JSON with your `wallet_address`, a numeric `wallet_balance` and `"giveaway_enabled":true`. `"wallet_balance":null` means the app cannot open the wallet — the listener is down, the passphrase file is missing, or the wallet is still scanning. Then open `https://yourdomain.com/testnet/` in a browser and, from a second wallet, run through a claim.

```bash
tmux attach -t drop-test-ownerapi          # the wallet's own output; Ctrl+B then D to leave
journalctl -u grin-drop-test -n 50         # the app
tail -f /opt/grin/drop-test/grin_drop_test.log   # the activity log: CLAIM_INIT, FINALIZE_OK, RATE_LIMIT …
```

### Funding the wallet

Menu `8` prints the wallet's slatepack address (and lets you correct the one shown on the donate page). The giveaway wallet **receives** like any other Grin wallet: from the sending wallet, produce a slatepack for that address, paste it into tab 2 of your own donate page, and finalise the response — that is the only inbound path, since the combined listener has no Tor onion. On testnet, claim a starting balance from another faucet the same way. The app writes `LOW_BALANCE` to the activity log, and `/api/status` reports `low_balance`, when the spendable balance falls under `low_balance_alert_grin` (default: 100 GRIN mainnet, 1000 testnet; `0` disables it).

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/drop-<net>/` | Wallet dir **and** app dir: `grin-wallet`, `wallet_data/`, `grin-wallet.toml`, `.owner_api_secret`, `.foreign_api_secret` |
| `…/.temp_<net>`, `…/.word_<net>` | Saved passphrase (plain text, 600); seed words if you chose to save them |
| `…/grin_drop_<net>.conf` | The network's settings, JSON, mode 600 — edited by Configure, read live by the app |
| `…/server/`, `…/public_html/` | The app and the site; re-created by Deploy |
| `…/grin_drop_<net>.log` | Activity log (claims, donations, limits), rotated daily |
| `…/drop-<net>-start.sh`, `…/drop-<net>-watchdog.sh` | The reboot and watchdog wrappers the crons call |
| `/opt/grin/drop-<net>-data/drop-<net>.db` | SQLite: claims, donations, invoices — survives a wallet reinstall |
| `/opt/grin/conf/drop_shared.conf` | Domain, site name, SSL type, GA4 ID, Turnstile keys — shared by both networks |
| `/etc/systemd/system/grin-drop-<net>.service` | The app, as `grin`, restart always |
| root crontab entries `# grin-drop-<net>-reboot` and `# 059_watchdog_<net>` | Wallet autostart and watchdog |
| `/etc/nginx/sites-available/<domain>`, `/etc/nginx/conf.d/script059-drop.conf` | The vhost and its rate-limit zones |
| `/var/www/grin-drop-home/` | The unified homepage |
| `/opt/grin/backups/grin_drop_backup_<DDMMYYYY>.tar.gz.enc` | Encrypted backups |
| `/opt/grin/logs/grin_drop_<date>.log` | This run's log |

## Backups

`B` opens the backup menu. **Backup now** writes one AES-256 encrypted archive of everything the two networks cannot recreate — each wallet directory minus the re-deployable bulk (`server/`, `public_html/`, `node_modules/`, logs), including the binary, `wallet_data/` with the seed, the toml, the secrets, the passphrase and seed files, the config — plus a consistent snapshot of each database taken with SQLite's online backup so a live write never produces a torn copy, plus `drop_shared.conf`. The password is the toolkit's standard **personal key + the archive's date** (`DDMMYYYY`), the same key every product's backup uses, stored in `/opt/grin/conf/grin_backup.conf` so the daily cron can run unattended. **Keep a copy of that key off the server** — with the box gone, the date alone opens nothing.

*Schedule* installs `/etc/cron.d/grin-drop-backup` (daily, keeps the newest 14 archives by default); *Settings* sets the key and retention and lists archives; *Offsite push* copies each archive to another server over `scp`. **Restore** stops both services and wallet sessions, decrypts, extracts straight back to `/opt/grin/…`, re-tightens the secret file permissions and restarts. Older `grin_drop_all_backup_*` archives from the first version restore too, but lack `wallet_data/`, so run *Scan wallet* afterwards.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Change the claim amount, cooldown or caps | Network menu → `4`. The app reads the config file on every request; Configure also restarts the service |
| Pause the site with a message | `4` → set the maintenance message, then set `maintenance_mode` to `true` in `grin_drop_<net>.conf` (Configure does not prompt for it). The API still answers so the page can show the overlay |
| Turn the giveaway off but keep donations | `4` → `giveaway_enabled` → `false` |
| See today's claims | `7`, or `L` → `1` for the activity log |
| Restart the wallet after a config change | `2` → `1` |
| Move the wallet to a different node | `1` → `5`, then `2` → `1` to restart the listener; run `1` → `3` Scan if the balance looks wrong afterwards |
| Update grin-wallet, or roll it back | `1` → `4` — the shared installer keeps the previous binary for a rollback |
| Re-deploy after `git pull` | `5` on each network; `1` → `3` at the top level if the nginx template changed |
| Add or change the Turnstile keys | Top menu `7` — nginx is re-applied and the services restarted |
| Start over on one network | `1` → `2` Re-install (the database is rescued first); the seed is gone, so recover with it only if you meant to |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Passphrase file: ✗ MISSING — wallet boots LOCKED; balance/claim/donate will all fail` on the listener screen | You answered `n` to saving the passphrase. `2` → `1` offers to save it now; or re-run `1` → `1` |
| *Wallet is busy syncing — claim is unavailable right now* on the page | The wallet is scanning the chain (first start, after a node switch, or the periodic balance refresh). Wait; the app serialises scans so this clears itself |
| `wallet_balance: null` in `/api/status` | The Owner API is not reachable or will not open: check `tmux has-session -t drop-<net>-ownerapi`, that port 3420 / 13420 is listening, and the passphrase file. `init_secure_api: HTTP 401` in the journal means the app's `.owner_api_secret` path in the config does not match the wallet's |
| `Node secret not found — run script 01 to build the node first.` during wallet setup | You chose the local node but `/opt/grin/conf/grin_instances_location.conf` does not name one for this network. Build it, or pick a public node |
| `certbot failed — check DNS points to this server and port 80 is open.` | Exactly that; and if the domain is on Cloudflare, switch the record to *DNS only* while certbot runs, or use the Cloudflare certificate option instead |
| *Bot challenge failed* on every claim | Turnstile site key and secret are from different Cloudflare sites, or the secret was set before the network was installed. Re-enter both at top menu `7` |
| Cooldown is 24 h although Configure shows 240 min | The note under [Choices](#choices-you-will-make). Type the cooldown you want at the prompt |
| Page loads with missing styles, or `503` on some requests | The vhost limits each IP to 5 requests per minute (burst 5) on `/testnet/` and `/mainnet/`, and that prefix covers the CSS and JS too. Raise `drop_test` / `drop_main` in `/etc/nginx/conf.d/script059-drop.conf` and reload nginx. Not observed on the live demo, which sits behind Cloudflare |
| `Scan cancelled — stop the Owner API session first to avoid conflicts.` | Two wallet processes on one `wallet_data/` corrupt each other. `2` → `2` Stop, then scan, then `2` → `1` |
| The wallet came back after a reboot but the app did not | Install asked *Enable autostart on boot?* and you said no. `6` → enable |
| A claim shows *Transaction Submitted!* but the visitor never receives it | The visitor's wallet needs to be online to see the confirmation, and the transaction needs to confirm — tell them to run `grin-wallet info` after a few minutes. If `FINALIZE_OK` is in the activity log the coins left your wallet |

## Related

- [Wallet & payment services](05-wallet-services.html) — the hub this script is launched from
- [Script 01](01-build-node.html) — the node the drop wallet talks to
- [Script 02](02-nginx-fileserver.html) — the reserved sub-domain prefixes and the same Let's Encrypt pattern
- [Accept GRIN in WooCommerce](053-woocommerce.html) — the other payments product on the hub
- [Ports and paths](reference-ports-and-paths.html) — 3004 / 3005, 3420 / 13420 and every directory above
- [Back up and restore](089-backup-restore.html) — the toolkit-wide backup (089) that uses the same personal key
- The toolkit's [script059_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script059_design.md), [script059_implementation.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script059_implementation.md) and [script059_security_audit.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script059_security_audit.md)
