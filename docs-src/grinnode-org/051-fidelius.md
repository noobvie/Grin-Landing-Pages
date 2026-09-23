---
title: Fidelius — your personal web wallet
description: How Script 051 deploys Fidelius, a browser wallet for your own node with server-held keys behind nginx, Basic Auth and HTTPS, plus WireGuard-only access.
section: Scripts
order: 5.1
short: Fidelius
label: Script 051
covers: 2026-09-19
updated: 2026-09-19
---

Fidelius is a wallet you use from a browser — on your phone, on a laptop, anywhere — while the wallet itself runs on your server next to your node. One small Node.js service manages as many wallets as you like, on mainnet and testnet at once, and the page is served by nginx over HTTPS behind a username and password. **The keys stay on the server**: every wallet is a normal `grin-wallet` whose seed lives in `/opt/grin/fidelius/`, and the browser only drives it. (Accio, the toolkit's other web wallet, is the opposite — keys in the visitor's browser, nothing on the server — and it has not run anywhere yet; see the [wallet hub](05-wallet-services.html#accio-the-public-web-wallet-not-yet-run).)

It is a **personal** wallet: it is meant for the server owner and nobody else. Basic Auth is the whole front door, and whoever passes it controls every wallet registered.

> **Warning:** Status — the hub marks Fidelius *building*. It has been through one live test on a VPS (2026-08-09, a synced mainnet node, which found and fixed a node-status bug), but the changes since — the node-status rework, the WireGuard private-access menu, the Transporter send rail — have **not** been run on a server. Start on **testnet**, keep amounts small on mainnet, and write the seed phrase of every wallet down the day you create it.

## What it does

1. Installs the pinned `grin-wallet` binary (v5.4.1) once, shared by every wallet, plus Node.js 24, nginx, certbot, `htpasswd`, tor, `qrencode` and `jq`.
2. Deploys the app to `/opt/grin/fidelius/app/` and runs it as the systemd service **`grin-fidelius`**, bound to `127.0.0.1:7420` — never reachable directly from outside.
3. Writes an nginx site for your domain that proxies to that port with **Basic Auth**, a strict Content-Security-Policy, per-IP rate limits (3 sends a minute, 10 API calls a minute, 20 page loads a minute) and HTTPS from Let's Encrypt or a Cloudflare Origin certificate.
4. Opens ports 80 and 443 in the firewall and adds a **fail2ban** jail: five wrong passwords in ten minutes bans the address for an hour.
5. Installs the 5-minute `grin-secret-sync` timer, so wallets pointed at your local node keep working after a node rebuild.
6. Optionally moves the whole thing off the public internet: nginx listens only on a **WireGuard** address and the certificate is issued by DNS instead of over port 80 (menu `V`).

From then on, wallets are created, unlocked, funded and spent **in the browser**. The script is only needed again to change settings, update the binary, or harden access.

## How it is built

- **One process, many wallets, both networks.** Each wallet is a directory under `/opt/grin/fidelius/` — `wallet_<network>_<name>/` — holding its own `grin-wallet.toml` and encrypted seed. The service keeps a registry (`wallets_info.json`) and, when you unlock a wallet, starts that wallet's own `grin-wallet` processes as children: an **Owner API** for balance and sending, and a **Listener** (Foreign API, over Tor) for receiving. A locked wallet has no processes.
- **Ports are allocated per wallet.** The first mainnet wallet gets Foreign 3415 and Owner 3420, the second 3416 / 3421, and so on; testnet counts from 13415 / 13420. All on localhost. This is why Fidelius should not share a server with the CMD wallet or Grin Drop, which want 3415 / 3420 too — and why, on a server that also solo-mines, a *second* mainnet wallet would land on 3416, the node's stratum port.
- **Wallet names must be unique across both networks.** Every URL in the app is `/api/wallet/<name>/…`, so a mainnet and a testnet wallet both called `savings` cannot coexist; the app refuses the second and suggests `savings-test`.
- **Two locks.** The browser locks all wallets after 15 minutes without mouse or keyboard activity (adjustable in the UI). The server has a backstop of its own (`WW_IDLE_LOCK_MINUTES`, default 60): after that long with no deliberate action it forgets the passphrase even if the tab was closed — listeners keep running, so receiving is unaffected.
- **The passphrase never touches a command line.** grin-wallet reads it from the app over stdin, so it does not appear in `ps` — the reason the binary is pinned to a version known to read stdin.
- **The service runs as root**, like the rest of the toolkit, with systemd hardening (`ProtectSystem=full`, `PrivateTmp`, `NoNewPrivileges`, write access only to `/opt/grin/fidelius` and `/opt/grin/logs`).

Design notes and the security audit are in the toolkit's [script051_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script051_design.md) and [script051_security_audit.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script051_security_audit.md).

## Before you start

| Need | Why |
|------|-----|
| A node, or a public node to point at | A wallet needs a node to read the chain. Your own node from [Script 01](01-build-node.html) on the same server is the default and the private choice; the wallet wizard also offers a curated list of public nodes (`api.grin.money`, `api.grinnode.org`, … — the same kind of endpoint [Script 04](04-publish-node-api.html) publishes) |
| A domain with an **A record** pointing at this server | For HTTPS. `wallet.yourdomain.com` is the pattern the script suggests. Using Cloudflare? For Let's Encrypt the record must be **DNS only** (grey cloud); with a Cloudflare Origin certificate it can stay proxied |
| Ports **80** and **443** open at the provider | Step 7 opens them in the server's own firewall; the provider's firewall or security group is yours to open |
| The toolkit's `web/051_fidelius/` folder present | Step 3 copies the app from the cloned repository — a partial clone has nothing to deploy |
| tor installed and running | Only for **Tor sends** and for the wallet's `.onion` listener; step 2 installs and enables it. Slatepack send/receive works without it |

## The menu

```text
 051) FIDELIUS · PERSONAL WEB WALLET  (Node.js)

  1 grin-wallet binary : not installed  → step 1
  2 Dependencies       : missing  → step 2
  3 App + systemd      : not deployed  → step 3
  4 nginx vhost        : not configured  → step 4
  5 SSL                : not configured  → step 5
  6 Basic Auth         : not configured  → step 6
  Web UI               : not live
  Wallets registered   : 0

  ─── First-time setup (run in order) ─────────────
  1) grin-wallet binary        (install · update · roll back · pin v5.4.1)
  2) Install dependencies      (nodejs, nginx, certbot, htpasswd, tor, qrencode, jq)
  3) Deploy app + systemd      (web/051_fidelius/ → /opt/grin/fidelius/app)
  4) Configure nginx           (reverse proxy → 127.0.0.1:7420)
  5) Setup SSL                 (Let's Encrypt or Cloudflare Origin)
  6) Setup Basic Auth          (set / change password)
  7) Configure firewall        (open ports 80 + 443)

  ─── Info / maintenance ──────────────────────────
  8) Status & info
  9) Edit saved settings       (domain, email, auth user)

  ─── Optional hardening ──────────────────────────
  V) Private access            (WireGuard tunnel + DNS-01 cert)

  ↩  Press Enter to refresh
  0) Back to main menu

Select [1-9 / V / 0]:
```

The status block at the top updates on every refresh, so you can see at a glance which step is next. Once WireGuard has been installed a `V Private access` line appears in it too.

| Key | Action |
|-----|--------|
| `1`–`7` | The setup chain, in order — see the step table below. One exception the script handles itself: step **5** (HTTPS) refuses to run without step **6** (Basic Auth) and offers to run it first, because an HTTPS site with no password would expose the wallet page to everyone |
| `8` | Status & info — dependencies, binary version, service, vhost, certificate and its expiry, Basic Auth user, Tor, fail2ban (with the number of banned addresses), the secret-sync timer, and every registered wallet with its ports. Also warns about duplicate wallet names left over from an older install |
| `9` | Edit the saved domain, Let's Encrypt e-mail, auth username and the server-side idle lock (minutes; `0` disables). Restarts the service if it is running |
| `V` | [Private access](#private-access-menu-v) — WireGuard + DNS-01 |
| `0` | Back to the hub |

`xp` typed at the prompt still opens the Grin XP variant — a leftover alias from when it had a row here; its real key is `3` on the hub.

## First-time setup, step by step

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | **grin-wallet binary.** Opens the toolkit's shared binary screen: `1` installs the pinned **v5.4.1** (downloaded from GitHub into `/opt/grin/wallet-bin/<tag>/`, SHA256-verified, copied to `/opt/grin/fidelius/grin-wallet`), `2` updates to upstream's latest after a warning, `3` rolls back to the previous version, `4` picks any cached version, `5` re-verifies the installed file, `6` prunes the cache. It stops and restarts `grin-fidelius` around a swap | `1` |
| 2 | **Dependencies.** Checks for `node`, `nginx`, `certbot`, `htpasswd`, `tor`, `qrencode`, `jq`; asks `Install missing packages now? [Y/n/0]`. If Apache is holding port 80 it offers to stop and disable it. Installs **Node.js 24** from NodeSource when `node` is missing or older than 24 (a newer one is left alone), then `nginx certbot python3-certbot-nginx apache2-utils tor qrencode jq`, and enables tor. Finally checks that `script` (util-linux) exists — wallet **recovery** needs it, because grin-wallet asks for the seed phrase on a real terminal | Enter |
| 3 | **Deploy app + systemd.** Lists what it will do, asks `Proceed? [Y/n/0]`, then copies `server.js`, `transporter.js`, `package.json` and `client/` to `/opt/grin/fidelius/app/`, runs `npm install --omit=dev`, writes `wallet.env`, the unit file `/etc/systemd/system/grin-fidelius.service` (logging to `/opt/grin/logs/grin-fidelius.log`, rotated weekly), enables and starts the service, and installs the `grin-secret-sync` timer | Enter |
| 4 | **Configure nginx.** Asks for the domain (validated as a hostname), then `Write HTTP vhost (step 5 adds HTTPS)? [Y/n/0]`. Creates the three rate-limit zones in `/etc/nginx/conf.d/script051-fidelius-ratelimit.conf` and writes an **HTTP-only** site at `/etc/nginx/sites-available/grin-fidelius` that redirects everything to HTTPS; `nginx -t`, reload, and the domain is saved to `config.conf` and `wallet.env` (the app checks the `Host` header against it) | Domain, Enter |
| 5 | **Setup SSL.** If no password file exists yet it runs step 6 first. Then `1) Let's Encrypt` — asks for an e-mail and runs `certbot certonly --nginx` — or `2) Cloudflare Origin Certificate` — you paste the certificate and the private key from the Cloudflare dashboard (*SSL/TLS → Origin Server → Create Certificate*), saved under `/etc/ssl/cloudflare-origin/`. Either way the site is rewritten as the full **HTTPS** vhost: `auth_basic`, security headers, the three proxied locations, dotfiles denied | `1` or `2` |
| 6 | **Setup Basic Auth.** Username (default `grin`), then `htpasswd` asks for the password twice. If the file already exists: `1` add or update this user, `2` recreate the file and drop every other user | A username you will type on your phone, and a **long** password |
| 7 | **Configure firewall.** `ufw allow 80/tcp` and `443/tcp` (or iptables, with a warning that those rules are not persistent), then `Install a fail2ban jail for Basic Auth brute force? [Y/n]` → `/etc/fail2ban/jail.d/grin-fidelius.conf` with two jails: wrong passwords (5 in 10 min → 1 h ban) and rate-limit hits (10 in 10 min → 10 min ban) | Enter, Enter |

Everything the steps ask for is remembered in `/opt/grin/fidelius/config.conf`, so re-running a step shows the previous answer in brackets.

## After it finishes

```bash
systemctl status grin-fidelius                       # active (running)
curl -i http://127.0.0.1:7420/api/wallets            # HTTP 200 and a JSON list (empty at first)
tail -f /opt/grin/logs/grin-fidelius.log             # the app's own log
```

Then open `https://wallet.yourdomain.com` in a browser. You should be asked for the Basic Auth username and password, and land on an empty **Wallet** tab with a **Setup** tab beside it. Note that `journalctl -u grin-fidelius` shows only systemd's start/stop lines — the app writes to the log file, not the journal.

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/fidelius/grin-wallet` | The one binary every wallet uses (copied from `/opt/grin/wallet-bin/<tag>/`) |
| `…/app/` | The Node.js app: `server.js`, `transporter.js`, `client/`, `node_modules/` |
| `…/config.conf` | Domain, e-mail, auth user, idle-lock minutes, and the private-access bind address |
| `…/wallet.env` | Environment for the service (public host, port, idle lock). Regenerated by steps 4, 5 and 9 — edit via the menu, not by hand |
| `…/wallets_info.json` | The wallet registry: name, network, directory, ports, node URL |
| `…/wallet_<net>_<name>/` | One directory per wallet: `grin-wallet.toml`, `wallet_data/wallet.seed` (the encrypted seed), the two wallet API secrets, `.wallet_address`, `.address_book.json` |
| `/etc/systemd/system/grin-fidelius.service` | The service, bound to `127.0.0.1:7420` |
| `/etc/nginx/sites-available/grin-fidelius` | The site (linked from `sites-enabled/`) — HTTP-only after step 4, full HTTPS after step 5 |
| `/etc/nginx/grin-fidelius.htpasswd` | Basic Auth users |
| `/etc/nginx/conf.d/script051-fidelius-ratelimit.conf` | The three rate-limit zones |
| `/etc/fail2ban/jail.d/grin-fidelius.conf` | The two jails (step 7) |
| `/etc/logrotate.d/grin-fidelius` | Rotation for the app log |
| `/opt/grin/logs/grin-fidelius.log` | The app log. nginx logs to `/var/log/nginx/grin-fidelius-access.log` and `-error.log` |
| `/opt/grin/logs/grin_fidelius_<date>.log` | This run of the script |
| `/etc/ssl/cloudflare-origin/` | `<domain>.pem` and `.key` — only with a Cloudflare Origin certificate |

## Using the wallet

The page has six tabs: **Wallet**, **Send**, **Receive**, **History**, **Node** and **Setup**.

**Creating your first wallet** happens on the Setup tab, under *Your Wallets*, through a short wizard: a name (`main`, say), the network, the directory (proposed as `wallet_<network>_<name>` under `/opt/grin/fidelius/`), the node to use — your local node or one of the public nodes, each pinged live — and then one of **New Wallet** (a fresh seed), **Recover** (paste a seed phrase) or **Skip** (register only, initialise later). New wallets take a passphrase twice. The 24-word seed phrase is shown once; the wizard refuses to finish if it could not read it back, so you always get a chance to write it down. A Tor step shows whether tor is running on the host; it cannot be changed from the browser.

**Unlocking** a wallet (the Wallet tab) means entering its passphrase; the app then starts that wallet's Owner API and shows the balance, the slatepack address with a QR code, and two service switches — the Owner API and the **Listener (Tor)**. The listener is what makes you reachable at your `grin1…` address; leave it on if you expect payments.

**Sending** (the Send tab) offers up to four methods, depending on what the host provides:

| Method | Needs | How it works |
|--------|-------|--------------|
| **Send via Tor** | tor running on the host; the recipient online with their Tor listener up | Interactive — enter the recipient's `grin1…` address (or scan/upload a QR), the amount, and it completes in one go. Mainnet and testnet addresses are checked against the wallet's network and a mismatch is refused |
| **Send via Transporter** | A Transporter URL configured on the Setup tab (from the [Connectivity Hub](09-connectivity-hub.html#grin-transporter-093), main menu 9); the recipient must use a Transporter on the same network | Asynchronous — the slate is queued and the recipient can be offline |
| **Batch Send via Tor (CSV)** | As Tor | Paste lines of `address,amount[,label]`; each row is sent in turn, stopping at the first failure |
| **Slatepack** | Nothing | Offline exchange: the wallet produces a slatepack text for you to deliver by any channel; paste the recipient's reply back to finalise. Funds are locked as soon as the slatepack is produced, so an unanswered send shows up as a pending transaction you can cancel |

Sending over Tor or Transporter to an address not yet in the address book prompts a **0.1 ∩ test-send** warning first; addresses are saved to the book automatically and marked confirmed once a payment to them completes.

**Receiving** (the Receive tab) shows your slatepack address and QR for Tor payments, and a box to paste an incoming slatepack for the manual flow — the wallet signs it and gives you the response to send back. You can also create an **invoice** slatepack for a payer to fulfil.

**Everything else** lives on the Wallet and Setup tabs: transaction history with cancel and re-broadcast, a **Show seed** button (passphrase-gated and rate-limited), an encrypted `.gws` **backup export** and import, delete (with or without the files on disk), accounts, and the address book. The Node tab shows the node the *open* wallet is using — local or public, synced or not, peers where visible — and has a `USE` button to switch back to the local node.

## Private access (menu `V`)

By default the wallet's login page is on the public internet, defended by Basic Auth and fail2ban. Menu `V` removes it from the internet altogether while keeping a real Let's Encrypt certificate for the same domain name, so the browser still sees the green padlock.

How it works: a **WireGuard** tunnel (`wg0`, address `10.9.0.1`, UDP `51820`) lets your devices reach the server privately. nginx is then told to **listen only on `10.9.0.1:443`** — not `0.0.0.0` — so from the internet there is nothing to connect to, not even a TLS handshake. Your domain's A record is changed to `10.9.0.1`, a private address, which only tunnelled devices can route to. The certificate is issued with **DNS-01**: Let's Encrypt checks a TXT record at your DNS provider instead of connecting to port 80, so the host needs no public port to obtain or renew it.

```text
  ─── Setup (in order) ────────────────────────────
  1) Install WireGuard        (interface 10.9.0.1, udp/51820)
  2) Add a device             (prints a QR code to scan)
  3) Devices                  (list / revoke / re-show QR)
  4) Certificate via DNS-01   (portless issue + renewal)
  5) Switch wallet to VPN-only  (needs a proven handshake)

  ─── Maintenance ─────────────────────────────────
  6) Revert to public HTTPS
  7) Diagnose access

  0) Back

Select [1-7 / 0]:
```

| Key | Action |
|-----|--------|
| `1` | Installs `wireguard`/`wireguard-tools`, generates the server key, asks for the public address your devices will dial (detected for you; it must not be the wallet's own domain, which will soon resolve inside the tunnel), opens UDP 51820, enables `wg-quick@wg0` at boot |
| `2` | Adds a device by name and prints a **QR code** for the WireGuard phone app (plus the config text). It offers to delete the stored copy of the device's private key afterwards — do it, and re-add the device if you ever need the QR again |
| `3` | Lists devices with their last handshake; re-shows a QR; revokes a device |
| `4` | Issues the certificate via DNS-01. Supported providers: **Cloudflare** and **DigitalOcean** — you paste an API token (stored for renewals). If the domain already has an HTTP-01 certificate the same lineage is re-issued with the new method |
| `5` | The switch. Two hard gates: it refuses until **at least one device has completed a handshake** (turn the tunnel on and load any page first), and it refuses an HTTP-01 certificate, because that would renew fine today and then fail silently in about 60 days once port 80 is gone. Then it rewrites the vhost with the private bind, verifies with `nginx -t`, reloads, checks that nginx really did bind `10.9.0.1:443`, and adds the WireGuard subnet to fail2ban's `ignoreip` so a mistyped password from your own phone cannot ban you |
| `6` | Puts the wallet back on the public listener |
| `7` | Diagnoses: tunnel state, handshakes, whether the domain resolves to the tunnel address, the listener, the certificate's renewal method, and an end-to-end request (a **401** means TLS and Basic Auth are both working) |

Things to know before choosing it:

- **Cloudflare users:** the A record must be **DNS only** (grey cloud). A proxied record sends browsers to Cloudflare, which has no route to `10.9.0.1`.
- Some home routers and ISP resolvers strip private addresses from DNS answers ("DNS rebinding protection"), so `wallet.yourdomain.com → 10.9.0.1` may fail to resolve on such a network. `7) Diagnose` detects it and prints the workaround (a `DNS =` line in the device config).
- The tunnel reaches **this server only** — it is not a VPN for your traffic — and it never touches SSH, so if anything goes wrong SSH is still the way in.
- The public mining pool (Script 07) also uses UDP **51820** for its own WireGuard interface; the two cannot share a server.
- WireGuard changes *who can reach* the login page, not what happens after: a stolen, unlocked phone is a full bypass. Keep the Basic Auth password anyway.
- Requires a WireGuard-capable kernel; on OpenVZ/LXC containers the script tells you it cannot proceed.

> **Note:** This whole menu was built and reviewed from the code (2026-08-08) and has **never been run on a VPS**. Treat the first switch as an experiment with SSH open in a second window.

## Backups and seeds

Three layers, use all three:

1. **Write the seed phrase down** when a wallet is created, and check it later with *Show seed* on the Wallet tab. The phrase is the wallet; nothing else is needed to recover it on another machine.
2. **Export a `.gws` backup** from the Wallet tab — an encrypted archive of the wallet directory you can keep off the server. *Import* on the Setup tab restores it, re-points it at this host's node, and reminds you that the balance reads zero until a scan.
3. **[Admin & Maintenance → Backup](089-backup-restore.html)** (Script 089) includes every `/opt/grin/fidelius/wallet_<network>_*` directory, the registry and `config.conf` — found by scanning the folder live, so wallets created from the browser at any time are picked up.

> **Warning:** Backups taken with the toolkit **before 2026-08-05 contain no Fidelius seeds** — the backup script only looked at a registry file Fidelius never wrote, while reporting success. If you have older archives, do not rely on them for Fidelius; export `.gws` files or take a fresh backup now.

## Changing a wallet's node

A wallet records its node in two places: the registry (what the UI wrote) and `grin-wallet.toml` (`check_node_api_http_addr`, what the wallet binary actually dials). The Node tab lets you switch a wallet between your local node and a public one, and this is the only safe way to do it, because the two settings must move **together**: a wallet pointed at your *local* node also carries `node_api_secret_path`, the path to your node's `.foreign_api_secret`, and if you re-point the URL by hand and leave that line in place, grin-wallet sends your node's secret as a password to the public host. The UI clears it for a public node and sets it for the local one. If the two settings ever disagree — after a hand edit, or a wallet created with *Skip* — the Node tab shows a drift notice rather than guessing.

A **rebuild of the local node** with Script 01 does not break anything: the `grin-secret-sync` timer re-points every local-node wallet within five minutes. Wallets on public nodes are deliberately left alone by that timer.

## Grin XP — the XP-themed variant

Hub key `3` opens **Grin XP** (script `051x`): a wallet page dressed up as a Windows XP desktop, with the wallet running in an iframe. It is **mainnet only** and, despite the name, is *not* Fidelius — it is a separate, older PHP app (`web/051_xp_wallet/`, served by nginx + php-fpm) with its own site `web-wallet-xp`, its own config in `/opt/grin/webwallet/xp-mainnet/`, its own `htpasswd` and rate limits. Its menu is the same shape as this page's: `a` dependencies (nginx, php, certbot, htpasswd, qrencode) · `b` deploy files · `c` nginx · `d` SSL · `e` Basic Auth · `f` firewall · `i` status · `j` settings. It opens with a red banner reminding you the GRIN is real and the theme cosmetic.

> **Warning:** Status — *building*, and its wallet link is unresolved. The XP app does not run a wallet of its own; it proxies to a `grin-wallet` already listening on this server and expects to find that wallet's Owner API secret through a registry entry (`MAINNET_WALLET_DIR`) that no current toolkit script writes, falling back to a directory (`/opt/grin/wallet/mainnet/`) that no current script creates. Read from the code, not tested on a server — assume it needs work before it can show a balance.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Add another wallet | Browser → Setup tab → *Your Wallets* → the wizard. No script needed |
| Change the Basic Auth password | Script 051 → `6` → `1` (add/update the user) |
| Add a second login user | Script 051 → `6`, type the new username, then `1` |
| Change the domain | `9` to save it, then `4` and `5` again to rewrite the site and get a certificate for the new name |
| Update `grin-wallet` | `1` → `1` for the pinned version; roll back with `3` if unlocking breaks. Wallets pick it up when the service restarts, which the screen does for you |
| Update the app after a toolkit `git pull` | `3` again — it re-copies the files and restarts the service; wallets and settings are untouched |
| See the app's log | `tail -f /opt/grin/logs/grin-fidelius.log` |
| Restart the service | `systemctl restart grin-fidelius` — every wallet locks; receiving resumes when you unlock and start the listener again |
| Unban my own address after too many wrong passwords | `fail2ban-client set grin-fidelius-auth unbanip <IP>` |
| Take the wallet off the public internet | `V` — see [Private access](#private-access-menu-v) |
| Change how long an idle wallet stays unlocked | Browser setting for the tab timer; `9` for the server-side backstop |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `grin-fidelius enabled but not active` at step 3 | The app crashed on start. `tail -n 50 /opt/grin/logs/grin-fidelius.log` for the reason (a missing module means `npm install` failed — re-run `3`); `journalctl -u grin-fidelius -n 50` for unit-level errors |
| `Basic Auth (step 6) is required` at step 5 | Deliberate: answer `Y` to run step 6 now, then SSL continues |
| `certbot failed` at step 5 | The A record is wrong or not propagated, port 80 is closed at the provider, or the domain is proxied through Cloudflare (switch to *DNS only*, or use the Cloudflare Origin option) |
| `nginx config test failed` at step 4 or 5 | Usually a certificate path that does not exist. `nginx -t` prints the line; re-run `5` |
| Browser shows the page but every wallet says **Node unreachable** | The wallet's node is down or unreachable, or — on an older deploy — the app was probing a node API that grin 5 removed. Check the node on the Node tab and with [Script 01's status check](01-build-node.html#after-it-finishes); update the app with `3` if the toolkit is newer than the deploy |
| Balance refresh or send fails with *Cannot parse response* on a local-node wallet | The node was rebuilt and `node_api_secret_path` points at the old directory. Wait for the 5-minute timer, or run `grin-secret-sync` |
| `Recover` in the wizard fails at once | `script` (util-linux) is missing — `apt install bsdutils` (Debian/Ubuntu) or `dnf install util-linux`; step 2 checks for it |
| `DUPLICATE wallet names:` on the status screen | Two wallets share a name across networks; only the first is reachable. Rename one directory and its entry in `wallets_info.json`, then restart the service |
| Locked out after private access — nothing loads | Tunnel off, or the phone's resolver strips the private A record. SSH in, run `V` → `7) Diagnose`; `6) Revert` puts the public listener back |
| `nginx did NOT bind 10.9.0.1:443` after the switch | `ip_nonlocal_bind` could not be set (common in LXC). Bring `wg0` up first and re-run `5`; until then the wallet is still on the public listener |
| Every other site on the server went down after enabling private access | nginx could not bind the WireGuard address at start-up and refused to start at all. `wg-quick up wg0`, then `systemctl start nginx`; the script normally prevents this with a sysctl and a unit drop-in — check `journalctl -u nginx` |
| Tor send fails, listener will not start | `systemctl status tor` on the host — `tor` is a host service the browser cannot start. Slatepack still works |

## Related

- [Wallet hub](05-wallet-services.html) — what a Grin wallet is, the hub menu, the CMD wallet, and Accio's status
- [Script 01](01-build-node.html) — the local node a wallet points at
- [Script 04](04-publish-node-api.html) — how the public nodes in the wizard's list are made
- [Ports and paths](reference-ports-and-paths.html) — every port and directory
- [Script 09](09-connectivity-hub.html#grin-transporter-093) — the Connectivity Hub and the Transporter behind the *Send via Transporter* method
- [Public pool](07-public-pool.html) — Script 07's pool, which shares UDP 51820 with private access; do not run both on one server
- [Back up and restore](089-backup-restore.html) — the toolkit-wide backup (089), which includes every Fidelius wallet directory
