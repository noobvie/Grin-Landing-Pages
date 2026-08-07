# Grin Landing Pages

Landing pages for the Grin ecosystem — currently
[grin.money](https://grin.money) and [grinnode.org](https://grinnode.org).
Each edition lives in `web/<site-name>-<year>/` so every version is preserved.

Sites are plain HTML/CSS/JS — zero dependencies, zero build step.

The deployment script is **domain-agnostic** and fully interactive — run it,
pick a menu option, follow the prompts.

---

## Repo Structure

```
Grin-Landing-Pages/
├── site_manager.sh                # interactive menu — run this
├── deploy/
│   ├── sites.conf                 # site manifest (batch git deploy: key→domain)
│   ├── analytics.conf             # GA4 site→ID map
│   ├── custom_repo.conf           # git deploy config
│   └── installer.conf             # install.ps1 publishing config
├── snippets/
│   └── ga4.html                   # GA4 reference (documentation only)
└── web/
    ├── grin-money-2026/           # grin.money
    └── grinnode-org-2026/         # grinnode.org
```

Config files in `deploy/` are committed with working defaults — edit in place.

---

## Sites

| Directory | Domain | Purpose |
|---|---|---|
| `web/grin-money-2026/` | [grin.money](https://grin.money) | Main landing — wallets, ecosystem, toolkit |
| `web/grinnode-org-2026/` | [grinnode.org](https://grinnode.org) | Node operator hub — Linux toolkit, Grim wallet |

---

## Quick Start

```bash
git clone https://github.com/noobvie/Grin-Landing-Pages.git
cd Grin-Landing-Pages
chmod 775 site_manager.sh
sudo ./site_manager.sh
```

The interactive menu handles everything from there.

---

## Menu Options

| # | Option | What it does |
|---|---|---|
| 1 | Add Domain | nginx vhost + Let's Encrypt SSL + security headers |
| 2 | Remove Domain | Remove nginx config, optionally revoke SSL |
| 3 | Deploy Site | Push/pull static files (local, rsync, git, or **ALL** — batch every site in `deploy/sites.conf`) |
| 4 | List Sites | Show all configured nginx sites with SSL status |
| 5 | Security Hardening | Audit/apply security headers, certbot auto-renewal |
| 6 | Install fail2ban | Install & configure fail2ban for nginx |
| 7 | fail2ban Mgmt | View bans, unban IPs |
| 8 | IP Filtering | Block/unblock IPs via ufw / iptables / firewalld |
| 9 | Update Script | `git pull` latest site_manager.sh |
| A | Analytics (GA4) | Manually tag a directory you submit — any web server (deploys tag automatically) |
| G | Desktop Installer | Publish `install.ps1` to `<domain>/install` |

### nginx config generated per domain

- HTTPS redirect, HTTP/2
- HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- Rate limiting (10 req/s, burst 30)
- Blocks `.php`, `.env`, `.git`, dotfiles, common attack paths
- 1-year immutable cache for static assets
- Per-domain access and error logs

---

## Batch Deploy — many sites at once (`deploy/sites.conf`)

Deploying 10+ sites one prompt-at-a-time doesn't scale. Declare every site once
in `deploy/sites.conf` (one row per site), then publish them all in a single
pass — each `web/<key>/` is copied straight from the clone on the server to its
web dir. Web dir is derived from the domain automatically — no per-site typing:

```
# <site_key>          <domain>          [web_dir_override]
grin-money-2026       grin.money
grinnode-org-2026     grinnode.org
some-other-2026       example.org       /var/www/custom/pub
```

- `site_key` matches a subdirectory under `web/` (same key as `analytics.conf`).
- `domain` → web dir `<nginx_root>/<domain>/public` (override column optional).
- GA4 is joined on `site_key` from `analytics.conf` and applied per site.

When ≥2 sites are listed, **Deploy Site (3)** detects them and asks
*"Deploy ALL N sites now?"* up front (answer `n` to fall back to single-site).
Or run it unattended:

```bash
# Publish every site in one pass (run on the server):
sudo ./site_manager.sh --action deploy --all

# Refresh content + publish all, hourly, via cron:
0 * * * * /path/to/site_manager.sh --action self_update --auto-confirm \
    && /path/to/site_manager.sh --action deploy --all \
    >> /var/log/grin-sites-deploy.log 2>&1
```

Content is published **from the clone on the server** (no re-clone) — refresh it
first with **option 9** or `git pull`. Each `web/<key>/` is rsynced to its web
dir, GA4 applied, ownership reapplied. The run prints a `deployed / skipped`
summary and exits non-zero if any site failed (cron-friendly).

---

## GA4 Analytics (Option A)

Each site maps to its own GA4 Measurement ID in `deploy/analytics.conf`:

```
grin-money-2026="G-98GRB5MKDT"
grinnode-org-2026="G-EERXEJ55PZ"
```

**Every deploy mode tags automatically** — you do not normally need option A.
`local`, `git` and `ALL` inject into the published web dir after the copy;
`rsync` stages the source in a temp dir, tags that, and pushes it. The git
source tree is never modified, so pulls never collide on generated files.

Option **A** is the manual/repair path: it asks for **one directory** and one
GA4 ID, then tags every top-level `*.html` in it. Use it when the target isn't
reachable by a deploy mode — a site on another web server (apache, caddy, a
static host), a directory whose name doesn't match an `analytics.conf` key, or
a one-off ID. It suggests an ID when the folder's basename matches a config
key, but any `G-XXXXXXXXXX` can be typed in. It also offers to set ownership,
since a non-nginx server may not run as `www-data`.

Injection is idempotent: a page that already carries the loader has its ID
**corrected** rather than duplicated, so changing an ID in `analytics.conf` and
re-deploying replaces the old one everywhere.

---

## Desktop Installer (Option G)

Publishes the PowerShell installer from
[Grin-Money-Desktop](https://github.com/noobvie/Grin-Money-Desktop) so users
can run:

```powershell
irm https://grin.money/install | iex
```

Config is in `deploy/installer.conf`. Use menu option **G** — the script clones
the repo, verifies the file, deploys it, and prints the nginx location block to
add if needed.

For unattended hourly deploys via cron, use `--auto-confirm`:

```bash
0 * * * * /path/to/site_manager.sh --action deploy-installer --auto-confirm \
    >> /var/log/grin-installer-deploy.log 2>&1
```

---

## Requirements

- **Server**: Linux (Debian/Ubuntu or RHEL/Rocky/Alma), bash 4+, nginx, certbot (auto-installed)
- **Local (rsync deploy)**: `rsync`, SSH key access to server
- **Local (macOS)**: Homebrew, bash 4+
- **Windows**: run inside WSL

## Logs

Per-action logs: `/opt/grin-landing/logs/site_<action>_YYYYMMDD_HHMMSS.log`
