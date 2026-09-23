---
title: Host a file server for chain snapshots
description: How Script 02 sets up an nginx file server with a Let's Encrypt certificate to distribute Grin chain snapshots, plus rate caps, fail2ban and IP blocking.
section: Scripts
order: 2
short: File server
label: Script 02
covers: 2026-09-19
updated: 2026-09-19
---

Script 02 turns your server into a web host for the chain snapshots that Script 03 produces. It installs **nginx** (a web server), asks for a domain name, gets a free HTTPS certificate from **Let's Encrypt**, and publishes a folder as a plain, browsable download page. Anyone running Script 01 anywhere in the world can then fetch your snapshot instead of syncing from genesis — the same way you fetched one when you built your node.

You need a synced node from [Script 01](01-build-node.html) and a domain name whose DNS you control. Script 02 sets up the *web host*; [Script 03](03-share-chain-data.html) then fills it with an archive and keeps it fresh.

## What it does

1. Installs nginx and **certbot** (the Let's Encrypt client) if they are missing, and opens ports 80 and 443 in the firewall.
2. Checks that a Grin node for the chosen network is actually running on this server, and works out from its configuration whether it is a pruned or a full archive node.
3. Creates the web folder — `/var/www/fullmain`, `/var/www/prunemain` or `/var/www/prunetest` — and writes an nginx site for your domain, first over plain HTTP.
4. Obtains the certificate, then rewrites the site for HTTPS only: HTTP redirects to HTTPS, HSTS is enabled, and the folder is served as a **directory listing** — a bare page of file names, sizes and dates.
5. Confirms certificate auto-renewal is in place.

Everything else on the menu is optional protection for a public download host: per-IP speed caps, request throttling with fail2ban, IP blocking, and a styled landing page in place of the bare listing.

## Before you start

| You need | Why |
|----------|-----|
| A running, synced node for the network you will share | The script refuses to set up a Grin domain when no node is listening on 3414 (mainnet) or 13414 (testnet), and derives the required subdomain from the node it finds |
| A domain name and access to its DNS | You will create an **A record** — `prunemain.yourdomain.com → your server's IP` — before running the script. Certificates are issued to the domain, not the IP |
| Ports **80** and **443** reachable from the internet | Let's Encrypt proves you own the domain by connecting to port 80; visitors download over 443. Open both in your provider's firewall or security group — the script handles the server-side firewall (ufw or firewalld) itself |
| An email address | Let's Encrypt sends certificate-expiry warnings there. Renewal is automatic; the email is a safety net |
| Free disk on `/var/www` at least the size of `chain_data` | The archive Script 03 writes here is close to the size of the chain data (the script checks and offers to clear the folder if it is short) |

> **Warning:** If your DNS is on Cloudflare, set the record to **DNS only** (grey cloud), not *Proxied*. Proxying hides your real IP: certbot cannot reach port 80 to validate the domain, and — for the Grin subdomains — other nodes connect directly to your IP to use your node as a peer, which the proxy breaks. Keep a Grin subdomain unproxied permanently. A custom domain can go back to *Proxied* once the certificate is issued.

## Choices you will make

### Which kind of site: a Grin snapshot host or a custom folder

The menu separates the two:

- **Grin Master Node domains** (menu 1 and 2) are for chain snapshots. The subdomain **must** start with one of three fixed prefixes, the folder is chosen for you, and the script checks that the matching node is running. These are the sites Script 03 publishes into and Script 01 downloads from.
- **Custom domains** (menu 3) serve any folder you like under any other name — `files.yourdomain.com` — with no Grin checks. Useful for sharing anything else from the same box.

### The three subdomain prefixes

The first label of the hostname is a **site key** that tells every other part of the toolkit what the snapshot is. It has to match the node on this server: the script reads the node's `grin-server.toml` and only accepts the prefix that fits.

| Prefix | Serves | Web folder | Node it requires |
|--------|--------|------------|------------------|
| `fullmain.` | Mainnet full archive snapshot | `/var/www/fullmain` | Mainnet, `archive_mode = true` |
| `prunemain.` | Mainnet pruned snapshot | `/var/www/prunemain` | Mainnet, pruned |
| `prunetest.` | Testnet pruned snapshot | `/var/www/prunetest` | Testnet, pruned |

So a server running a pruned mainnet node and a pruned testnet node gets two domains — `prunemain.yourdomain.com` and `prunetest.yourdomain.com` — one per menu entry. A server can hold at most one mainnet domain and one testnet domain; to change one, remove it first (menu 4).

These prefixes are reserved: a custom domain (menu 3) cannot use them, and cannot point at the three folders above.

## The menu

```text
╔════════════════════════════════════════════════════════════════╗
║     02)   Nginx Server Management Script                       ║
╚════════════════════════════════════════════════════════════════╝

Select an action:

  1) Setup 1st Grin Master Node domain  - Mainnet  (fullmain / prunemain)
  2) Setup 2nd Grin Master Node domain  - Testnet  (prunetest)
  3) Add Custom Domain                  - Any non-Grin domain
  4) Remove Domain                      - Remove domain and its configuration
  5) List Domains                       - Show all configured domains

  6) Limit Rate / Bandwidth     - Set per-IP speed cap (anti-DDoS / abuse)
  7) Lift Rate / Bandwidth      - Remove or reset per-IP speed cap
  8) Install fail2ban           - Install & configure fail2ban for nginx
  9) Fail2ban Management        - Status, unban IPs, list bans
 10) IP Filtering               - Block / Unblock IPs via ufw or iptables

 11) Landing Page               - Styled download page instead of the bare file list

  0) Exit

Enter choice [0-11]:
```

| Key | Action |
|-----|--------|
| `1` | Set up the **mainnet** snapshot domain — `fullmain.` or `prunemain.`, whichever matches the running node |
| `2` | Set up the **testnet** snapshot domain — `prunetest.` |
| `3` | Serve any other folder under any other domain; optionally with a monthly per-IP download quota |
| `4` | Remove a domain: its nginx site, certificate and logs. The files are kept unless you say otherwise |
| `5` | List every nginx site on the server with its folder, whether it is enabled and whether it has a certificate |
| `6` / `7` | Add or lift [download speed caps](#per-ip-speed-caps-menu-6-and-7), per IP or for everyone |
| `8` / `9` | Install [fail2ban with request throttling](#request-throttling-and-fail2ban-menu-8-and-9), then check its status and unban addresses |
| `10` | [Block or unblock](#blocking-addresses-menu-10) an IP or a network range in the firewall |
| `11` | Replace the bare file list with a [styled landing page](#the-landing-page-menu-11) |
| `0` | Back to the main menu |

The script returns to this menu after every action. Each session is logged to `/opt/grin/logs/nginx-session-<date>.log`.

## Setting up a Grin domain, step by step

Create the DNS A record first, wait until `ping prunemain.yourdomain.com` answers with your server's IP, then pick `1` (mainnet) or `2` (testnet).

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | nginx and certbot are checked; if either is missing you get one `Install now?` prompt. Ports 80/443 are opened in ufw or firewalld if one is active | `Y` |
| 2 | The script looks for a Grin node on the network's P2P port. With none running it stops: *No mainnet Grin node detected on port 3414* | Start or build the node with Script 01, then come back |
| 3 | If this network already has a domain, it is shown and the script stops — remove it with `4` first if you want to change it | — |
| 4 | Domain prompt. It prints the prefix your node requires (only `fullmain` for an archive node, only `prunemain` for a pruned one) and rejects anything else | Type the full hostname, e.g. `prunemain.yourdomain.com`; `0` cancels |
| 5 | Email prompt for Let's Encrypt | Type an address you read |
| 6 | The web folder is set from the prefix and shown. The script compares the node's `chain_data` size with free space on `/var/www`; if there is not enough it offers to empty the folder | Accept the cleanup if offered, or free space first |
| 7 | Summary: domain, email, folder | `Proceed with setup? (Y/n/0)` — `Y` |
| 8 | The folder is created and handed to the web user (`www-data` on Ubuntu/Debian, `nginx` on Rocky/Alma). An HTTP-only nginx site is written, enabled and loaded | Wait |
| 9 | `certbot --nginx` requests the certificate. If it fails the script prints the four usual causes (DNS not pointing here, 80/443 closed, a firewall, Cloudflare proxy on) and **exits** — fix the cause and run the option again | Wait |
| 10 | The site is rewritten for HTTPS: port 80 redirects, port 443 serves the folder with HSTS and security headers, human-readable sizes, local times. `nginx -t` is run before the reload; on failure the previous config is restored | Wait |
| 11 | Auto-renewal check: certbot's systemd timer (or cron job) is confirmed and a `certbot renew --dry-run` is tried | Wait |
| 12 | Summary: URL, folder, how to add files, log paths | Read it |

The HTTP-first-then-HTTPS order is deliberate: nginx refuses to start a site that references a certificate file which does not exist yet, so the site goes live on port 80, certbot uses it to prove ownership, and only then is the HTTPS version written.

## After it finishes

Open `https://prunemain.yourdomain.com/` in a browser. You should see an empty directory listing over a valid certificate — empty because nothing has been published yet; that is Script 03's job. From a shell:

```bash
curl -sI https://prunemain.yourdomain.com/ | head -1     # HTTP/2 200
curl -sI http://prunemain.yourdomain.com/  | head -1     # HTTP/1.1 301 (redirect to https)
sudo nginx -t                                            # syntax is ok / test is successful
```

Once Script 03 has run, the listing shows the archive and its companions, and a visitor sees exactly what you saw when Script 01 downloaded your snapshot:

```text
chaindata.json                          machine-readable manifest — Script 01 reads this first
check_status_before_download.txt        "Sync completed…" or "Sync is in progress. DO NOT download…"
grin_pruned_mainnet_20260919.tar.gz     the snapshot
grin_pruned_mainnet_20260919.sha256     its checksum
README.txt                              download and install instructions for humans
```

[prunemain.grin.money](https://prunemain.grin.money) is a live example — with the landing page from menu `11` installed rather than the bare list.

### What was created

| Path | Purpose |
|------|---------|
| `/etc/nginx/sites-available/<domain>` | The site configuration (symlinked from `sites-enabled/`) |
| `/var/www/fullmain`, `/var/www/prunemain` or `/var/www/prunetest` | The web root Script 03 publishes into |
| `/etc/letsencrypt/live/<domain>/` | The certificate and key, renewed by certbot's timer |
| `/var/log/nginx/<domain>-access.log`, `<domain>-error.log` | Per-site request and error logs |
| `/opt/grin/logs/nginx-session-<date>.log` | This session's log |

Custom domains (menu `3`) default to `/var/www/fileserver` or a folder you name. With the quota option on they also get `/usr/local/bin/nginx-bandwidth-limiter.sh`, a `/etc/cron.d/nginx-bandwidth-limiter` job every 5 minutes with a monthly reset, and a `/var/log/nginx/<domain>-bandwidth.log`.

> **Warning:** Answer **N** to *Enable bandwidth limiting?* when adding a custom domain. The quota feature places an nginx `map` block inside the site's `server` block, which nginx rejects, so the setup stops at the *Enhancing Nginx configuration* step with the certificate already issued. This is a toolkit bug, noted for the maintainers. For per-IP caps use menu `6` instead — that path is separate and works on any site the script created.

## Protecting a public download host

A snapshot host serves multi-gigabyte files to strangers. The rest of the menu lets you limit what one visitor can take and shut out abusers. None of it is required; a small host with a modest bandwidth allowance will want at least a default speed cap.

### Per-IP speed caps (menu 6 and 7)

Speed caps are applied with nginx's `limit_rate`, which caps **each connection** — a client opening two connections gets twice the rate. Values are written as `500k` (500 KB/s) or `5m` (5 MB/s).

```text
  1) Set per-IP speed cap          - cap a specific IP address
  2) Set default rate for all IPs  - apply a global cap to all visitors
  3) Enable for a domain           - inject rate limit into a site config
  0) Back to main menu
```

The caps live in one file, `/etc/nginx/conf.d/grin_ip_limits.conf`, as a table from IP to bytes per second with a default of `0` (unlimited). Setting a cap with `1` or `2` also injects the `limit_rate` directive into every site the script created; `3` does that injection alone, for a site added later. The screen above the menu always shows the current default, the per-IP overrides and which sites have the directive.

Menu `7` undoes it: lift one IP's cap, clear every cap (default back to unlimited), or take the directive out of one site.

### Request throttling and fail2ban (menu 8 and 9)

**fail2ban** watches log files and temporarily bans addresses that misbehave. Menu `8` runs four steps in one go:

1. Installs fail2ban (`apt`; on Rocky/Alma via the EPEL repository).
2. Creates an nginx request-rate zone, `grin_req`, at **20 requests per second** per IP (`/etc/nginx/conf.d/script02-fileserver.conf`), and adds `limit_req zone=grin_req burst=30 nodelay` to every site the script created. Above the limit a client gets HTTP 429 and nginx logs the event.
3. Writes `/etc/fail2ban/jail.d/nginx-grin.conf` with three jails: `nginx-limit-req` (10 rate-limit hits within 60 s → banned 10 min), `nginx-botsearch` (2 requests for known exploit paths → banned 1 h), and `nginx-http-auth` (3 failed logins → banned 1 h; rarely relevant on a file server).
4. Enables and restarts fail2ban, then reloads nginx.

> **Note:** There is no menu action that removes the request limit again — menu `7` only lifts the *speed* caps from menu `6`. To turn throttling off, delete the two `limit_req` lines from the site in `/etc/nginx/sites-available/`, run `nginx -t` and reload nginx.

Menu `9` is the day-to-day view:

```text
  A) Overall status          - All jails (nginx-botsearch / nginx-http-auth / nginx-limit-req / sshd)
  B) Check nginx-http-auth   - Detailed status of nginx-http-auth jail
  C) Unban an IP             - Remove a ban from nginx-http-auth
  D) List banned IPs         - Top 50 IPs banned in nginx-http-auth
  0) Back to main menu
```

Each report is also saved under `/opt/grin/logs/fail2ban_*.log`. `C` and `D` act on the `nginx-http-auth` jail only; for the jail that actually bans downloaders use the CLI: `fail2ban-client set nginx-limit-req unbanip 1.2.3.4`.

### Blocking addresses (menu 10)

Blocks a single IP or a CIDR range (`1.2.3.0/24`) in whichever firewall is active — firewalld, ufw, or raw iptables — with an optional note, and records it in `/etc/grin-toolkit/blocked_ips.list` so you can unblock or list later. Blocks are server-wide, not just for nginx. With no firewall installed, blocking is unavailable and the script says so.

## The landing page (menu 11)

The bare directory listing works but tells a visitor nothing. Menu `11` replaces it, for one of your snapshot sites, with a styled download page that:

- shows the latest snapshot — name, size, checksum, how long ago it was built — with a download button, copy-ready install commands for Linux/macOS, Windows and streaming extraction, and a table of every file;
- polls the site every 20 seconds, so while Script 03 is rebuilding the archive the page **blocks the download** and points visitors at the other mirrors from the community registry (`mirrors.json`, copied from `extensions/grinmasternodes.json`);
- adds `robots.txt`, `sitemap.xml` and a logo, and optionally a Google Analytics 4 tag (asked once, kept in `/etc/grin-toolkit/landing.conf`; leave blank for none).

Pick the site, and the script writes `index.html` and the support files into the web root and patches the nginx site. Script 01 and other tools still get the plain listing: the root URL serves the page only to browsers and the file list to everything else, and a JSON listing is exposed at `/__listing/`. For an already-installed page the menu offers **Regenerate** (refresh page, mirror list and SEO files) or **Remove** (back to the bare listing).

Script 03 deliberately leaves `index.html` and these support files alone when it clears old archives, so the page survives every rebuild.

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| See which sites exist and whether they have certificates | Script 02 → `5` |
| Check the certificate will renew | `sudo certbot renew --dry-run`. Renewal runs from certbot's own timer; nothing in the toolkit needs to run |
| Move the snapshot site to a new domain | Script 02 → `4` to remove the old one (keep the files), fix DNS, then `1` or `2` with the new name |
| Slow everyone down to protect my bandwidth allowance | Script 02 → `6` → `2`, e.g. `5m` |
| Give one address a lower cap without affecting others | Script 02 → `6` → `1` |
| See who is hammering the server | `tail -f /var/log/nginx/<domain>-access.log`, and Script 02 → `9` → `A` if fail2ban is installed |
| Block a persistent abuser outright | Script 02 → `10` → `1` |
| Share a different folder under another name | Script 02 → `3` (answer `N` to bandwidth limiting) |
| Get listed as a community snapshot host | Run Script 03 until the listing shows an archive, then follow the registry steps on [its page](03-share-chain-data.html#join-the-community-registry) |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `No mainnet Grin node detected on port 3414` (or testnet on 13414) | The Grin domain options need the node running, not just installed. Script 01 → `S` starts it; give it a few minutes to open its ports, then retry |
| `Prefix 'files' is not valid for mainnet` / `…reserved for Grin Master Nodes` | Grin domains must start with `fullmain`, `prunemain` or `prunetest` and must match the node; custom domains may not use those names. Use the other menu entry |
| `Failed to obtain SSL certificate` | The domain does not resolve to this server yet, port 80 is closed in the provider firewall, or Cloudflare proxy is on. The script exits after this message; fix the cause and run the option again — the HTTP-only site it left behind is harmless |
| `A Grin mainnet domain is already configured` | One per network. Script 02 → `4` removes the old one; keep the files when asked if the snapshot folder should stay |
| `Nginx configuration test failed` | Another site or a hand-edited file is broken. Run `nginx -t` yourself — it names the file and line. The script restores its own previous config before reporting this |
| `Insufficient free space — chain_data (~N GiB) exceeds available` | Script 03 will not be able to write the archive. Accept the folder cleanup if offered, or free space on the partition holding `/var/www` |
| Visitors get HTTP 429 | The request limit from menu `8` (20 requests/s) is triggering — usually a download manager opening many connections. Raise the rate in `/etc/nginx/conf.d/script02-fileserver.conf` or remove the `limit_req` lines from the site |
| A legitimate address is banned | Script 02 → `9` → `C` for the `nginx-http-auth` jail, or `fail2ban-client set nginx-limit-req unbanip <ip>` for the request-limit jail |
| `fail2ban is not installed. Run option 7 (Install fail2ban) first` | The message's number is stale — installing fail2ban is menu `8` |
| `No file-server domains found` in menu `11` | The landing page only installs on a site with directory listing on — a Grin or custom domain created by menu `1`–`3`. Set one up first |

## Related

- [Script 01](01-build-node.html) — the node whose snapshot you will share must be running on this server
- [Script 03](03-share-chain-data.html) — compresses the chain data into this web folder and keeps it fresh on a schedule
- [Script 04](04-publish-node-api.html) — publishes the node API over HTTPS on another subdomain, alongside this file server
- [Script 08](08-admin-maintenance.html) — [Nginx extended features](08-admin-maintenance.html#nginx-extended-features-key-4), and the [Remote Node Manager](08-admin-maintenance.html#remote-node-manager-key-1) that checks every community snapshot host
