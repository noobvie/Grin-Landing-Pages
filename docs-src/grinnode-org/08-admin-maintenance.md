---
title: Admin and maintenance
description: Script 08: node status, a remote fleet monitor, host-tamper alerts, host tuning advice, nginx extras, key-only SSH, disk cleanup, self-update and uninstall.
section: Scripts
order: 8
short: Admin
label: Script 08
covers: 2026-09-20
updated: 2026-09-20
---

Script 08 is the operations toolbox. Nothing here installs a Grin product; everything here keeps the server that runs them healthy, watched and up to date. It is also home to the two things every operator eventually needs — [backups](089-backup-restore.html) and the [full uninstall](#full-grin-cleanup-key-del).

If you are new, learn one screen first: **Node Status & Sync** (key `5`). It answers "is my node running, and is it caught up?" for both networks without any typing.

## The menu

Hub 08 is the one hub where the key *is* the script number: each numbered sub-script sits on its last digit (081 → `1`, 082 → `2`, 083 → `3`, 084 → `4`, 089 → `9`) and the un-numbered built-in screens fill the gaps. These keys are stable and this page uses them.

```text
  Monitoring & Host
  1)   Remote Node Manager       monitor · mass deploy · remote control
  2)   Provider Access Watch     host-tamper detection + off-box alerts
  3)   Host Optimization & Hard. profile CPU/RAM/IO → tuning advice

  Network & Status
  4)   Nginx Extended Features   audit · reverse proxy · security · logs
  5)   Node Status & Sync        ports, tmux, versions + chain tip
  6)   Top 20 Bandwidth Consumers parse nginx logs, block/limit IP

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
| `2` | [Provider Access Watch](#provider-access-watch-key-2) — script 082 | Installs a small watcher and a systemd timer |
| `3` | [Host Optimization & Hardening](#host-optimization-hardening-key-3) — script 083, with SSH Key Hardening (085) inside it | The advisor changes nothing; the SSH tool does |
| `4` | [Nginx Extended Features](#nginx-extended-features-key-4) — script 084 | Yes — writes nginx config |
| `5` | [Node Status & Sync](#node-status-sync-key-5) | No — read-only |
| `6` | [Top 20 Bandwidth Consumers](#top-20-bandwidth-consumers-key-6) | Only if you block or rate-limit an IP |
| `7` | [Disk Cleanup](#disk-cleanup-key-7), with the automatic cleanup and the swap manager | Yes — deletes files |
| `8` | [Self-Update](#self-update-key-8) | Yes — overwrites the toolkit's files |
| `9` | [Backup & Restore](089-backup-restore.html) — script 089, its own page | Yes |
| `DEL` | [Full Grin Cleanup](#full-grin-cleanup-key-del) — script 08del | **Removes everything** |

Two keys changed hands on 2026-08-25: `3` used to be Node Status and `5` used to be SSH Key Hardening. There is deliberately no alias for the old meanings — every screen prints its own banner, so a mis-key is obvious before anything happens. Key `10` still opens Backup & Restore (its old slot) as a silent alias.

Every screen writes its run to `/opt/grin/logs/` — the admin hub itself to `grin_admin_<date>.log`, each sub-script to its own `grin_<name>_<date>.log`. On the hub's own screens (`6`, `7`) a value prompt accepts `q` to cancel.

## Node Status & Sync (key 5)

One read-only screen, three parts:

1. **Port status** — whether anything listens on the eight toolkit ports: node API 3413 / 13413, P2P 3414 / 13414, wallet listener 3415 / 13415, stratum 3416 / 13416, with the PID. A wallet port marked ⚠ is one you should not expose to the internet.
2. **tmux sessions** — every `grin*` session on *both* tmux servers: the `grin` user's socket (where the toolkit starts nodes; attach with `gtmux attach -t <name>`) and root's (`tmux attach -t <name>`). A session on the root socket next to one on the grin socket is the classic duplicate-node situation — see [Script 01's troubleshooting](01-build-node.html#troubleshooting).
3. **Running Grin processes and binary versions** — each `grin` process and the `--version` of every distinct binary.

Then **Chain Sync** asks each node for its tip over the Foreign API and reports one of:

| Line | Meaning |
|------|---------|
| `[ONLINE]` with height, last block, difficulty | The node answered. Compare the height with [grinscan.org](https://grinscan.org) (mainnet) or [test.grinscan.org](https://test.grinscan.org) (testnet) to see how far behind it is |
| `[OFFLINE] — nothing listening on port N` | No node on that port. Start it with Script 01 → `S` |
| `[NO SECRET]` | The port is open but the node's `.foreign_api_secret` could not be read. Run `grin-secret-sync` |
| `[AUTH FAILED]` with HTTP 401 or 403 | The node is **running**; the secret on disk is not the one it loaded. Run `grin-secret-sync`, and if it persists restart the node |
| `[NO DATA]` or `[API ERROR]` | The node answered with something other than a tip — usually still starting up. Wait a few minutes |

A healthy node reads `[ONLINE]` with a height that moves between two runs a minute apart. The screen distinguishes "node down" from "wrong credential" on purpose: an empty reply used to be reported as offline, and a perfectly healthy node looked dead.

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
| Manage server list | List, add, remove, test every connection, and **Bootstrap SSH keys** — generates `/root/.ssh/grin_deploy` (ed25519, no passphrase) if missing, prints the public key, then runs `ssh-copy-id` to each server (asks for that server's password once) and verifies key login |
| Push toolkit update | Downloads a branch tarball on each selected server and copies it over its toolkit directory — the remote equivalent of [Self-Update](#self-update-key-8) |
| Run command | Runs one shell command on the selected servers and shows each reply |
| Remote node control | `a` start, `b` stop, `c` restart the Grin nodes on the selected servers (both tmux sockets, as the `grin` user — the same rules as Script 01); `d` upgrade the grin binary; `e` reboot after a one-minute delay, with a confirmation |

Every action asks which servers: `all` or a comma-separated list of numbers.

> **Warning:** Two remote actions do not work as shipped (verified against GitHub on 2026-09-20, not on a server). *Upgrade grin binary* looks for a release asset named `linux-amd64`, but grin publishes `linux-x86_64`, so it stops with *could not get latest release URL* — upgrade with Script 01 → `B` on each box instead. And *Push toolkit update* offers the branches `addons` and `corefeatures`, which do not exist on GitHub (the branch is `add-ons`; there is no `corefeatures`) — those two choices download nothing. `main` works; for `add-ons` use *Custom branch* and type the name with the hyphen.

Remote *start* launches every installed node at once, without the 1000-second stagger Script 01 uses; on a small VPS expect the second node to take a long time to open its ports.

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

**Set it up in this order:** `1` snapshot a baseline on a box you trust right now — then **copy the printed SHA-256 off the server** (a notes app, a password manager). An intruder can rewrite the baseline file on the box to hide their changes, but not your saved copy of its hash; if the hash in `6` ever differs from your note, the baseline itself was tampered with. Then `4` configure at least one alert channel — a finding that only lands in a log on the same server the intruder is on is worthless — and `6` to send a test. Then `5` enable the timer; the default interval is **15 minutes** (first run 2 minutes after boot).

| Channel | What you enter | Notes |
|---------|----------------|-------|
| ntfy | A topic URL such as `https://ntfy.sh/<random-topic>` | Simplest; pick an unguessable topic name |
| Telegram | Bot token from @BotFather, and your chat id | |
| Email | An address | Needs `sendmail`, `mail` or `msmtp` on the box |
| Nostr | Secret key and relay URL | Needs `nak` (or `nostril` + `websocat`) installed; otherwise logged as skipped |

Every configured channel is tried independently. Standing findings (a changed file, a new key) alert once and again only if the set of findings changes; events (a login, a clock jump) alert once each. `5` in the alert menu toggles the new-login alert, which is on by default — turn it off if your own logins are frequent.

**What was created:** `/opt/grin/access-watch.sh` (the worker, reinstalled on every launch), `grin-access-watch.service` and `.timer`, `/opt/grin/conf/access-watch/` (mode 700) holding `baseline`, `alert.conf` (mode 600 — your tokens) and `state/`, and the log `/opt/grin/logs/access-watch.log`. Re-snapshot the baseline after *you* change something it watches (a new SSH key, a system upgrade that replaces `sshd`), or every check will keep reporting it.

> **Note:** Built 2026-07-25 and checked only by syntax and code reading — it has not been run on a VPS. Test every alert channel with `6` before trusting it.

## Host Optimization & Hardening (key 3)

Script 083 profiles the VPS — CPU, RAM, disk, kernel settings, time sync, logging, firewall, SSH — and reports what a Grin node needs from *this* box, sized from what it measured. It is **advisory only**: nothing on the host is changed, and every finding carries the exact `fix:` command for you to run and review. That is deliberate for a remote server: a wrong `sysctl` is recoverable, but `ufw enable` before an SSH allow-rule leaves a box you can only reach from the provider's console.

```text
  Report
  1)   Full report               every check, grouped by area
  2)   Export report to file     plain text, for pasting or keeping

  Single area
  3)   CPU & memory              cores, steal, RAM, swap sizing
  4)   Disk & IO                 space, device type, scheduler, atime
  5)   Kernel & node limits      sysctl, THP, fd limits, peer count
  6)   Security & firewall       ufw, exposed node API, updates

  Hardening
  7)   SSH posture               read-only summary of SSH config
  8)   SSH Key Hardening →       open the SSH tool (makes changes)
```

Findings are graded **CRIT** / **WARN** / **INFO** / **OK** / **NA**. The full report is longer than a screen, so it is shown in a pager — press `q` to leave it — and ends with an explicit `[END]` marker so you know nothing was cut off. `2` writes the same report, without colour, to `/opt/grin/reports/` as `host_optimization_<date>.txt` (mode 600 — it lists open ports and firewall state).

The checks that matter most for a Grin node:

- **Node API bound to all interfaces** — 3413 / 13413 reachable from the internet is CRIT with no firewall, WARN with ufw in the way, OK on loopback. Publish the API the supported way, with [Script 04](04-publish-node-api.html), never by opening the port.
- **Firewall installed but off**, or no firewall at all — CRIT.
- **No swap**, or swap too small for the cold-boot rebuild a node does — a 2 GB box needs it. Add it from [Disk Cleanup → Swap manager](#disk-cleanup-key-7).
- **`vm.swappiness` too high**, transparent hugepages set to *always* (hurts the node's LMDB database), a low open-file limit, an inbound peer limit that is too high for the RAM (Script 01 sets 999, which is right for a big box and wrong for a small one).
- **No time synchronisation** — peers reject blocks from a node whose clock drifts.
- **Pending security updates**, no `unattended-upgrades`, no `fail2ban`.

A summary of **zero findings is reported as a failed run, not a pass** — the probes did not work (usually: not root).

> **Note:** Built 2026-08-25 and never run on a VPS. The sizing thresholds (peer tiers by RAM, swap sizes) are labelled heuristics; read a finding's observed value before running its fix.

### SSH Key Hardening (script 085)

`7` shows your SSH posture; `8` opens the only tool in the toolkit that *changes* SSH: script 085, which had its own hub key until 2026-08-25. Its job is to get a public key onto the server, prove that key login works, and only then turn password login off — with a guaranteed way back.

```text
  1)  Add a public key          paste · generate on server · fetch URL
  2)  List installed keys       fingerprints in /root/.ssh/authorized_keys
  3)  Verify key login          anti-lockout self-test (run this first!)
  4)  Disable password login    key-only; optional safety timer
  5)  Make key-only permanent   cancel safety timer after testing
  6)  Re-enable password login  rollback / break-glass
  7)  SSH status & audit        effective config, keys, firewall
  8)  How to connect with key   remote-tool steps (Windows/Linux/macOS)
```

Do it in order: `1` → `3` → `4` → test in a second terminal → `5`.

- **Add a key** three ways: paste the `.pub` line from your laptop (recommended); generate a pair on the server, in which case the private key is shown **once** for you to copy and you are asked to delete the server's copy; or fetch a *public* key from a URL such as `github.com/<user>.keys`. Private keys are never fetched from anywhere.
- **Verify key login** checks `authorized_keys`, permissions, `sshd -t`, that public-key auth is enabled, how *this* session authenticated, and tries a loopback login with the key.
- **Disable password login** writes `PasswordAuthentication no`, `KbdInteractiveAuthentication no` and `PermitRootLogin prohibit-password` — to a drop-in, `99-grin-hardening.conf` in `/etc/ssh/sshd_config.d/`, where the distro supports it — validates with `sshd -t` before applying, and **reloads** sshd rather than restarting it, so your current session survives. It refuses to run with no key installed.

> **Danger:** Do not lock yourself out. Choose the **safety timer** (`A`, default 5 minutes) unless you have *already* logged in with the key in another terminal. With the timer, passwords come back on their own unless you return and press `5` to commit. If you did test first and pick `B`, you are asked to confirm it once more. `6` is the break-glass at any time — but it only helps if you can still get in, which is the point of testing first. The tool also warns if ufw is active with no rule for your SSH port.

Every change backs up the previous config to `/opt/grin/conf/ssh_backups/`. The scope is the root account only, which is the account the toolkit runs as.

## Nginx Extended Features (key 4)

Script 084 is for the nginx you already have from Scripts 02, 04, 06 or a wallet product. It never touches the file-server vhosts (`fullmain`, `prunemain`, `prunetest` and their web roots are reserved for [Script 02](02-nginx-fileserver.html)).

```text
  1)  Config & SSL Audit       nginx -t, cert expiry, enabled/disabled check
  2)  Reverse Proxy Manager    add · remove · list reverse proxy vhosts
  3)  Enhance Security         harden SSL settings and HTTP security headers
  4)  Log Rotation Setup       configure logrotate (10 MB or 10 days)
```

**Config & SSL Audit** runs `nginx -t`, lists every file in `sites-available` with whether it is enabled, its type (proxy or file server) and its upstream or root, then connects to each `server_name` on port 443 and reports the certificate's days to expiry — yellow at 30 days or less, red at 14. Read-only.

**Reverse Proxy Manager** puts any local web service behind HTTPS on its own domain: `A` asks for the domain, a Let's Encrypt email and the upstream URL (for example `http://127.0.0.1:3000`), writes an HTTP-only vhost, runs `certbot --nginx`, then writes the full HTTPS vhost with WebSocket support, the standard forwarding headers, an HTTPS redirect and HSTS, and adds a daily `certbot renew` cron if none exists. The domain must already point at this server. `R` removes a proxy (optionally deleting its certificate), `L` lists them.

**Enhance Security** edits `nginx.conf` in place — `server_tokens off`, TLS 1.2 and 1.3 only with a modern cipher list — and writes `/etc/nginx/conf.d/security-headers.conf` with four headers (`X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`) for every site, then tests and reloads. Runs without asking.

> **Note:** nginx's `add_header` is not additive: a `server` or `location` block that sets *any* header of its own discards this global set for that block. The toolkit's own vhosts (Script 04, the pool, Fidelius…) all set their own headers, so on those sites the four global headers are simply not in force — that is expected, they carry stricter sets of their own.

**Log Rotation Setup** writes `/etc/logrotate.d/nginx-grin` for `/var/log/nginx/*.log`, then runs a dry run.

> **Note:** Two things to know before pressing `4` (from reading the code, not from a server). Debian and Ubuntu's nginx package already ships `/etc/logrotate.d/nginx` for the same files, so logrotate will report a *duplicate log entry* and skip the second definition; the dry-run output shown on screen is where you would see that. And the policy it prints — "10 MB or 10 days, whichever first" — is not what `size 10M` means in logrotate: `size` makes rotation depend on size alone and ignores `daily`. If the packaged config is present you do not need this one.

## Top 20 Bandwidth Consumers (key 6)

Parses every access log under `/var/log/nginx/` and ranks the twenty client IPs that were served the most bytes — the quick answer to "who is downloading my chain snapshots all day?". Then `1` lets you enter an IP and either **block it** (`ufw deny from <ip>`, after a confirmation) or **rate-limit it** with an iptables `hashlimit` rule (over 25 connections a minute gets dropped, burst 100). The iptables rule is not saved anywhere, so it is gone after a reboot; the ufw rule persists. Without ufw the screen prints the equivalent `iptables` command instead of running it.

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

- **`/opt/grin` breakdown** — read it first. `node/` (chain data) and `backups/` are the usual large ones; chain data is never touched here (use Script 01 → `R` for a corrupted chain), and old backup archives are pruned by [the backup schedule's retention](089-backup-restore.html#schedule-automatic-backups).
- **`6` nginx web dir contents** — this is where Script 03's snapshot archives are (`/var/www/prunemain` and friends). Emptying one deletes the archive, its checksum and status file, *and* Script 02's landing page for that site; Script 03's next scheduled publish writes a fresh archive, and Script 02 must re-deploy the landing page. Prefer Script 03's own settings for keeping fewer archives.
- **`D` system journal** — `journalctl --vacuum-time=<N>d`, asks for N (default 7).
- **`A` /tmp** — files older than a day.
- **`7` automatic cleanup** — installs `/opt/grin/auto_cleanup.sh` and a cron entry (`/etc/cron.d/grin-auto-cleanup`, daily at **04:30**) that deletes txhashset fast-sync snapshot files under `/tmp` and `/opt/grin/node`, and every file in `/opt/grin/logs` older than N days (default 7). It also installs `/etc/logrotate.d/grin-toolkit-logs`, which rotates the toolkit's continuous logs (watchdogs, collectors, backup pushes) once they pass 10 MB, keeping four compressed rotations. Enable this on every server; `3` inside runs it now.

> **Note:** Three rows measure paths the toolkit does not use, so on a toolkit-built server they always show nothing to clean: *Chain Data Tar Archives* scans `/var/www/html/grin` (Script 03 writes to `/var/www/prunemain` etc. — use `6`), *Grin node logs* (`C`) looks in `~/.grin/main/log` (node logs are in each node directory and rotate via logrotate when Super Auto set it up), and *Grin-toolkit logs* (`E`) looks in `/var/log` (toolkit logs are in `/opt/grin/logs`, pruned by `7`). Not a fault of your server.

### Swap manager

`8` manages a *stack* of swapfiles under `/opt/grin/swap/` (`swap-001`, `swap-002`…), each with its own `/etc/fstab` entry so it is back after a reboot. **Add** creates a new file of N GB and enables it without touching the existing swap — safe even while swap is in use; **Remove** disables and deletes one file, and fails loudly (without deleting) if the kernel cannot move its pages elsewhere. A pre-existing `/swapfile` from Script 01 or the distro is listed and can be removed from here too. Script 01 already adds 2 GB (4 GB on a box under 2 GB RAM); the Host Optimization report tells you if that is too little.

## Self-Update (key 8)

Downloads the toolkit from GitHub as a tarball and copies it over the directory this toolkit runs from. You pick the branch:

```text
  1)  main          — stable releases
  2)  add-ons       — addon features in development
  3)  corefeatures  — core features in development
  4)  publicpool    — public mining pool development
  5)  Custom branch — enter branch name manually
```

`main` is the right answer unless a maintainer told you otherwise. After a confirmation it downloads, extracts, copies every file in place and makes the scripts executable. Then it offers **Enter** to exit the toolkit completely (start it again to run the new code) or `0` to go back — going back runs a mixed set of old and new scripts, so exit.

- Files you edited locally are overwritten; files removed upstream are left behind. If you would rather update with git, `cd Grin-Node-Toolkit && git pull` does the same thing from the clone directory, and it is what [Getting started](getting-started.html#keeping-the-toolkit-up-to-date) recommends.
- To update from your own fork, save its `owner/repo` slug to `/opt/grin/conf/github_repo.conf`.
- Updating the toolkit does not touch a node; the node *binary* is updated by Script 01 → `B`.
- Products that keep a **copy** of code outside the clone — the solo-mining collector and stats page, Fidelius, GrinScan — need their own "deploy new code" action afterwards; each product page says which.

> **Note:** Branch `3` (`corefeatures`) does not exist on GitHub and the download fails with *Download failed. Check your internet connection or branch name* (verified 2026-09-20). Nothing is changed when a download fails.

## Backup & Restore (key 9)

Script 089 — the toolkit-wide encrypted backup, its schedule, the offsite push and the restore. It has [its own page](089-backup-restore.html). Take one before `DEL`, before a provider migration, and on a schedule.

## Full Grin Cleanup (key DEL)

Script 08del removes everything Grin from the server, in eight confirmed steps. It **cannot be undone**.

Before you start: take a [backup](089-backup-restore.html) and **copy the archive off the server** — step 4 below deletes `/opt/grin` wholesale, which includes `/opt/grin/backups/`, every wallet directory, and the backup key file. Write the wallet seed words down as well.

The screen opens with a red box listing the eight steps and asks you to type exactly `DESTROY`; anything else aborts with nothing changed. Then each step lists what it found and asks `[y/N]` before deleting it — you can say no to any step and yes to the next.

| Step | What it removes | Notes |
|------|-----------------|-------|
| 1 | Every running node and wallet process, and every `grin_*` tmux session on both tmux servers | Steps 4 and 5 refuse to run while a Grin process is alive |
| 2 | Web roots and data directories: nginx roots containing *grin*, `/var/www/fullmain`, `prunemain`, `prunetest`, any `/var/www/*grin*` and `/var/lib/*grin*` | Snapshots, dashboards, explorer sites |
| 3 | Grin nginx vhosts in `sites-available` and `sites-enabled`, the toolkit's rate-limit zone files; then `nginx -t` and a reload | nginx itself and Let's Encrypt certificates stay |
| 3b | Grin systemd units — `grin-*`, `grinscan-*`, `floonet-rs` services and timers — stopped, disabled and deleted | Fidelius, Drop, pool, explorer, transporter, relay, the secret-sync and access-watch timers |
| 4 | **`/opt/grin` entirely**, plus `/grin*`, `/usr/local/bin/grin*`, the Floonet relay binary and its `/etc` and `/var/lib` dirs, and anything else named `grin*` directly under `/opt`, `/usr/local/bin` or `/usr/bin` | Nodes, chain data, every wallet, keys vault, backups, logs, configs |
| 5 | `~/.grin` (a manual install's directory) | Only exists if grin was ever run by hand |
| 6 | `/var/log/grin*.log` and a `log/` folder in the clone | See note below |
| 7 | Grin lines from root's crontab, Grin `/etc/cron.d` files, Grin `/etc/logrotate.d` files | Each sub-step confirmed separately |
| 8 | The toolkit's Tor hidden services: their `torrc` blocks and the key directories under `/var/lib/tor/grin-*`, then a Tor reload | **This destroys the `.onion` identities** — back them up first if you will ever want the same addresses again |

What is left: nginx, certbot and its certificates, Tor itself, the `grin` system user, swapfiles under `/opt/grin/swap` (deleted with step 4, but their `/etc/fstab` lines remain — remove them by hand), and the toolkit clone, which you delete yourself.

> **Note:** If the toolkit clone lives directly under `/opt` with a name starting `grin` — the mass-deployment default is `/opt/grin-node-toolkit` — step 4's scan lists it too, and confirming would delete the running toolkit mid-run. Check step 4's list before answering. Also, step 6 looks in `/var/log` and a `log/` folder that the toolkit never writes; the real logs in `/opt/grin/logs` went with step 4 — including this run's own log, so the *Review log* path printed at the end no longer exists.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| Node Status shows `[AUTH FAILED]` | The node is up; the secret on disk is not the one it loaded. `grin-secret-sync`, then restart the node if it persists |
| Node Status shows `[OFFLINE]` but `gtmux ls` shows a session | The node is inside its session but has not opened its port yet — a Grin node takes a few minutes after launch. Attach and read the log |
| *No grin tmux sessions found on either tmux server* while a node is running | The node was started by hand outside the toolkit. Stop it and start it with Script 01 → `S` so it runs as `grin` on the grin socket |
| Remote *Upgrade grin binary*: `could not get latest release URL` | The script looks for a `linux-amd64` asset; grin publishes `linux-x86_64`. Use Script 01 → `B` on each server |
| Self-Update or Push toolkit update: *Download failed* | Branch does not exist (`corefeatures`; `addons` in the mass-deploy menu — the real name is `add-ons`), or no internet. Nothing was changed |
| Provider Access Watch reports the same finding every check | Something you changed yourself (a new key, a package upgrade that replaced `sshd`). Re-snapshot the baseline with `1` and save the new hash |
| Access Watch: *No alert channel configured* | Findings stay on the box. Set at least ntfy or Telegram in `4` and send a test |
| SSH: locked out after disabling passwords | If you used the safety timer, wait — passwords return automatically. If not: the provider's console, then `6` (re-enable) or delete `/etc/ssh/sshd_config.d/99-grin-hardening.conf` and reload sshd |
| Host Optimization: *No checks produced a result* | The probes failed, usually because the tool was not run as root. Not a pass |
| Nginx audit: `<domain> — could not connect or no SSL` | The domain does not resolve to this server, port 443 is closed, or the vhost has no certificate yet |
| Swap: `swapoff failed … pages can't be relocated` | Not enough free memory to absorb the file's contents. Add another swapfile first, or stop the node, then remove |
| `DEL`: a step says *Grin processes are still running* | Step 1 was skipped or a process survived. Say yes to step 1 (or stop the process) and run again |

## Related

- [Getting started](getting-started.html) — the main menu, updating, removing everything
- [Back up and restore](089-backup-restore.html) — Script 089, key `9` on this hub
- [Script 01](01-build-node.html) — starting, rebuilding and updating the node this screen monitors
- [Script 03](03-share-chain-data.html) — the community host registry the Remote Node Manager checks
- [Script 04](04-publish-node-api.html) — the supported way to expose the node API, and the onion identity that `DEL` step 8 destroys
- [Ports and paths](reference-ports-and-paths.html) — every port the status screen checks, and where the files under `/opt/grin` live
