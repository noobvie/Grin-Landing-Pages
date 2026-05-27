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
│   ├── analytics.conf.example     # GA4 site→ID map
│   ├── custom_repo.conf.example   # git deploy config
│   └── installer.conf.example     # install.ps1 publishing config
├── snippets/
│   └── ga4.html                   # GA4 reference (documentation only)
└── web/
    ├── grin-money-2026/           # grin.money
    └── grinnode-org-2026/         # grinnode.org
```

Config files in `deploy/` follow the same pattern: copy the `.example`, edit it,
the real file is git-ignored.

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
| 3 | Deploy Site | Push/pull static files (local, rsync, or git) |
| 4 | List Sites | Show all configured nginx sites with SSL status |
| 5 | Security Hardening | Audit/apply security headers, certbot auto-renewal |
| 6 | Install fail2ban | Install & configure fail2ban for nginx |
| 7 | fail2ban Mgmt | View bans, unban IPs |
| 8 | IP Filtering | Block/unblock IPs via ufw / iptables / firewalld |
| 9 | Update Script | `git pull` latest site_manager.sh |
| A | Analytics (GA4) | Inject/update GA4 tracking (config-driven, multi-site) |
| G | Desktop Installer | Publish `install.ps1` to `<domain>/install` |

### nginx config generated per domain

- HTTPS redirect, HTTP/2
- HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- Rate limiting (10 req/s, burst 30)
- Blocks `.php`, `.env`, `.git`, dotfiles, common attack paths
- 1-year immutable cache for static assets
- Per-domain access and error logs

---

## GA4 Analytics (Option A)

Each site maps to its own GA4 Measurement ID via `deploy/analytics.conf`.

```bash
cp deploy/analytics.conf.example deploy/analytics.conf
```

Example config:

```
grin-money-2026="G-98GRB5MKDT"
grinnode-org-2026="G-EERXEJ55PZ"
```

Run option **A** from the menu — it offers batch (all sites) or single-site
processing. Changing an ID in the config and re-running replaces the old ID
everywhere automatically.

---

## Desktop Installer (Option G)

Publishes the PowerShell installer from
[Grin-Money-Desktop](https://github.com/noobvie/Grin-Money-Desktop) so users
can run:

```powershell
irm https://grin.money/install | iex
```

First run: `cp deploy/installer.conf.example deploy/installer.conf` and edit it.
Then use menu option **G** — the script clones the repo, verifies the file, deploys
it, and prints the nginx location block to add if needed.

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
