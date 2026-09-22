---
title: Share your chain data with the community
description: How Script 03 packs your node's chain data into a snapshot, publishes it on your nginx host on a schedule, mirrors it over SSH and adds reboot autostart.
section: Scripts
order: 3
label: Script 03
covers: 2026-09-19
updated: 2026-09-20
---

Script 03 is how a node becomes a **snapshot host**: it packs the node's `chain_data` folder into a `.tar.gz`, writes it into the web folder Script 02 set up, and does it again on a schedule so the snapshot never goes stale. Other people's Script 01 then downloads from you. The same script also holds three small scheduling chores that any node benefits from — starting the node on reboot, cleaning up state-sync leftovers, and copying the finished archive to mirror servers.

You need a **synced** node from [Script 01](01-build-node.html) and, for publishing, the matching domain from [Script 02](02-nginx-fileserver.html). The reboot autostart (key `G`) needs neither.

> **Warning:** Producing a snapshot **stops the node** for as long as the compression takes, and everything that depends on the node — the public API, a wallet listener, the explorer, the stats collector, a mining pool — is interrupted with it. The node is restarted automatically at the end. Plan for the node being down for tens of minutes: a full archive took 20–40 minutes with the old single-threaded compressor and now uses every core, and a pruned snapshot is a few GB and finishes far sooner; the exact time depends on your CPU and disk. Pick a schedule time when nobody minds.

## What it does

For each network you share, one run of the pipeline:

1. Finds the running node on its P2P port (3414 or 13414), reads its `grin-server.toml` to learn the network, whether it is pruned or archive, and where `chain_data` is, and records that in `/opt/grin/conf/grin_instances_location.conf`.
2. Verifies the node is **fully synced** — the Owner API's `get_status` must say `no_sync`, or `grin client status` must; either passing is enough. An unsynced node is never snapshotted.
3. Checks that the web folder's disk can hold the new archive (chain size × an estimated ratio + 512 MiB headroom). If there is room for the old and the new archive, the old one **keeps serving during the build**; if not, it is removed first; if there is room for neither, the run aborts before anything is touched.
4. Stops the node (SIGTERM, up to 120 s, then SIGKILL), deletes `txhashset_snapshot_*.zip` files from `chain_data` (multi-gigabyte leftovers the node creates when other nodes state-sync from it), and writes a status note telling visitors not to download yet.
5. Compresses `chain_data` with `tar` piped into **pigz** (parallel gzip, installed on demand; plain gzip if it cannot be) at low CPU and IO priority, into a hidden temporary file, then computes the SHA256 and **swaps** the new archive, checksum, `README.txt` and `chaindata.json` manifest into place in one move — so a downloader never sees a half-written file.
6. Hands the files to the web user and **restarts the node** as the `grin` user in its tmux session — on the failure path too, so a compression that dies never leaves the node down.

The output in the web folder is `grin_pruned_mainnet_20260919.tar.gz` (or `grin_full_mainnet_…`, `grin_pruned_testnet_…`), its `.sha256`, `README.txt` with download instructions, `check_status_before_download.txt` and `chaindata.json`. Script 01 reads the manifest first and the file list as a fallback.

> **Note:** The pipeline sets the server's timezone to **UTC** on every run, without asking. Every snapshot host is kept on one clock so the archive's timestamps — which other servers use to judge whether your snapshot is fresh — mean the same thing everywhere.

## Before you start

| You need | Why |
|----------|-----|
| A running, synced node | Both the setup (key `A`) and the pipeline look for a live process on the P2P port. A node that is still syncing fails the sync check and nothing is published |
| A Grin domain from Script 02 | Key `A` reads the nginx sites to find `/var/www/fullmain`, `/var/www/prunemain` or `/var/www/prunetest`; with none configured it sends you to Script 02 |
| Free disk on the web folder's partition about the size of `chain_data` | The archive compresses only a little (the chain is mostly cryptographic data). The pre-flight check refuses to start a run that cannot finish |
| `cron` installed | Every schedule on this menu is a root crontab entry. Script 01 installs `cron`; the script says so if `crontab` is missing |
| For mirrors: a second server with SSH access | Optional. The remote-copy feature pushes the finished archive to other hosts over `rsync`; the key setup is guided |

## The menu

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 03) Grin Node Share & Schedule Manager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Note that sharing script below will stop your Grin node
 and interrupt addons services like Grin API/wallet/explorer/health/mining...
 Grin process must be running to let the script schedule jobs for you.
Current Grin share schedule(s) in crontab:

  No Grin share cron jobs found.

Options:

  A) Create Nginx config        [not configured]
  B) Share chain data now! [depends on A]

  C) Remote copy setup          [not configured]  (mirrors, keys, schedule)
  D) Copy to mirrors now        [depends on A + C]  (node keeps running)

  E) Schedule to share chain data
  F) Disable to share chain data

  G) Auto startup Grin node
  H) Disable auto startup Grin node

  I) Auto-delete txhashset snapshots  (schedule cleanup cron)
  J) Compression benchmark            (picks the level; node keeps running)

  → Want to become Grin Master Node? Contribute your sub.domain to the registry:
    extensions/grinmasternodes.json  (see README.md for details)

  0) Back to master script

Select [A-J / 0]:
```

The block under the banner lists every toolkit cron line currently installed — share schedules, autostart entries, cleanup and copy jobs — so the menu doubles as the place to see what is scheduled.

| Key | Action |
|-----|--------|
| `A` | [Detect nodes and domains](#a-create-the-share-configuration) and save which networks to share. Required once before `B` or `E` |
| `B` | [Run the pipeline now](#b-share-chain-data-now) for mainnet, testnet or both — stops the node |
| `C` | [Set up mirrors](#c-and-d-mirrors-over-ssh): SSH key, remote hosts, copy schedule |
| `D` | Push the current archive to every enabled mirror now — the node keeps running |
| `E` | [Schedule the pipeline](#e-schedule-the-snapshot) — one cron line per network, staggered |
| `F` | Remove the share schedule for all networks, or one |
| `G` | [Start the node on reboot](#g-and-h-start-the-node-on-reboot) |
| `H` | Remove the reboot entry |
| `I` | [Schedule cleanup](#i-clean-up-txhashset-snapshots) of the node's own state-sync zips |
| `J` | [Benchmark](#j-compression-benchmark) compression levels on a sample of your chain data — read-only |
| `0` | Back to the main menu |

## A) Create the share configuration

`A` asks nothing you could get wrong. It scans both P2P ports, prints what it found — network, pruned or full, the `chain_data` path and size, free disk on `/` and `/var/www` — then reads `/etc/nginx/sites-enabled/` for the Grin domains Script 02 created and pairs each with its node.

| Situation | What the script does |
|-----------|----------------------|
| No node on either port | Asks you to start one and press Enter to retry, or `0` to cancel |
| A domain exists for a network whose node is not running | Stops with *Nginx has a mainnet domain configured but no mainnet node is running* — start it with Script 01 → `S` and run `A` again |
| No Grin domain at all | Sends you to Script 02 |
| Domains for both networks | Asks *Which networks to share?* — `1` both (default), `2` mainnet only, `3` testnet only |
| A domain for one network | Selects it automatically |

The result is saved to `/opt/grin/conf/grin_share_nginx.conf`: the networks chosen, the web folder per node, the web user that will own the files, and the 120-second stop timeout. Re-run `A` whenever you add a domain or a node.

## B) Share chain data now

`B` runs the pipeline immediately. With both networks configured it first asks which to run — `1` mainnet only, `2` testnet only, `3` both (mainnet first, then testnet, never at the same time) — then warns once more and asks `Continue? [Y/n/0]`.

Progress is printed step by step and written to `/opt/grin/logs/share_nginx_<network>_<type>_<date>.log`. The steps are numbered 0a (disk pre-flight), 0 (clear old files), 1 (stop node), 2 (delete txhashset zips), 3 (peer list kept on purpose — it gives downloaders working peers if the DNS seeds are down), 4 (status: in progress), 5 (compress + swap), 6 (README), 7 (manifest + status: completed), 8 (ownership), 9 (restart node).

The first run is the one to watch. Do it with `B` before you schedule anything, and read the summary line at the end: `Nginx share complete: mainnet / pruned → local: /var/www/prunemain`.

## After a run

```bash
# archive, .sha256, README, manifest and status note are all there
ls -lh /var/www/prunemain/
# "Sync completed. You may download the pruned mainnet archive. …"
cat /var/www/prunemain/check_status_before_download.txt
# the manifest: name, size, sha256 and the build time others judge freshness by
curl -s https://prunemain.yourdomain.com/chaindata.json
# the node is back in its session
gtmux ls
```

The proof that everything works end to end is Script 01 on another machine: run it, pick your zone, and your hostname should appear among the fresh hosts once you are in the registry — or paste `https://prunemain.yourdomain.com` as a custom URL.

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/conf/grin_share_nginx.conf` | The share configuration from `A` |
| `/opt/grin/conf/grin_instances_location.conf` | Where each node lives — refreshed on every run, and used to find a node that is not running |
| `/var/www/<site_key>/grin_<type>_<network>_<date>.tar.gz` + `.sha256` | The snapshot and its checksum |
| `/var/www/<site_key>/chaindata.json` | Manifest: archive name, size, SHA256, build time. Present only when the archive is complete |
| `/var/www/<site_key>/check_status_before_download.txt` | Human-readable status; *Sync completed.* is the phrase other tools look for |
| `/var/www/<site_key>/README.txt` | Download and install instructions, for Linux, Windows and the Grim wallet |
| `/opt/grin/logs/share_nginx_*.log`, `cron_nginx.log`, `schedule.log` | Per-run logs, the cron job's log, and a log of every schedule change |
| root crontab entries tagged `# grin-node-toolkit: …` | Every schedule this menu installs; `crontab -l` shows them |

## E) Schedule the snapshot

`E` installs **one cron line per network**, so mainnet and testnet never stop-and-compress at the same time. It asks for the cron log path (default `/opt/grin/logs/cron_nginx.log`), then for each network shows a preset list. Times are UTC.

For a **pruned** node:

```text
  1) Mon & Thu at 00:00  (0 0 * * 1,4)  [Default — fixed]
  2) 3x/week — Tue, Thu, Sat at 13:42  (42 13 * * 2,4,6)  [random]
  3) Daily at 13:42  (42 13 * * *)  [random]
  4) 2x/week — Tue, Sat at 13:42  (42 13 * * 2,6)  [random]
  0) Cancel / skip this network
```

Testnet's fixed default is **Tue & Fri at 06:00** so it never coincides with mainnet's. Presets 2–4 draw a random time and random days each time the menu opens, which is what spreads the load between networks and between hosts.

For a **full archive** node the presets are rarer, because the archive is ~20 GB and the node is down for the whole compression: the default is the **1st and 15th at 00:00**, then biweekly or monthly at a random time, and a twice-weekly option marked *heavy*.

> **Warning:** Keep the cadence inside what downloaders accept. Script 01 on other servers skips a **pruned** snapshot older than **5 days** and a **full** archive older than **70 days** — a pruned node cannot use a snapshot beyond the chain's cut-through horizon, so a stale one wastes the whole download. The fixed defaults and the daily and three-times-a-week presets stay inside those limits. The **twice-weekly** preset can leave a six-day gap when the two random days it draws are adjacent (Mon & Tue, say) — check the days it shows before accepting, or pick again. A cron line written by hand is your own responsibility.

`F` removes the schedule for both networks (default), or mainnet or testnet alone. The cron lines are tagged `grin_share_nginx_main` / `grin_share_nginx_test`; the job runs `bash …/03_grin_share_chain_data.sh --cron-nginx-main` (or `-test`), and if the node is not running when the job fires it tries to start it first.

## C and D) Mirrors over SSH

One box can only serve so much bandwidth. The remote-copy feature pushes the **finished archive** — never the raw chain data — from your web folder to other servers with `rsync` over SSH, so several hosts publish the same snapshot while only one of them ever stops its node. A mirror needs nothing but nginx (Script 02) and SSH access; it does not need a node.

`C` opens its own menu, in the order you should do things:

```text
  Set up a mirror — in this order
  1) SSH access — create a key, install it on the mirror, verify
  2) Add a mirror — do 1 for that host first
  3) Test every configured mirror (connection + identity)

  Manage
  4) Enable / disable a mirror
  5) Remove a mirror
  6) Schedule the copy (N hours after the build)
  7) Remove a copy schedule

  0) Back
```

- **SSH access (1)** creates a dedicated key, `/root/.ssh/grin_share_ed25519`, on *this* server, installs its public half on the mirror (automatically with `ssh-copy-id`, which prompts for the mirror's password in your terminal — the script never reads it — or manually with commands it prints for you to run *on the mirror*), then verifies a password-less login. Every prompt says which machine the step belongs on.
- **Add a mirror (2)** asks which archive it serves (`fullmain` / `prunemain` / `prunetest`), a short name, `user@ip`, port, key path, the remote folder (default `/var/www/<site_key>`) and an optional bandwidth cap in KB/s, then tests the connection. Mirrors are stored one per line in `/opt/grin/conf/grin_share_targets.conf`.
- **Schedule the copy (6)** does not ask for a second clock: it takes the build schedule from `E` and adds the offset you give (default 3 hours), refusing an offset that would cross midnight. The job — `--cron-remote <site_key>`, logged to `/opt/grin/logs/cron_remote.log` — is safe to fire when nothing changed: a mirror that already holds the current build is skipped, and a copy that overlaps a build notices the archive changed under it and stops rather than publish a mixed set.

`D` runs the copy right now for every enabled mirror, with a `Force re-upload? [y/N]` option for a mirror that was wiped. Copies are logged to `/opt/grin/logs/remote_<site_key>_<date>.log`, and if the Provider Access Watch (Admin & Maintenance) has an alert channel set up, a failed scheduled copy is reported there.

`rsync` verifies every file it transfers; a separate SHA256 pass over the 17–20 GB archive is off by default to spare the disk (`RC_VERIFY_LOCAL` / `RC_VERIFY_REMOTE` turn it on). The `.sha256` travels with the archive either way.

## G and H) Start the node on reboot

A node started by the custom wizard in Script 01 does not come back after a reboot. `G` fixes that with a root `@reboot` crontab entry — **the same entry Super Auto installs**, so the two never fight.

Choose `1` mainnet, `2` testnet or `3` both. For each, the script finds the node — the running process, or the installed directory (`/opt/grin/node/mainnet-full`, `mainnet-prune`, `testnet-prune`) if it is stopped — and asks for a **boot delay**: default **5 seconds** for mainnet, **1000 seconds** (about 17 minutes) for testnet, because a small VPS cannot boot two Grin nodes at once and mainnet's start-up must be over before testnet begins. The entry then starts the node the right way: as the `grin` user, in its tmux session (`grin_pruned_mainnet` and so on), after fixing file ownership. The `gtmux` viewer is installed at the same time.

If an entry already exists you are asked whether to replace it. `H` lists the entries present and removes one or both.

> **Tip:** Autostart brings a node back after a reboot; it does not notice a node that has *crashed* while the server stayed up. That is the sync watchdog's job — installed from **[Script 07 → Solo mining → Watchdogs](07-mining-services.html#watchdogs-and-autostart)**, and useful on any node.

## I) Clean up txhashset snapshots

When another node performs a state sync from yours, your node writes a `txhashset_snapshot_<height>.zip` into `chain_data` to serve it, and never deletes it. On a busy public node these add up to gigabytes. The share pipeline removes them before every compression; `I` schedules a standalone sweep as well — every **4 hours** (default), 12 or 24 — across all three standard node directories, logged to `/opt/grin/logs/cron_clean_txhashset.log`. The node keeps running; the zips are not part of the chain.

## J) Compression benchmark

Compression level is a trade-off: chain data is mostly cryptographic material and barely compresses, so a full archive is packed at level 1 (fast) and a pruned snapshot, downloaded far more often, at level 6. `J` lets you check that on your own data: it compresses a sample (default 400 MB) of the largest files at several levels and prints ratio and time for each, without stopping the node or writing to the web folder. It prints ratio, seconds and MB/s per level and a projected archive size. If the numbers say a different level is worth it, set `COMPRESS_LEVEL_FULL=…` or `COMPRESS_LEVEL_PRUNED=…` as a `NAME=value` line at the top of the root crontab (`crontab -e`), which applies to the scheduled job; `COMPRESS_THREADS=…` caps how many cores the compressor takes so other services keep some.

## Join the community registry

Once your host has served its first snapshot, add it to the list Script 01 picks download hosts from:

1. Fork the [toolkit repository](https://github.com/noobvie/Grin-Node-Toolkit) and open `extensions/grinmasternodes.json`.
2. Add your hostname under your **zone** (`america`, `asia`, `europe`, `africa`) and **site key** — `prunemain.yourdomain.com` goes in the `prunemain` list, and so on.
3. Add a `_contacts` entry keyed by your base domain (`yourdomain.com`) with an owner name and a way to reach you — used to tell you if your host goes stale.
4. Open a pull request.

Every listed host is checked by the toolkit's remote node monitor (**[Admin & Maintenance → Remote Node Manager](08-admin-maintenance.html#remote-node-manager-key-1)**, script 081): reachable over HTTPS, archive no older than the limit for its site key (5 days pruned, 70 days full), and the status note reading *Sync completed.* Keep your schedule inside those limits and your host stays in rotation.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| See what is scheduled | Open Script 03 — the menu banner lists every toolkit cron line; or `crontab -l` |
| Publish a fresh snapshot right now | Script 03 → `B` (the node stops for the duration) |
| Change the snapshot schedule | Script 03 → `E` again — it replaces the existing line for that network |
| Stop sharing but keep the site | Script 03 → `F`. The last archive stays online and ages out of the registry check by itself |
| Stop sharing and take the site down | `F` here, then Script 02 → `4` |
| Add a second server as a mirror | Script 03 → `C` → `1`, `2`, `3` in that order, then `6` to schedule |
| Make a node survive reboots | Script 03 → `G` |
| Check the last scheduled run | `tail -50 /opt/grin/logs/cron_nginx.log`, then the per-run `share_nginx_*.log` it names |
| Read how the snapshot is built and why | [Script 03 design](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script03_design.md) in the repository |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Nginx not configured. Run option A first.` | `B` and `E` need the configuration `A` writes. Run `A` |
| `No Grin domains configured in nginx` | Script 02 has not created a `fullmain`/`prunemain`/`prunetest` site yet |
| `Nginx has a mainnet domain configured but no mainnet node is running` | `A` insists every configured network has a live node. Script 01 → `S`, wait for it to open its ports, retry |
| `SYNC CHECK FAILED — BACKUP ABORTED` | The node is not at the chain tip (API `sync_status` ≠ `no_sync` and `grin client status` agrees). Nothing was stopped or deleted. Wait for the sync to finish — a fresh node needs a few minutes even from a snapshot |
| `not enough space on … even after reclaiming` | The web folder's partition cannot hold the new archive. Nothing was touched and the node was not stopped. Free space, or move the site to a bigger disk |
| The log says `SKIPPED mainnet: nothing listening on port 3414 and no usable entry in …` | A scheduled run found no node and could not start one. Start it with Script 01 → `S` and check `G` autostart is in place |
| `compression failed (tar=N compressor=M) — partial archive removed` | Usually the disk filled mid-run or an IO error. The previous archive is untouched and the node was restarted. Check `df -h` and the per-run log |
| `Grin did not start within 5s — check: gtmux attach -t …` | The restart at step 9 is slow on a small box rather than failed. `gtmux ls` a minute later; if the session is gone, Script 01 → `S` |
| Status file says *DO NOT download* long after the run should have ended | A run died before step 7. `gtmux ls` to confirm the node is up, then `B` again; the pipeline overwrites the note on success |
| `crontab unavailable — install cronie/cron and retry` | `apt install cron` (Ubuntu/Debian) or `dnf install cronie` (Rocky/Alma), then rerun |
| Copy to a mirror fails with a permission or connection error | Script 03 → `C` → `3` tests every mirror. Redo `1` step 3 (verify) for that host; the key must be installed for the exact `user@ip` the mirror line uses |
| `an offset of Nh from H:00 crosses midnight` | The copy would land on the next calendar day and cron's day-of-month field cannot follow. Use a smaller offset, or schedule the build earlier in the day |

## Related

- [Script 01](01-build-node.html) — builds the node; its `_max_age` rules decide which snapshot hosts downloaders trust
- [Script 02](02-nginx-fileserver.html) — the web host this script publishes into, and its rate caps and landing page
- [Script 07](07-mining-services.html#watchdogs-and-autostart) — the sync watchdog that restarts a stuck node, next to solo mining
- [Script 08](08-admin-maintenance.html) — the [remote node monitor](08-admin-maintenance.html#remote-node-manager-key-1) that checks every registry host, and the [Provider Access Watch](08-admin-maintenance.html#provider-access-watch-key-2) alert channel used by mirror copies
