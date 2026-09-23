---
title: Troubleshooting
description: Every error message in the Grin Node Toolkit manual in one A–Z index, plus problems any script can hit: GLIBC, permissions, busy ports, certbot, 401.
section: Reference
order: 3
covers: 2026-09-23
updated: 2026-09-23
---

Start here when something fails and you are not sure which page covers it. The first section covers the problems that can come from any script; below it is an index of every symptom listed on the other pages of this manual, sorted A–Z, each linked to the row that explains it.

## Where to look first

Most problems name their own cause somewhere on the server. Read that before changing anything.

| What failed | Where the reason is |
|-------------|---------------------|
| A toolkit menu action | The log it names when it finishes, under `/opt/grin/logs/` — one file per run; `ls -t /opt/grin/logs` lists the newest first |
| A node | Its own log, `grin-server.log` in the node directory, or the live screen: `gtmux attach -t grin_pruned_mainnet` (detach with Ctrl+B, then D) |
| A web app, wallet listener or other service | `systemctl status <service>` and `journalctl -u <service> -n 50` |
| A website | `/var/log/nginx/`, and `nginx -t` for the configuration |
| A certificate | `/var/log/letsencrypt/letsencrypt.log` |
| Everything at once | [Admin & Maintenance → Node Status & Sync](08-admin-maintenance.html#node-status-sync-key-5) shows every node, port and session on one screen |

When you ask for help on [GitHub](https://github.com/noobvie/Grin-Node-Toolkit/issues), attach the run's log file. Check it for anything private before you post it.

## Problems any script can hit

These show up on many pages because they come from the server, not from one product.

| Symptom | Cause and fix |
|---------|---------------|
| `version 'GLIBC_2.38' not found` | The distribution is too old for the official Grin binaries; the node and the wallets both need glibc 2.38 or newer. Reinstall the server on Ubuntu 24.04. **Never upgrade glibc by hand** — it breaks the whole system. Script 01 → `G` can build the node from source, but the wallet products still need a new enough system. See [What you need](getting-started.html#what-you-need) |
| A node will not start after being run by hand: `Permission denied`, or `lock file is held by another grin process` | The node was once started as root, which leaves root-owned files behind, or a second copy is still running on the other tmux server. Start nodes only from the menu: Script 01 → `K` stops every copy, then `S` starts it as the `grin` user and repairs file ownership. See [Script 01 troubleshooting](01-build-node.html#troubleshooting) |
| `Address already in use`, *port … is in use* or *held by ANOTHER process* | Two programs want the same port. Find the owner with `ss -ltnp` and look for the port number. Common collisions: two wallet products on one server (3415 / 3420), the public pool's API and another app on 8080, Fidelius's private access and the pool on WireGuard 51820/udp. Stop the other program or move one of them — the toolkit never kills a process it did not start. Every default is on [Ports and paths](reference-ports-and-paths.html) |
| `certbot failed`, *Failed to obtain SSL certificate* | Let's Encrypt could not reach your domain on port 80. Check, in this order: the A record points at this server (`dig +short sub.yourdomain.com` against `curl -4 ifconfig.me`); an **AAAA** record, if you have one, points here too, because Let's Encrypt tries IPv6 first; port 80 is open at the provider; Cloudflare is set to *DNS only* for the name while the certificate is issued. Wait for DNS changes to spread, then run the option again. Repeated failures can hit Let's Encrypt's rate limit — wait an hour |
| HTTP **401** from a node API | The caller's secret does not match what the running node loaded. The usual cause is editing a secret file while the node runs: restart the node. After a node rebuild, `grin-secret-sync` re-points every consumer within 5 minutes, or run it by hand now. For the public API, re-run [Script 04](04-publish-node-api.html#troubleshooting) → `4` |
| `nginx config test failed`, or `nginx -t` reports an error | One file in `/etc/nginx/` is broken. It is not necessarily the site you were changing. Run `nginx -t`: it names the file and line. Common causes: a site that points at a certificate that was never issued, a hand edit, or a leftover site from an old install. Fix or remove that file and test again. A failed test does not take running sites down — nginx keeps its old configuration until a reload succeeds — but do not restart nginx or reboot until the test passes, because that is when a broken file stops every site |

## Every symptom, A–Z

Type part of the message into the filter, or use your browser's find. Each entry opens the row on its own page, which gives the cause and the fix.

<div data-symptom-index></div>

## Related

- [Glossary](reference-glossary.html) — the terms these messages use
- [Ports and paths](reference-ports-and-paths.html) — which port belongs to what
- [Getting started](getting-started.html#common-first-run-problems) — the problems of a first run
