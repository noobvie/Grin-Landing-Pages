---
title: Build or control a Grin node
description: How Script 01 installs a Grin node from a chain snapshot, what each wizard choice means, and how to start, stop, update or rebuild a node from its menu.
section: Scripts
order: 1
short: Build a node
label: Script 01
covers: 2026-10-23
updated: 2026-10-24
---

Script 01 is the foundation of the toolkit: it puts a synced Grin node on the server, and every other script builds on that node. It is also where you come back to start, stop or update a node, or to rebuild a corrupted one.

> **Note:** Status — Script 01's menu was rebuilt in October 2026: one status screen with numbered keys for each node action. The new menu has been tested against a simulated server only, not yet on a real VPS. If a screen differs from this page, the script's own text is the one to trust.

## What it does

An ordinary Grin install syncs the chain from genesis over the peer network. That takes hours to days and, with the current [PIBD](reference-glossary.html#sync-and-pibd) (Parallel Initial Block Download) mechanism, sometimes stalls or loops. Script 01 avoids all of it:

1. Downloads the latest official `grin` release (linux-x86_64) from GitHub. The release binary is not checksum-checked; the chain snapshot in *full download* mode is.
2. Generates the node configuration with grin's own `server config` command, then patches in the toolkit's standard paths and your choices.
3. Downloads a **pre-synced [chain snapshot](reference-glossary.html#chain-data-and-snapshots)** from a community host, checking that the snapshot is fresh, and extracts it into the node directory.
4. Starts the node as the unprivileged `grin` user inside a [tmux](reference-glossary.html#tmux-and-gtmux) session, adds a [Tor](reference-glossary.html#tor-and-onion-addresses) `.onion` address for its API, and re-points any already-installed services at the new node.

The result is a node at the current chain height within the time it takes to download a few gigabytes. Every build then offers **autostart on reboot** and the **[node event recorder](reference-glossary.html#node-event-recorder)**; **Super Auto** turns both on without asking and adds a [sync watchdog](reference-glossary.html#watchdog) and log rotation.

## Choices you will make

Whichever menu key you use, these are the decisions behind it. Read them once and the prompts make sense.

### Network: mainnet, testnet or both

**Mainnet** is the real Grin network. **Testnet** is a separate chain of worthless test coins, useful for rehearsing wallet and mining setups. A server can host at most one node per network. Choosing **Both** builds mainnet first, then testnet, each in its own directory with its own copy of the binary. The install only offers networks that have no node yet.

### Mode: pruned or full archive

| | Pruned | Full archive |
|--|--------|--------------|
| Keeps | The full header chain and every [kernel](reference-glossary.html#kernel); block *bodies* only for recent blocks | Everything since genesis |
| Disk needed | About 10 GB free (a few GB of chain data plus room to grow) | 25 GB free and growing |
| Good for | Running a node, wallets, mining, the public API, the [stats dashboard](06-global-health.html) | Serving old blocks: the [GrinScan](06b-grinscan.html) explorer, sharing full snapshots |
| Available on | Mainnet and testnet | Mainnet only |

Pruned is the default and the right choice unless you know you need old block bodies. A pruned node is a fully validating node: it verifies every block, it just does not keep all of them. The two modes use different directories (`mainnet-prune` and `mainnet-full`); building one mainnet mode removes the other mode's directory.

### Chain data source

| Option | What happens | When to use it |
|--------|--------------|----------------|
| **On-the-fly** (default) | Streams the snapshot from the host straight into `tar`. Nothing is stored beside the extracted data, and the script switches host automatically if the download breaks. No SHA256 check in this mode | Almost always: it is the fastest and needs the least disk |
| **Full download** | Saves the `.tar.gz` to disk first (resumable), verifies its SHA256, checks free space, then extracts | When your connection is unreliable and you want a resumable, checksum-verified download |
| **Slow sync** | No snapshot at all. The node starts with an empty `chain_data/` and syncs from genesis over P2P, exactly as a stock Grin install would | Only when no snapshot host is fresh or reachable. Takes hours to days |

For the first two options you also pick a **download zone**: America, Asia, Europe, Africa, or **Auto** (every zone at once). The script loads the community host list from `extensions/grinmasternodes.json`, shuffles the zone's hosts to spread the load, and probes each one for a snapshot that is recent enough (**5 days** for a pruned snapshot, **70 days** for a full archive). It downloads from the first host that passes and keeps the others as fallbacks; the menu says "fastest", but hosts are not ranked by speed or age. A zone with no hosts listed uses America's list. If none of the zone's hosts is fresh, the script tries every zone; if that fails too, it asks for a custom URL or `0` to go back.

> **Note:** The snapshot is a convenience, not a trust decision you are stuck with. The node validates the data it receives from peers from that point on; a bad snapshot would simply fail to sync. Once your own node is synced you can share your own snapshot with [Script 03](03-share-chain-data.html) and become one of the hosts.

## The menu

Script 01 opens on one screen, whatever state the server is in: a **status block** for each network, then the keys. It never kills or changes anything just to draw this screen. On a fresh server:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 01) GRIN NODES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  MAINNET  not installed
  TESTNET  not installed
  conf ✓ matches disk
  ──────────────────────────────────────────────────────────────

  ── One-shot setup ─── wipe the box, rebuild both nodes

  A) Super Auto — wipe all, rebuild both pruned  (type REBUILD)

  ── Nodes ──────────── start, stop, update, rebuild, install

  1) Start a node                        no node installed
  2) Stop a node                         nothing is running
  3) Update Grin binary                  no node installed
  4) Rebuild a node                      no node installed
  5) Install a node                      → both / mainnet / testnet

  ── Source build ───── your own Grin binary

  G) Compile Grin binary from source / roll back old Grin version

  0) Back to main menu

Select [A / 1-5 / G / 0]:
```

With both nodes built and running, the same screen reads:

```text
  MAINNET  pruned  /opt/grin/node/mainnet-prune  RUNNING  v5.5.1  gtmux  autostart ✓
  TESTNET  pruned  /opt/grin/node/testnet-prune  RUNNING  v5.5.1  gtmux  autostart ✓
  conf ✓ matches disk
  ...
  1) Start a node                        every installed node is already running
  2) Stop a node                         → mainnet / testnet
  3) Update Grin binary                  → both / mainnet / testnet
  4) Rebuild a node                      → mainnet / testnet · chain_data or full
  5) Install a node                      no free network
```

A key that can act shows, after the arrow, the networks it would act on. A key that cannot act is printed dim with the reason; pressing it prints *Not available now: …* and asks again. Every action touches **only the network it names**, then returns to this screen with a fresh scan.

| Key | Action |
|-----|--------|
| `A` | [Super Auto](#super-auto): wipe every node, rebuild both networks pruned, with autostart, watchdog, event recorder and log rotation. Recommended for a first node |
| `1` | **Start a node** that is installed but stopped. The normal way to bring a node back after a stop |
| `2` | **Stop a node.** Asks which network when both run |
| `3` | **Update Grin binary** to the latest release, for mainnet, testnet or both (the default). Chain data is kept. See [Day-to-day operations](#day-to-day-operations) |
| `4` | **Rebuild a node**: `1` *chain_data only* (fresh snapshot, same config, secrets and `.onion`; you type `REBUILD`) or `2` *full reinstall* (deletes that network's node directory and runs the [wizard](#the-custom-wizard-step-by-step) for it; you type `REBUILD`, or `DELETE-ARCHIVE` when a full archive would go) |
| `5` | **Install a node** on a network that has none yet: runs the [wizard](#the-custom-wizard-step-by-step) |
| `G` | [Compile from source](#compile-from-source-key-g), install that build, or roll back to the previous binary |
| `0` | Back to the main menu |

When only one network applies, the script picks it and says so; otherwise it asks *Network [1-2 / 0]* (for *Update Grin binary*, *Network [1-3 / Enter = 3 / 0]*, where `3` is both). The old letter keys still work as shortcuts: `s` = `1`, `b` = `3`, `m` / `t` = `4` for mainnet / testnet.

### Reading the status block

| You see | Meaning |
|---------|---------|
| `RUNNING` / `STOPPED` | Whether a `grin` process of that node directory exists, including one that is still booting and has not opened its ports |
| `gtmux` / `root tmux` / `no session` | Which tmux server holds the node's session. `gtmux` is normal. `root tmux` means the node was started by hand as root; stop it with `2` and start it with `1` |
| `autostart ✓` / `✗` / `—` | The `@reboot` line starts this node / starts a different directory (left over from a pruned ↔ full switch; re-point it in Script 03 → `G` or by accepting the wizard's offer) / does not exist |
| `(binary or config missing)` and *cannot start — repair with 4) Rebuild a node* | The directory exists but `grin` or `grin-server.toml` is gone. Only the full reinstall under `4` repairs it |
| `also on disk: …` | A second directory for the same network (for example both `mainnet-prune` and `mainnet-full`); only one can use the port |
| `conf: …` in yellow | `/opt/grin/conf/grin_instances_location.conf`, which every other script reads, does not match what is on disk |
| `P2P port 3414 (mainnet) is held by a non-grin process` | Something other than Grin listens on the node's port. Find and stop it before you start the node |

## Super Auto

Super Auto is the answer to "just give me a working node". One key, one confirmation, and both networks are built and hardened. It will:

- Build **mainnet-prune** and **testnet-prune** with the chain snapshot streamed on-the-fly from a fresh host in any zone.
- Enable **autostart on reboot** (a crontab `@reboot` entry: mainnet starts 5 seconds after boot, testnet 1000 seconds later so they never compete for the disk).
- Install the **sync watchdog**, a cron job every 5 minutes that restarts a node that is down, or whose height has stopped advancing while public height references keep moving. Its default config watches **mainnet only**: testnet is listed but disabled in `/opt/grin/conf/grin_node_watchdog.json`.
- Install the **node event recorder**, a read-only timer (every 30 seconds) that logs each time a node goes down or comes back and saves its console and logs at the moment of failure. It never restarts anything. View it in [Admin & Maintenance](08-admin-maintenance.html#node-event-recorder) → Diagnostics → Node event recorder.
- Set up **log rotation** for each `grin-server.log` (`/etc/logrotate.d/grin-node-<network>`: rotated once it passes 50 MB, seven compressed copies kept).
- Add a **Tor `.onion` address** for each node's API (see [step 13b](#the-custom-wizard-step-by-step)).

It wants **20 GB free** on the filesystem holding `/opt/grin/node`. With less it warns and asks you to type `FORCE` to go ahead anyway.

> **Danger:** Super Auto is **destructive on a server that already has a node.** It stops every Grin node and deletes the binaries and `chain_data` of *both* networks before rebuilding, and it only ever builds *pruned* nodes, so a full archive would be gone. It lists what it will remove (version, chain size, date) and asks you to type `REBUILD`, or `DELETE-ARCHIVE` when a full archive is among them. On an empty server it asks a plain `Proceed? [Y/n]`. Wallets are not touched, but if you have anything on the box you are not sure about, use `5` (install) or `4` (rebuild one network) instead.

> **Warning:** Super Auto looks for a legacy `~/.grin` directory only **after** the wipe. If it finds one, answer `D` (delete) or `Enter` (keep): `0` there goes back to the menu with the old nodes already deleted and nothing rebuilt.

## The custom wizard, step by step

Key `5` (install) and the *full reinstall* under key `4` run the wizard, a pipeline of numbered steps. It prints each step's header as it goes, so you can follow along. At most prompts `0` goes back to the Script 01 menu.

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | The node scan behind the menu. Before an install, the script also looks for a legacy `~/.grin` directory from a manual install, which can shadow the toolkit's config | `D` deletes it (recommended), `Enter` keeps it, `0` goes back |
| 2 | Updates the package index and upgrades the system, then installs what is missing: `tar openssl libncurses tmux jq tor curl wget sqlite3 rsync cron`, and makes sure Tor is running | Wait |
| 2b | Sets `vm.swappiness = 10` and `vm.vfs_cache_pressure = 50` (`/etc/sysctl.d/99-grin-node.conf`). Adds a `/swapfile` (2 GB, or 4 GB when RAM is under 2 GB) unless about 2 GB of swap already exists, so the node's memory-heavy start-up is not OOM-killed | Nothing |
| 3 | Network selection, only the networks with no node yet | `1` mainnet, `2` testnet, `3` both (Enter = mainnet) |
| 4 | Archive mode, then a free-space advisory (10 GB pruned, 25 GB full) | `1` pruned, `2` full (mainnet only); `Y` to go on with low space |
| 5 | Prepares the node directory `/opt/grin/node/<network>-<mode>`. A mainnet build removes the other mainnet mode's directory. A fresh install stops here if free disk is below 10 GB (pruned) or 25 GB (full). **Any existing files in the directory are removed without asking**, because the directory belongs to the node being built | Nothing |
| 6 | Downloads the latest `grin` release for linux-x86_64 from GitHub. With *Both* it is downloaded once and copied to each node. A binary armed with [`G`](#compile-from-source-key-g) → `3` is meant to be used instead, but currently is not | Wait |
| 7 | Runs `./grin server config` (`--testnet` for testnet) so grin writes its own default `grin-server.toml` with the right chain type and ports | Nothing |
| 8 | Patches the config: archive mode, absolute paths for `chain_data`, the log and both API secret files; peer limits (999 in, 199 out); 10 rotated log files; file log level `Debug`. The stratum (mining) settings are left alone — they belong to [Script 07](07-mining-services.html) | Nothing |
| 8b | Ensures `.api_secret` and `.foreign_api_secret` exist, restored from the vault at `/opt/grin/keys/<network>/` if this is a rebuild, otherwise generated and saved there | Nothing |
| 9 | Chain data source: transfer mode, then zone and host discovery | `1` on-the-fly, `2` full download, `3` slow sync; then a zone |
| 10–12 | On-the-fly: one streaming step. Full download: SHA256 check of the archive, a free-space check (archive size × 1.2), extraction, then deletion of the archive | Confirm removal of an old archive or `chain_data/` if one exists |
| 8c | Creates the `grin` system user if needed and gives it ownership of this node's directory only; the rest of `/opt/grin` keeps its owners (runs here, just before the start, despite its number) | Nothing |
| 13 | Starts the node: `./grin server run` inside a tmux session named `grin_pruned_mainnet` (or `grin_full_mainnet`, `grin_pruned_testnet`), as the `grin` user, on the `grin` user's tmux socket. Any stale session with that name and any leftover grin process for the directory is cleaned up first | Nothing |
| 13b | Writes a Tor hidden service that forwards the `.onion` address (port 80) to the node's API on `127.0.0.1:3413` (`13413` for testnet) and reloads Tor. The address is printed and kept across rebuilds. The API behind it still asks for the node's secret, so it is for your own use; a public onion for wallets is a [Script 04](04-publish-node-api.html) option | Nothing |
| 14 | Summary: network, mode, directory, tmux session, elapsed time, log file, `.onion` address | Read it |
| 14b | Re-points every installed service (stats collector, explorers, wallets, Script 04's nginx, pool stratum) at the node and installs the 5-minute `grin-secret-sync` timer | Nothing |
| 14c | Offers **autostart on reboot** for this node (the same `@reboot` line as Super Auto) | Enter = yes, `n` = no |
| 14d | Offers the **node event recorder**, once per run | Enter = yes, `n` = no |

With *Both* selected, steps 4–14d run for mainnet, then straight away for testnet. There is no pause between the two builds, so on a small VPS the testnet node can start while mainnet is still booting.

> **Warning:** A full reinstall (and Super Auto) regenerates `grin-server.toml` from scratch. If you mine solo on this node, the stratum settings that [Script 07](07-mining-services.html) added are gone afterwards: run its setup again. A public pool's stratum settings are written back into the config by `grin-secret-sync` (step 14b, then every 5 minutes), but only after the node has already started, so the pool's stratum stays off until you restart the node: Script 01 → `2` *Stop a node*, then `1` *Start a node*.

## Compile from source (key G)

`G` opens its own menu for running a `grin` binary you compiled yourself. Use it when a fix is on grin's `staging` branch but not in a release yet, when your system's glibc is too old for the release binary, or to go back to the previous binary after an update.

```text
  1) Compile a branch/tag into a binary   (default: staging)
  2) Install a local compiled binary into the node(s) already installed
     replaces <node_dir>/grin, keeps grin.prev, restarts the node
  3) Install a local compiled binary into the NEXT node you build
     for a node that does not exist yet — Step 6 uses it instead of
     downloading the GitHub release. Applies to this run only.
  4) Roll back — restore <node_dir>/grin.prev
  5) Purge the cargo build cache  (frees several GB)
  0) Back
```

| Key | What it does |
|-----|--------------|
| `1` | Asks for a git ref (branch, tag or commit; Enter = `staging`), checks disk and memory, installs the build tools and Rust if missing, checks out `/opt/grin/src/grin` and runs `cargo build --release`. The result is kept in `/opt/grin/bin/`. Then offers `2` or `3` |
| `2` | Installs a binary from `/opt/grin/bin/` into the installed node(s), keeping the old one as `<node_dir>/grin.prev` plus an archived copy in `/opt/grin/bin/`, then starts the node(s) |
| `3` | Meant to arm the binary for the next install (key `5`, `4` full reinstall or `A`) in this Script 01 session, instead of the GitHub download. It does not carry over at the moment: see the known problem below |
| `4` | Puts `grin.prev` back |
| `5` | Deletes the cargo `target/` cache. The next compile then takes much longer |

After the checkout, `1` offers the **toolkit's grin patches** (`scripts/patches/grin/` in the toolkit): fixes the toolkit carries until grin ships its own. At the time of writing they speed up the daily chain compaction that can freeze an archive node's API for hours, and log how long each compaction took. They are applied all-or-nothing; if one does not fit the chosen ref you can build plain upstream instead. A patched binary's name contains `-tkp<N>-` so it never passes for a release.

> **Warning:** A compile takes 20–45 minutes and needs about 5 GB of disk and 3 GB of RAM plus swap; the script warns below that and offers to add swap. Run it inside `tmux new -s grinbuild`, because a dropped SSH session kills the build. The patched build has not been compiled on a VPS yet.

> **Note:** `2` and `4` stop **every** running node, then start only the nodes they changed, with no pause between mainnet and testnet. `2` changes every installed node, so a node that was stopped before is started too. `4` changes only nodes that have a `grin.prev`: a node without one is stopped and **left stopped**, so start it again with Script 01 → `1`. A rollback uses up `grin.prev`, so a second `4` has nothing to restore.

> **Warning:** Known problem, read from the code: `3` (and the `3` offered after a compile) does not survive leaving the `G` menu. The menu runs each action in a separate process, so the armed binary is forgotten when you go back to the Script 01 menu, and the next install downloads the GitHub release as usual. Until this is fixed, build the node normally, then use `G` → `2` to swap in your compiled binary.

## After it finishes

Give the node a few minutes: a Grin node loads its chain into memory at start-up before it opens its ports and accepts peers. Then check it.

```bash
gtmux ls                                   # the node session(s)
gtmux attach -t grin_pruned_mainnet        # live output; Ctrl+B then D to detach
tail -f /opt/grin/node/mainnet-prune/grin-server.log
```

A healthy node's log shows the tip height advancing every minute or so and a stable count of peers. A JSON status check that does not need tmux:

```bash
cd /opt/grin/node/mainnet-prune
curl -s -u "grin:$(cat .api_secret)" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"get_status","params":[],"id":1}' \
  http://127.0.0.1:3413/v2/owner
```

Look for `"sync_status":"no_sync"` (grin's way of saying *synced*) and a `height` close to what a public explorer shows. For testnet use `testnet-prune` and port `13413`. **[Admin & Maintenance → Node Status & Sync](08-admin-maintenance.html#node-status-sync-key-5)** prints the same for every node.

Make sure inbound **3414** (mainnet) and **13414** (testnet) are open in your provider's firewall or security group, otherwise other nodes cannot reach yours and you only make outbound connections.

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/node/<network>-<mode>/grin` | The node binary (`grin.prev` beside it after an update or source install) |
| `…/grin-server.toml` | Node configuration (patched by the script; edit by hand only if you know grin's options) |
| `…/chain_data/` | The chain database: the thing the snapshot filled |
| `…/grin-server.log` | The node's own log; grin keeps 10 rotated files, and Super Auto adds daily rotation |
| `…/.api_secret`, `…/.foreign_api_secret` | Credentials for the node's Owner and Foreign APIs; copies live in `/opt/grin/keys/<network>/` |
| `/opt/grin/conf/grin_instances_location.conf` | Where each node is installed, read by every other script |
| `/var/lib/tor/grin-<network>-raw-tcp/` | The Tor hidden-service identity (`hostname` holds the `.onion` address) |
| `/opt/grin/logs/01_build_new_grin_node_<date>.log` | This run's log |
| `/usr/local/bin/gtmux`, `/usr/local/bin/grin-secret-sync` | Helpers: view node sessions; re-sync API secrets to consumers |
| `/opt/grin/bin/`, `/opt/grin/src/grin` | Compiled and replaced binaries; the source checkout for `G` |
| `/etc/sysctl.d/99-grin-node.conf`, `/swapfile` | Memory tuning and swap from step 2b |
| `/etc/logrotate.d/grin-node-<network>` | Log rotation (Super Auto only) |

### If you did not use Super Auto

The wizard offers autostart on reboot (step 14c) and the event recorder (step 14d). If you declined, add autostart later from **[Script 03](03-share-chain-data.html#g-and-h-start-the-node-on-reboot) → key `G` (Auto startup Grin node)**. The **sync watchdog** is installed from the mining hub, **[Script 07 → Solo mining → Watchdogs](07-mining-services.html#watchdogs-and-autostart)**, because it grew out of the solo-mining health checks; it protects any toolkit node, mining or not. Log rotation for `grin-server.log` is only set up by Super Auto.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Start a node after a stop | Script 01 → `1` *Start a node* (or let autostart do it after a reboot). With both networks stopped, start mainnet, let it finish booting, then start testnet |
| Stop a node | Script 01 → `2` *Stop a node*. If the sync watchdog is installed it restarts a stopped mainnet node within 5 minutes, so remove the watchdog first ([Script 07 → Solo mining → Watchdogs](07-mining-services.html#watchdogs-and-autostart)) if it must stay down |
| Update to a new Grin release | Script 01 → `3` *Update Grin binary*. Chain data is kept. Each node is stopped, gets the new binary and is started again only if it was running. With *both*, testnet waits 1000 seconds after mainnet (set `GRIN_STAGGER_SECS` in the environment to change it); keep the session open until it ends |
| Go back to the previous binary | Script 01 → `G` → `4` (restores `grin.prev`) |
| Fix a corrupted or stuck chain | Script 01 → `4` *Rebuild a node* → `1` *chain_data only*: fresh snapshot, same config, same secrets, same `.onion` |
| Switch pruned ↔ full | Script 01 → `4` → mainnet → `2` *full reinstall*, then pick the other mode at step 4 (the old directory is removed) |
| Add testnet next to mainnet | Script 01 → `5` *Install a node* |
| Run a fix that is only on grin's `staging` branch | Script 01 → `G` → `1`, then `2` to install it into your node(s) |
| Change the API secrets deliberately | `grin-secret-sync --rotate <network>` from a root shell, then restart the node |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `version 'GLIBC_2.38' not found` right after the build | The distribution is too old for the release binary. Reinstall on Ubuntu 24.04, or compile with `G`. Do not upgrade glibc by hand; see [Getting started](getting-started.html#what-you-need) |
| `lock file is held by another grin process` | Two copies of grin are pointed at the same `chain_data`, usually a node started by hand as root next to the toolkit's. Script 01 → `2` stops that network's node on both tmux servers, then `1` starts the right one |
| `Error loading config file: Permission denied` or the node exits at once after a manual start | Files in the node directory are owned by root because the node was once run as root. Start it from the menu (`1`): the launcher fixes ownership and runs it as `grin` |
| `Not available now: …` after pressing a key | The key cannot act in the current state, for example `5` when both networks are installed, or `1` when every node already runs. The reason is the dim text on that key's row |
| *cannot start — repair with 4) Rebuild a node* | The node directory lost its `grin` binary or `grin-server.toml`. Use `4` → that network → full reinstall; the API secrets and `.onion` identity are kept |
| `No fresh hosts in <zone> — trying all zones` | Every snapshot host in the chosen zone is older than the freshness limit or unreachable. The script carries on with all zones by itself |
| `All known sources are unavailable or have chain data older than 5 days` (70 for a full archive) | No host in any zone is fresh. Paste a custom base URL, or `0` and choose slow sync |
| `Insufficient disk space` in step 5, or the check fails in step 11 | Free space, or choose pruned instead of full. Old archives in `/opt/grin/node/*/` and `apt clean` are the usual quick wins; **[Admin & Maintenance → Disk cleanup](08-admin-maintenance.html#disk-cleanup-key-7)** does it from the menu |
| `Another instance of script 01 is already running` | Script 01 is open in another SSH session. Finish or close that one. If none exists, remove `/var/run/grin-toolkit-01.lock` |
| Both nodes are slow or one gets killed shortly after boot | A small VPS cannot boot two Grin nodes at once. Start one, wait until its height advances, then start the other. Check `free -m`: the swapfile from step 2b should be active. Or run only mainnet |
| `get_status` returns `401` | The secret in `.api_secret` does not match what the running node loaded, typically after editing the file while the node ran. Restart the node; the 5-minute `grin-secret-sync` timer keeps the consumers aligned |
| Height stops advancing | Wait ten minutes first: a node occasionally pauses while it verifies a batch. If it stays stuck, `4` → *chain_data only* rebuilds the chain data from a fresh snapshot |

## Related

- [Getting started](getting-started.html): requirements, install, how the menus work
- [Script 03](03-share-chain-data.html): share your chain snapshot, reboot autostart, scheduled tasks
- [Script 04](04-publish-node-api.html): publish the node API over HTTPS (and a public onion) for wallets and explorers
- [Script 07](07-mining-services.html): solo mining on this node, and the sync watchdog that protects any node
- [Script 08](08-admin-maintenance.html): node status screen, diagnostics and the event recorder, disk cleanup, self-update; [Back up and restore](089-backup-restore.html)
