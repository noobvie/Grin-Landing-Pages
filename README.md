# Grin Landing Pages

This repo is a living archive of [grin.money](https://grin.money) landing pages — one new theme per year. Each edition lives in its own `web/<site-name>-<year>/` directory so every version is preserved. Future years will bring fresh designs while past ones remain browsable here.

The current live site is `web/grin-money-2026/` — plain HTML/CSS/JS, zero dependencies, zero build step.

The deployment script is **domain-agnostic** — it works for any static site on any domain.

---

## Repo Structure

```
Grin-Landing-Page/
├── deploy/
│   ├── site_manager.sh          # nginx, SSL, security, and deploy management
│   ├── custom_repo.conf         # your local deploy config (git-ignored)
│   └── custom_repo.conf.example # template — copy and fill in
└── web/
    └── grin-money-2026/         # site: grin.money
        ├── index.html
        ├── css/style.css
        └── js/main.js
```

Each site lives in its own `web/<site-name>/` directory. The deploy script reads `custom_repo.conf` to know which site to pull and where to put it.

---

## Quick Start

### 1. Add a domain on your server (nginx + SSL)

```bash
sudo ./deploy/site_manager.sh --action add \
    --domain grin.money \
    --email admin@grin.money
```

### 2. Configure your deploy

```bash
cp deploy/custom_repo.conf.example deploy/custom_repo.conf
# Edit: set SITE_NAME, GIT_REPO, GIT_BRANCH, DEPLOY_TARGET_DIR
```

### 3. Deploy

```bash
# Git pull on the server (interactive — prompts to confirm branch)
sudo ./deploy/site_manager.sh --action deploy --deploy-mode git

# rsync push from your local machine
./deploy/site_manager.sh --action deploy --deploy-mode rsync \
    --remote ubuntu@your-server --remote-path /var/www/grin.money/public \
    --src ./web/grin-money-2026
```

---

## Deploying Multiple Sites

Each site in `web/<site-name>/` is independent. To deploy a different site:

```bash
# In custom_repo.conf:
SITE_NAME="another-site"
DEPLOY_TARGET_DIR="/var/www/another-domain.com/public"
GIT_BRANCH="main"
```

Or pass it directly:

```bash
sudo ./deploy/site_manager.sh --action deploy --deploy-mode git \
    --site-name another-site \
    --dir /var/www/another-domain.com/public
```

---

## Branch Switching (Testing / Staging)

The git deploy mode always asks you to confirm or change the branch before deploying. To deploy a staging branch:

1. Edit `custom_repo.conf`: set `GIT_BRANCH=staging`
2. Run deploy — or just type the branch name when prompted

```
Current branch: main
Deploy branch [press Enter to keep, or type another branch/tag]: staging
```

---

## What `site_manager.sh` Does

| Option | Description |
|--------|-------------|
| `add`              | nginx vhost + Let's Encrypt SSL + security headers + rate limiting |
| `remove`           | Remove nginx config, optionally revoke SSL and delete files |
| `deploy`           | Push/pull files: `local`, `rsync`, or `git` mode |
| `list`             | List all configured nginx sites with SSL status |
| `security`         | Audit headers, apply global hardening, set up certbot auto-renewal |
| `fail2ban_install` | Install fail2ban with nginx jails |
| `fail2ban_mgmt`    | View bans, unban IPs |
| `ip_filter`        | Block/unblock IPs via ufw / iptables / firewalld |

### nginx config generated per domain

- HTTPS redirect from HTTP, HTTP/2 enabled
- HSTS (2 years), CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- Rate limiting (10 req/s, burst 30)
- Blocks `.php`, `.env`, `.git`, dotfiles, common attack extensions
- 1-year immutable cache for CSS/JS/fonts/images
- Per-domain access and error logs

---

## Requirements

- **Server**: Linux (Debian/Ubuntu or RHEL), bash 4+, nginx, certbot (auto-installed)
- **Local (rsync deploy)**: `rsync`, SSH key access to server
- **Local (macOS)**: Homebrew, bash 4+ — certbot limited to local dev only
- **Windows**: run inside WSL
