---
title: Build or control a Grin node
description: How Script 01 installs a Grin node from a chain snapshot in under an hour, what each choice in its wizard means, and how to start, rebuild or update a node.
section: Scripts
order: 1
label: Script 01
covers: 2026-09-19
updated: 2026-09-20
---

Script 01 is the foundation of the toolkit: it puts a synced Grin node on the server, and every other script builds on that node. It is also the place you come back to for restarting a node, rebuilding a corrupted one, or updating the node binary.

## What it does

An ordinary Grin install syncs the chain from genesis over the peer network. That takes hours to days and, with the current PIBD (Parallel Initial Block Download) mechanism, sometimes stalls or loops. Script 01 avoids all of it:

1. Downloads the latest official `grin` release from GitHub and verifies its SHA256.
2. Generates the node configuration with grin's own `server config` command, then patches in the toolkit's standard paths and your choices.
3. Downloads a **pre-synced chain snapshot** from a community host, checking that the snapshot is fresh, and extracts it into the node directory.
4. Starts the node as the unprivileged `grin` user inside a tmux session, adds a Tor `.onion` mirror of its API, and re-points any already-installed services at the new node.

The result is a node at the current chain height within the time it takes to download a few gigabytes. When run through **Super Auto**, it also enables autostart on reboot, a sync watchdog and log rotation.

## Choices you will make

Whichever menu path you take, these are the decisions behind it. Read them once and the prompts make sense.

### Network: mainnet, testnet or both

**Mainnet** is the real Grin network. **Testnet** is a separate chain of worthless test coins, useful for rehearsing wallet and mining setups. A server can host at most one node per network. Choosing **Both** builds mainnet first, then testnet, each in its own directory with its own binary.

### Mode: pruned or full archive

| | Pruned | Full archive |
|--|--------|--------------|
| Keeps | The full header chain and every kernel; block *bodies* only for recent blocks | Everything since genesis |
| Disk needed | About 10 GB free (a few GB of chain data plus room to grow) | 25 GB free and growing |
| Good for | Running a node, wallets, mining, the public API, the [stats dashboard](06-global-health.html) | Serving old blocks: the [GrinScan](06b-grinscan.html) explorer, sharing full snapshots |
| Available on | Mainnet and testnet | Mainnet only |

Pruned is the default and the right choice unless you know you need old block bodies. A pruned node is a fully validating node — it verifies every block, it just does not keep all of them. The two modes use different directories (`mainnet-prune` and `mainnet-full`); switching one to the other rebuilds the node and removes the other variant's directory.

### Chain data source

| Option | What happens | When to use it |
|--------|--------------|----------------|
| **On-the-fly** (default) | Streams the snapshot from the host straight into `tar`. Nothing is stored beside the extracted data, and the script switches host automatically if the download breaks | Almost always — it is the fastest and needs the least disk |
| **Full download** | Saves the `.tar.gz` to disk first (resumable), verifies its SHA256, checks free space, then extracts | When your connection is unreliable and you want a resumable download |
| **Slow sync** | No snapshot at all. The node starts with an empty `chain_data/` and syncs from genesis over P2P, exactly as a stock Grin install would | Only when no snapshot host is fresh or reachable. Takes hours to days |

For the first two options you also pick a **download zone** — America, Asia, Europe or Africa. The script loads the community host list from `extensions/grinmasternodes.json`, probes every host in the zone for a snapshot that is recent enough (**5 days** for a pruned snapshot, **70 days** for a full archive) and uses the freshest, with the others as fallbacks. If the zone has no fresh host it falls back to America, and if that fails too it offers a custom URL or a return to the menu.

> **Note:** The snapshot is a convenience, not a trust decision you are stuck with. The node validates the data it receives from peers from that point on; a bad snapshot would simply fail to sync. Once your own node is synced you can share your own snapshot with [Script 03](03-share-chain-data.html) and become one of the hosts.

## The Step 1 menu

Script 01 starts with a **Process & Port Check**: it looks for running Grin processes, occupied ports (3413, 3414, 13414, 3415) and nodes already installed on disk. The menu it shows depends on what it finds — three different situations, three different menus.

### A fresh server (nothing installed)

```text
  A) 🚀 Super Auto — install both nodes (mainnet + testnet, pruned) + autostart/watchdog/logrotate
  1) Custom wizard — pick network / mode / source yourself  (default)
  G) Compile binary from source first  (staging / any branch or tag)
  0) Return to main menu
```

| Key | Action |
|-----|--------|
| `A` | [Super Auto](#super-auto) — the one-key path. Both networks, pruned, snapshot streamed from the fastest host, then autostart + watchdog + log rotation. Recommended for a first node |
| `1` | The [custom wizard](#the-custom-wizard-step-by-step): choose network, mode and source yourself |
| `G` | Build the `grin` binary from a git branch or tag before installing — for a system whose glibc is too old for the release binary, or to pick up a fix on upstream's `staging` branch |
| `0` | Back to the main menu |

### Nodes installed but not running

```text
  A) 🚀 Super Auto — WIPE ALL & rebuild both (pruned) + autostart/watchdog/logrotate
  K) Kill all conflicting processes and continue
  C) Continue anyway with warning only (if processes are unrelated to Grin)
  S) Start installed node (no rebuild — try this first)
  R) Rebuild chain_data only  — for corrupted chain (preserves config + .onion + secrets)
  G) Compile binary from source  (staging / any branch or tag)
  N) Abort  (resolve manually)
  0) Return to main menu
  Enter) Recheck
```

| Key | Action |
|-----|--------|
| `S` | **Start the installed node** — the normal way to bring a node back after a reboot or a stop. Try this first |
| `R` | Re-download the chain snapshot into the existing node, keeping its config, API secrets and Tor identity. Use it when the node reports a corrupted or stuck chain |
| `K` | Stop whatever is holding the ports and continue into a new build |
| `C` | Ignore the conflict and continue — only if you are sure the process on the port is not Grin |
| `A` | Super Auto, which here **deletes every installed node** first (it lists what will go and asks for confirmation) |
| `N` | Abort and sort it out by hand |
| `Enter` | Re-run the check, for example after stopping something in another terminal |

### Nodes running

When a node already occupies its port the menu turns into a control panel for it:

```text
  A — 🚀 Super Auto  ⚠ WIPE ALL & rebuild both (pruned) + autostart/watchdog/logrotate
  B — update binary only  (no chain rebuild; restarts mainnet, then testnet 1000s later)
  G — compile binary from source  (staging / any branch or tag)
  M — kill mainnet  & rebuild mainnet
  T — kill testnet  & rebuild testnet
  K — kill all Grin processes & rebuild both networks
  0 — return to master script
```

| Key | Action |
|-----|--------|
| `B` | **Update the node binary** to the latest release without touching chain data. The node is restarted; with both networks installed, testnet restarts 1000 seconds after mainnet so the two never boot at once |
| `M` / `T` | Stop and rebuild one network, leaving the other running |
| `K` | Stop both and rebuild both |
| `1` / `S` | With only one network running, the free slot is offered: `1` installs the other network alongside, or `S` starts it if it is already on disk |

## Super Auto

Super Auto is the answer to "just give me a working node". One key, no further questions except a confirmation, and well under an hour later both networks are running and hardened. It will:

- Build **mainnet-prune** and **testnet-prune** with the chain snapshot streamed on-the-fly from the fastest fresh host across all zones.
- Enable **autostart on reboot** (a cron `@reboot` entry: mainnet starts 5 seconds after boot, testnet 1000 seconds later so they never compete for the disk).
- Install the **sync watchdog**, a cron job every 5 minutes that restarts a node that is down, or whose height has stopped advancing while public height references keep moving.
- Set up **log rotation** for `grin-server.log`.
- Publish a **Tor `.onion` mirror** of each node's API.

It needs **20 GB free** on the filesystem holding `/opt/grin/node` and refuses to start with less.

> **Danger:** Super Auto is **destructive on a server that already has a node.** It kills every Grin process and deletes the binaries and `chain_data` of *both* networks before rebuilding — and it only ever builds *pruned* nodes, so a full archive would be gone. The script lists exactly what it will remove and asks for confirmation (twice when an archive is at stake). Wallets are not touched, but if you have anything on the box you are not sure about, use the custom wizard instead.

## The custom wizard, step by step

Pick `1` on a fresh server (or reach it through `K`/`M`/`T`) and the script runs a pipeline of numbered steps. It prints each step's header as it goes, so you can follow along.

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | Process & port check (the menu above). Also detects a legacy `~/.grin` directory from a manual install and offers to delete it — recommended, it can shadow the toolkit's config | Choose a path |
| 2 | Updates the package index and upgrades the system, then installs what is missing: `tar openssl tmux jq tor curl wget sqlite3 rsync cron`. Adds a swapfile (2 GB, or 4 GB when RAM is under 2 GB) and tunes swappiness so the node's memory-heavy start-up is not OOM-killed | Wait |
| 3 | Network selection | `1` mainnet, `2` testnet, `3` both |
| 4 | Archive mode | `1` pruned, `2` full (mainnet only) |
| 5 | Prepares the node directory — `/opt/grin/node/<network>-<mode>` — and checks free disk (10 GB pruned, 25 GB full). **Any existing files in that directory are removed without asking**, because the directory belongs to the node being built | Nothing |
| 6 | Downloads the latest `grin` release for linux-x86_64 from GitHub and verifies it. With *Both*, it is downloaded once and copied to each node | Wait |
| 7 | Runs `./grin server config` (`--testnet` for testnet) so grin writes its own default `grin-server.toml` with the right chain type and ports | Nothing |
| 8 | Patches the config: archive mode, absolute paths for `chain_data`, the log and both API secret files; sets peer limits | Nothing |
| 8b | Ensures `.api_secret` and `.foreign_api_secret` exist, restored from the vault at `/opt/grin/keys/<network>/` if this is a rebuild, otherwise generated and saved there | Nothing |
| 8c | Creates the `grin` system user and gives it ownership of `/opt/grin` | Nothing |
| 9 | Chain data source: transfer mode, then zone and host discovery | Pick `1` on-the-fly, `2` full download or `3` slow sync; then a zone |
| 10–12 | *Full download only:* SHA256 check of the archive, a free-space check (archive size × 1.2), extraction, then deletion of the archive | Confirm removal of an old `chain_data/` if one exists |
| 13 | Starts the node: `./grin server run` inside a tmux session named `grin_pruned_mainnet` (or `grin_full_mainnet`, `grin_pruned_testnet`), as the `grin` user, on the `grin` user's tmux socket. Any stale session with that name and any leftover grin process for the directory is cleaned up first | Nothing |
| 13b | Writes a Tor hidden-service config for the node's API and reloads Tor. The `.onion` address is printed and is preserved across rebuilds | Nothing |
| 14 | Summary: network, mode, directory, tmux session, elapsed time, log file. Then re-syncs the API secrets to every installed consumer and installs the 5-minute self-heal timer | Read it |

With *Both* selected, steps 4–14 run for mainnet and then repeat for testnet, with a 1000-second pause before the testnet node starts (set `GRIN_STAGGER_SECS` in the environment to change it).

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

Look for `"sync_status":"no_sync"` — grin's way of saying *synced* — and a `height` close to what a public explorer shows. For testnet use `testnet-prune` and port `13413`. **[Admin & Maintenance → Node Status & Sync](08-admin-maintenance.html#node-status-sync-key-5)** prints the same for every node.

Make sure inbound **3414** (mainnet) and **13414** (testnet) are open in your provider's firewall or security group, otherwise other nodes cannot reach yours and you only make outbound connections.

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/node/<network>-<mode>/grin` | The node binary |
| `…/grin-server.toml` | Node configuration (patched by the script; edit by hand only if you know grin's options) |
| `…/chain_data/` | The chain database — the thing the snapshot filled |
| `…/grin-server.log` | The node's own log, rotated by logrotate when Super Auto set it up |
| `…/.api_secret`, `…/.foreign_api_secret` | Credentials for the node's Owner and Foreign APIs; copies live in `/opt/grin/keys/<network>/` |
| `/opt/grin/conf/grin_instances_location.conf` | Where each node is installed — read by every other script |
| `/var/lib/tor/grin-<network>-raw-tcp/` | The Tor hidden-service identity (`hostname` holds the `.onion` address) |
| `/opt/grin/logs/01_build_new_grin_node_<date>.log` | This run's log |
| `/usr/local/bin/gtmux`, `/usr/local/bin/grin-secret-sync` | Helpers: view node sessions; re-sync API secrets to consumers |

### If you did not use Super Auto

The custom wizard starts the node but does not make it survive a reboot. Add that from **[Script 03](03-share-chain-data.html#g-and-h-start-the-node-on-reboot) → key `G` (Auto startup Grin node)**, which installs the same `@reboot` entry Super Auto uses. The **sync watchdog** is installed from the mining hub — **[Script 07 → Solo mining → Watchdogs](07-mining-services.html#watchdogs-and-autostart)** — because it grew out of the solo-mining health checks; it protects any toolkit node, mining or not. Log rotation for `grin-server.log` is only set up by Super Auto.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Start a node after a reboot or stop | Script 01 → `S` (or let autostart do it) |
| Stop a node | Attach with `gtmux attach -t <session>` and press Ctrl+C. There is no separate stop action in the menu — and if the sync watchdog is installed it will restart a stopped node within 5 minutes, so remove the watchdog first ([Script 07 → Solo mining → Watchdogs](07-mining-services.html#watchdogs-and-autostart)) if you want it to stay down |
| Update to a new Grin release | Script 01 → `B`. Chain data is kept; the node restarts on the new binary |
| Fix a corrupted or stuck chain | Script 01 → `R` — fresh snapshot, same config, same secrets, same `.onion` |
| Switch pruned ↔ full | Script 01 → `M` and pick the other mode in step 4 (the old directory is removed) |
| Add testnet next to a running mainnet | Script 01 → `1` when the free-slot menu offers it |
| Run a fix that is only on grin's `staging` branch | Script 01 → `G`, choose the branch, then continue the build; step 6 uses your compiled binary instead of the release |
| Change the API secrets deliberately | `grin-secret-sync --rotate <network>` from a root shell, then restart the node |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `version 'GLIBC_2.38' not found` right after the build | The distribution is too old for the release binary. Reinstall on Ubuntu 24.04, or rebuild with `G` (source build). Do not upgrade glibc by hand — see [Getting started](getting-started.html#what-you-need) |
| `lock file is held by another grin process` | Two copies of grin are pointed at the same `chain_data`, usually a node started by hand as root next to the toolkit's. Script 01 → `K` stops everything on both tmux servers, then `S` starts the right one |
| `Error loading config file: Permission denied` or the node exits at once after a manual start | Files in the node directory are owned by root because the node was once run as root. Start it from the menu (`S`): the launcher fixes ownership and runs it as `grin` |
| "No fresh hosts in zone" | Every snapshot host in the zone is older than the freshness limit or unreachable. Accept the fallback to America, try another zone, paste a custom base URL, or choose slow sync |
| Disk check fails in step 5 or 11 | Free space, or choose pruned instead of full. Old archives in `/opt/grin/node/*/` and `apt clean` are the usual quick wins; **[Admin & Maintenance → Disk cleanup](08-admin-maintenance.html#disk-cleanup-key-7)** does it from the menu |
| Both nodes are slow or one gets killed shortly after boot | A small VPS cannot boot two Grin nodes at once; that is why testnet starts 1000 seconds after mainnet. If it still happens, check `free -m` — the swapfile from step 2 should be active — or run only mainnet |
| `get_status` returns `401` | The secret in `.api_secret` does not match what the running node loaded — typically after editing the file while the node ran. Restart the node; the 5-minute `grin-secret-sync` timer keeps the consumers aligned |
| Height stops advancing | Wait ten minutes first — a node occasionally pauses while it verifies a batch. If it stays stuck, `R` rebuilds the chain data from a fresh snapshot |

## Related

- [Getting started](getting-started.html) — requirements, install, how the menus work
- [Script 03](03-share-chain-data.html) — share your chain snapshot, reboot autostart, scheduled tasks
- [Script 04](04-publish-node-api.html) — publish the node API over HTTPS for wallets and explorers
- [Script 07](07-mining-services.html) — solo mining on this node, and the sync watchdog that protects any node
- [Script 08](08-admin-maintenance.html) — node status screen, disk cleanup, self-update; [Back up and restore](089-backup-restore.html)
