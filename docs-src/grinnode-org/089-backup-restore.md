---
title: Back up and restore
description: What the toolkit-wide backup (Script 089) captures and leaves out, the one personal key, scheduling, the offsite push, and restoring onto a fresh server.
section: Scripts
order: 8.9
short: Backups
label: Script 089
covers: 2026-09-20
updated: 2026-09-20
---

Script 089 — **Admin & Maintenance → Backup & Restore**, key `9` — makes one encrypted archive of everything on the server that you could not simply reinstall: configuration, API secrets, wallet seeds, product databases, nginx sites, certificates, cron schedules and Tor identities. Chain data is deliberately left out — a new node gets it from a snapshot in minutes. The same script restores such an archive, schedules unattended backups, and pushes every archive to another machine over SSH.

Several products carry their own backup as well (solo mining, Grin Drop, the public pool, the relay, the Transporter). They all share this script's engine, key and archive folder; [the last section](#other-backups-in-the-toolkit) says which archive holds what, because **two wallets are not in this one**.

## What is backed up

A backup walks these sources. "Ask" means an interactive backup asks `[Y/n]`; the scheduled backup takes the default.

| Source | Ask? | What it holds |
|--------|------|---------------|
| `/opt/grin/conf/` | Always | Every small config the scripts share — node locations, product settings, the wallets registry, watchdog and schedule state. The two backup-key files inside it are **excluded** |
| `/opt/grin/keys/` | Always | The node API secret vault, which is what keeps `.api_secret` and `.foreign_api_secret` the same across a node rebuild — and, after a restore, on a new server |
| Grin nginx sites | Always | Every file in `sites-available` whose name contains *grin* or whose root is a Grin web root, plus a list of which were enabled |
| `/etc/letsencrypt/live` and `renewal` | Always | Your certificates |
| root and `www-data` crontabs | Always | Collector, snapshot and backup schedules |
| Wallets in the registry | Ask (default yes) | The directories listed in `/opt/grin/conf/grin_wallets_location.conf` — today that is the CMD wallet from [hub 05](05-wallet-services.html#the-cmd-wallet-quick-setup), `/opt/grin/cmdwallet/<network>/`, seed included |
| Grin Drop | Ask (default yes) | `/opt/grin/drop-<net>/` (config, secrets, wallet seed) and the database in `drop-<net>-data/`; a second question includes or skips the LMDB `wallet_data/` |
| Product databases | Always | `grin-stats/stats.db` and `config.env`, `grin-price/grin-price.db`, both GrinScan databases, every `solo-stats/*.db` — each taken as a consistent **online snapshot** (`sqlite3 .backup`), so a collector writing at that moment does not produce a torn copy |
| Tor onion identities | Ask (default yes) | `/var/lib/tor/grin-<network>-raw-tcp` (Script 01's node onion), `grin-<network>-nginx` (Script 04's API onion) and the legacy `grin-<network>` — the **secret key** that *is* the `.onion` address |
| Floonet relay | Ask (default yes) | `/etc/floonet-rs/` and the relay's databases (NIP-05 usernames, stored events) |
| Fidelius | Ask (default yes) | Every `/opt/grin/fidelius/wallet_<network>_*` directory found on disk, with the registry `wallets_info.json`, `config.conf` and `wallet.env` — seeds included |
| Accio gateway state | Ask (default yes) | `/opt/grin/accio-<net>/gateway-state/` and `gateway.json` — the table that maps each wallet to its receiving address; not a cache |
| `/opt/grin/logs/` | Ask (default **no**) | Logs |

**Not included, on purpose:** `chain_data/` (Script 01 rebuilds it from a snapshot), the node and wallet binaries (re-downloaded; a *source-built* node binary from Script 01 → `G` is the one thing you would have to recompile), `/var/www/` (every product re-deploys its web files), Fidelius's and Accio's application code, the GrinScan and pool applications.

> **Warning:** Two wallets that hold real money are **not** in this archive, and the script does not say so on screen:
> - the **solo-mining wallet** (`/opt/grin/solowallet/<network>/`, seed and saved passphrase) — the solo setup never writes the registry this script reads, so only its stats databases are captured. Use [the solo menu's own backup](07-mining-services.html#backups).
> - the **public pool wallet** and pool database — covered by [the pool's own backup](07-public-pool.html#backups-and-scheduled-tasks), by design.
>
> And one that *is* captured but is **not put back by the restore menu**: the CMD wallet. The restore only writes wallets back to `/opt/grin/wallet/`, a folder no current script creates, so `/opt/grin/cmdwallet/` stays in the archive. [Restoring it by hand](#restore-on-a-fresh-server) is a one-line `tar`. (Read from the code, not verified on a server.)

Whatever the archive holds, the **24 seed words** written on paper are the backup that needs no key, no server and no toolkit. Have both.

## Before you start

| Need | Why |
|------|-----|
| A **personal key** you will never lose | Every archive is encrypted with it; without it a backup is noise. See below |
| `openssl` and `sqlite3` | Encryption, and the consistent database snapshots. Script 01 installs both; without `sqlite3` databases are live-copied instead, which is usually fine |
| Somewhere **off the server** to keep archives | A backup that lives only on the box it protects is lost with the box. The offsite push does this automatically |
| For the offsite push: a second machine reachable over SSH | Any Linux box or VPS with a user that owns one directory |

## The menu

```text
  9  Backup & Restore — Grin Node Toolkit

  Auto-backup: not scheduled
  Offsite push: not configured

  B)  Backup now
      Saves conf, wallets, ALL product DBs (online snapshot), nginx, SSL, crontabs · encrypted

  S)  Schedule automatic backup
      Daily or 2 days per week · random off-peak time

  R)  Restore from a backup
      Restores files from a previous backup archive

  P)  Offsite push (scp to a remote server)
      Auto-copy every finished archive to a remote box over ssh

  0)  Return
```

Key `10` on the admin hub still reaches this screen (its slot before 2026-08-05).

## The personal key

The first backup or schedule asks you to invent a **personal key** (at least 4 characters, typed twice). It is stored, base64-encoded, in `/opt/grin/conf/grin_backup.conf` (mode 600) so that scheduled backups can encrypt without you, and it is **shared by every product backup on the server** — solo, Drop, pool, relay, Transporter and this one all use it.

Each archive's password is the key followed by the date in its filename: `<personal key><DDMMYYYY>`. The date part is read from the filename at restore time; the key part you type by hand. The key file is never inside an archive, so an archive by itself tells an attacker nothing.

> **Danger:** Write the key down somewhere that is not this server. If you forget it *and* lose the server, every archive is permanently unreadable — the wallet seeds inside them included. The script says this in red when you set it; it means it.

Changing the key: this screen has no "change key" action — a key is only asked for when none exists. The product backup menus (Grin Drop, solo, pool, relay, Transporter) each have a *set key* item that replaces the shared key for **future** archives; older archives keep needing the key they were made with. If you had a per-product key from before 2026-07-10, the first run adopts it as the shared key.

## Backup now, step by step

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | Destination. Default `/opt/grin/backups/` | Enter for the default, or another path |
| — | Personal key: loaded from the key file, or set now if there is none | Type it twice the first time |
| 2 | Collects the always-on sources (conf, keys vault, nginx, Let's Encrypt, crontabs) and lists each with ✓ or — | Nothing |
| 3 | Wallets from the registry | `Y` |
| 4 | Grin Drop, if installed; then whether to include its `wallet_data/` | `Y`, `Y` |
| 5 | Product databases, listed with sizes (`stats.db` can be ~100 MB) | Nothing |
| 5b–5e | Tor identities, Floonet relay, Fidelius, Accio — each only if present, each `[Y/n]` | `Y` |
| 6 | Logs | Usually `n` |
| 7 | Writes a `MANIFEST.txt`, snapshots the databases, builds the tar, encrypts it with AES-256-CBC (PBKDF2, 600 000 iterations), moves it into place with mode 600, pushes it offsite if configured | Wait |

The result is one file in `/opt/grin/backups/`:

```text
grin_toolkit_backup_<DDMMYYYY>.tar.gz.enc
```

**One archive per day** — a second backup the same day overwrites the first. The screen ends by reminding you that the password is your key plus that date.

### Check it

```bash
ls -la /opt/grin/backups/
# read the manifest without restoring anything (asks for the personal key + date)
D=20092026   # the DDMMYYYY from the filename
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in /opt/grin/backups/grin_toolkit_backup_$D.tar.gz.enc | tar -tzf - | head -40
```

`openssl` prompts for the password; type your key immediately followed by the date. A listing that starts with `MANIFEST.txt` and `crontabs/` is a good archive; *bad decrypt* means the key or date was wrong.

## Schedule automatic backups

`S` installs a line in root's crontab that runs the backup unattended with the defaults above (wallets, Drop, identities included; logs excluded) and then prunes old archives.

| Choice | Options |
|--------|---------|
| Frequency | Daily, or two days a week that you pick (1 = Monday … 7 = Sunday) |
| Time | Chosen for you at random from ten off-peak slots between 01:00 and 04:30, so a fleet of servers does not all back up at once. Shown before you confirm |
| Retention | 7, 14 or 30 days, keep all, or a custom number. After each run, this script's archives older than that in the backup folder are deleted |

The entry is tagged so the menu can show, replace or remove it, and looks like:

```text
30 3 * * * bash /path/to/scripts/089_backup_restore.sh --auto-backup --keep-days 14
``` A scheduled run **fails, silently, until a personal key exists** — the menu makes you set one before it installs the schedule, but a box that got its cron line before the shared key existed needs one set from this screen once. The run's log lines land in a `grin_backup_restore_<date>.log` file in `/opt/grin/logs/`.

## Offsite push

`P` sends every finished archive — this one and every product's — to one remote machine with `scp`, right after it is created. It uses a dedicated passphrase-less SSH key, `/root/.ssh/grin_backup_push_ed25519`, because cron cannot type a passphrase; protect the *remote* side instead by giving the push a low-privilege user that owns only the backup directory.

```text
  1) Configure target        (host / port / user / dir · generates the key)
  2) Show target-host command  (paste on the remote to authorize)
  3) Send key with ssh-copy-id (asks the remote password once)
  4) Test connection
  5) Remote retention days
  6) Push newest archives now (seed the remote with current backups)
  7) Catch-up retry cron      (re-push newest if it missed the remote)
  E) Enable    D) Disable (target kept)
```

Set it up as `1` → `2` or `3` → `4` → `E`, then `6` once to copy what you already have. `5` prunes archives on the remote older than N days (0 keeps all); `7` installs a cron that re-sends the newest archive if a push failed while the remote was down. A failed push never fails the backup — the local archive stays, the failure is logged to `/opt/grin/logs/backup-push.log`, and the target is saved in `/opt/grin/conf/grin_backup_remote.conf` (mode 600, never inside an archive).

Only current-format archives are safe to store where others might read them; archives named `temp_dir_*` from before 2026-07-10 derived their password from the filename and should be treated as readable by anyone who has the file.

## Restore on a fresh server

The restore writes files back where they came from and re-enables the nginx sites it finds; it does not install software. So the order on a new server is: **toolkit → restore → Script 01 → each product's setup**. Restoring *before* building the node is what lets Script 01 pick the old API secrets up from the restored vault and reuse the restored `.onion` key, so wallets and mirrors that knew the old server keep working.

1. Install the toolkit ([Getting started](getting-started.html)) and run it once so `/opt/grin/` exists.
2. Copy the archive over: `mkdir -p /opt/grin/backups` then `scp` the `.enc` file into it from wherever you keep archives.
3. **Admin & Maintenance → Backup & Restore → `R`.** Pick the archive from the list (or `C` for a custom path). Type the personal key; the date is read from the filename. The manifest is shown — read it — then confirm.
4. The restore stops Tor while it swaps identity directories (and Fidelius if it is running), puts files back with the permissions each service expects, re-enables the nginx sites that were enabled, runs `nginx -t` and reloads if it passes, and prints *Next steps*.
5. **Script 01** — build the node(s) the old server had. Step 8b restores the API secrets from the vault; step 13b reuses the onion key. Then `grin-secret-sync` once.
6. Each product's own setup for the software the archive does not carry: [Fidelius](051-fidelius.html) steps 1 and 3, [Grin Drop](059-grin-drop.html) install, [GrinScan](06b-grinscan.html) and [Script 06](06-global-health.html) install, the [Floonet relay](09-connectivity-hub.html#guided-setup-step-by-step) (Script 09 → Floonet Relay → guided setup). Their restored configs and databases are picked up as the services start.
7. Point DNS at the new server. Let's Encrypt certificates came with the archive; renewal works again once a product setup has installed certbot (its package timer, or the cron [Script 02](02-nginx-fileserver.html) writes, takes it from there).
8. Set the personal key again (the key file is never in an archive) — the same key, so the naming of future archives stays consistent — and re-create the schedule and the offsite target.

**The CMD wallet by hand.** If the manifest lists `wallet: /opt/grin/cmdwallet/...`, put it back yourself before starting its listener:

```bash
D=20092026   # date from the archive name
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in /opt/grin/backups/grin_toolkit_backup_$D.tar.gz.enc -out /root/restore.tar.gz
tar -xzf /root/restore.tar.gz -C / opt/grin/cmdwallet
chmod -R go-rwx /opt/grin/cmdwallet && rm /root/restore.tar.gz
```

> **Warning:** Restoring onto a **running** server overwrites what is there. Stop the node and every wallet listener first — extracting a wallet's `wallet_data/` (an LMDB database) over an open wallet can corrupt it. The restore screen warns about this and then does not check.

> **Note:** The full sequence above is assembled from the scripts' own *Next steps* and from how Script 01 treats an existing vault and onion key; it has not been rehearsed end-to-end on a fresh VPS. Rehearse it on a throw-away server before you depend on it.

## Test your restore

A backup you have never restored is a hope, not a backup. Once, and after any big change:

- Rent the cheapest VPS for an hour, run the sequence above with testnet only, and check that **Node Status & Sync** shows the node, that a restored wallet reports the expected balance with `grin-wallet info`, and that a restored `.onion` hostname matches the old one.
- At minimum, run the `openssl … | tar -tzf -` listing from [Check it](#check-it) on the *offsite* copy, from the offsite machine — that proves the key, the date and the transfer in one go.

## What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/backups/grin_toolkit_backup_<DDMMYYYY>.tar.gz.enc` | The archive, mode 600, directory mode 700 |
| `/opt/grin/conf/grin_backup.conf` | The personal key (base64, mode 600) — shared by every product backup |
| `/opt/grin/conf/grin_backup_remote.conf` | The offsite target, when configured |
| `/root/.ssh/grin_backup_push_ed25519` | The dedicated push key |
| `/usr/local/bin/grin-backup-push` | The push command cron wrappers call |
| `/opt/grin/logs/grin_backup_restore_<date>.log`, `backup-push.log` | Logs |
| `/opt/grin/temp/` | Where archives from before 2026-07-10 were kept; still restorable from `R`, never pruned |

## Other backups in the toolkit

All of these use the same key, the same folder and the same name pattern, and all are pushed offsite by the same target.

| Archive | Made by | Holds |
|---------|---------|-------|
| `grin_toolkit_backup_*` | This page | Everything in the table above |
| `grin_solo_backup_*` | [Solo mining → Backups](07-mining-services.html#backups) | The **solo wallet** (seed, passphrase), its config and stats — the only archive with this seed |
| `grin_drop_backup_*` | [Grin Drop → Backups](059-grin-drop.html#backups) | The Drop wallet and database (also in the toolkit archive) |
| `grin_pubpool_backup_*`, `grin_pubpooltestnet_backup_*` | [Public pool → Backups](07-public-pool.html#backups-and-scheduled-tasks) | The **pool wallet**, pool database, WireGuard identity, vhost — not in the toolkit archive |
| `grin_tor_onion_<net>.tar.gz` | [Script 04 → `V`](04-publish-node-api.html#the-tor-onion) | The API onion's key files, **unencrypted** (also in the toolkit archive, encrypted) |
| Relay and Transporter archives | Their `B` menus on [Script 09](09-connectivity-hub.html) | Relay config and databases (also here); the Transporter queue (only there) |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| *Wrong key or corrupt backup* on restore | The key is not the one in force when the archive was made, or you included the date — the restore adds the date itself. Try the previous key if it was changed since |
| `bad decrypt` from a manual `openssl` | Password must be key immediately followed by `DDMMYYYY` from the filename, no space |
| Scheduled backup never appears | No personal key existed when cron ran; the run logs *no backup personal key set* and stops. Open this screen, `B` once to set the key, done |
| *Backup needs a personal key* / *Scheduling needs a personal key* | You cancelled the key prompt. Set one |
| `~ live copy (no .backup)` next to a database | `sqlite3` is missing or the snapshot timed out (60 s); the file was copied live after a checkpoint. Install `sqlite3` for consistent snapshots |
| *Archive came out empty (zero bytes)* | Disk full while writing. Free space (Disk Cleanup) and retry; nothing was kept or pushed |
| *Offsite push FAILED — local archive is safe* | Remote down, key not authorised, or wrong path. `P` → `4` to test; `7` installs the catch-up retry |
| Restored a wallet, `grin-wallet info` shows nothing | The wallet's `node_api_secret_path` points at the old node's secret file. `grin-secret-sync` re-points every wallet at the live node |
| CMD wallet missing after restore | Expected — see [Restore on a fresh server](#restore-on-a-fresh-server) for the manual extraction |
| `nginx config test failed — fix before reloading` after restore | A restored vhost references a certificate that is not on this box yet, or a product not yet reinstalled. Disable that site, install the product, re-enable |

## Related

- [Admin and maintenance](08-admin-maintenance.html) — the hub this lives on, and the full uninstall that deletes `/opt/grin/backups` with everything else
- [Script 01](01-build-node.html) — the node build that reuses the restored secrets and onion key
- [Script 04](04-publish-node-api.html) — the onion identity backup and recovery for the published API
- [Solo mining](07-mining-services.html#backups) and [Public pool](07-public-pool.html#backups-and-scheduled-tasks) — the two wallets this archive does not hold
- [Grin Drop](059-grin-drop.html#backups) · [Fidelius](051-fidelius.html#backups-and-seeds) — what each expects after a restore
- [Ports and paths](reference-ports-and-paths.html) — the `/opt/grin` layout the archive mirrors
