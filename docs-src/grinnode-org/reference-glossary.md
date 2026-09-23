---
title: Glossary
description: Plain-language definitions of the Grin, server and web terms this manual uses — node, slatepack, Foreign API, stratum, tmux, vhost and more.
section: Reference
order: 2
covers: 2026-09-23
updated: 2026-09-23
---

The words this manual uses without stopping to explain them, grouped by topic. Each entry is short and links to the page where the term actually matters; the definitions match the ones given on those pages. Every heading is a link target, so a page can point straight at a term.

## The node and the chain

### Node

The program — `grin` — that keeps a copy of the Grin blockchain, checks every block and transaction, and talks to other nodes. It holds no coins and no keys; that is the [wallet](#wallet)'s job. The toolkit runs one node per network, as the `grin` user, in a [tmux](#tmux-and-gtmux) session. [Script 01](01-build-node.html) builds it.

### Mainnet, testnet and tGRIN

**Mainnet** is the real Grin network, where GRIN has value. **Testnet** is a parallel chain whose coins, **tGRIN**, are worthless — made for rehearsing. The toolkit keeps the two completely apart: separate directories, ports and wallets. Rehearse anything unfamiliar on testnet first. See [Getting started](getting-started.html#mainnet-and-testnet).

### Pruned node and archive node

A **pruned** node keeps every block header and every [kernel](#kernel), but the full block *bodies* only for recent blocks. It still verifies everything and is the right choice for almost every use. A **full archive** node keeps every block since genesis — needed only to serve old blocks, for example to a block explorer. The toolkit's directories are `mainnet-prune`, `testnet-prune` and `mainnet-full`. See [Script 01](01-build-node.html#mode-pruned-or-full-archive).

### Chain data and snapshots

`chain_data/` is the node's database: the chain it has downloaded and verified. A **snapshot** is a compressed copy of a synced node's `chain_data`, published by community hosts so a new node can start in minutes instead of syncing for days. Script 01 downloads one ([chain data source](01-build-node.html#chain-data-source)); [Script 03](03-share-chain-data.html) lets you publish your own.

### Sync and PIBD

**Syncing** is a node catching up with the chain. Starting from nothing, Grin downloads the chain state in parallel pieces — **PIBD**, *Parallel Initial Block Download* — which can take hours to days and sometimes stalls. That is why the toolkit starts from a snapshot. A node reports `"sync_status":"no_sync"` once it is caught up.

### Kernel

Every Grin transaction leaves a **kernel** on the chain: a small signed record that proves the transaction happened and carries its fee. Kernels are never pruned, so they are how an explorer or a [payment proof](#payment-proof) finds a transaction later. There are no addresses or amounts on the chain to look up instead.

### Mempool

The waiting room of transactions a node has received but that are not in a block yet. A transaction leaves the mempool when a miner includes it, usually within a minute or two.

### txhashset snapshot

A `txhashset_snapshot_<height>` zip your node writes whenever another node syncs its state from yours. They pile up in the node directory; [Script 03](03-share-chain-data.html#i-clean-up-txhashset-snapshots) removes them before each share and can schedule a clean-up.

### P2P port

The port other nodes use to connect to yours: **3414** on mainnet, **13414** on testnet. It is one of the few ports that must be open in your provider's firewall. See [Ports and paths](reference-ports-and-paths.html#which-ports-must-be-open-at-the-provider).

## Node APIs and secrets

### Foreign API and Owner API

A node answers on one HTTP port (3413, testnet 13413) with two APIs. The **Foreign API** (`/v2/foreign`) serves public chain data and broadcasts transactions — it is what wallets and explorers use, and what [Script 04](04-publish-node-api.html#foreign-api-and-owner-api) publishes. The **Owner API** (`/v2/owner`) manages the node — status, peers, validation — and stays on the server. A *wallet* has its own pair with the same names on different ports (3415 and 3420); see [Wallet](#wallet).

### API secrets

The two password files in a node directory: `.api_secret` protects the Owner API and `.foreign_api_secret` the Foreign API. Programs send them as HTTP Basic credentials with the user name `grin`. The toolkit keeps a copy of each in `/opt/grin/keys/<network>/`, so rebuilding a node does not change them. See [Getting started](getting-started.html#where-things-live-on-the-server).

### grin-secret-sync

A small helper the toolkit installs with a timer that runs every 5 minutes. It finds each node's secret files and re-points every installed service at them, so a rebuilt or moved node does not leave the services behind it locked out with HTTP 401. `grin-secret-sync --rotate <network>` changes a secret on purpose. See [Script 01](01-build-node.html#day-to-day-operations).

## Wallets and transactions

### Wallet

A separate program — `grin-wallet` — that holds your [seed](#seed-phrase), builds and signs transactions, and asks a node what is on the chain. It exposes a **Foreign API** (port 3415 / 13415) through which it receives, and an **Owner API** (3420 / 13420) through which it is managed; both stay on localhost. See [A Grin wallet, in plain words](05-wallet-services.html#a-grin-wallet-in-plain-words).

### Seed phrase

The 24 words printed once when a wallet is created. They *are* the wallet: anyone holding them holds the coins, and they are the only way to restore the wallet on another machine. Write them on paper and keep them off the server. See [Back up and restore](089-backup-restore.html).

### Passphrase

The password that encrypts the seed file on disk. It is asked for every time the wallet is unlocked. The toolkit's always-on wallets save it in a protected file on the server so they can unlock themselves after a reboot — one more reason the server itself must be kept safe.

### Slate and slatepack

A Grin payment is a two-way exchange. The sender's wallet writes a partial transaction — a **slate** — the receiver's wallet signs it and hands it back, and the sender finalises and broadcasts it. A **slatepack** is a slate written as a block of text, so it can be copied and pasted through any channel: a chat, an email, a web form.

### Slatepack address

A wallet's `grin1…` address (`tgrin1…` on testnet). It is a key for *reaching* a wallet — over Tor, or to encrypt a slatepack to it — not a place on the chain where coins sit. The same key gives the wallet its Tor address.

### Listener

A wallet left running so it can answer incoming payments without you. The toolkit uses two modes: **`listen`** (receive only, Foreign API on 3415, with its own Tor address) and **`owner_api`** (receive *and* send, both APIs on 3420, no automatic Tor), which the toolkit's services use. See [the two listener modes](05-wallet-services.html#the-two-listener-modes).

### Invoice

The same exchange started from the other end: the receiver writes an invoice slatepack for an amount, the payer's wallet pays it with `grin-wallet pay`, and the receiver finalises. Shops and donation pages use it — see [WooCommerce](053-woocommerce.html#how-a-grin-payment-works-here) and [Grin Drop](059-grin-drop.html#donating).

### Payment proof

A statement signed by the receiver's wallet saying it received a given amount in a given transaction. It is optional and only possible when the sender knew the receiver's slatepack address. A payment proof shows who was paid; a [kernel](#kernel) on chain only shows that the transaction was mined.

## Mining

### Miner and Cuckatoo32

A **miner** is a machine — usually a dedicated rig — that races to solve Grin's proof of work, *Cuckatoo32*. Its speed is measured in **graphs per second** (G/s, kG/s, MG/s), not hashes. A new block arrives about every minute. See [How solo mining works](07-mining-services.html#how-solo-mining-works).

### Stratum

The protocol a miner uses to fetch work and hand in solutions, over a plain TCP connection such as `stratum+tcp://your-server:3416`. A Grin node has a stratum server built in (3416 / 13416), switched off until you set up mining; the public pool puts its own stratum on 3333 / 13333 in front of it.

### Coinbase and maturity

The **coinbase** is the new money in each block — 60 GRIN — paid to whoever mined it. The node asks the wallet to build it with a `build_coinbase` call. A coinbase is locked for **1,440 blocks (about 24 hours)** before it can be spent; until then it is *immature*.

### Solo mining and pools

**Solo**: your rigs mine against your own node and every block you find pays its whole coinbase to your wallet — rare but large. **Pool**: many miners share the work and the pool splits each block between them — small, steady payments. The toolkit offers both, one per server. See [solo mining](07-mining-services.html) and [the public pool](07-public-pool.html).

### PPLNS

*Pay Per Last N Shares* — the way the toolkit's public pool splits a block: by the work each miner submitted in the last 60 blocks. Leaving just before a block is found still earns your part, so hopping between pools does not pay. See [Fees and payouts](07-public-pool.html#fees-and-payouts).

### Orphan block

A block that was found but lost the race: the network kept a different block at the same height, so its coinbase never matures. The toolkit's mining tools detect orphans and never pay them out.

## Transport and privacy

### Tor and .onion addresses

**Tor** is a network that relays traffic through volunteers' servers so neither end learns where the other is. A service reachable only through Tor has a `.onion` address. Grin wallets use Tor to send a payment straight to the receiver's [slatepack address](#slatepack-address); the toolkit also gives node APIs an onion mirror. See [Script 04's onion](04-publish-node-api.html#the-tor-onion).

### Nostr relay

**Nostr** is an open protocol for passing signed messages through servers called **relays**. The Goblin wallet sends slatepacks as encrypted Nostr messages, so the receiver can pick up a payment when it next comes online. Script 091 deploys a relay — see [Floonet relay](09-connectivity-hub.html#floonet-relay-091).

### Goblin

An independent Grin wallet, by the developer known as *dog*, that pays by human-readable name (`alice@yourdomain.com`) and moves slatepacks over Nostr and Tor. The toolkit does not ship it; it deploys the relay Goblin connects to, and the public pool has an optional Goblin payout method, off by default.

### Store-and-forward (Transporter)

A mailbox for slates: the sender drops an encrypted slatepack into a queue on a server, and the receiver collects it later, so the two never need to be online at the same moment. The toolkit's version is the [Grin Transporter](09-connectivity-hub.html#grin-transporter-093), which has not yet been run on a server.

### WireGuard

A fast, simple VPN. The toolkit uses it for two private links: the public pool's regional gateways tunnel miners to the pool server, and Fidelius can be made reachable only over a WireGuard connection from your own devices. It listens on UDP 51820. See [Fidelius private access](051-fidelius.html#private-access-menu-v).

## The server

### VPS

A *virtual private server* — a small Linux machine rented from a hosting provider, always on, reached over SSH. The toolkit is meant to run on a clean one. See [What you need](getting-started.html#what-you-need).

### glibc

The C library that almost every Linux program is built against. The official Grin binaries need **glibc 2.38 or newer**, which is why Ubuntu 24.04 is the minimum and 22.04 does not work. Check with `ldd --version`, and never upgrade glibc by hand.

### root, sudo and the grin user

**root** is the Linux administrator account; `sudo` runs one command as root. The toolkit's scripts must run as root, but the node itself runs as an unprivileged **`grin`** user the toolkit creates. Starting a node as root by hand leaves root-owned files that stop the next normal start.

### tmux and gtmux

**tmux** keeps a terminal session running after you disconnect — the toolkit runs each node inside one. Because those sessions belong to the `grin` user, a plain `tmux ls` as root does not show them; the toolkit's **`gtmux`** helper does (`gtmux ls`, `gtmux attach -t grin_pruned_mainnet`). Detach with Ctrl+B, then D. See [Watching the node](getting-started.html#watching-the-node).

### systemd service

The standard way Linux runs a background program and restarts it if it dies. The toolkit's web apps and wallet listeners are systemd services (`systemctl status <name>`, logs with `journalctl -u <name>`); the nodes themselves run in tmux instead.

### cron

Linux's scheduler. The toolkit uses it for recurring jobs — snapshot sharing, the sync watchdog, dashboard collectors, scheduled backups — and for `@reboot` entries that start nodes when the server boots.

### Watchdog

A scheduled check that repairs something when it fails. The main one is the **sync watchdog**: every 5 minutes it restarts a node that is down or whose height has stopped moving. The mining tools add watchdogs for the wallet listener and the stratum port. See [Watchdogs and autostart](07-mining-services.html#watchdogs-and-autostart).

### Swap

Disk space the kernel uses as overflow memory. A Grin node's start-up needs a lot of memory at once, so Script 01 adds a swapfile (2 GB, or 4 GB on servers with under 2 GB of RAM) to keep small servers from killing it.

### Firewall

Two layers decide which ports the internet can reach: your **provider's firewall** (often called a security group), set in their control panel, and the server's own, **ufw** (or firewalld on Rocky/Alma). The toolkit opens ports in the server's firewall; the provider's you open yourself. See [Ports and paths](reference-ports-and-paths.html#which-ports-must-be-open-at-the-provider).

## The web side

### DNS A record

The entry at your domain registrar or DNS host that points a name such as `api.yourdomain.com` at your server's IP address. Every script that sets up a public site asks for a domain whose A record already points at the server, because the certificate step checks it.

### nginx, vhosts and reverse proxies

**nginx** is the web server in front of everything the toolkit publishes. Each site is a **vhost** — a config file in `/etc/nginx/sites-available/` answering for one domain. Most toolkit sites are **reverse proxies**: nginx takes the HTTPS request on port 443 and passes it to an app listening on localhost. Test any change with `nginx -t` before reloading.

### Let's Encrypt and certbot

**Let's Encrypt** issues free HTTPS certificates; **certbot** is the tool that requests and renews them. To prove you own a domain it fetches a file from your server over port 80, so the [A record](#dns-a-record) must be right and port 80 open. Certificates renew automatically.

### Cloudflare proxy

Cloudflare can sit in front of a domain (the orange cloud in its dashboard). That hides your server's IP address, but it also gets in the way of the certificate check and of anything that is not web traffic. Set a name to **DNS only** while a script issues its certificate, and never proxy a stratum or P2P name.

### Basic Auth

A user name and password that the browser asks for before showing a page, enforced by nginx. The toolkit uses it to lock private pages — Fidelius, the solo-mining stats page — to their owner.

## Toolkit words

### Hub

A main-menu entry that opens its own sub-menu of products, with the live status of each: **5** wallets and payments, **7** mining, **8** admin and maintenance, **9** connectivity. See [the menu](index.html#the-menu).

### (DEV)

The main menu's mark for a hub that is still being built — 5, 7 and 9 today. Some products inside are finished; each page in this manual starts with a status note saying which.

### Super Auto

Script 01's one-key install: both networks, pruned, from the fastest snapshot, plus autostart on reboot, the sync watchdog and log rotation. It wipes any existing node first. See [Super Auto](01-build-node.html#super-auto).

### Personal key

The one key that encrypts every backup archive on a server — the toolkit-wide backup and each product's own. Keep it somewhere other than the server; without it an archive cannot be opened. See [The personal key](089-backup-restore.html#the-personal-key).

## Related

- [Troubleshooting](reference-troubleshooting.html) — every symptom in the manual, A–Z
- [Ports and paths](reference-ports-and-paths.html) — every port and directory mentioned here
- [Getting started](getting-started.html) — the first page to read
