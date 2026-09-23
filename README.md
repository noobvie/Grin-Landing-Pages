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
├── docs-src/
│   └── grinnode-org/              # Markdown source of the toolkit manual
├── tools/
│   └── build-docs.mjs             # renders docs-src → web/grinnode-org-2026/docs/
└── web/
    ├── grin-money-2026/           # grin.money
    └── grinnode-org-2026/         # grinnode.org  (+ docs/ = the generated manual)
```

Config files in `deploy/` are committed with working defaults — edit in place.

---

## Sites

| Directory | Domain | Purpose |
|---|---|---|
| `web/grin-money-2026/` | [grin.money](https://grin.money) | Main landing — wallets, ecosystem, toolkit |
| `web/grinnode-org-2026/` | [grinnode.org](https://grinnode.org) | Node operator hub — Linux toolkit, Grim wallet |
| `web/grinnode-org-2026/docs/` | [grinnode.org/docs/](https://grinnode.org/docs/) | Grin Node Toolkit manual — **generated, do not edit the HTML by hand** (only `docs.css` is hand-maintained; see below) |

---

## Toolkit manual (`docs-src/` → `web/grinnode-org-2026/docs/`)

The manual at grinnode.org/docs/ is written in Markdown under
`docs-src/grinnode-org/`, one file per page, and rendered to static HTML by a
zero-dependency Node script. The rendered HTML **is committed**, so the server
still deploys plain files and nothing runs there.

```bash
node tools/build-docs.mjs            # render every page + sitemap.xml + robots.txt
node tools/build-docs.mjs --check    # validate only (dead links, anchors, duplicate ids, descriptions), write nothing
```

Run the build after editing any `.md` and commit the output with it. Each page
starts with a front-matter block (`title`, `description` ≤160 chars, `section`,
`order`, optional `label`, `short`, `covers`, `updated`) — the sidebar, prev/next
links, JSON-LD and sitemap are all derived from it, so a new page needs nothing
but a new `.md` file. Supported Markdown: headings, paragraphs, fenced code (with
a copy button), inline code/bold/italic/links, lists, pipe tables, and
`> **Note:**` / `**Tip:**` / `**Warning:**` / `**Danger:**` blockquotes, which
become callouts.

`covers` is the date the page was checked against the toolkit's code; `updated`
is when the page text last changed. Both are printed on the page — keep them
honest rather than fresh.

### Pages (20, written 2026-09-19 → 09-23)

`index`, `getting-started`; one page per script — `01-build-node`,
`02-nginx-fileserver`, `03-share-chain-data`, `04-publish-node-api`,
`05-wallet-services` (hub + CMD wallet + Accio status), `051-fidelius`,
`053-woocommerce`, `059-grin-drop`, `06-global-health` (dashboard, grincoin
explorer, Tiny Explorer), `06b-grinscan`, `07-mining-services` (hub + solo),
`07-public-pool`, `08-admin-maintenance`, `089-backup-restore`,
`09-connectivity-hub`; and three references — `reference-ports-and-paths`,
`reference-glossary`, `reference-troubleshooting`. The manual stays **flat**
(GA4 is injected one directory deep only): a new reference is
`reference-<topic>.md`, never a sub-folder. Sub-product pages sort under their
hub with a decimal `order` (051 → 5.1, 06b → 6.5, 089 → 8.9).

### Writing a page

- **Audience:** someone who can SSH into a VPS and paste commands but has never
  run a Grin node. Second person, plain words, explain a term the first time
  (or link it to the glossary), exact paths/ports/commands everywhere.
- **The code wins.** Every key, path, port, cron cadence and claim comes from
  the script, not the toolkit README or CLAUDE.md — the two were wrong often
  enough to fill a 100-row log (now the toolkit's
  `docs/generated/script00_report_manual_findings.md`). When they disagree,
  write what the code does and add a row there.
- **Say what has never run.** A product that has not been deployed on a VPS
  gets a `> **Warning:** Status — …` callout at the top (Accio has no page at
  all until it has run). Anything read from code but not seen working gets a
  `> **Note:**`.
- **Name products, not keys** — keys move. Only hub 05 (fixed slots) and hub 08
  (key = last digit of the sub-script) have stable keys worth quoting.
- **Shape of a script page** (copy `01-build-node.md`): intro → status callout →
  What it does → Before you start → Choices → The menu (real menu in a `text`
  block + key table) → step table → After it finishes / What was created →
  Day-to-day → Troubleshooting → Related.
- **Troubleshooting tables** are two columns, `Symptom | Cause and fix`, under a
  heading named exactly *Troubleshooting*. The builder gives every row an anchor
  (`#ts-…`) and lists it in `reference-troubleshooting`'s A–Z index
  automatically — never copy rows there by hand. Quote the message's first
  words in code, the rest in prose.
- **Builder limits:** no backslash escapes (`\|` still splits a table cell, `\*`
  prints a backslash); a `|` inside backticks in a table splits the cell too;
  every heading on a page needs a unique text (duplicates are suffixed `-2` and
  `--check` fails); link unwritten pages as plain text, not links. Tables of
  three or more columns scroll on phones by design; keep them to four at most.
- **Verify** with `--check`, then look at the page at 1440 px and at a true
  390 px. Headless Edge clamps `--window-size` to ~500 px wide, so shoot mobile
  through an `<iframe width="390">` page with `--allow-file-access-from-files`
  (delete the helper file afterwards). A scrolling table at desktop width, or
  anything wider than the page on a phone, is a bug.

### Clean URLs

Links, canonicals, JSON-LD and the sitemap are extension-less
(`/docs/01-build-node`); the files on disk stay `<slug>.html` and the Markdown
keeps linking `slug.html` (that is what the dead-link check reads — the builder
strips the extension on output). nginx adds it back with the `location /docs/`
block in `site_manager.sh`'s vhost template, which also 301s any `.html` URL to
the clean one and returns a real 404 for a missing page. Following a link from
a page opened straight from disk therefore does not work — read pages one at a
time, or preview through the vhost.

**One-time step on the live server:** vhosts are only generated by *Add
Domain*, and re-running it re-issues the certificate and overwrites hand edits,
so paste the block into the existing grinnode.org vhost instead — inside the
`server { listen 443 … }` block, after `location / { … }` — then
`nginx -t && systemctl reload nginx`:

```nginx
location /docs/ {
    if ($request_uri ~ "^/docs/index(\.html)?(\?.*)?$") { return 301 /docs/$2; }
    if ($request_uri ~ "^(/docs/[^?]+)\.html(\?.*)?$")  { return 301 $1$2; }
    try_files $uri $uri.html $uri/ =404;
    expires 1h;
}
```

Check afterwards: `curl -sI https://grinnode.org/docs/01-build-node` → 200,
`…/01-build-node.html` → 301, `…/docs/nope` → 404. (The block was rendered from
the template and read, not run through `nginx -t` — do that on the server.)

### Open items

- **Not deployed yet.** grinnode.org/docs/ returned 404 on 2026-09-23. The
  toolkit README and grin.money's toolkit page already link to it, so deploy
  this site together with those changes.
- **Soft 404 elsewhere on the site:** `location /` falls back to `/index.html`,
  so any missing URL outside `/docs/` returns the home page with HTTP 200.
  Fine for a one-page site; worth a real 404 if more pages are added.
- **Nothing in the manual was verified on a VPS** beyond live probes of the
  demo sites; every "not verified on a server" Note on the pages is still open.
  Re-verify a page against the code (and bump `covers`) whenever its script
  changes.

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
