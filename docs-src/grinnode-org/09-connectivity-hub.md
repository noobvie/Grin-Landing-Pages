---
title: Connectivity hub — relay and slate transport
description: How Script 09 deploys a Floonet Nostr relay for Goblin wallets and the Grin Transporter, a store-and-forward queue for slates — setup, checks, backups.
section: Scripts
order: 9
short: Relay & Transporter
label: Script 09
covers: 2026-09-23
updated: 2026-09-23
---

A Grin payment is a short conversation: the sender's wallet writes a **slatepack** (a block of encrypted text), the receiver's wallet signs it and sends one back, and only then can the transaction go on chain. Something has to carry those messages. **Tor** carries them directly when both wallets are online at the same moment; a **Nostr relay** carries them as encrypted direct messages that the receiver's wallet picks up when it next connects; a **store-and-forward queue** holds them in a mailbox on a server until the receiver's software comes to collect. Script 09 — main menu 9, *Grin Connectivity Hub* — deploys the second and third of these on your server. It does not touch the node's own peer-to-peer network ([Script 01](01-build-node.html)) and holds no wallets itself ([Script 05](05-wallet-services.html) does).

> **Warning:** Status — the hub is marked **(DEV)** in the main menu. Its three rows are at very different stages: the **Floonet relay** is finished and runs in public at [relay.grin.money](https://relay.grin.money); the **Grin Transporter** is built but has **never been deployed on a server**; the **CoinSwap mixer** is a reserved row with no code behind it. The relay is safe to deploy today. Treat the Transporter as something to rehearse on testnet, with no real money, until someone has proven a full round trip on a VPS.

## The hub menu

The hub prints two separate signals on every row: a **readiness marker** for the product itself (✅ ready, 🔧 in progress, ⏳ reserved) and, on the right, the **state on this server** (`not installed`, `installed (stopped)`, or `● active` with the networks that are running). *✅ not installed* is normal — a finished product you have not deployed here.

The menu as of today:

```text
 09) GRIN CONNECTIVITY HUB (IN DEVELOPMENT)

  How Grin participants reach each other — transport, relays, messaging.

  1) Floonet Relay           ✅  not installed
     floonet-rs — Nostr relay carrying slatepacks for Goblin-style wallets

  2) CoinSwap Mixer          ⏳  reserved — not built yet
     mwixnet hop — breaks the on-chain link between coins (ledger privacy)

  3) Grin Transporter        🔧  not installed
     Store-and-forward slate relay — offline auto-payouts (HTTP, not SMTP)

  0) Back to main menu
```

| Row | What it opens |
|-----|---------------|
| Floonet Relay | The [Floonet relay](#floonet-relay-091) deployer (`091_grin_floonet_relay.sh`) |
| CoinSwap Mixer | A single notice screen; see below |
| Grin Transporter | The [Grin Transporter](#grin-transporter-093) (`093_grin_transporter.sh`), after a testnet / mainnet choice |

The **CoinSwap Mixer** row is reserved for a future deployer of one hop in a Grin CoinSwap route (the `mwixnet` project, which breaks the link between coins on the permanent chain); it is not built, and selecting it prints what the slot is for, says *Nothing was installed or changed*, and returns.

Keys in this hub are assigned by position, so they can move when a row is added — go by the product name.

---

## Floonet relay (091)

**Nostr** is an open protocol for passing signed messages through servers called **relays**. The **Goblin** wallet (by the developer known as *dog*, github.com/2ro) uses it to move Grin payments: a slatepack travels as an end-to-end encrypted Nostr direct message, the wallets reach relays over Tor, and users can be paid by a human-readable name such as `alice@yourdomain.com`. **Floonet** is that developer's Grin-oriented relay software, `floonet-rs` — a hardened build of the widely used `nostr-rs-relay` with an event-kind allowlist, NIP-42 login, a built-in username registry and optional paid access.

Script 091 **deploys his software unchanged** — it does not fork it. What the toolkit adds is the server work around it: the Rust build, a hardened systemd service, nginx with a Let's Encrypt certificate in front (in place of upstream's Caddy), firewall rules, a browser landing page, event retention and encrypted backups. A server runs **one relay**, shared by mainnet and testnet users alike — the relay only carries encrypted messages and never looks at the chain.

**Who connects:** Goblin wallet users who add your relay to their list (*Settings → Nostr Relays*, paste `wss://relay.yourdomain.com`). The more independent relays exist, the less any single operator can see or block. The relay needs **no Grin node** and no wallet.

### What the relay needs

| You need | Why |
|----------|-----|
| A domain or subdomain (e.g. `relay.yourdomain.com`) with a DNS **A record** pointing at this server | Wallets connect to `wss://<domain>`; Let's Encrypt must reach the server by that name |
| Ports **80** and **443** open in your provider's firewall | Certificate issuance and the public `wss://` endpoint. The script opens them in `ufw` or `firewalld` if either is active |
| About **4 GB free** on `/opt` | The Rust toolchain and the build directory. Below that, setup asks before continuing |
| About **3.5 GB of RAM**, or swap | The compile can run out of memory on a small box. With less RAM and little swap, setup offers a **temporary 2 GB swap file** and removes it after the build |
| Debian/Ubuntu, or Rocky/Alma | Anything else is refused |
| About 15 minutes | Most of it is the automated build |

### The menu

```text
 091) FLOONET RELAY — Grin-native Nostr relay (floonet-rs)

  Status: ● active · wss://relay.yourdomain.com/ · SSL ✓

  Setup
  1) Guided setup (install / update / reconfigure — start here)
  2) Domain & SSL only (re-run nginx/certbot, e.g. after a DNS fix)

  Monitor & control
  3) Status dashboard
  4) Live logs
  5) Start / stop / restart
  6) Test relay (WebSocket handshake + NIP-11)

  Configure
  7) Relay settings (name, description, size/kind limits)
  8) Access control (NIP-42 auth, pubkey whitelists)
  9) NIP-05 usernames (name authority)
  10) GoblinPay (charge GRIN for names / write access)
  11) Edit config.toml directly
  L)  Refresh landing page (rebuild the public homepage)

  Maintenance
  R) Event retention (prune old traffic — upstream never expires anything)
  B) Backup & restore    U) Update floonet-rs    D) Uninstall

  0) Back
```

Everything except `1`, `2`, `L` and `B` needs the relay installed first and says so if it is not.

### Guided setup, step by step

Key `1`. All questions come first; after the summary the rest runs unattended. Every step is safe to re-run — on an existing install, `1` updates and reconfigures it and keeps your `config.toml` and data.

| Step | What happens | What you do |
|------|--------------|-------------|
| 0 | Asks for the relay domain and checks that it resolves to this server's public IP (a mismatch is a warning — you may continue, but SSL will fail until DNS is right). Then the Let's Encrypt email, the relay name (default `Floonet relay @ <domain>`), a short description, and whether to offer `name@<domain>` usernames (default yes). Shows a summary | Answer, then `Proceed? [Y/n]` |
| 1 | Installs build dependencies: git, a C compiler, `protobuf-compiler`, OpenSSL headers, `sqlite3` | Wait |
| 2 | Installs Rust with `rustup` (minimal profile) — only if `cargo` is not already present | Wait |
| 3 | Clones `github.com/2ro/floonet-rs` into `/opt/grin/floonet/src`, or refreshes an existing checkout | Wait |
| 4 | Uses an upstream prebuilt release if one exists (none has been published so far); otherwise compiles with `cargo build --release`, 5–15 minutes on a small VPS. The temporary swap offer appears here | `Y` to the swap offer on a small box |
| 5 | Runs upstream's own installer when present (binary to `/usr/local/bin/floonet-rs`, hardened service unit); falls back to a toolkit unit running as a dedicated `floonet` user. Seeds `/etc/floonet-rs/config.toml` from upstream's example, forces the relay to listen on **127.0.0.1 only**, and moves it off port 8080 to **8181** (or the next free port) | Wait |
| 6 | Writes the relay's public URL, name and description into `config.toml`; turns on the username registry if you said yes | Wait |
| 7 | nginx: rate limits (60 requests/minute per IP, 20 connections), the browser landing page, an HTTP-only site, the certificate, then the full `wss://` site; opens 80/443 in the firewall | Wait |
| 8 | Enables and starts `floonet-rs`, then checks for a WebSocket answer on the local port | Wait |
| — | Prints the relay URL — *✓ verified end-to-end* when the public handshake worked — and offers a **daily encrypted backup** (default yes) | `Y`, and set the backup key if asked |

If a step fails, setup stops, names the step and prints the session log path (`/opt/grin/logs/floonet_session_<date>.log`). Fix the cause and choose `1` again.

> **Warning:** If the certificate cannot be issued (DNS not pointing here yet, port 80 closed, or a Cloudflare proxied record), the relay still starts — **over unencrypted `ws://`**, and setup ends with `ws://<domain> — NO SSL yet`. Do not hand that address to anyone: without TLS, logins and message metadata cross the network in the clear. Fix DNS, set any Cloudflare record to *DNS only* (grey cloud), then run `2`.

### Checking the relay

Run **`6` Test relay**. It checks, in order, a WebSocket handshake on the local port, the same over public `wss://`, and the relay's **NIP-11 information document**. The first two only prove that *something* answers the upgrade request; the NIP-11 document is the real proof that floonet-rs itself is behind your domain. From any machine:

```bash
curl -s -H 'Accept: application/nostr+json' https://relay.yourdomain.com/
```

Good output is a JSON document naming your relay:

```json
{
  "id": "wss://relay.yourdomain.com/",
  "name": "Floonet relay @ relay.yourdomain.com",
  "supported_nips": [1, 2, 9, 11, 12, 15, 16, 20, 22, 33, 40],
  "software": "https://floonet.dev/floonet-rs",
  ...
}
```

An HTML page or a 404 instead means nginx is answering but the relay is not — see [Troubleshooting](#troubleshooting). Opening `https://relay.yourdomain.com/` in a browser shows the landing page: what the relay is, its live status, and a step-by-step for adding it to Goblin (plus claiming a username, when usernames are on).

> **Note:** The NIP list is floonet-rs's own set. Some public Floonet relays (relay.floonet.dev among them) run a different server, `strfry`, and advertise a longer list; that is a different program, not a setting you missed. Slatepack delivery works either way.

The **status dashboard** (`3`) shows the service state, the binary version, the listener, certificate days left, database size and event count, errors in the journal over the last hour, and live local and public handshakes.

#### Relay files

| Path | Purpose |
|------|---------|
| `/usr/local/bin/floonet-rs` | The relay binary |
| `/etc/floonet-rs/config.toml` | Relay configuration — every menu under *Configure* edits this file |
| `/etc/floonet-rs/env` | Secret overrides (the GoblinPay token), mode 600; created only if you set one |
| `/var/lib/floonet-rs/` | The relay's SQLite database: stored events and the username registry |
| `floonet-rs.service` | The systemd service |
| `/opt/grin/floonet/src/` | Source checkout and build directory |
| `/opt/grin/conf/grin_floonet.conf` | Toolkit settings: domain, email, backup and retention choices, the installed source revision |
| `/etc/nginx/sites-available/floonet-relay` | The `wss://` site; rate-limit zones in `/etc/nginx/conf.d/script09-floonet.conf` and `script09-floonet-conn.conf` |
| `/var/www/floonet-relay/` | The browser landing page |
| `/etc/cron.d/grin-floonet-backup`, `/etc/cron.d/grin-floonet-prune` | Daily backup and daily retention, when enabled |

### Settings worth knowing

**Usernames (`9`).** With the name authority on, anyone can register `name@<your domain>` through their wallet; the relay answers the lookups at `/.well-known/nostr.json`. Registration is self-service and signed with the user's own key. Usernames live **only in this relay's database** — see [backups](#backups-and-moving-the-relay).

**Access control (`8`).** A fresh relay is open: anyone may read and write. *Require auth to write* is the cheapest brake against strangers parking data on your disk — writers must then prove they hold a key, which every wallet can. NIP-42 login for reading, login for direct messages only, and hex-pubkey allowlists are here too, for a private or invite-only relay.

**GoblinPay (`10`).** Optional: charge GRIN for usernames (`pay_mode = name`) or for write access (`write`) through a separate GoblinPay payment server you run or use. Set the **server URL first** — the menu refuses a paid mode without one, because floonet-rs will not start in that state. The API token is stored in `/etc/floonet-rs/env`, never in `config.toml`.

**Relay settings (`7`).** Name, description, maximum event size, and the event-kind allowlist. The allowlist is what keeps a relay lean; leave it alone unless you know which Nostr kinds you need.

**Event retention (`R`).** floonet-rs keeps every event forever, so an open relay's database only grows. This screen ages out traffic you choose — by default kind **1059**, the *gift wraps* that carry slatepacks — once it is older than a number of days (**minimum 7**, because Goblin looks back 3 days and a send expires after 24 hours). Age is measured from when your relay *received* the event, not from the event's own timestamp, which the sender controls. Identity events (profiles, contact and relay lists) are refused outright: there is no other copy of them. Use *Preview* first; *Run prune now* shows the preview and asks again; *Enable daily schedule* runs it at 04:10. Pruning stops the file growing but does not shrink it — *Reclaim disk space* runs SQLite's `VACUUM`, which briefly blocks the relay and needs free disk equal to the database size.

After any change, the menus offer to restart the relay (`Apply now (restart the relay)? [Y/n]`); the change takes effect only after a restart.

### Backups and moving the relay

Moving the relay to a new server **under the same domain** keeps wallets connected with no action on their side — they only know the address. What does not survive a fresh install is the **username registry** and stored events, which exist only in `/var/lib/floonet-rs/`. So back up:

- **`B` Backup & restore** — encrypted archives of `/etc/floonet-rs/` (config and token), a consistent snapshot of the database, and the toolkit settings file. *Backup now*, *Restore*, a daily schedule (03:25, keeping 7 by default), retention and an off-box copy over `scp`. Archives go to `/opt/grin/backups/` as `grin_floonet_backup_<date>.tar.gz.enc`, encrypted with the toolkit's shared personal key.
- The toolkit-wide [backup script](089-backup-restore.html) also asks to include the relay (step 5c).

To move: restore the archive on the new server, point the DNS record at it, then run guided setup (`1`) — it rebuilds the binary and service and keeps the restored config and data. If the **domain** changes, every username changes with it; restoring the database cannot save `alice@old-domain`.

### Updating and removing

- **`U` Update** fetches upstream's latest source, rebuilds and restarts — but only if the source revision differs from the one installed.
- **`D` Uninstall** asks you to type `REMOVE`, then deletes the service, binary, nginx site, rate-limit zones, landing page, and backup/prune crons. It then asks separately about the data and config (default **yes**), the certificate (default **no** — keeping it avoids Let's Encrypt's duplicate-certificate limit on a reinstall) and the build directory (default yes). Archives in `/opt/grin/backups/` are never touched.

> **Note:** Three known limits, from the toolkit's [security audit](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script09_security_audit.md): the build follows upstream's latest code rather than a pinned, reviewed revision; the prebuilt-release path (unused today — upstream publishes no releases) has no checksum check; and a failed certificate leaves the relay on `ws://` with only a warning, as described above.

---

## Grin Transporter (093)

> **Warning:** Status — the Transporter's first phase is built and was security-reviewed in August 2026, but it has **never been deployed on a server**. It runs **standalone**: Grin Drop and the public pool do not use it, and the wallet software most people run cannot talk to it (see [which wallets can use it](#which-wallets-can-use-it)). Everything below is read from the code, not from a live run. Try it only on **testnet**, both sides on your own servers, and prove a full round trip before you point anything real at it.

The Transporter is a **mailbox for slates**. The sender's software drops an encrypted slatepack into a queue on your server, addressed to the receiver's slatepack address; the receiver's software comes by later, proves it owns that address, collects the slate, signs it, and drops the reply into the *sender's* queue; the sender picks the reply up on its next visit and finalizes the transaction. Neither side has to be online at the same moment — which is what Tor needs — and nobody has to copy and paste text. It is ordinary HTTPS (Node.js, Express and SQLite behind nginx), not email.

What the server can and cannot see:

- It **never holds a wallet or keys** and never sees an amount. A deposit is a slatepack the sender's wallet already encrypted to the receiver.
- **Anyone may deposit** — like anyone may drop a sealed envelope through your letterbox. Abuse is bounded by caps (below), not by accounts.
- **Only the owner may read or delete** a queue: the receiver signs a one-time challenge with the key behind its slatepack address and gets a 15-minute access token. No accounts, no passwords.
- An uncollected slate **expires after 14 days** (336 hours).

> **Note:** The Transporter was number 092 until 2026-08-04; older notes may use that number.

### Which wallets can use it

| Wallet | Can it use a Transporter? |
|--------|---------------------------|
| [Fidelius](051-fidelius.html), the toolkit's personal web wallet | Yes — it has a built-in *Send via Transporter* method and polls for incoming slates while a wallet is unlocked. Also not yet run on a server |
| `grin-wallet` plus the **poll agent** from this menu | Yes — the agent (`agent.js`) drives the wallet from outside: it sends, polls, receives and finalizes on a schedule |
| `grin-wallet` on its own, Grim, Goblin, others | No — they speak Tor, slatepack text, or Nostr, not this queue |

Both sides of a payment must use a Transporter on the **same network** (testnet queues and mainnet queues are separate instances), though not necessarily the same server — the agent deposits the reply to whichever Transporter URL it is configured with.

### What the Transporter needs

| You need | Why |
|----------|-----|
| **Node.js 24 or newer** | The server uses Node's built-in SQLite. Install offers to remove an older Node and install 24 from NodeSource — other Node apps on the box (Tiny Explorer, for one) then run on 24 after their next restart |
| For the **agent**: a `grin-wallet` running the **combined listener** on this box | The agent needs the wallet's Owner API (to send) and Foreign API (to receive) on one port: `grin-wallet owner_api` with `owner_api_include_foreign = true`, on **3420** (mainnet) or **13420** (testnet), a `.owner_api_secret` in the wallet folder, and a **passphrase file** the agent can read. The [CMD Wallet quick setup](05-wallet-services.html#the-cmd-wallet-quick-setup) with listener mode **`owner_api`** gives you this; a Grin Drop, solo-mining or public-pool wallet also qualifies |
| For agents on **other** servers: a domain with a DNS A record, ports 80/443 open | They reach your queue at `https://<domain>`. An agent on the same box can use `http://127.0.0.1:7466` (testnet) or `7456` (mainnet) and needs no domain |
| Optional: Tor | For a `.onion` front — see [the onion front](#the-onion-front) |

> **Warning:** The agent reads the wallet passphrase from a **file on disk** so that it can unlock the wallet unattended. Anyone who can read that file and the wallet folder can spend the wallet. Keep that wallet small, and back up its seed through the wallet's own product — the Transporter backup does not contain it.

### The menus

The first screen picks the network. Testnet is listed first and labelled *prove the round trip here first*; mainnet carries a warning to deploy only after a verified testnet round trip. Each network is a separate instance with its own port, service, database and agent.

```text
 093) GRIN TRANSPORTER — [TESTNET]

  Store-and-forward slate queue — automated + offline-tolerant sends.
  Server: 127.0.0.1:7466   Service: grin-transporter-test

  Server
  1) Install server        (Node.js + app + systemd)
  2) Configure server      (TTL / size / queue caps)
  3) Domain & SSL          (nginx + Let's Encrypt)
  4) Tor hidden service    (optional .onion front)
  5) Start / Stop
  6) Status

  Agent (wallet side)
  7) Install poll agent    (wire a local wallet)
  8) Agent actions         (address / send / poll / cron)

  B) Backup & restore    (config + queue snapshot, encrypted)
  L) Logs
  D) Delete instance
  0) Back
```

### Setting it up, step by step

The server half (`1`–`6`) makes this box a Transporter that others can deposit into. The agent half (`7`–`8`) wires a wallet on this box to *some* Transporter — this one or someone else's. You can do either half alone.

| Key | What happens | What you do |
|-----|--------------|-------------|
| `1` Install server | Checks for Node.js 24, copies the app to `app/` under `/opt/grin/transporter-{main,test}`, runs `npm install`, writes a default `config.json` (an existing one is kept; new settings are added), writes the `grin-transporter-{main,test}` service running as the `grin` user | `Y` to autostart on boot and to start now |
| `2` Configure server | Asks for each limit in turn, showing the current value — see [the limits](#the-limits) | Enter keeps a value; restart when asked |
| `3` Domain & SSL | Asks for the domain and whether search engines may index the **landing page** (default yes; queue addresses are never indexed). Writes an HTTP-only site, gets the certificate, then the full HTTPS site with a 60 requests/minute limit per IP | Answer; give an email for Let's Encrypt |
| `4` Tor hidden service | Optional. Installs `tor` if missing, adds a hidden service to `/etc/tor/torrc` pointing at the onion port (7566 testnet / 7556 mainnet), restarts the Transporter and Tor, prints the `.onion` address | Read [the onion front](#the-onion-front) first |
| `5` Start / Stop | Start a stopped service, or restart / stop a running one | — |
| `6` Status | Service, port, `/health` answer, domain, onion, database size, the current limits, ownership proofs in the last 24 h (ok / failed), and whether an agent and its cron are installed | — |
| `7` Install poll agent | Asks for the Transporter URL (default this box's local port), then lists wallets on this box that run the combined listener on the right port, or lets you enter paths by hand. Writes `agent.json` in `/opt/grin/transporter-agent-<network>/` and offers a test (`status`) | Pick your wallet; supply the passphrase file if it was not found |
| `8` Agent actions | `1` show this wallet's slatepack address · `2` status · `3` send GRIN via the Transporter · `4` poll now · `5` cancel an unanswered send · `6` turn the poll **cron** on or off (every 10 minutes by default, 1–59 allowed) | Turn on the cron once a manual poll works |

> **Warning:** A send **locks the coins it spends at send time**, because the reply may take days. If the other side never answers, the coins stay locked until you release them: `8` → `5`, with the `tx_slate_id` the send printed. A wrong-but-valid address does not fail — the deposit succeeds into a queue nobody reads — so send a small test amount to any new address first.

What one poll does, as the agent's log shows it: for each slate waiting in your queue, an incoming payment (`S1`) is received by your wallet and the signed reply is deposited in the sender's queue (`S1 received … — reply queued`); a reply to your own send (`S2`) is finalized and broadcast (`S2 finalized + broadcast`). Slates it cannot use are left for a retry and removed after five deliveries — but only when the wallet itself answered, so a wallet that is down never causes a payment to be thrown away. The summary line ends `processed=… skipped=… failed=… removed=…`.

### The limits

All in `/opt/grin/transporter-{main,test}/config.json`, all editable with `2`. Deposits are open, so these are what keep them honest.

| Setting | Default | What it bounds |
|---------|---------|----------------|
| `ttl_hours` | 336 (14 days) | How long an uncollected slate is kept |
| `max_slate_bytes` | 16384 | Size of one deposit |
| `max_queue_per_addr` | 100 | Slates waiting for one recipient |
| `max_queue_total` | 10000 | Slates stored in total |
| `max_per_depositor_per_addr` | 5 | How many of **one** recipient's slots a single depositor may hold. This is the setting that stops a stranger burying a known address in junk — keep it low |
| `max_deposits_per_ip_hour` | 60 | Deposits per source per hour |
| `auth_fail_limit`, `auth_lock_minutes` | 5, 15 | Failed ownership proofs before a 15-minute lockout, per address and source |

### The onion front

`4` gives the Transporter a `.onion` address on its **own** local port, separate from the one nginx uses. That split is a security control: both arrive from `127.0.0.1`, and a Tor visitor can forge the headers nginx would otherwise vouch for, so the app tells them apart by port and ignores forwarding headers on the onion side. The trade-off is that all onion visitors count as **one** depositor, so together they can hold only `max_per_depositor_per_addr` slates for any one recipient; raise it if you expect real onion traffic.

> **Note:** The screen suggests agents can use `http://<onion>` through a Tor SOCKS proxy, and `7` accepts an `.onion` URL. The agent, however, has **no Tor or SOCKS support of its own** (Fidelius refuses onion URLs for the same reason), and the cron line runs it without any Tor wrapper. Whether it can be made to work — for instance with `torsocks` — has not been tested. Use `https://` for agents.

### Checking the Transporter

On the server, the health endpoint should answer (testnet shown; mainnet is 7456):

```bash
curl -s http://127.0.0.1:7466/health
```

```json
{"ok":true,"service":"grin-transporter","version":"0.3.0","network":"testnet","queued":0,"uptime_s":42}
```

From outside, the same at `https://<domain>/health`, and `https://<domain>/` shows the public landing page: what the depot is, this station's URL and limits, and which wallets can use it. On the agent side, `8` → `2` prints the Transporter's health and how many slates wait in your own queue.

#### Transporter files

| Path | Purpose |
|------|---------|
| `/opt/grin/transporter-{main,test}/app/` | The server app and its landing page |
| `…/config.json` | Limits and ports |
| `…/transporter.db` | The queue (encrypted slates, challenges, auth events) |
| `grin-transporter-{main,test}.service` | The systemd service |
| `/opt/grin/transporter-agent-<network>/` | `agent.js` and `agent.json` (paths to the wallet's secret and passphrase files; mode 600) |
| `/opt/grin/conf/grin_transporter.conf` | Toolkit settings shared by both networks: domains, onions, certbot email, backup retention |
| `/etc/nginx/sites-available/grin-transporter-<network>` | The HTTPS site; rate-limit zone in `/etc/nginx/conf.d/script09-transporter-<network>.conf` |
| `/var/lib/tor/grin-transporter-<network>/` | The onion identity, if `4` was used |
| `/etc/cron.d/grin-transporter-agent-<network>` | The poll schedule; log `/opt/grin/logs/transporter_agent_<network>.log`, rotated weekly |

### Backups and removal

**`B` Backup & restore** makes **one** encrypted archive covering **both** networks: the toolkit settings, each network's `config.json` and a snapshot of its queue, each `agent.json`, and the onion's **secret key** — back up the key, not the address, because only the key reproduces the address that every configured agent points at. The wallet's seed is not in it. Daily schedule at 04:25, keeping 7; archives are `/opt/grin/backups/grin_transporter_backup_<date>.tar.gz.enc` under the toolkit's shared personal key. The [toolkit-wide backup](089-backup-restore.html) does not include the queue.

**`D` Delete instance** asks you to type `DELETE`, then removes that network's service, app, nginx site, agent and cron, and its block in `/etc/tor/torrc`. The onion keys in `/var/lib/tor/` are kept (delete them only if you never want that address back), the daily backup schedule is kept while the other network's instance still exists, and the queue database goes only if you confirm separately.

---

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Check the relay is really working | Relay menu → `6`, or the `curl` NIP-11 check in [Checking the relay](#checking-the-relay) |
| Watch relay traffic or errors | Relay menu → `4` (Ctrl+C returns to the menu), or `journalctl -u floonet-rs -f` |
| Rename the relay or change its description | Relay menu → `7`, then restart when asked; `L` refreshes the landing page |
| Stop strangers filling the relay's disk | Relay menu → `8` → *require auth to write*, and `R` → retention |
| Move the relay to another domain | Relay menu → `2` with the new domain (it also rewrites the relay URL and offers a restart). Usernames under the old domain do not carry over |
| Update floonet-rs | Relay menu → `U` |
| See whether anything is waiting in my Transporter queue | Transporter → network → `8` → `2` |
| Send GRIN through the Transporter | `8` → `3`: recipient slatepack address (`tgrin1…` on testnet), amount |
| Release coins from a send that was never answered | `8` → `5` with the `tx_slate_id` |
| Tighten or loosen Transporter limits | `2`, then restart when asked |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| Goblin shows the relay as added but nothing arrives; the public address returns nginx's *Not found* page | The relay process is not running — often crash-looping — while nginx still answers. `journalctl -u floonet-rs -n 30` shows why. A handshake *OK* on the status screen can be stale; the NIP-11 `curl` is the real check |
| Journal: *goblinpay.url must be set when goblinpay.pay_mode is enabled* | A paid GoblinPay mode was set without a server URL. Set `pay_mode = "off"` in `/etc/floonet-rs/config.toml` and restart, or set the URL in `10` first. Re-running guided setup also resets it |
| Journal: *error binding to 127.0.0.1:8080: Address already in use* | An old config still uses port 8080, which something else holds (the public pool's API, another web app). Find the owner with `ss -tlnp` (look for `:8080`); guided setup moves the relay off 8080 automatically |
| *certbot could not issue a certificate*; relay only on `ws://` | DNS does not point here yet, port 80 is closed, or a Cloudflare record is proxied (orange cloud). Fix it, then relay menu → `2` |
| `cargo build failed` | Usually out of memory or disk. Accept the temporary swap offer, free space on `/opt`, and scroll up to the first error line. Re-run `1` |
| Service fails with `status=238/STATE_DIRECTORY` | A leftover from an earlier upstream-style install. Guided setup `1` repairs the state directory and starts the relay again |
| `name@domain` lookups return nothing | The username registry is off (`9` → enable), or the relay was reinstalled without restoring its database |
| Agent: *Wallet owner API not reachable at … — is the owner_api session running?* | The wallet is not running the combined `owner_api` listener on 3420 / 13420. A wallet in plain `listen` mode cannot be used |
| Agent: *Cannot read wallet pass file …* | The passphrase file in `agent.json` is missing or unreadable by the `grin` user. Re-run `7` and give the right path |
| Agent log: *S1 has no sender address — cannot route reply, skipping* | The payment was sent without a sender address (a plain slatepack send), so there is nowhere to deliver the reply. The sender must use the Transporter send path, which embeds it |
| Agent log: *CRITICAL: received … GRIN but reply deposit failed* | Your wallet signed the payment but the reply could not be queued. The log prints the reply slatepack — deliver it to the sender by hand, or the sender's coins stay locked |
| Deposit refused: *You already have the maximum pending slates for this recipient*, *Recipient queue is full* or *Store is at capacity* | A limit was hit — the fair-share cap, the per-recipient cap or the global cap. The receiver's next poll drains the queue; an operator can raise the limits with `2` |
| *Too many failed attempts — locked out, retry later* | Five failed ownership proofs for that address from that source. Wait 15 minutes; if it recurs, the agent is using the wrong wallet for that address |

## Related

- [Wallet & payment services](05-wallet-services.html) — the CMD Wallet quick setup, whose `owner_api` listener mode is what the Transporter agent needs
- [Fidelius](051-fidelius.html) — the web wallet with a built-in *Send via Transporter* method
- [Back up and restore](089-backup-restore.html) — the toolkit-wide archive, which includes the relay but not the Transporter queue
- [Admin & maintenance](08-admin-maintenance.html) — the full cleanup also removes the relay and Transporter services
- [Ports and paths](reference-ports-and-paths.html) — 8181, 7456/7466 and 7556/7566 alongside every other port
- Upstream: [floonet-rs](https://github.com/2ro/floonet-rs), [docs.floonet.dev](https://docs.floonet.dev), [Goblin](https://docs.goblin.st)
