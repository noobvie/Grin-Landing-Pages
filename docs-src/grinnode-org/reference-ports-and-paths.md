---
title: Ports and paths
description: Every port the Grin Node Toolkit uses, which ones must be open in the provider firewall, and where each script keeps its files, configs and logs on the server.
section: Reference
order: 1
covers: 2026-10-24
updated: 2026-10-24
---

One page to look things up: the port each service listens on, which of them need a hole in the firewall, and the directories the toolkit creates. Every value here was checked against the scripts' own constants; where a script lets you change a port, the table gives the default.

## Which ports must be open at the provider

Almost everything the toolkit runs binds to **localhost only** (`127.0.0.1`) and is reached through nginx on 443, so it never needs a firewall rule. The exceptions — the only inbound ports you open in the provider's firewall or security group — are:

- **80 and 443** — nginx. 443 is HTTPS for every public site (chain snapshots, node API, explorer, dashboard, wallets); 80 is needed for Let's Encrypt to issue and renew certificates, and redirects to HTTPS.
- **3414** (mainnet) and **13414** (testnet) — the node's **P2P** port, so other nodes can connect to yours. A node with this port closed still syncs, but only makes outbound connections and contributes less to the network.
- **A published stratum port**, only if you run mining: **3333** / **13333** for the public pool, or the node's own **3416** / **13416** if you open solo mining to the internet.
- **51820/udp** (and **51821/udp**), only if you run WireGuard — the pool's regional gateways, or Fidelius' private access.

Everything else on this page that is not marked *(public)* stays closed. If a port here is already taken by something else on your server, the service's own config usually lets you move it — the toolkit picked unusual numbers (7420, 7456, 8181, 8471…) to avoid the common clashes.

## Grin node and wallet

Per network. The node and the wallet are separate programs with separate ports; the wallet's two APIs are on ports of their own.

| Port | Mainnet / Testnet | Protocol | Purpose |
|------|-------------------|----------|---------|
| 3413 / 13413 | node | HTTP | Node API v2 — `/v2/foreign` (public chain data) and `/v2/owner` (management) on one port, localhost. [Script 04](04-publish-node-api.html) publishes `/v2/foreign` through nginx |
| 3414 / 13414 | node | TCP (P2P) | Peer connections — **public** |
| 3416 / 13416 | node | TCP | The node's built-in stratum server for mining: solo miners connect here; the public pool uses it as its upstream. Localhost unless solo mining is published |
| 3415 / 13415 | wallet | HTTP | Wallet Foreign API — receives transactions and `build_coinbase` calls from the node, localhost |
| 3420 / 13420 | wallet | HTTP | Wallet Owner API — the wallet's management API used by the toolkit's services (Drop, WooCommerce, the pool, the Transporter), localhost |

## Node API extras (Script 04)

| Port | Protocol | Purpose |
|------|----------|---------|
| 8413 / 18413 | HTTP | nginx's localhost listener behind the Tor onion of the mainnet / testnet node API — Tor maps the `.onion`'s port 80 here |

## Web and wallet services

All localhost, all fronted by nginx on 443.

| Port | Protocol | Purpose |
|------|----------|---------|
| 3004 / 3005 | HTTP | Grin Drop (059) — testnet / mainnet |
| 3006 / 3007 | HTTP | WooCommerce bridge (053) — mainnet / testnet |
| 3010 / 3011 | HTTP | GrinScan explorer (06b) — testnet / mainnet |
| 5060 | HTTP | Global Grin Health (06) — the "submit your node" form server behind the dashboard |
| 7420 | HTTP | Fidelius web wallet (051) |
| 7480 / 7490 | HTTP | Accio gateway (052) — mainnet / testnet. *Written, never deployed* |
| 7580 / 7590 | HTTP | Accio gateway, onion side — mainnet / testnet. *Written, never deployed* |
| 7581 / 7591 | HTTP | Accio nginx onion front — mainnet / testnet. *Written, never deployed* |
| 8000 | HTTP | Grin Explorer by Grincoin.org (06, menu `C`), in the tmux session `grin-explorer` |
| 8471 | HTTP | Tiny Explorer (06d), mainnet only |

## Connectivity hub (Script 09)

| Port | Protocol | Purpose |
|------|----------|---------|
| 8181 | HTTP / `wss` | Floonet Nostr relay (091), localhost, nginx front-end; configurable — 8181 was chosen to dodge the common 8080 clash |
| 7456 / 7466 | HTTP | Grin Transporter (093) — mainnet / testnet, localhost. *Built standalone, never VPS-deployed* |
| 7556 / 7566 | HTTP | Grin Transporter's onion front — mainnet / testnet. *Same status* |

## Public mining pool (Script 07)

| Port | Protocol | Purpose |
|------|----------|---------|
| 3333 / 13333 | TCP | Public pool stratum — miners connect here, mainnet / testnet install — **public** |
| 3416 / 13416 | TCP | The node's built-in stratum the pool feeds from, localhost |
| 8080 / 8090 | HTTP | Pool central API — mainnet / testnet, localhost, nginx-proxied |
| 3391+ / 13391+ | TCP | One internal port per regional gateway, on the pool's WireGuard address, reached only over the tunnel |
| 51820 / 51821 | UDP | WireGuard between the central hub and its regional gateways — mainnet `wg-grinpool` (10.66.66.0/24) / testnet `wg-grinpool-tn` (10.66.67.0/24) — **public** on the hub |
| 8081 / 8091 | HTTP | *Play & chat* games service (`/play/`) — mainnet / testnet, localhost, nginx-proxied. Only when installed |
| 443 (+ 80) | HTTPS | Latency probe on a **regional gateway** box (`grin-gateway-probe`): miners' browsers time `https://<gateway>/ping`; 80 is for its certificate. Works for gateway names under the pool's own domain, or under the parent set in the pool config key `latency_probe_domain` |

Solo mining (the other half of Script 07) needs no pool ports: miners connect straight to the node's 3416 / 13416. The toolkit tests the public pool on mainnet only; the testnet ports are there for a testnet install.

> **Warning:** **51820/udp is used twice.** The pool hub's WireGuard (mainnet) and Fidelius' WireGuard private access both default to it, on different interfaces (`wg-grinpool` vs `wg0`). Two interfaces cannot share one UDP port, so run one of the two per server or change one side's port.

## nginx

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | HTTP | Let's Encrypt validation; redirects to HTTPS — **public** |
| 443 | HTTPS | Every public site and API the toolkit serves — **public** |

## Grin node directories

One directory per node, named after the network and mode. A server has at most one node per network, so at most two of these exist at once (mainnet pruned *or* full, plus testnet).

| Network | Mode | Directory | tmux session |
|---------|------|-----------|--------------|
| Mainnet | Pruned | `/opt/grin/node/mainnet-prune/` | `grin_pruned_mainnet` |
| Mainnet | Full archive | `/opt/grin/node/mainnet-full/` | `grin_full_mainnet` |
| Testnet | Pruned | `/opt/grin/node/testnet-prune/` | `grin_pruned_testnet` |

Full archive mode on testnet is not offered — its chain is too large for a practical archive. Inside each directory: the `grin` binary, `grin-server.toml`, `chain_data/`, `grin-server.log`, and the two secret files `.api_secret` and `.foreign_api_secret`. After a binary update or a source install you also find `grin.prev` (the binary it replaced, for a rollback) and `.grin_binary_info`; `.grin_last_start` and `.grin_last_exit` are stamps the node's tmux pane writes when the node starts and stops. The sessions live on the `grin` user's tmux server — list them with `gtmux ls`, not `tmux ls`.

## Where things live under `/opt/grin`

Everything the toolkit installs goes under `/opt/grin/`, one folder per product. The clone of the toolkit itself is wherever you ran `git clone`, and can be deleted or moved without affecting anything below.

```text
/opt/grin/
├── node/                     the nodes (table above)
├── keys/<network>/           node API secrets, kept across rebuilds        Script 01
├── bin/                      source-built and replaced node binaries, .info  Script 01
├── src/grin/                 grin git checkout for source builds              Script 01
├── node-events/<network>/    event recorder ledger, status, evidence/         086
├── conf/                     small config files the scripts share (table below)
├── logs/                     one log per script run, plus cron/watchdog logs
├── lib/                      helper libraries installed for cron and timers
├── backups/                  local backup archives, onion identities          089, 04, 059, 07
├── temp/                     backup archives from before the shared engine (legacy)
├── reports/                  host-optimisation reports; diag/ = Diagnostics  083, 086
├── grin-api-collector/       REST collectors for the published node API      04
├── grin-stats/               dashboard collector: stats.db, config.env       06
├── grin-price/               price collector: grin-price.db                  06
├── grinscan/{main,test}/     GrinScan config, DB and copied node secrets     06b
├── tiny-explorer/            Tiny Explorer app, config.json, log             06d
├── cmdwallet/<network>/      the CMD wallet quick setup                       05
├── cmdwallet/.retired/       set-aside mainnet CMD wallets — NOT backed up    05
├── wallet-bin/<tag>/         grin-wallet binaries, one per version            05 (shared)
├── fidelius/                 Fidelius app, config.conf, wallet_<net>_<name>/  051
├── webwallet/xp-mainnet/     XP-themed wallet config                          051x
├── accio-{main,test}/        Accio gateway + gateway-state/ (never deployed)  052
├── woocommerce/<network>/    WooCommerce bridge, bridge.conf, bridge.log      053
├── drop-{main,test}/         Grin Drop app + wallet, grin_drop_<net>.conf     059
├── drop-{main,test}-data/    Grin Drop database — survives a wallet reinstall 059
├── solowallet/<network>/     solo-mining wallet                               07 solo
├── solo-stats/               solo-mining collector state and SQLite DB        07 solo
├── pubpool/<network>/        public pool app                                  07 pool
├── pubpoolwallet/<network>/  public pool wallet                               07 pool
├── pubgames/<network>/       Play & chat games service                        07 pool
├── pubgames-data/<network>/  games database                                   07 pool
├── floonet/src/              Floonet relay source checkout (binary → /usr/local/bin)  091
├── transporter-{main,test}/  Grin Transporter app + DB (never deployed)       093
└── access-watch.sh           Provider Access Watch probe script               082
```

Web roots are separate, under `/var/www/`: `fullmain`, `prunemain`, `prunetest` (chain snapshots, Script 02/03), `grin-node-api` and `grin-node-api-testnet` (Script 04), `grin-stats` (06), `web-wallet-xp` (051x), `grin-drop-home` (059), `grin-pool` and `grin-pool-testnet` (07), `grin-play` and `grin-play-testnet` (07 games), `floonet-relay` (091).

A few notes on the tree: `bin/` holds node binaries compiled by Script 01 → `G` and an archived copy of every binary a key-`3` update or a source install replaced, each with an `.info` file saying where it came from; `src/grin/` is the checkout kept for the next compile (`G` → `5` purges its build cache). `wallet-bin/` installs **v5.5.0** by default; Fidelius alone pins **v5.4.1**. `cmdwallet/.retired/` holds mainnet CMD wallets that a re-initialize or *Nuke* moved aside, with their old seed — copy them off the server or delete them. The games database is `pubgames-data/<network>/grinium-games.db`.

Tor identities are under `/var/lib/tor/`: `grin-<network>-raw-tcp/` (Script 01's private node mirror), `grin-<network>-nginx/` (Script 04's public API onion), and per-product directories for Accio and the Transporter. The `hostname` file in each holds the `.onion` address; the `hs_ed25519_secret_key` beside it *is* the identity.

## Runtime config created on first run

Small files under `/opt/grin/conf/` that scripts write the first time they run and read afterwards. They are the toolkit's memory of what you chose; a backup of `/opt/grin/conf/` plus the wallet seeds is most of what a rebuild needs.

| File | Purpose | Written by |
|------|---------|-----------|
| `grin_instances_location.conf` | Where each node is installed — read by nearly every other script | 01 (refreshed by 03) |
| `grin_node_watchdog.json` | Sync-watchdog settings (testnet is off by default) | 01 / 07 |
| `grin_share_nginx.conf` | Chain-snapshot sharing over nginx: networks, web folders, timeout | 03 |
| `grin_share_ssh.conf` | Chain-snapshot sharing over SSH | 03 |
| `grin_share_targets.conf` | Remote mirror list for the copy job, one per line | 03 |
| `grin_wallets_location.conf` | Registry of wallet directories, used by backups | 05 / 051x |
| `grin_solo_payment.json` | Solo-mining payout settings | 07 solo |
| `grin_solo_backup.conf`, `grin_solo_quiet.conf` | Solo-mining backup schedule; quiet-hours for its alerts | 07 solo |
| `grin_pubpool.json`, `grin_pubpool_testnet.json` | Public pool settings per network | 07 pool |
| `grin_pubpool_backup.conf` (+ `_testnet`) | Pool backup schedule | 07 pool |
| `grin_gateway.json`, `wg/`, `wg-testnet/` | Regional-gateway settings and WireGuard material | 07 pool |
| `host_monitor_port.conf` | Custom hosts for the remote node monitor | 081 |
| `host_monitor_last_state.conf` | Last-known port state, for change alerts | 081 |
| `mass_deploy.conf` | Fleet server list for mass deployment | 081 |
| `access-watch/` | Provider Access Watch baseline and alert channel | 082 |
| `ssh_hardening_policy.conf`, `ssh_backups/` | The SSH guided setup's saved policy; backups of the sshd config taken before each change | 085 |
| `node-events/recorder.conf` | Node event recorder settings and alert channels | 086 |
| `grin_backup.conf`, `grin_backup_remote.conf` | The one backup key file and the off-box push target | 089 |
| `grin_drop_backup.conf`, `drop_shared.conf` | Grin Drop backup schedule; settings shared by both networks | 059 |
| `grin_floonet.conf` | Floonet relay settings | 091 |
| `grin_transporter.conf` | Grin Transporter settings | 093 |
| `github_repo.conf` | Repository override for self-update (optional) | 08 |

Product-specific configs that live *with* the product rather than here:

| File | Product |
|------|---------|
| `/opt/grin/fidelius/config.conf` + `wallets_info.json` | Fidelius (051) |
| `/opt/grin/drop-<net>/grin_drop_<net>.conf` | Grin Drop (059) |
| `/opt/grin/grin-stats/config.env` | Global Grin Health (06) |
| `/opt/grin/tiny-explorer/config.json` | Tiny Explorer (06d) |
| `/opt/grin/woocommerce/<net>/bridge.conf` | WooCommerce bridge (053) |

## System-wide files the toolkit adds

For completeness — the places outside `/opt/grin` and `/var/www` a script may have touched, so you know where to look.

| Where | What |
|-------|------|
| `/etc/nginx/sites-available/`, `sites-enabled/` | One site per public service (`grin-node-api`, `grin-fidelius`, `web-wallet-xp`, the snapshot hosts…) |
| `/etc/nginx/conf.d/` | Shared rate-limit and connection zones (`grin-rate-limit.conf`, `grin-conn-limit.conf`, per-product `script##-…` files such as `script02-fileserver.conf` — older boxes keep Script 02's zone in `grin_limit_req.conf` — and `grin_ip_limits.conf` for Script 02's per-IP speed caps) |
| `/etc/nginx/snippets/cloudflare-realip.conf` | Real-IP restoration behind Cloudflare |
| `/etc/letsencrypt/live/<domain>/` | Certificates, renewed by certbot's own timer |
| `/etc/systemd/system/` | `grin-secret-sync.service` + `.timer` (every 5 minutes), `grin-node-events.service` + `.timer` (every 30 seconds), `grin-fidelius.service`, `grinscan-{main,test}.service`, `grin-tiny-explorer.service`, `grin-submit.service`, `grin-woo-bridge-{main,test}.service` and `grin-woo-wallet-{main,test}.service`, `grin-pool-manager`, `grin-games[-testnet].service`, `grin-gateway-probe` (on a gateway box), `grin-access-watch.timer`, `floonet-rs.service`, `grin-transporter-*.service` |
| `/etc/cron.d/` | `grin-node-sync-watchdog` (every 5 minutes), `grin-node-api-rest` / `-node`, `grin-solo-*`, `grin-stratum-watchdog`, `grin-auto-cleanup`, `grin-pool-manager-vacuum` (Sundays 03:00 UTC), `grin-games-vacuum` (Sundays 03:30 UTC), backup jobs — one file per job, named after it |
| `/etc/tor/torrc` | Hidden-service stanzas between `# >>> grin-toolkit:… >>>` markers; nothing outside the markers is touched |
| `/usr/local/bin/` | `gtmux`, `grin-secret-sync`, `grin-node-events`, `grin-stats-collector`, `grin-price-collector`, `grin-node-submit`, `grin-ecosystem-checker`, `grin-solo-mining-collector`, `grin-stratum-watchdog`, `grin-backup-push`, `grin-gateway-ctl`, `floonet-rs` |
| `/etc/logrotate.d/` | `grin-node-<network>` for `grin-server.log` (Super Auto: daily or past 50 MB, 7 kept, `copytruncate`), `grin-node-events`, and the node-API nginx logs |
| `/etc/sysctl.d/99-grin-node.conf`, `/swapfile` | Memory tuning (`vm.swappiness = 10`, `vm.vfs_cache_pressure = 50`) and the swapfile from Script 01's step 2b |
| `/etc/ssh/sshd_config.d/00-grin-hardening.conf` | The SSH hardening drop-in (hub 08 → Host Optimization → SSH Key Hardening); an older `99-grin-hardening.conf` is removed when it is applied or reverted |
| `/etc/grin-toolkit/` | `landing.conf` (Script 02's landing page) and `blocked_ips.list` (Script 02's IP blocks) |
| `/etc/fail2ban/jail.d/nginx-grin.conf` | Script 02's fail2ban jails |
| `/root/.ssh/grin_share_ed25519` | The SSH key Script 03 uses to copy snapshots to mirrors (list in `/opt/grin/conf/grin_share_targets.conf`) |
| `/var/run/grin-toolkit-01.lock` | Script 01's run lock (or `/tmp/grin-toolkit-01.lock`); released when the run ends |
| A `grin` system user | Owns the node directories and runs the nodes; never log in as it |
| A `grinops` group (optional) | Created by the SSH guided setup so your admin user can read `/opt/grin/backups` |

## Logs

Every interactive run writes a log under `/opt/grin/logs/`, named `<script>_<date>_<time>.log`, and prints the path when it finishes — attach that file when you report a problem. Long-running jobs use one fixed name each (`cron_nginx.log`, `cron_remote.log`, `stratum-watchdog.log`, `access-watch.log`…) and are rotated by logrotate. The node event recorder's export lands in `/opt/grin/logs/` as `grin_node_events_export_<UTC>.tar.gz`; Diagnostics writes its support bundles and reports to `/opt/grin/reports/diag/` (readable by root only). The node's own log is `grin-server.log` in the node directory; nginx sites log to `/var/log/nginx/` as `<site>.access.log`.

## Related

- [Glossary](reference-glossary.html) and [Troubleshooting](reference-troubleshooting.html) — the other two reference pages
- [Getting started](getting-started.html#mainnet-and-testnet) — the short version of this page for a first node
- [Script 01](01-build-node.html#what-was-created) — what a node build creates
- [Script 04](04-publish-node-api.html) — the node API ports in use
- [Script 06](06-global-health.html) and [GrinScan](06b-grinscan.html) — the explorer and dashboard ports 3010/3011, 5060, 8000, 8471
- [Wallet hub](05-wallet-services.html) — the wallet ports 3415/3420 and the listener modes that use them; [Fidelius](051-fidelius.html) allocates them per wallet
- [Script 07](07-mining-services.html) — solo mining: the node's stratum 3416 / 13416 published to miners, the reward wallet on 3420 / 13420
- [Public pool](07-public-pool.html) — Script 07's pool: 3333 / 13333, the 8080 / 8090 API, region ports and the WireGuard tunnels
- [Connectivity hub](09-connectivity-hub.html) — Script 09: the Floonet relay on 8181 and the Transporter on 7456 / 7466 (onion fronts 7556 / 7566)
- [Script 08](08-admin-maintenance.html#node-status-sync-key-5) — the status screen that shows which of these ports are actually listening; [Back up and restore](089-backup-restore.html)
