---
title: Grin Node Toolkit Manual
description: A plain-language guide to installing and running a Grin node and its services on a Linux VPS with the Grin Node Toolkit — for first-time operators.
section: Start here
order: 0
covers: 2026-09-19
updated: 2026-09-23
---

The [Grin Node Toolkit](https://github.com/noobvie/Grin-Node-Toolkit) is a set of Bash scripts, driven from one interactive menu, that installs and manages a [Grin](https://grin.mw) node and everything you might want to run next to it: an HTTPS API for wallets, chain-snapshot sharing, a block explorer, a network dashboard, wallet services, a mining pool, and the admin chores that keep a server healthy.

This manual explains each part in plain language. It assumes you can open an SSH session to a Linux server and copy commands; it does not assume you have run a Grin node before.

## Where to start

<div class="cards">
<a class="card" href="getting-started.html"><div class="card-label">Start here</div><h3>Getting started</h3><p>What server you need, how to install the toolkit, and how the menu works.</p></a>
<a class="card" href="01-build-node.html"><div class="card-label">Script 01</div><h3>Build or control a Grin node</h3><p>From an empty VPS to a synced node in under an hour, using a chain snapshot.</p></a>
<a class="card" href="05-wallet-services.html"><div class="card-label">Script 05</div><h3>Wallets and payments</h3><p>What a Grin wallet is, and a command-line wallet next to your node in a few minutes.</p></a>
<a class="card" href="08-admin-maintenance.html"><div class="card-label">Script 08</div><h3>Admin and maintenance</h3><p>Node status at a glance, backups, disk cleanup, self-update and SSH hardening.</p></a>
</div>

The shortest path to a running node is **Getting started → Script 01 → Super Auto**. Everything else in the toolkit is optional and builds on that node.

## What the toolkit does for you

- **Skips the slow first sync.** Syncing Grin from genesis can take days and the current PIBD mechanism can stall. The toolkit downloads a verified, pre-synced chain snapshot from a community host instead, so a node is running in well under an hour.
- **Keeps the node alive.** Autostart on reboot, a sync watchdog, log rotation, swap tuning and a Tor `.onion` mirror are set up for you.
- **Turns a node into infrastructure.** Publish the node API over HTTPS, share your own snapshots with the community, run an explorer or a network map, host a web wallet, a giveaway portal, or a mining pool — each one a menu option.
- **Runs mainnet and testnet side by side.** Every service uses separate ports and directories per network, so one server can serve both.

## The menu

The toolkit has two levels. The main menu lists the products; most of the *Add-ons* are hubs that open their own sub-menu with live status of what is installed.

```text
Grin Node Toolkit
│
├── Core
│   ├── 1) Build / Control Grin Node
│   ├── 2) Manage Nginx Server
│   └── 3) Share Grin Chain Data / Schedule
│
├── Add-ons
│   ├── 4) Publish Grin Node API
│   ├── 5) Grin Wallet & Payment Services   (hub)
│   ├── 6) Global Grin Health               (+ GrinScan explorer, Tiny Explorer)
│   ├── 7) Grin Mining Pool Deployment      (hub: solo mining or public pool)
│   ├── 8) Admin & Maintenance              (hub)
│   └── 9) Grin Connectivity Hub            (hub)
│
└── 0) Exit
```

| Menu item · manual page | What it is for |
|-------------------------|----------------|
| **1** · **Build / Control Grin Node** — [Script 01](01-build-node.html) | Install the node binary, bootstrap chain data from a snapshot, start, rebuild or update a node |
| **2** · **Manage Nginx Server** — [Script 02](02-nginx-fileserver.html) | An nginx file server with Let's Encrypt SSL for distributing chain snapshots; rate caps, fail2ban, IP filtering |
| **3** · **Share Grin Chain Data** — [Script 03](03-share-chain-data.html) | Compress and publish your node's chain data on a schedule, over nginx or SSH; reboot autostart |
| **4** · **Publish Grin Node API** — [Script 04](04-publish-node-api.html) | Expose the node's public (Foreign) API over HTTPS so wallets and explorers can use your node |
| **5** · **Grin Wallet & Payment Services** — [Script 05](05-wallet-services.html) · [Fidelius](051-fidelius.html) · [WooCommerce](053-woocommerce.html) · [Grin Drop](059-grin-drop.html) | Hub for wallet products: a personal web wallet, a self-custodial public web wallet, a WooCommerce gateway, a giveaway portal, a CLI wallet quick setup |
| **6** · **Global Grin Health** — [Script 06](06-global-health.html) · [GrinScan](06b-grinscan.html) | A network-stats dashboard with a peer map, plus the GrinScan block explorer and a tiny stateless explorer |
| **7** · **Grin Mining Pool Deployment** — [Solo mining](07-mining-services.html) · [Public pool](07-public-pool.html) | Solo mining against your own node, or a full public pool with Tor payouts |
| **8** · **Admin & Maintenance** — [Script 08](08-admin-maintenance.html) · [Backup & restore](089-backup-restore.html) | Remote node monitor, host-tamper watch, status screen, nginx extras, SSH hardening, backups, disk cleanup, self-update, full uninstall |
| **9** · **Grin Connectivity Hub** — [Connectivity hub](09-connectivity-hub.html) | Privacy and transport layer: a Nostr relay for Goblin wallets, a store-and-forward slate queue |

**Reference pages:** [Ports and paths](reference-ports-and-paths.html) — every port, which must be open, and where each script keeps its files. [Glossary](reference-glossary.html) — the Grin, server and web terms this manual uses. [Troubleshooting](reference-troubleshooting.html) — every error message in the manual, A–Z, with the fix one click away.

> **Note:** The **menu key is not the script number.** Inside a hub, keys are assigned per hub (the wallet hub uses fixed slots, the admin hub matches each sub-script's last digit). This manual names products, not keys, wherever a key could move. What each number *means* is stable and is what the file names in the repository use.

## Requirements in one line

A clean Linux VPS running **Ubuntu 24.04 LTS** (or another distribution with glibc 2.38 or newer), root access, and at least **10 GB** of free disk for a pruned node. The full list, including which distributions do *not* work and why, is in [Getting started](getting-started.html#what-you-need).

## Sites built with the toolkit

Everything below was deployed semi-automatically with the menu — they double as live examples of what each script produces.

| Site | Built with |
|------|-----------|
| [prunemain.grin.money](https://prunemain.grin.money) / [prunetest.grin.money](https://prunetest.grin.money) / [fullmain.grin.money](https://fullmain.grin.money) | Scripts 01 + 02 + 03 — pruned mainnet, pruned testnet and archive mainnet nodes sharing chain snapshots |
| [api.grin.money](https://api.grin.money) / [testapi.grin.money](https://testapi.grin.money) | Script 04 — public node API |
| [world.grin.money](https://world.grin.money) | Script 06 — global health dashboard and peer map |
| [grinscan.org](https://grinscan.org) / [test.grinscan.org](https://test.grinscan.org) | Script 06b — GrinScan block explorer |
| [scan.grin.money](https://scan.grin.money) | Script 06d — Tiny Explorer |
| [drop.grin.money](https://drop.grin.money) | Script 059 — Grin Drop giveaway portal |
| [solo.grin.money](https://solo.grin.money) | Script 07 — solo mining stats page |
| [grinium.com](https://grinium.com) | Script 07 — public mining pool *(in development)* |
| [relay.grin.money](https://relay.grin.money) | Script 091 — Floonet Nostr relay |

## Getting help

- **An error message you do not recognise:** search [Troubleshooting](reference-troubleshooting.html) — every symptom this manual covers, A–Z, with a filter box.
- **Bugs and questions about the toolkit:** open an issue on [GitHub](https://github.com/noobvie/Grin-Node-Toolkit/issues). Include the log file the script names at the end of its run — every action writes one under `/opt/grin/logs/`.
- **Grin itself:** the [Grin forum](https://forum.grin.mw) and the [official documentation](https://docs.grin.mw).
- **Source of truth:** the toolkit's [README](https://github.com/noobvie/Grin-Node-Toolkit#readme) and the design documents in its `docs/generated/` folder go deeper than this manual on architecture and security.

> **Warning:** The toolkit is under active development and performs system-level operations — it installs packages, changes firewall rules and writes to `/etc/nginx`. Run it on a **clean server** you can afford to rebuild, never on a box with data you cannot lose.
