---
title: Getting started
description: What server to rent, which Linux to install, how to run the Grin Node Toolkit for the first time, and how its menu, logs and directories work.
section: Start here
order: 1
covers: 2026-09-19
updated: 2026-09-19
---

By the end of this page you will have the toolkit installed on a server and its main menu open. Building the node itself is the next page, [Script 01](01-build-node.html).

## What you need

**A VPS (virtual private server).** A small, always-on Linux box rented from a hosting provider. You connect to it over SSH from your own computer; the node runs there 24/7. A low-cost SSD or NVMe VPS is plenty — around **US$30 a year** buys enough for a pruned node. [LowEndTalk](https://lowendtalk.com) and [LowEndBox](https://lowendbox.com) list deals.

| Resource | Minimum | Comfortable |
|----------|---------|-------------|
| Disk | **10 GB free** for one pruned node (Script 01 checks this). 25 GB for a full archive; Super Auto asks for 20 GB | 40 GB+ if you also want to share snapshots or run an explorer |
| RAM | Works on 2 GB — the toolkit adds a swapfile (2 GB, or 4 GB on boxes under 2 GB RAM) because a Grin node's start-up is memory-heavy | 4 GB if you run mainnet and testnet together or add web services |
| CPU | 1 vCPU | 2 vCPU — node start-up pegs one core for a few minutes |
| Network | Inbound port 3414 (mainnet) / 13414 (testnet) reachable, so other nodes can connect to yours | |

**A supported Linux.** The toolkit downloads the official pre-built Grin binary, which is compiled against **glibc 2.38 or newer**. That is a hard floor: on an older system the node exits immediately with `version 'GLIBC_2.38' not found`. Check yours with `ldd --version`.

| Distribution | Status |
|--------------|--------|
| **Ubuntu 24.04 / 26.04 LTS** | **Tested and recommended** |
| Ubuntu 22.04 LTS | **Not supported** — glibc 2.35. Many providers still default to it; pick 24.04 when you order |
| Debian 13 (trixie) or newer | Best effort, not fully tested. Debian 12 has glibc 2.36 — too old |
| Other Debian-based (Mint, Pop!_OS, Kali…) | Best effort; must still meet the glibc floor |
| Rocky Linux / AlmaLinux 10+ | Runs, not fully tested |
| Rocky / Alma 9 or older | Not supported (glibc 2.34); the script prints upgrade instructions |
| Fedora, Arch, others | Not supported — the script exits |

> **Danger:** On Ubuntu 22.04 (or any glibc below 2.38) **do not try to upgrade glibc.** `libc.so.6` is the library every program on the machine links against; installing a newer `libc6` from another release breaks the system, usually beyond SSH. Reinstall the VPS on Ubuntu 24.04, or compile the node yourself with Script 01 → key `G` (build from source), which links against whatever glibc you have. Note that the wallet products download the same kind of pre-built binary, so a source build is only a partial escape.

**Root access.** Every script runs with `sudo`. The toolkit creates a dedicated `grin` system user and runs the node as that user — you never run the node as root yourself.

> **Warning:** Use a **clean, empty server.** Some scripts install packages, set the clock to UTC, change firewall rules and write to `/etc/nginx`. They could affect or delete existing data. Do not run the toolkit on a server that already hosts something you cannot afford to lose.

## Install the toolkit

Connect to the server over SSH, then paste these four lines:

```bash
git clone https://github.com/noobvie/Grin-Node-Toolkit.git
cd Grin-Node-Toolkit
chmod +x grin-node-toolkit.sh scripts/*.sh
sudo ./grin-node-toolkit.sh
```

What each line does:

1. `git clone` downloads the toolkit into a folder named `Grin-Node-Toolkit` in your current directory (install `git` first if the command is missing: `sudo apt install git`).
2. `cd` moves into that folder. You run the toolkit from here every time.
3. `chmod +x` marks the scripts as executable.
4. `sudo ./grin-node-toolkit.sh` starts the main menu as root.

The toolkit itself lives where you cloned it; everything it *installs* goes under `/opt/grin/` (see [Where things live](#where-things-live-on-the-server)). Deleting the clone does not remove a node.

## Your first run

On start the main script checks your operating system. Unsupported distributions exit with a message; older Rocky/Alma releases get upgrade instructions. Then the menu appears:

```text
 Grin Node Toolkit v2026.09.20
 Keeping Grin shining bright...

  Core Features

  1) Build/Control Grin Node
  2) Manage Nginx Server
  3) Share Grin Chain Data / Schedule

  Addons

  4) Publish Grin Node API
  5) Grin Wallet & Payment Services (DEV)
  6) Global Grin Health
  7) Grin Mining Pool Deployment (DEV)
  9) Grin Connectivity Hub (DEV)

  8) Admin & Maintenance

  0) Exit

Select an option [0-9]:
```

Press **1** to build your node. The next page, [Script 01](01-build-node.html), walks through what it asks.

### How the menus work

- **Numbers** are the main actions; **letters** are secondary ones (`B` back, `R` refresh, `D` delete, `L` logs, and so on). **`0`** always goes back or exits. `Enter` on an empty prompt takes the default shown in brackets — `[A/1/G/0, Enter = 1]` means plain Enter picks `1`.
- **Backing out.** When a script asks you to type a value (a domain, a path), use the cancel key it shows — `q` in newer prompts, `0` in menus. Avoid `Ctrl+C` mid-action: it kills the script, and a half-finished action may need cleaning up.
- **Hubs** (5, 7, 8, 9) print their own sub-menu with the live status of each product — installed, running, version — so you can see the state of the server before choosing.
- **A product's screen shows its number** in the banner (`01) Grin Node Setup`), which is the same number as its script file in the repository. Sub-menu keys are separate from those numbers and can differ between hubs.
- **Every action writes a log**, named by script and timestamp, under `/opt/grin/logs/` — for example `/opt/grin/logs/01_build_new_grin_node_20260919_142201.log`. The script prints the path when it finishes. Attach it when you report a problem.

## Mainnet and testnet

Grin has two networks: **mainnet**, where GRIN has value, and **testnet**, a parallel chain of worthless test coins (**tGRIN**) for trying things out. The toolkit treats them as two independent installations that can live on one server: separate directories, separate ports, separate wallets. Nothing on testnet touches mainnet.

| | Mainnet | Testnet |
|--|---------|---------|
| Node directory | `/opt/grin/node/mainnet-prune` (or `mainnet-full`) | `/opt/grin/node/testnet-prune` |
| P2P port (must be reachable) | 3414 | 13414 |
| Node API port (localhost) | 3413 | 13413 |
| Wallet Foreign / Owner API | 3415 / 3420 | 13415 / 13420 |
| Built-in stratum (mining) | 3416 | 13416 |
| tmux session name | `grin_pruned_mainnet` / `grin_full_mainnet` | `grin_pruned_testnet` |

If you are new, build **both** (Super Auto does) and use testnet to rehearse anything you are unsure about — [wallet setup](05-wallet-services.html), sending, mining — before doing it on mainnet. The complete list of ports and directories, including which ports must be open at the provider, is on [Ports and paths](reference-ports-and-paths.html).

## Where things live on the server

```text
/opt/grin/
├── node/
│   ├── mainnet-prune/        the node: grin binary, grin-server.toml, chain_data/,
│   │                         grin-server.log, .api_secret, .foreign_api_secret
│   └── testnet-prune/        same layout for testnet
├── conf/                     small config files the scripts share
│   └── grin_instances_location.conf   where each node is installed
├── keys/<network>/           the node API secrets, kept across rebuilds
├── logs/                     one log per script run
├── lib/                      helper libraries installed for cron jobs
└── <product>/                each add-on gets its own folder (fidelius/, drop-main/ …)
```

Two files in a node directory matter for everything else you install later:

- **`.api_secret`** protects the node's *Owner* API — management calls such as status and peer lists. Only trusted local programs use it.
- **`.foreign_api_secret`** protects the *Foreign* API — the public chain-data calls that wallets and explorers make. [Script 04](04-publish-node-api.html) publishes exactly this API over HTTPS.

The values are generated once and kept in `/opt/grin/keys/`, so rebuilding a node does not change them and nothing that depends on them stops working. You will not normally need to touch either file.

## Watching the node

The node runs inside a **tmux** session owned by the `grin` user. Because that session lives on the `grin` user's tmux server, a plain `tmux ls` as root does not show it; use the `gtmux` helper the toolkit installs:

```bash
gtmux ls                              # list node sessions
gtmux attach -t grin_pruned_mainnet   # watch the live node output
```

Inside tmux, press **Ctrl+B, then D** to detach and leave the node running. Do not press Ctrl+C in the session — that stops the node.

The node's own log is `grin-server.log` in the node directory. A one-line health check that works on any toolkit-built node:

```bash
cd /opt/grin/node/mainnet-prune
curl -s -u "grin:$(cat .api_secret)" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"get_status","params":[],"id":1}' \
  http://127.0.0.1:3413/v2/owner
```

The reply includes the current `height` and the number of connected peers. For testnet, use `testnet-prune` and port `13413`. **[Admin & Maintenance → Node Status & Sync](08-admin-maintenance.html#node-status-sync-key-5)** shows the same information for every node on one screen without any typing.

> **Tip:** Do not start the node by hand as root "just to test". A root-run node writes root-owned files into the node directory and the next start as the `grin` user fails with *permission denied*. Always start and stop nodes through the menu.

## Keeping the toolkit up to date

The toolkit changes often. Update it from the menu — **[Admin & Maintenance → Self-update](08-admin-maintenance.html#self-update-key-8)** (which also lets you pick a branch) — or by hand from the clone directory:

```bash
cd ~/Grin-Node-Toolkit && git pull
```

Updating the toolkit does not touch your node; updating the *node binary* is a separate action inside Script 01 (key `B`).

## Removing everything

**[Admin & Maintenance → DEL](08-admin-maintenance.html#full-grin-cleanup-key-del)** runs the full cleanup: it stops every Grin process and tmux session, then removes the node and wallet directories, the nginx sites and web roots, binaries, and the toolkit's logs. It asks you to type `DESTROY` to begin and then confirms each step individually. **[Back up wallet seeds first](089-backup-restore.html)** — this cannot be undone. The clone directory is left for you to delete.

## Common first-run problems

| Symptom | Cause and fix |
|---------|---------------|
| `version 'GLIBC_2.38' not found` | Your distribution is too old for the pre-built binary. Reinstall on Ubuntu 24.04, or use Script 01 → `G` to build from source. See [What you need](#what-you-need). |
| `The Grin Node Toolkit must be run as root` | Start with `sudo ./grin-node-toolkit.sh`. |
| `Unsupported OS` at start | Fedora, Arch and similar are not supported. Rocky/Alma 9 needs an upgrade to 10. |
| `command not found: jq` (or `tmux`, `curl`…) | Script 01 installs its dependencies in Step 2. If a package fails to install, run `sudo apt update` and retry. |
| The menu is missing key 5, 7 or 9 features | Products marked **(DEV)** are still being built. Everything under 1–4, 6 and 8 is stable. |
| Nothing listens on 3414 after the build | The node may still be starting — a Grin node takes a few minutes to open its ports after launch. Check with `gtmux attach -t grin_pruned_mainnet`. |
