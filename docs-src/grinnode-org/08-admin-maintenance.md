---
title: Admin and maintenance
description: Script 08: node status, diagnostics and an event recorder, a fleet monitor, host-tamper alerts, tuning advice, nginx extras, SSH hardening, cleanup, updates.
section: Scripts
order: 8
short: Admin
label: Script 08
covers: 2026-11-06
updated: 2026-11-06
---

Script 08 is the operations toolbox. Nothing here installs a Grin product; everything here keeps the server that runs them healthy, watched and up to date. It is also home to the two things every operator eventually needs — [backups](089-backup-restore.html) and the [full uninstall](#full-grin-cleanup-key-del).

If you are new, learn one screen first: **Node Status & Sync** (key `5`). It answers "is my node running, and is it caught up?" for both networks without any typing. When the answer is "no, and I don't know why", the next screen is **Diagnostics & Support** (key `6`).

## The menu

Hub 08 is the one hub where the key *is* the script number: each numbered sub-script sits on its last digit (081 → `1`, 082 → `2`, 083 → `3`, 084 → `4`, 086 → `6`, 089 → `9`) and the un-numbered built-in screens fill the gaps (`5`, `7`, `8`), with one more on the letter `E`. These keys are stable and this page uses them.

```text
  Monitoring & Host
  1)   Remote Node Manager       monitor · mass deploy · remote control
  2)   Provider Access Watch     host-tamper detection + off-box alerts
  3)   Host Optimization & Hard. profile CPU/RAM/IO → tuning advice

  Network, Status & Diagnostics
  4)   Nginx Extended Features   audit · proxy · security · bandwidth
  5)   Node Status & Sync        ports, tmux, versions + chain tip
  6)   Diagnostics & Support     health check · support bundle · log triage
  E)   Ecosystem Page Entries    hide / un-hide rows on the ecosystem status page

  Maintenance
  7)   Disk Cleanup              tar archives + OS temp/logs + nginx dirs
  8)   Self-Update               pull latest changes from GitHub
  9)   Backup & Restore          backup conf, nginx, SSL, crontabs · restore

  Danger Zone
  DEL) Full Grin Cleanup         remove EVERYTHING about Grin now!

  0)   Return to main menu
```

| Key | Opens | Changes anything? |
|-----|-------|-------------------|
| `1` | [Remote Node Manager](#remote-node-manager-key-1) — script 081 | Only when you use its mass-deployment actions |
| `2` | [Provider Access Watch](#provider-access-watch-key-2) — script 082 | Installs a small watcher and a [systemd timer](reference-glossary.html#systemd-service) |
| `3` | [Host Optimization & Hardening](#host-optimization-hardening-key-3) — script 083, with SSH Key Hardening (085) inside it | The reports change nothing; the SSH tool and Automatic Security Updates do |
| `4` | [Nginx Extended Features](#nginx-extended-features-key-4) — script 084, with Top 20 Bandwidth Consumers inside it | Yes — writes nginx config; blocks an IP if you ask |
| `5` | [Node Status & Sync](#node-status-sync-key-5) | No — read-only |
| `6` | [Diagnostics & Support](#diagnostics-support-key-6) — script 086, with stratum latency and the node event recorder inside it | Read-only, except a load test that asks first, the recorder's install and settings, and an optional stack-tool install |
| `E` | [Ecosystem Page Entries](#ecosystem-page-entries-key-e) | Yes — writes your local hidden list |
| `7` | [Disk Cleanup](#disk-cleanup-key-7), with the automatic cleanup and the [swap](reference-glossary.html#swap) manager | Yes — deletes files |
| `8` | [Self-Update](#self-update-key-8) | Yes — overwrites the toolkit's files |
| `9` | [Backup & Restore](089-backup-restore.html) — script 089, its own page | Yes |
| `DEL` | [Full Grin Cleanup](#full-grin-cleanup-key-del) — script 08del | **Removes everything** |

Three keys have changed hands over time: `3` used to be Node Status, `5` used to be SSH Key Hardening, and `6` used to be Top 20 Bandwidth Consumers (now option `5` inside Nginx Extended Features). There is deliberately no alias for the old meanings — every screen prints its own banner, so a mis-key is obvious before anything happens. Key `10` still opens Backup & Restore (its old slot) as a silent alias.

Every screen writes its run to `/opt/grin/logs/` — the admin hub itself to `grin_admin_<date>.log`, each sub-script to its own `grin_<name>_<date>.log`. On the hub's own screens (`7`, `8`) a value prompt accepts `q` to cancel.

## Node Status & Sync (key 5)

One read-only screen, three parts:

1. **Port status** — whether anything listens on the eight toolkit ports: node API 3413 / 13413, P2P 3414 / 13414, wallet listener 3415 / 13415, stratum 3416 / 13416, with the PID. A wallet port marked ⚠ is one you should not expose to the internet.
2. **[tmux sessions](reference-glossary.html#tmux-and-gtmux)** — every `grin*` session on *both* tmux servers: the `grin` user's socket (where the toolkit starts nodes; attach with `gtmux attach -t <name>`) and root's (`tmux attach -t <name>`). A session on the root socket next to one on the grin socket is the classic duplicate-node situation — see [Script 01's troubleshooting](01-build-node.html#troubleshooting).
3. **Running Grin processes and binary versions** — each `grin` process and the `--version` of every distinct binary.

Then **Chain Sync** asks each node for its tip over the Foreign API and reports one of:

| Line | Meaning |
|------|---------|
| `[ONLINE]` with height, last block, difficulty | The node answered. Compare the height with [grinscan.org](https://grinscan.org) (mainnet) or [test.grinscan.org](https://test.grinscan.org) (testnet) to see how far behind it is |
| `[OFFLINE] — nothing listening on port N` | No node on that port. Start it with Script 01 → *Start a node* |
| `[NO SECRET]` | The port is open but the node's `.foreign_api_secret` could not be read. Run `grin-secret-sync` |
| `[AUTH FAILED]` with HTTP 401 or 403 | The node is **running**; the secret on disk is not the one it loaded. Run `grin-secret-sync`, and if it persists restart the node |
| `[NO DATA]` or `[API ERROR]` | The node answered with something other than a tip — usually still starting up. Wait a few minutes |

A healthy node reads `[ONLINE]` with a height that moves between two runs a minute apart. The screen distinguishes "node down" from "wrong credential" on purpose: an empty reply is not proof a node is down, and treating it as one makes a perfectly healthy node look dead.

## Diagnostics & Support (key 6)

> **Warning:** Status — script 086, its stratum latency screen, its node event recorder and the public status page are built and reviewed but have **never been run on a VPS**. The thresholds behind each finding are untested heuristics. Read a finding's *observed* value before acting on it.

Script 086 answers one question from evidence: *is this the toolkit, this server, or Grin itself?* It runs the checks you would otherwise paste into a chat one by one, tags each finding with where to look first, and can pack everything into one file to hand to whoever is helping you. It must run as root (it exits otherwise), because the probes read root-only state.

```text
 086)  Diagnostics & Support Bundle

  Is it our code, this host, or upstream grin? Collect the evidence first.

  Check
  1)   Quick health check        ~30 s · findings + likely origin
  2)   Build support bundle      ~3 min · one .tar.gz to share

  Dig deeper
  3)   Node API performance      get_block cold/warm · parallel burst
  4)   Node log triage           known error signatures · hourly timeline
  5)   Consumer load test        pauses explorers ~1 min (asks first)
  8)   Mining / stratum latency  template delay · stale shares · threads

  Over time
  7)   Node event recorder       timeline · availability % · evidence · alerts

  6)   Saved reports             list · delete old
  0)   Return to admin centre

  Read-only except option 5 (and 7's install/settings, 8's optional installs). Reports: /opt/grin/reports/diag
```

| Key | What it does | Changes anything? |
|-----|--------------|-------------------|
| `1` | Checks the host (memory, swap, disk and IO pressure, CPU steal, OOM kills, full filesystems, clock sync), every running node (runs as `grin`, one process per dir, secrets, Owner and Foreign API, peers, lag behind a public reference tip, log level), the last hour of each node log, the toolkit services that use the node, and, for a node with stratum on, the template latency in its newest saved key `8` run (it never runs a probe itself). On screen, in a pager — `q` leaves it | No |
| `2` | The same checks over 24 hours plus config, a diff of `grin-server.toml` against what the same binary generates as its default, peers by version, the node's tmux pane (panics land there), API timings, services, network, `sar` history, a 30-second CPU/disk sample per process, the recorder's state and, for each node with stratum on, a stratum file (`11_stratum_<net>.txt`, no live probe) — packed into one `.tar.gz` | No |
| `3` | Times `get_block` from the tip back towards genesis, each height twice (cold, then warm), plus a 20-request parallel burst. It offers two optional *IncompleteMessage experiments* that add one or two lines to the node log | Only the optional log lines |
| `4` | Matches the node log against known Grin error signatures and prints an hourly timeline; window last hour, 6 h, 24 h or since the node started. The signatures include stale and bad shares: stale shares become a warning above 3 % of accepted plus stale, or above 10 an hour when the window has no accepted lines | No |
| `5` | Measures the mainnet node's CPU and disk with the read-only explorers (`grin-tiny-explorer`, `grinscan-main`) running, stopped, then restarted — 45 s each. They are down for about a minute; you must type `yes`. Only units it stopped are restarted, Ctrl+C included. The pool, wallets and nodes are never touched | **Yes** — stops the explorers briefly |
| `6` | Lists saved reports and deletes those older than N days. Stratum screens go with the rest; the `.json` baselines stay, so a before/after compare still works | Deletes only its own reports |
| `7` | The [node event recorder](#node-event-recorder) | Its own install, settings and evidence |
| `8` | [Mining / stratum latency](#mining-stratum-latency) | Nothing on the node, except one sub-screen that briefly pauses it and may offer to install a tool; it asks first |

Reports go to `/opt/grin/reports/diag/` (mode 700, each file 600): `grin_diag_<host>_<time>.tar.gz` with a `.summary.txt` next to it, `api_perf_<net>_<time>.txt`, `consumer_load_<time>.txt`, and from key `8` `stratum_<net>_<time>.txt` with its `.json` baseline and `stratum_stack_<net>_<time>.txt`. The screen prints the `scp` line to copy a bundle to your own machine.

**[Likely origin](reference-glossary.html#likely-origin).** Every finding carries one of these tags, and the summary counts critical and warning findings per tag under *Where to look first*:

| Tag | Look at |
|-----|---------|
| `host` | This VPS — disk, RAM, CPU steal, clock |
| `toolkit` | The toolkit's setup — how the node was launched, secrets, services |
| `upstream` | Grin itself — check the upstream issue tracker |
| `client` | Programs calling the node API |
| `chain` | Chain data on disk |
| `network` | P2P and sync |
| `config` | `grin-server.toml` settings |
| `consumer` | A toolkit service that uses the node |

A tag is a **lean from a pattern match** (a log signature, a threshold), not a diagnosis — the screen says so every time. Use it to decide where to look first, then confirm. As on Host Optimization, a run with **zero findings is reported as broken, not as a pass**.

**Privacy.** No secret value is printed or put on a command line; peer and visitor IP addresses are masked; long token-like strings are redacted. **Hostnames and domains are not masked** — read a bundle before posting it anywhere public. Set `GRIN_DIAG_OFFLINE=1` before starting to skip the calls that leave the box (the public reference tip and the upstream latest-release lookup).

### Mining / stratum latency

`6` → `8`. When a new block arrives, a node has to hand its miners a new job, and the time that takes decides how many shares go stale. This screen measures it. Pick a node, and the probe opens one extra connection to that node's stratum port, the same way a miner does, and times each new tip to the first job. It never submits a share. `Blocks to measure (3, 5 or 10)` defaults to 5, at about one minute per block; Ctrl+C stops the run and keeps the rows it has.

If no miner or pool is connected, it stops and explains first, because the probe's connection makes the node start building block templates, and each build asks the wallet listener for a coinbase. With the listener unreachable it refuses to run: the node would keep retrying and logging errors after the probe left. Otherwise it asks `Run the probe anyway? [y/N]`. On a node with the stratum server off, it says so and measures nothing.

Every run saves its screen and a baseline to `/opt/grin/reports/diag/`, then opens this menu:

```text
  1)  Build log               where a template build spends its time (DEBUG)
  2)  Rejects per hour        stale · low difficulty · invalid (node log)
  3)  Thread CPU              10 s sample of every node thread
  4)  Stack capture           pauses the node briefly (asks first)
  5)  Save baseline           keep this run for a before/after compare
  R)  Run the probe again     same node, gate and blocks prompt, auto-saves
  C)  Compare baselines       two saved runs, side by side

  0)  Back to Diagnostics
```

`C` is the useful one after a change: run once, change the node or its binary, run again, compare. `4` is the only key here that touches the running node. If no stack tool is installed it offers to install `elfutils` and `gdb` with your package manager; the default is no.

> **Note:** Read from the code, not seen working on a server.

### Node event recorder

`6` → `7`. A small timer that checks each node every 30 seconds and writes down every time it goes down or comes back, with a guess at *why* and the evidence saved at that moment — the node's tmux pane, its log window, kernel lines and host state. It answers "how often does my node fall over, for how long, and what was it doing?", which a status screen run by hand cannot.

It is **read-only**: it never starts, stops, restarts or signals a node. Restarting is the [sync watchdog](reference-glossary.html#watchdog)'s job (Script 01 installs it); the recorder only records.

```text
  Set up
  I)  Install / refresh
  P)  Public status page        publish this node's uptime · preview · verify
  A)  Alert settings            channels · import · test · thresholds
  S)  Status
  R)  Remove                    keeps the ledger, evidence and config

  View
  1)  Timeline                  last events per network
  2)  Availability              uptime % · outages by class · MTBF · 7 / 30 / 90 d
  3)  Show evidence             pick a bundle · summary + matched lines
  4)  Export for upstream       masked .tar.gz for a GitHub issue
  C)  Capture evidence now      a bundle on demand · no event recorded

  0)  Back to Diagnostics
```

**Set it up:** `I` installs it (Script 01 also offers it during a build, and Super Auto installs it). If the box's sync watchdog is older than the recorder, `I` offers to regenerate it, so a watchdog restart saves the node's pane before it is destroyed. Then `A` → set at least one alert channel, or `A` → `5` to copy the channels you already set in [Provider Access Watch](#provider-access-watch-key-2) (a copy, not a link), and `A` → `6` to send a test. At the end of an install, `I` also offers to turn on the mainnet [public status page](#public-status-page).

**What the classes mean.** Each outage gets a class. Like the origin tags, it is a lean, not a verdict, and it may be refined once the evidence is read:

| Class | Usually means |
|-------|---------------|
| `hung` | The process is alive but the API stopped answering (timeout, closed port, bad reply; also a compaction or IO stall on an archive node) |
| `crashed` | The process exited with an error code, or a panic was found in the log |
| `killed` | Killed with SIGKILL — often the kernel's out-of-memory killer |
| `unexplained_stop` | It stopped cleanly but nothing in the toolkit planned that stop (for example Ctrl+C inside its tmux session) |
| `failed_start` | It never answered within the start timeout, or exited before its first answer |
| `wedged` | The sync watchdog decided it was stuck and restarted it |
| `corrupted` | The start-up log shows broken chain data. **Restarts will not fix this** — the chain data needs a resync: Script 01 → *Rebuild a node*. The evidence summary also names a *Script 03 restore*, but Script 03 only publishes snapshots and has no such action |

Planned stops (the toolkit's own *Stop a node*, a rebuild, a full cleanup), node starts and host reboots are recorded but **never counted as outages**. *Availability* is (up + auth fault) ÷ (up + auth fault + counted down), over 7, 30 and 90 days: an auth fault means the node answers and only a secret is wrong, so it counts as up, the same as on the public status page. The screen also shows outages by class, MTBF, mean time to recover and the longest outage. All times are UTC.

**Alerts** go to the channels you set, at most one of each per outage: *DOWN* once an outage lasts 3 minutes, *CORRUPTED* at once, a *restart loop* (3 watchdog restarts within 60 minutes), *recovery* after a DOWN, and an *unclean host reboot*. Every threshold, the evidence size caps (50 MB per bundle, 500 MB in total, 180 days) and the watched networks are under `A` → `7`; the timer re-reads them on every check.

**Evidence and export.** Raw bundles do **not** mask IP addresses or hostnames. To share one, use `4`: it masks IPs fully, replaces this host's name, redacts secrets and every 20+-character token, and writes `/opt/grin/logs/grin_node_events_export_<time>.tar.gz`. Copy it off soon — the automatic cleanup in [Disk Cleanup](#disk-cleanup-key-7) ages out `/opt/grin/logs`.

**What was created:** the worker `/usr/local/bin/grin-node-events` (`check`, `capture`, `show`, `test-alert`, `publish`, `verify-chain`), `grin-node-events.service` and `.timer`, copies of the libraries it runs from in `/opt/grin/lib/`, the config `/opt/grin/conf/node-events/recorder.conf` (mode 600 — it holds your alert tokens; written only if absent), `/etc/logrotate.d/grin-node-events`, and the records in `/opt/grin/node-events/<network>/`: `ledger.jsonl` (history), `status.json` (current state), `evidence/` (mode 700), and, once you publish, `public/` and `.public_salt`. `R` removes the program and its units and withdraws the served status files, but keeps the records, the public history and the config; [backups](089-backup-restore.html) carry the ledger and the public history; [Full Grin Cleanup](#full-grin-cleanup-key-del) removes everything and asks about the evidence first.

### Public status page

`6` → `7` → `P`. Publishes the recorder's numbers so that anyone can see how reliable your node is. It is **off by default**, per network.

```text
  1)  mainnet  on / off
  2)  testnet  on / off
  3)  Interval
  4)  Preview                   the exact bytes served, or about to be
  5)  Verify chain              every link of the public history
  6)  Readable by the web user  www-data check
  7)  Where it is served
  0)  Back
```

Turning a network on asks `Publish the <net> node's status page? [y/N]`. Use `4` first to read exactly what goes public: the node's state, its uptime %, a dated outage history with a known error type, dated planned stops, node compaction times, and a hash-chained copy of that history, in which each line carries the hash of the one before, so a changed line shows up in `5`. Process ids, free-text reasons and evidence stay private, and an outage is listed only once it has closed. The files refresh every 300 seconds (`3` sets 60–3600), and at once when an outage closes.

The files live in `/opt/grin/node-events/<network>/public/`: `availability.json`, `history.json` and the chain `history.jsonl`. Beside that folder is `.public_salt` (mode 600), a secret the chain depends on: with a chain and no salt, publishing refuses to run. Backups carry the two together. Turning a network off removes the served `.json` files and keeps the chain.

Nothing here is a web page yet: two other products serve the files, and both need their own update to do it. [Script 04](04-publish-node-api.html) serves them on the node API site's status page and under `/rest/`, for either network; the [Tiny Explorer](06-global-health.html) serves mainnet at `/availability`. `7` prints the addresses.

> **Note:** Read from the code, not seen working on a server.

## Ecosystem Page Entries (key E)

Hides rows on the ecosystem status page that [Global Grin Health](06-global-health.html) publishes, for example a site you would rather not list. The screen shows every entry, grouped by category, with `[hidden]` beside the ones already hidden. Type a number to hide or un-hide that entry, `r` to run the ecosystem checker now, `0` to go back. It needs the Network Stats part of Global Grin Health installed, and says so if it is not.

Your choice is a list of URLs in `/opt/grin/grin-stats/ecosystem_hidden.json`, not an edit to the lists that ship with the toolkit, so a Self-Update does not undo it. The page changes on the next hourly checker run, or when you press `r`. If the hourly cron is off, only `r` does it, and the screen says so.

> **Warning:** The checker that applies the list is a copy in `/usr/local/bin/`, made only by *Install* in [Global Grin Health's Network Stats menu](06-global-health.html). A toolkit update does not refresh that copy. On a box installed before this screen existed, the old checker ignores your list: the rows stay on the page, and `r` still reports *the status page now reflects the hidden list*. After updating the toolkit, run that *Install* again, then `r`.

> **Note:** Read from the code, not seen working on a server.

## Remote Node Manager (key 1)

Script 081 watches *other* machines from this one, and can push changes to them. It has two halves.

### Monitoring

```text
  1) Run check now
  2) Reconfigure host list
  3) Show crontab / email setup
  4) Mass Deployment         update, control and run commands on remote nodes
  0) Return to main menu
```

**Run check now** always starts with the **registry check**: it reads `extensions/grinmasternodes.json` (the community snapshot hosts Script 01 downloads from — see [Script 03](03-share-chain-data.html#join-the-community-registry)) and, per host, tests HTTPS reachability, finds the `.tar.gz` in the directory listing, reads its age from the `Last-Modified` header against the limit for that site key (**70 days** for the full archive, **5 days** for pruned), and checks that `check_status_before_download.txt` reads *Sync completed.* A host that fails shows the owner contact from the registry. Results go to a `grin_master_nodes_status_<date>.log` file in `/opt/grin/logs/`. This part needs `jq`.

Then it checks **your own list**, if you have made one with **Reconfigure host list** (`2`). Each line is either a TCP check — `host port [label]`, for example a friend's node on `3414` — or an HTTP check — `https://url - [label]`, which passes on any 2xx or 3xx reply. Enter them one at a time or paste a block. The list is saved to `/opt/grin/conf/host_monitor_port.conf`; the last result per host to `host_monitor_last_state.conf`, which is how the script knows what *changed* since the previous run.

For unattended use, **Show crontab / email setup** (`3`) prints the lines to add with `crontab -e`:

```bash
# every 5 minutes, email only when a host changes state
*/5 * * * * /path/to/scripts/081_host_monitor_port.sh --email you@example.com
# every 5 minutes, always email
*/5 * * * * /path/to/scripts/081_host_monitor_port.sh --email you@example.com --force
```

Email needs the `mail` command (`apt install mailutils`) and a working local mail setup; without it the script logs a warning and carries on. Configure the host list interactively *before* adding the cron line — a cron run with no list has nothing to check and exits quietly.

### Mass deployment

`4` opens a fleet menu for servers you administer over SSH. The fleet lives in `/opt/grin/conf/mass_deploy.conf`, one server per line (defaults: port 22, user root, toolkit at `/opt/grin-node-toolkit`):

```text
label|host|ssh_port|user|key_path|toolkit_path
```

| Action | What it does |
|--------|--------------|
| Manage server list | List, add, test every connection, **Remove servers** and **Bulk add servers** (both below), and **Bootstrap SSH keys** — generates `/root/.ssh/grin_deploy` (ed25519, no passphrase) if missing, prints the public key, then runs `ssh-copy-id` to each server (asks for that server's password once) and verifies key login |
| Push toolkit update | Downloads a branch tarball on each selected server and copies it over its toolkit directory — the remote equivalent of [Self-Update](#self-update-key-8). Branches: `main` (default), `add-ons`, or *Custom branch* |
| Run command | Runs one shell command on the selected servers and shows each reply |
| Remote node control | `a` start, `b` stop, `c` restart the Grin nodes on the selected servers (as the `grin` user, on both tmux sockets — the same rules as Script 01); `d` upgrade the grin binary to the latest official release and restart the nodes; `e` reboot after a one-minute delay, with a confirmation; `f` push a binary from this server and `g` roll one back (both below). A stop closes **node** sessions only — wallet listeners that share the `grin_` prefix keep running — and, on a server with the [node event recorder](#node-event-recorder), first leaves a planned-stop marker so the stop is not counted as an outage |
| Host security updates | *Status*, *Enable*, *Disable*, *Run security patch now* and *Last patch run* on the selected servers: the same work as [Automatic Security Updates](#automatic-security-updates), sent over SSH, so a remote server needs no toolkit. A patch run is detached on the server and logs to `/var/log/grin-host-updates/run-now_<UTC>.log`, so a dropped connection does not interrupt it. It never reboots; rebooting stays on `e` |

Every action asks which servers: `all` or a comma-separated list of numbers. Pressing Enter there also means `all`; only *Remove servers* treats Enter as cancel.

**Upgrade grin binary** (`d`) asks `Upgrade to latest official release and RESTART nodes on N server(s)? [y/N]`, then on each server downloads the `linux-x86_64` release, checks its sha256 when the release publishes one, and refuses a binary that prints no version. Only then does it stop the nodes, keep the old binary as `grin.prev` and install the new one. A node directory that fails gets `grin.prev` back, and the start step always runs.

Remote *start* and *Upgrade grin binary* launch every installed node at once, without the 1000-second stagger Script 01 uses; on a small VPS expect the second node to take a long time to open its ports.

**Push binary from this server** (`f`) sends a binary you built here to the fleet, so each server need not compile its own. You pick from `/opt/grin/bin` (the list shows each file's date, version and sha256), set a pause between servers (default 120 seconds), then choose `1) Full push` or `2) Dry run`, which only checks and copies to `/opt/grin/bin` on the server while its nodes keep running. Servers go one at a time. Each is checked for matching architecture and free disk, the file is copied and its sha256 verified with the node still running, and then one session stops **every** node on that server and swaps the binary. This server itself is skipped.

> **Warning:** `f` and `g` leave the nodes **stopped**, unlike `d`. At the end you get `Reboot the swapped servers so @reboot autostart brings the nodes up? [y/N]`, offered only for servers with an autostart line. Anything else stays down until you start it with `a`, with one exception: on a server with the node-sync watchdog (Super Auto installs it), a watched network's node is restarted by the watchdog's next five-minute check, on whatever binary is then in place.

**Roll back pushed binary** (`g`) stops the nodes the same way and restores `grin.prev` over `grin`. A server with no `grin.prev` is skipped. A successful rollback deletes `grin.prev`, so there is one step back, not several.

**Remove servers** takes numbers such as `2,5,7`, or `all`; Enter cancels. After `Revoke access and remove these N server(s)? [y/N]` it deletes this controller's `grin_deploy` key from each target's `authorized_keys`, removes the server's line from the list and forgets its host key. If a target cannot be reached it asks `Remove '<label>' from the list anyway? The key stays on the target. [y/N]`. If this server has no readable `/root/.ssh/grin_deploy.pub`, it warns and only removes the list lines, with no further question, and the key stays on every target.

> **Warning:** Do not remove a server whose disk is full. The revoke rewrites `authorized_keys` from a temporary copy without checking that the copy was written, so a failed write empties the file and ends key login for every key on that account. Even a clean revoke ends this controller's access, so before you remove a server, make sure you have another way in: if the deploy key was that account's only key and password login is off, nothing is left to log in with.

**Bulk add servers** adds many at once, using each password only to install the deploy key. Give it a list file or paste the lines (hidden), one server per line:

```text
label|ip|port|user|password
```

`port` and `user` may be empty (22 and root). A line with no password uses one shared password, asked once. It installs `sshpass` if needed (from EPEL on Rocky and Alma), asks for the toolkit path (default `/opt/grin-node-toolkit`), and writes only the servers whose key login then works. The toolkit never saves a password, but your list file holds them, so answer yes to `Securely delete the password file <src> now? [Y/n]`. That question comes only at the end of a finished run. If a run stops early (no lines read, no shared password, `sshpass` or the key could not be set up), delete the file yourself with `shred -u`.

**Host keys.** Fleet connections trust a server's SSH key the first time they meet it and refuse a key that changes, so a swapped server never receives commands silently. The cost is that a server you rebuild at the same address stops working until its old key is forgotten; see [Troubleshooting](#troubleshooting).

> **Note:** The upgrade, binary push and rollback, server removal, bulk add and fleet security updates are read from the code; none has been run on a server.

## Provider Access Watch (key 2)

A rented VPS can be opened from the outside — by the provider's console, a rescue boot, or anyone who has those credentials — and nothing inside the guest is told. Script 082 records what the box looks like when you trust it, then keeps comparing. "Host tamper" here means any of:

- a new or removed key in any user's `authorized_keys` (identified by fingerprint, so a swapped key of the same length is still caught) — **HIGH**;
- a changed SHA-256 of the `sshd` binary, `sshd_config` and its drop-ins, `sudoers`, `passwd`, `group`, `crontab`, `cron.d`, `hosts.allow`, `hosts.deny`, `ld.so.preload`, or any `.service` / `.timer` in `/etc/systemd/system`;
- a different `boot_id` — the machine rebooted and you did not do it (rescue boot, migration);
- a different kernel or kernel command line — a rescue or single-user boot — **HIGH**;
- a new accepted SSH login (from the journal);
- a heartbeat gap far longer than the check interval with no reboot — the VM was paused or the clock jumped.

It **detects**; it cannot prevent. The two measures that would raise the ceiling — full-disk encryption with remote unlock, and keeping wallet seeds off the VPS — are out of scope and described under `7`.

```text
  Baseline & checks
  1)  Snapshot baseline       record trusted state (prints off-box hash)
  2)  Run check now           diff current state vs baseline
  3)  Show last report        findings from the most recent check

  Automation & alerts
  4)  Configure alert channels ntfy · Telegram · email · Nostr · test
  5)  Scheduled watch (timer)  enable/disable · set interval
  6)  Status                   baseline, timer, channels at a glance

  Info
  7)  Beyond detection         LUKS remote-unlock · wallet-off-VPS
```

**Set it up in this order:** `1` snapshot a baseline on a box you trust right now — then **copy the printed SHA-256 off the server** (a notes app, a password manager). An intruder can rewrite the baseline file on the box to hide their changes, but not your saved copy of its hash; if the hash in `6` ever differs from your note, the baseline itself was tampered with. Then `4` configure at least one alert channel — a finding that only lands in a log on the same server the intruder is on is worthless — and `4` → `6` to send a test. Then `5` enable the timer; the default interval is **15 minutes** (first run 2 minutes after boot).

| Channel | What you enter | Notes |
|---------|----------------|-------|
| ntfy | A topic URL such as `https://ntfy.sh/<random-topic>` | Simplest; pick an unguessable topic name |
| Telegram | Bot token from @BotFather, and your chat id | |
| Email | An address | Needs `sendmail`, `mail` or `msmtp` on the box |
| Nostr | Secret key and relay URL | Needs `nak` (or `nostril` + `websocat`) installed; otherwise logged as skipped |

Every configured channel is tried independently. Standing findings (a changed file, a new key) alert once and again only if the set of findings changes; events (a login, a clock jump) alert once each. `5` in the alert menu toggles the new-login alert, which is on by default — turn it off if your own logins are frequent. The [node event recorder](#node-event-recorder) uses the same delivery code and can import these channels.

**What was created:** `/opt/grin/access-watch.sh` (the worker, reinstalled on every launch; if that refresh fails, the installed worker keeps running), `grin-access-watch.service` and `.timer`, `/opt/grin/conf/access-watch/` (mode 700) holding `baseline`, `alert.conf` (mode 600 — your tokens) and `state/`, and the log `/opt/grin/logs/access-watch.log`. Re-snapshot the baseline after *you* change something it watches (a new SSH key, a system upgrade that replaces `sshd`), or every check will keep reporting it.

> **Note:** Built 2026-07-25 and checked only by syntax and code reading — it has not been run on a VPS. Test every alert channel with `4` → `6` before trusting it.

## Host Optimization & Hardening (key 3)

Script 083 profiles the VPS — CPU, RAM, disk, kernel settings, time sync, logging, firewall, SSH — and reports what a Grin node needs from *this* box, sized from what it measured. Its reports are **advisory only**: they change nothing on the host, and every finding carries a `fix:` line, an exact command or a menu path, for you to review. That is deliberate for a remote server: a wrong `sysctl` is recoverable, but `ufw enable` before an SSH allow-rule leaves a box you can only reach from the provider's console. Apart from `7`, which opens the SSH tool below, key `9` is the one action on this screen that writes, and it asks before every change.

```text
  Report
  1)   Full report               every check, grouped by area
  2)   Export report to file     plain text, for pasting or keeping

  Single area
  3)   CPU & memory              cores, steal, RAM, swap sizing
  4)   Disk & IO                 space, device type, scheduler, atime
  5)   Kernel & node limits      sysctl, THP, fd limits, peer count
  6)   Security & firewall       ufw, exposed node API, updates

  Hardening   configure first, then verify
  7)   SSH Key Hardening →       keys, key-only login, guided user+sudo setup
  8)   SSH posture               read-only summary — check your work
  9)   Automatic Security Updates →  security-only patches, no reboots
```

Findings are graded **CRIT** / **WARN** / **INFO** / **OK** / **NA**. The full report is longer than a screen, so it is shown in a pager — press `q` to leave it — and ends with an explicit `[END]` marker so you know nothing was cut off. `2` writes the same report, without colour, to `/opt/grin/reports/` as `host_optimization_<date>.txt` (mode 600 — it lists open ports and firewall state).

The checks that matter most for a Grin node:

- **Node API bound to all interfaces** — 3413 / 13413 reachable from the internet is CRIT with no firewall, WARN with ufw in the way, OK on loopback. Publish the API the supported way, with [Script 04](04-publish-node-api.html), never by opening the port.
- **Firewall installed but off**, or no firewall at all — CRIT.
- **No swap**, or swap too small for the cold-boot rebuild a node does — a 2 GB box needs it. Add it from [Disk Cleanup → Swap manager](#disk-cleanup-key-7).
- **`vm.swappiness` too high**, transparent hugepages set to *always* (hurts the node's LMDB database), a low open-file limit, an inbound peer limit that is too high for the RAM (Script 01 sets 999, which is right for a big box and wrong for a small one).
- **No time synchronisation** — peers reject blocks from a node whose clock drifts.
- **Pending security updates**, no `unattended-upgrades` or `dnf-automatic`, no `fail2ban`. [Key `9`](#automatic-security-updates) handles the first two.

A summary of **zero findings is reported as a failed run, not a pass** — the probes did not work (usually: not root).

> **Note:** Built 2026-08-25 and never run on a VPS. The sizing thresholds (peer tiers by RAM, swap sizes) are labelled heuristics; read a finding's observed value before running its fix.

### SSH Key Hardening (script 085)

`7` opens the only tool in the toolkit that *changes* SSH: script 085, which had its own hub key until 2026-08-25. `8` shows the result read-only. Its job is to get a public key onto the server, prove that key login works, and only then turn password login off — with a guaranteed way back.

```text
  Start here
  W)  GUIDED SETUP →          key ▸ normal user ▸ sudo ▸ root, in order
      Creates the user, installs the key, proves both work, THEN locks
      SSH down. Does every step below in the safe sequence.

  Keys   individual actions — to adjust, not to set up
  1)  Add a public key          paste · generate on server · fetch URL
  2)  List installed keys       fingerprints in /root/.ssh/authorized_keys

  Hardening
  3)  Verify key login          anti-lockout self-test (run this first!)
  4)  Disable password login    key-only; optional safety timer
  5)  Make key-only permanent   cancel safety timer after testing
  6)  Re-enable password login  rollback / break-glass

  Info
  7)  SSH status & audit        effective config, keys, firewall
  8)  How to connect with key   remote-tool steps (Windows/Linux/macOS)
```

There are two ways to use it. **`W`** sets up a separate admin account and shuts root out of SSH (below). The numbered keys keep logging in as **root** and only turn passwords off: do them in order `1` → `3` → `4` → test in a second terminal → `5`.

- **Add a key** three ways: paste the `.pub` line from your laptop (recommended); generate a pair on the server, in which case the private key is shown **once** for you to copy and you are asked to delete the server's copy; or fetch a *public* key from a URL such as `github.com/<user>.keys`. Private keys are never fetched from anywhere. A pasted fingerprint, a private key or a wrapped key is refused with the reason.
- **Verify key login** checks `authorized_keys`, permissions, `sshd -t`, that public-key auth is enabled, how *this* session authenticated, and tries a loopback login with the key.
- **Disable password login** writes `PasswordAuthentication no`, `KbdInteractiveAuthentication no` and `PermitRootLogin prohibit-password` — to a drop-in, `00-grin-hardening.conf` in `/etc/ssh/sshd_config.d/`, where the distro supports it (an older `99-grin-hardening.conf` is removed) — validates with `sshd -t` before applying, and **reloads** sshd rather than restarting it, so your current session survives. It refuses to run while **root's** `authorized_keys` is empty; that is the only account it checks, so after the guided setup it says nothing about the key you actually log in with.
- **Written is not applied.** sshd keeps the *first* value it reads for a setting, so another file — on Ubuntu usually `50-cloud-init.conf` with `PasswordAuthentication yes` — can silently win. After every apply the tool asks sshd what it actually resolved. If a setting did not take, it lists every file that sets it and offers `f` to comment out the other lines (kept behind a `#GRIN-DISABLED# ` prefix and put back on any rollback) and check again, or `q` to roll the whole change back. It never leaves you half-applied.

> **Danger:** Do not lock yourself out. Choose the **[safety timer](reference-glossary.html#safety-timer)** (`A`, default 5 minutes) unless you have *already* logged in with the key in another terminal. With the timer, passwords come back on their own unless you return and press `5` to commit. If you did test first and pick `B`, you are asked to confirm it once more. `6` is the break-glass at any time — but it only helps if you can still get in, which is the point of testing first. The tool also warns if ufw is active with no rule for your SSH port.

Every change backs up the previous config to `/opt/grin/conf/ssh_backups/`.

### Guided setup (W)

`W` walks the whole "your key → a normal user → `sudo` → root" setup in the only safe order. At the end, SSH passwords are off, **direct root SSH is off**, and you log in as the new user and become root with `sudo -i`. Steps 1–5 change users and keys but not sshd, so they cannot lock you out; step 7 is the only one that touches SSH, and it refuses to run until step 6 has proven the new way in works. Keep your current session open until the end.

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | Name the admin user — created, or an existing one adopted | A lowercase name; avoid `admin` and `grin` |
| 2 | Set that user's password. SSH will not accept it; `sudo` asks for it, and an account with no password cannot `sudo` at all | Type it into `passwd` (the toolkit never sees it) |
| 3 | Add the user to `sudo` (Debian/Ubuntu) or `wheel` (Rocky/Alma); offers to install `sudo` if missing | Confirm |
| 4 | Install your laptop's public key into **that user's** `~/.ssh/authorized_keys` — root's keys are left alone | Paste, generate or fetch, as with `1` |
| 5 | Optional: a `grinops` group that can read `/opt/grin/backups`, so you can `scp` backups as the new user without `sudo` | `y` or `n` |
| 6 | **Proof.** In a second terminal, `ssh <user>@<server> -p <port>` then `sudo -i`. The tool looks for an *Accepted publickey* line for that user in the SSH log (or, for a key generated on the server, tries a loopback login) and asks `sudo` whether the user may run everything. Both must go green. The log line can be an old one, so check that the date shown is from just now. On a box that logs only to the journal and runs OpenSSH 9.8 or newer (Debian 13, for example) the search may find nothing even after a good login, because it looks for lines from `sshd` (read from the code); if it stays red, `q` is safe | Log in, come back, `r` to re-check (`q` stops with nothing changed) |
| 7 | Applies `PasswordAuthentication no` and `PermitRootLogin no`, and offers `AllowUsers` so only the listed accounts may log in (it names any other account with keys that would be locked out). Then the auto-undo timer — default **10 minutes**, `0` for none | Choose, confirm, then log in as the user in a new terminal and press `5` |

It finishes by printing the login line and an `~/.ssh/config` block for your laptop. Use `sudo -i`, not `sudo ./grin-node-toolkit.sh` — plain `sudo` keeps the user's home directory, and you need a root shell to see the node's tmux sessions.

The choices are saved in `/opt/grin/conf/ssh_hardening_policy.conf` at step 7 *before* you are asked to apply, so the file stays even if you answer no to *Apply now?* or the auto-undo timer rolls the change back. While that file says root login is off, `4` also applies it (and warns); `6` re-enables passwords and root SSH and offers to forget the policy.

> **Danger:** Step 7 turns off direct root SSH, and with `AllowUsers` it shuts out every other account too. Do not lock yourself out:
> - Keep the auto-undo timer (do not answer `0`) and keep your current session open.
> - Before pressing `5`, open a **new** terminal, log in as the new user with your key, and run `sudo -i`. Press `5` only when both work.
> - **Do not reboot the server while the timer runs.** The timer is a background process, not a systemd unit; a reboot kills it, so the change is never undone and stays in force.
> - If you are locked out anyway, your only way in is the provider's web console or rescue mode. A cloud image often has no root password for the console, so set one (`passwd`) before you start.

> **Note:** The guided setup and the "did it take" check are read from the code; they have not been run on a server.

### Automatic Security Updates

`9` keeps a node that runs for months unattended patched, from the distro's **security channel only**. It never reboots. Library updates never restart a service. A patched daemon package (nginx, tor, php-fpm, openssh) may restart itself; the Grin node and the pool are not packages, so no update touches them.

```text
  1)   Show status               read-only
  2)   Enable                    asks first; NodeSource is opt-in
  3)   Disable                   asks first; removes toolkit files only
  4)   Run security patch now    asks first; detached, no reboot
  5)   Last patch run            read-only; result and log tail

  0)   Back to Host Optimization
```

- **Enable** sets up `unattended-upgrades` on Debian and Ubuntu (`20auto-upgrades`, a toolkit drop-in `52grin-unattended-upgrades`, and `/etc/needrestart/conf.d/50-grin.conf`), or `dnf-automatic` on Rocky and Alma. On apt it asks whether to allow NodeSource too; say no unless you want it, because NodeSource ships every Node.js release, not only security fixes. Enable fails if the settings it reads back are not security-only, not scheduled, or allow a reboot.
- **Disable** turns the schedule off and removes the toolkit's files. Packages stay installed. A host that had automatic updates on before Enable ends with them **off**.
- **Run security patch now** starts one pass detached from your session and logs to `/var/log/grin-host-updates/run-now_<UTC>.log`; `5` reads the result. On apt it refuses until Enable has installed the security-only policy; on dnf it runs `dnf upgrade --security` either way. If a kernel was patched, the reboot is yours to schedule.

The state and copies of any file it replaced live in `/var/lib/grin-toolkit/host-updates/`, outside `/opt/grin`, because the policy protects the host whether or not Grin stays on it: [Full Grin Cleanup](#full-grin-cleanup-key-del) leaves it in place. To do the same across several servers, use [mass deployment](#mass-deployment).

> **Note:** Read from the code, not seen working on a server.

## Nginx Extended Features (key 4)

Script 084 is for the nginx you already have from Scripts 02, 04, 06 or a wallet product. It never touches the file-server vhosts (`fullmain`, `prunemain`, `prunetest` and their web roots are reserved for [Script 02](02-nginx-fileserver.html)).

```text
  1)  Config & SSL Audit       nginx -t, cert expiry, enabled/disabled check
  2)  Reverse Proxy Manager    add · remove · list reverse proxy vhosts
  3)  Enhance Security         harden SSL settings and HTTP security headers
  4)  Log Rotation Setup       configure logrotate (10 MB or 10 days)
  5)  Top 20 Bandwidth Consumers parse access logs, block/limit an IP
```

**Config & SSL Audit** runs `nginx -t`, lists every file in `sites-available` with whether it is enabled, its type (proxy or file server) and its upstream or root, then connects to each `server_name` on port 443 and reports the certificate's days to expiry — yellow at 30 days or less, red at 14. Read-only.

**Reverse Proxy Manager** puts any local web service behind HTTPS on its own domain: `A` asks for the domain, a Let's Encrypt email and the upstream URL (for example `http://127.0.0.1:3000`), writes an HTTP-only vhost, runs `certbot --nginx`, then writes the full HTTPS vhost with WebSocket support, the standard forwarding headers, an HTTPS redirect and HSTS, and adds a daily `certbot renew` cron if none exists. The domain must already point at this server. `R` removes a proxy (optionally deleting its certificate), `L` lists them.

**Enhance Security** edits `nginx.conf` in place — `server_tokens off`, TLS 1.2 and 1.3 only with a modern cipher list — and writes `/etc/nginx/conf.d/security-headers.conf` with four headers (`X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`) for every site, then tests and reloads. Runs without asking.

> **Note:** nginx's `add_header` is not additive: a `server` or `location` block that sets *any* header of its own discards this global set for that block. The toolkit's own vhosts (Script 04, the pool, Fidelius…) all set their own headers, so on those sites the four global headers are simply not in force — that is expected, they carry stricter sets of their own.

**Log Rotation Setup** writes `/etc/logrotate.d/nginx-grin` for `/var/log/nginx/*.log`, then runs a dry run.

> **Note:** Two things to know before pressing `4` (from reading the code, not from a server). Debian and Ubuntu's nginx package already ships `/etc/logrotate.d/nginx` for the same files, so logrotate will report a *duplicate log entry* and skip the second definition; the dry-run output shown on screen is where you would see that. And the policy it prints — "10 MB or 10 days, whichever first" — is not what `size 10M` means in logrotate: `size` makes rotation depend on size alone and ignores `daily`. If the packaged config is present you do not need this one.

### Top 20 Bandwidth Consumers

`5` parses every access log under `/var/log/nginx/` and ranks the twenty client IPs that were served the most bytes — the quick answer to "who is downloading my chain snapshots all day?". Then `1` lets you enter an IP and either **block it** (`ufw deny from <ip>`, after a confirmation) or **rate-limit it** with an iptables `hashlimit` rule (over 25 connections a minute gets dropped, burst 100). The iptables rule is not saved anywhere, so it is gone after a reboot; the ufw rule persists. Without ufw the screen prints the equivalent `iptables` command instead of running it.

Nothing to show means no nginx access logs, or logs not in the standard *combined* format.

## Disk Cleanup (key 7)

One screen that first measures, then offers actions. It shows: tar archives in the chain-share directory; every web root from the enabled nginx sites, with its size; the size of `/tmp`, txhashset snapshot files, Grin node logs, the system journal and toolkit logs; a per-folder breakdown of `/opt/grin`; and whether automatic cleanup is on.

```text
  1) Delete ALL tar archives
  2) Keep newest N tar archives, delete rest
  3) Delete tar archives older than N days
  4) Clean selected OS/Log items  (enter letters, e.g. A C E)
  5) Clean ALL OS/Log items
  6) Delete nginx web dir contents  (choose directory)
  7) Automatic cleanup schedule  (txhashset snapshots + /opt/grin/logs >N days)
  8) Swap manager  (add/remove swapfiles by GB)
```

What actually frees space on a toolkit-built server:

- **`/opt/grin` breakdown** — read it first. `node/` (chain data) and `backups/` are the usual large ones; chain data is never touched here (use Script 01 → *Rebuild a node* for a corrupted chain), and old backup archives are pruned by [the backup schedule's retention](089-backup-restore.html#schedule-automatic-backups).
- **`6` nginx web dir contents** — this is where Script 03's snapshot archives are (`/var/www/prunemain` and friends). Emptying one deletes the archive, its checksum and status file, *and* Script 02's landing page for that site; Script 03's next scheduled publish writes a fresh archive, and Script 02 must re-deploy the landing page. Prefer Script 03's own settings for keeping fewer archives.
- **`D` system journal** — `journalctl --vacuum-time=<N>d`, asks for N (default 7).
- **`A` /tmp** — files older than a day.
- **`7` automatic cleanup** — installs `/opt/grin/auto_cleanup.sh` and a cron entry (`/etc/cron.d/grin-auto-cleanup`, daily at **04:30**) that deletes txhashset fast-sync snapshot files under `/tmp` and `/opt/grin/node`, and every file in `/opt/grin/logs` older than N days (default 7) — including a [recorder export](#node-event-recorder) you have not copied off yet. It also installs `/etc/logrotate.d/grin-toolkit-logs`, which rotates the toolkit's continuous logs (watchdogs, collectors, backup pushes) once they pass 10 MB, keeping four compressed rotations. Enable this on every server; `3` inside runs it now.

> **Note:** Three rows measure paths the toolkit does not use, so on a toolkit-built server they always show nothing to clean: *Chain Data Tar Archives* scans `/var/www/html/grin` (Script 03 writes to `/var/www/prunemain` etc. — use `6`), *Grin node logs* (`C`) looks in `~/.grin/main/log` (node logs are in each node directory and rotate via logrotate when Super Auto set it up), and *Grin-toolkit logs* (`E`) looks in `/var/log` (toolkit logs are in `/opt/grin/logs`, pruned by `7`). Not a fault of your server.

### Swap manager

`8` manages a *stack* of swapfiles under `/opt/grin/swap/` (`swap-001`, `swap-002`…), each with its own `/etc/fstab` entry so it is back after a reboot. **Add** creates a new file of N GB and enables it without touching the existing swap — safe even while swap is in use; **Remove** disables and deletes one file, and fails loudly (without deleting) if the kernel cannot move its pages elsewhere. A pre-existing `/swapfile` from Script 01 or the distro is listed and can be removed from here too. Script 01 already adds 2 GB (4 GB on a box under 2 GB RAM); the Host Optimization report tells you if that is too little.

## Self-Update (key 8)

Downloads the toolkit from GitHub as a tarball and copies it over the directory this toolkit runs from. You pick the branch:

```text
  1)  main          — stable releases
  2)  add-ons       — addon features in development
  3)  Custom branch — enter branch name manually
```

`main` is the right answer unless a maintainer told you otherwise. After a confirmation it downloads, extracts, copies every file in place and makes the scripts executable. Then it offers **Enter** to exit the toolkit completely (start it again to run the new code) or `0` to go back — going back runs a mixed set of old and new scripts, so exit.

- Files you edited locally are overwritten; files removed upstream are left behind. If you would rather update with git, `cd Grin-Node-Toolkit && git pull` does the same thing from the clone directory, and it is what [Getting started](getting-started.html#keeping-the-toolkit-up-to-date) recommends.
- To update from your own fork, save its `owner/repo` slug to `/opt/grin/conf/github_repo.conf`.
- Updating the toolkit does not touch a node; the node *binary* is updated by Script 01 → *Update Grin binary*.
- Products that keep a **copy** of code outside the clone — the solo-mining collector and stats page, Fidelius, GrinScan, the node event recorder, Script 04's status page and its collector, the Tiny Explorer, Global Grin Health's ecosystem checker — need their own "deploy new code" action afterwards (for the recorder: `6` → `7` → `I`; for Script 04: *Deploy / Update page* and *Enable REST API*; for the Tiny Explorer: *Update*; for the checker: *Install* under Network Stats); each product page says which.

## Backup & Restore (key 9)

Script 089 — the toolkit-wide encrypted backup, its schedule, the offsite push and the restore. It has [its own page](089-backup-restore.html). Take one before `DEL`, before a provider migration, and on a schedule.

## Full Grin Cleanup (key DEL)

Script 08del removes everything Grin from the server, in eight numbered steps plus two sub-steps, each confirmed. It **cannot be undone**.

> **Danger:** This deletes every wallet directory, the wallet seeds inside them, the backups in `/opt/grin/backups/`, the backup key file and the `.onion` identities. Funds in a wallet whose seed words you have not written down are lost for good. Back up first, copy the archive off the server, and check that you can read it ([Check it](089-backup-restore.html#check-it)) before you type `DESTROY`.

Before you start: take a [backup](089-backup-restore.html) and **copy the archive off the server** — step 4 below deletes `/opt/grin` wholesale, which includes `/opt/grin/backups/`, every wallet directory, and the backup key file. Write the wallet seed words down as well.

The screen opens with a red box listing the steps and asks you to type exactly `DESTROY`; anything else aborts with nothing changed. Then each step lists what it found and asks `[y/N]` before deleting it — you can say no to any step and yes to the next.

| Step | What it removes | Notes |
|------|-----------------|-------|
| 1 | Every running node and wallet process, and every `grin_*` tmux session on both tmux servers | First leaves [planned-stop markers](reference-glossary.html#planned-stop-marker), so the node event recorder logs the wipe as planned. Steps 4 and 5 refuse to run while a Grin process is alive |
| 2 | Web roots and data directories: nginx roots containing *grin*, `/var/www/fullmain`, `prunemain`, `prunetest`, any `/var/www/*grin*` and `/var/lib/*grin*` | Snapshots, dashboards, explorer sites |
| 3 | Grin nginx vhosts in `sites-available` and `sites-enabled`, the toolkit's rate-limit zone files; then `nginx -t` and a reload | nginx itself and Let's Encrypt certificates stay |
| 3b | Grin systemd units — `grin-*`, `grinscan-*`, `floonet-rs` services and timers — stopped, disabled and deleted | Fidelius, Drop, pool, explorer, transporter, relay, the secret-sync, access-watch and event-recorder timers |
| 3c | The [node event recorder](#node-event-recorder): worker, logrotate stanza, its library copies, its config (with your alert tokens) and `/opt/grin/node-events`, public status history and salt included | If evidence bundles exist it asks separately: *No* moves them, with the ledger, the public history and its salt, to `/root/grin-node-events-saved_<UTC>/` first |
| 4 | **`/opt/grin` entirely**, plus `/grin*`, `/usr/local/bin/grin*`, the Floonet relay binary and its `/etc` and `/var/lib` dirs, and anything else named `grin*` directly under `/opt`, `/usr/local/bin` or `/usr/bin` | Nodes, chain data, every wallet, keys vault, backups, logs, configs. The toolkit running the cleanup is kept; see the note below |
| 5 | `~/.grin` (a manual install's directory) | Only exists if grin was ever run by hand |
| 6 | `/var/log/grin*.log` and a `log/` folder in the clone | See note below |
| 7 | Grin lines from root's crontab, Grin `/etc/cron.d` files, Grin `/etc/logrotate.d` files | Each sub-step confirmed separately |
| 8 | The toolkit's Tor hidden services: their `torrc` blocks and the key directories under `/var/lib/tor/grin-*`, then a Tor reload | **This destroys the `.onion` identities** — back them up first if you will ever want the same addresses again |

What is left: nginx, certbot and its certificates, Tor itself, the `grin` system user, swapfiles under `/opt/grin/swap` (deleted with step 4, but their `/etc/fstab` lines remain — remove them by hand), the OS automatic security-update policy from [Automatic Security Updates](#automatic-security-updates) if you enabled it (the cleanup prints a reminder; use *Disable* before you delete the clone if you want it gone), and the toolkit clone, which you delete yourself. If you kept the event recorder's evidence at step 3c, it is in `/root/grin-node-events-saved_<UTC>/` — raw, unmasked logs, plus the public history's secret salt; delete it once you no longer need it. An admin user and `grinops` group made by the [guided SSH setup](#guided-setup-w), and the SSH drop-in, are not touched either.

> **Note:** If the toolkit clone lives directly under `/opt` with a name starting `grin` — the mass-deployment default is `/opt/grin-node-toolkit` — step 4 keeps it and prints `Kept: <path> (the toolkit running this cleanup)`. A clone **inside** a listed path, such as one under `/opt/grin`, is not kept: step 4 warns that the path contains the toolkit, and answering `y` deletes the toolkit too. To keep it, answer `N`, move the clone out, and run the cleanup again. Also, step 6 looks in `/var/log` and a `log/` folder that the toolkit never writes; the real logs in `/opt/grin/logs` went with step 4 — including this run's own log, so the *Review log* path printed at the end no longer exists.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| Node Status shows `[AUTH FAILED]` | The node is up; the secret on disk is not the one it loaded. `grin-secret-sync`, then restart the node if it persists |
| Node Status shows `[OFFLINE]` but `gtmux ls` shows a session | The node is inside its session but has not opened its port yet — a Grin node takes a few minutes after launch. Attach and read the log |
| *No grin tmux sessions found on either tmux server* while a node is running | The node was started by hand outside the toolkit. Stop it and start it with Script 01 → *Start a node* so it runs as `grin` on the grin socket |
| Diagnostics: `This tool must run as root` | 086 reads root-only state and refuses to run without it. Start the toolkit as root (`sudo -i` first if you log in as an admin user) |
| Diagnostics: `No running grin node` (CRIT) | No `grin server` process exists on the box. Start the node with Script 01, or find out why it exited: `gtmux ls`, then the node log — or the recorder's timeline if it is installed |
| Diagnostics: *No checks produced a result* | The probes did not run, so this is not a pass. Read the `grin_diagnostics_<date>.log` in `/opt/grin/logs/` |
| Recorder: `status is STALE: last check … ago` | The recorder's timer is not running. `6` → `7` → `S` for its state; `I` reinstalls the timer |
| Self-Update: *Download failed* | The name typed at *Custom branch* does not exist on GitHub, or there is no internet. Nothing was changed |
| Mass deployment: `Host key verification failed` on a server you rebuilt | The server has a new SSH key at the same address, and the fleet refuses a changed key. If you did rebuild it, run `ssh-keygen -R <host>` (for a port other than 22, `ssh-keygen -R "[<host>]:<port>"`), or remove and re-add the server. If you did not, find out why the key changed before connecting |
| Remote binary push: nodes down after it finished | Expected: `f` and `g` leave nodes stopped. Start them with Remote node control `a`, or reboot a server that has an autostart line |
| Ecosystem page still shows a row you hid | The checker has not run since, or it is an old copy that ignores the list. Press `r` on the `E` screen; if the row stays, re-run *Install* under Network Stats in Global Grin Health, then `r` again |
| Provider Access Watch reports the same finding every check | Something you changed yourself (a new key, a package upgrade that replaced `sshd`). Re-snapshot the baseline with `1` and save the new hash |
| Access Watch: *No alert channel configured* | Findings stay on the box. Set at least ntfy or Telegram in `4` and send a test |
| SSH: `Effective PasswordAuthentication: yes — the setting did NOT take` | Another sshd file sets the same keyword first (often `50-cloud-init.conf`). Press `f` to comment it out reversibly and re-check, or `q` to roll back |
| SSH: locked out after disabling passwords | If you used the safety timer and the server has not rebooted since, wait — passwords (and root SSH) return automatically. If not: the provider's console, then `6` (re-enable), or delete `/etc/ssh/sshd_config.d/00-grin-hardening.conf` (on a system without drop-ins, the block between the `grin-toolkit ssh hardening` marker lines at the end of `/etc/ssh/sshd_config`), remove the `#GRIN-DISABLED# ` prefix from any line that carries it, and reload sshd |
| SSH guided setup: *no successful publickey login found in the log yet* | Step 6 needs real evidence. Log in as the new user by key in a second terminal (not with a password), then press `r` |
| Host Optimization: *No checks produced a result* | The probes failed, usually because the tool was not run as root. Not a pass |
| Nginx audit: `<domain> — could not connect or no SSL` | The domain does not resolve to this server, port 443 is closed, or the vhost has no certificate yet |
| Swap: `swapoff failed … pages can't be relocated` | Not enough free memory to absorb the file's contents. Add another swapfile first, or stop the node, then remove |
| `DEL`: a step says *Grin processes are still running* | Step 1 was skipped or a process survived. Say yes to step 1 (or stop the process) and run again |

## Related

- [Getting started](getting-started.html) — the main menu, updating, removing everything
- [Back up and restore](089-backup-restore.html) — Script 089, key `9` on this hub
- [Script 01](01-build-node.html) — starting, rebuilding and updating the node this screen monitors, and the build step that offers the event recorder
- [Script 03](03-share-chain-data.html) — the community host registry the Remote Node Manager checks
- [Script 04](04-publish-node-api.html) — the supported way to expose the node API, and the onion identity that `DEL` step 8 destroys
- [Ports and paths](reference-ports-and-paths.html) — every port the status screen checks, and where the files under `/opt/grin` live
