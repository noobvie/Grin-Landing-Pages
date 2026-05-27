# Grin Landing Pages

A living archive of landing pages for the Grin ecosystem — currently
[grin.money](https://grin.money) and [grinnode.org](https://grinnode.org).
Each edition lives in its own `web/<site-name>-<year>/` directory so every
version is preserved. Future years bring fresh designs while past ones remain
browsable here.

Sites are plain HTML/CSS/JS — zero dependencies, zero build step.

The deployment script is **domain-agnostic** — it works for any static site on
any domain, and several extras (GA4 injection, Grin-Money Desktop installer
publishing, fail2ban, IP filtering) are bundled in.

---

## Repo Structure

```
Grin-Landing-Pages/
├── site_manager.sh              # nginx, SSL, security, deploy, extras
├── deploy/
│   ├── custom_repo.conf.example   # git deploy config (copy → custom_repo.conf)
│   └── installer.conf.example     # install.ps1 publishing config (copy → installer.conf)
├── snippets/
│   └── ga4.html                   # GA4 snippet injected by --action analytics_ga4
└── web/
    ├── grin-money-2026/           # site: grin.money
    │   ├── index.html
    │   ├── grin-node-toolkit.html
    │   ├── grin_black_white.svg
    │   ├── css/
    │   └── js/
    └── grinnode-org-2026/         # site: grinnode.org
        ├── index.html
        ├── favicon.svg
        └── og-image.svg
```

Each site lives in its own `web/<site-name>/` directory. The deploy script
reads `deploy/custom_repo.conf` to know which site to pull and where to put it.

---

## Sites

| Directory | Live domain | Purpose |
|---|---|---|
| `web/grin-money-2026/` | [grin.money](https://grin.money) | Main landing — wallets, ecosystem, Grin-Node-Toolkit pitch (`/grin-node-toolkit.html`) |
| `web/grinnode-org-2026/` | [grinnode.org](https://grinnode.org) | Node operator hub — Linux toolkit, Grim wallet, MimbleWimble primer |

---

## Quick Start

```bash
git clone https://github.com/noobvie/Grin-Landing-Pages.git
cd Grin-Landing-Pages
chmod 775 site_manager.sh
sudo ./site_manager.sh
```

### 1. Add a domain on your server (nginx + SSL)

```bash
sudo ./site_manager.sh --action add \
    --domain grin.money \
    --email admin@grin.money
```

### 2. Configure your deploy

```bash
cp deploy/custom_repo.conf.example deploy/custom_repo.conf
# Edit: set SITE_NAME, GIT_REPO, GIT_BRANCH, DEPLOY_TARGET_DIR
```

### 3. Deploy

When deploying, the script will prompt you for a user:group to set ownership on
deployed files (e.g. `www-data:www-data`). The choice is saved to
`deploy/deploy_state.conf` for subsequent runs.

```bash
# Git pull on the server (interactive — prompts to confirm branch + ownership)
sudo ./site_manager.sh --action deploy --deploy-mode git

# rsync push from your local machine
./site_manager.sh --action deploy --deploy-mode rsync \
    --remote ubuntu@your-server --remote-path /var/www/grin.money/public \
    --src ./web/grin-money-2026
```

---

## Deploying Multiple Sites

Each site in `web/<site-name>/` is independent. To deploy a different site:

```bash
# In custom_repo.conf:
SITE_NAME="grinnode-org-2026"
DEPLOY_TARGET_DIR="/var/www/grinnode.org/public"
GIT_BRANCH="main"
```

Or pass it directly:

```bash
sudo ./site_manager.sh --action deploy --deploy-mode git \
    --site-name grinnode-org-2026 \
    --dir /var/www/grinnode.org/public
```

---

## Branch Switching (Testing / Staging)

The git deploy mode always asks you to confirm or change the branch before
deploying. To deploy a staging branch:

1. Edit `custom_repo.conf`: set `GIT_BRANCH=staging`
2. Run deploy — or just type the branch name when prompted

```
Current branch: main
Deploy branch [press Enter to keep, or type another branch/tag]: staging
```

---

## What `site_manager.sh` Does

| Option | Action flag | Description |
|---|---|---|
| 1 | `add`              | nginx vhost + Let's Encrypt SSL + security headers + rate limiting |
| 2 | `remove`           | Remove nginx config, optionally revoke SSL and delete files |
| 3 | `deploy`           | Push/pull files: `local`, `rsync`, or `git` mode |
| 4 | `list`             | List all configured nginx sites with SSL status |
| 5 | `security`         | Audit headers, apply global hardening, set up certbot auto-renewal |
| 6 | `fail2ban_install` | Install fail2ban with nginx jails |
| 7 | `fail2ban_mgmt`    | View bans, unban IPs |
| 8 | `ip_filter`        | Block/unblock IPs via ufw / iptables / firewalld |
| 9 | `self_update`      | `git pull` latest `site_manager.sh` from GitHub |
| A | `analytics_ga4`    | Inject Google Analytics 4 tracking into a site's HTML |
| G | `deploy_installer` | Pull `install.ps1` from Grin-Money-Desktop and serve at `<domain>/install` |

### nginx config generated per domain

- HTTPS redirect from HTTP, HTTP/2 enabled
- HSTS (2 years), CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- Rate limiting (10 req/s, burst 30)
- Blocks `.php`, `.env`, `.git`, dotfiles, common attack extensions
- 1-year immutable cache for CSS/JS/fonts/images
- Per-domain access and error logs

---

## Analytics — GA4 Injection (Option A)

Adds the GA4 `<script>` snippet from `snippets/ga4.html` into the `<head>` of a
site's HTML files. Re-running it updates the measurement ID in place rather
than duplicating tags.

```bash
sudo ./site_manager.sh --action analytics_ga4
# Prompts for: site directory, GA4 Measurement ID (G-XXXXXXXXXX)
```

The snippet is committed in `snippets/ga4.html` so the placeholder can be
reviewed before injection.

---

## Grin-Money Desktop Installer (Option G)

Publishes the PowerShell installer from
[Grin-Money-Desktop](https://github.com/noobvie/Grin-Money-Desktop) at
`https://<domain>/install` so end users can run:

```powershell
irm https://grin.money/install | iex
```

### Setup

```bash
cp deploy/installer.conf.example deploy/installer.conf
# Edit: INSTALLER_SERVING_DOMAIN, INSTALLER_TARGET_DIR, INSTALLER_OWNER
sudo ./site_manager.sh --action deploy_installer
```

The script:

1. Clones / fast-forwards `Grin-Money-Desktop` into `INSTALLER_CACHE_DIR`.
2. Verifies `install.ps1` begins with the `INSTALLER_SIGNATURE_LINE`
   (`#Requires -Version 5.1` by default) — refuses to deploy otherwise.
3. Copies it to `INSTALLER_TARGET_DIR` with the configured owner/perms.
4. Smoke-tests `https://<domain>/install` and prints the nginx `location` block
   to add if the URL doesn't resolve yet.

### nginx location block (paste into the vhost or a custom include)

```nginx
location = /install {
    default_type text/plain;
    alias /var/www/grin-money-desktop-installer/install.ps1;
    add_header Cache-Control "public, max-age=300";
    add_header X-Content-Type-Options "nosniff";
}
location = /install.ps1 {
    default_type text/plain;
    alias /var/www/grin-money-desktop-installer/install.ps1;
}
```

### Unattended (cron) deploys

```bash
# /etc/crontab — pull + redeploy hourly, skip if no new commits upstream
0 * * * * /path/to/site_manager.sh --action deploy-installer --auto-confirm \
    >> /var/log/grin-installer-deploy.log 2>&1
```

`--auto-confirm` skips the y/N prompt and exits cleanly when the upstream
branch hasn't moved.

### Behind a control panel (Hestia, cPanel, Plesk, etc.)

Panel-managed nginx configs are regenerated from templates — editing the
domain's main vhost will be overwritten. Place the `/install` location block in
a custom include the panel preserves (for Hestia:
`/home/<user>/conf/web/<domain>/nginx.ssl.conf_install`), then reload nginx.

---

## Self-Update (Option 9)

Pulls the latest `site_manager.sh` from this repo without re-deploying any
site:

```bash
sudo ./site_manager.sh --action self_update
```

Useful on long-lived servers where the toolkit is checked out into
`/opt/grin-landing/` or similar.

---

## Logs

Per-action logs are written to `/opt/grin-landing/logs/site_<action>_YYYYMMDD_HHMMSS.log`.

---

## Requirements

- **Server**: Linux (Debian/Ubuntu or RHEL/Rocky/Alma), bash 4+, nginx, certbot (auto-installed)
- **Local (rsync deploy)**: `rsync`, SSH key access to server
- **Local (macOS)**: Homebrew, bash 4+ — certbot limited to local dev only
- **Windows**: run inside WSL
