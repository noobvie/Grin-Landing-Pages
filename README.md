# Grin Landing Pages

Landing pages for the Grin ecosystem — currently
[grin.money](https://grin.money) and [grinnode.org](https://grinnode.org).
Each edition lives in `web/<site-name>-<year>/` so every version is preserved;
a past edition can stay online under `/<year>/` of its domain (see
[Archived editions](#archived-editions-year)).

Sites are plain HTML/CSS/JS — zero dependencies, zero build step.

The deployment script is **domain-agnostic** and fully interactive — run it,
pick a menu option, follow the prompts.

---

## Repo Structure

```
Grin-Landing-Pages/
├── site_manager.sh                # interactive menu — run this
├── deploy/
│   ├── sites.conf                 # site manifest (key→domain, archived editions)
│   ├── analytics.conf             # GA4 site→ID map
│   ├── custom_repo.conf           # git deploy config
│   └── installer.conf             # option G: install.sh + install.ps1 at grinnode.org/install
├── snippets/
│   └── ga4.html                   # GA4 reference (documentation only)
├── docs-src/
│   └── grinnode-org/              # Markdown source of the toolkit manual
├── tools/
│   └── build-docs.mjs             # renders docs-src → web/grinnode-org-2027/docs/
└── web/
    ├── grin-money-2027/           # grin.money
    ├── grin-money-2026/           # grin.money/2026/ — archived edition
    ├── grinnode-org-2027/         # grinnode.org  (+ docs/ = the generated manual)
    ├── grinnode-org-2026/         # grinnode.org/2026/ — archived edition
    └── fidelius-2026/             # fidelius.grin.money
```

Config files in `deploy/` are committed with working defaults — edit in place.

---

## Sites

| Directory | Domain | Purpose |
|---|---|---|
| `web/grin-money-2027/` | [grin.money](https://grin.money) | Main landing for newcomers — "The Jedusor File" case-file edition |
| `web/grin-money-2026/` | [grin.money/2026/](https://grin.money/2026/) | Archived 2026 edition — published by the grin.money deploy, `noindex`, banner to the current site |
| `web/grinnode-org-2027/` | [grinnode.org](https://grinnode.org) | Node operator hub — Linux toolkit, Grim wallet |
| `web/grinnode-org-2027/docs/` | [grinnode.org/docs/](https://grinnode.org/docs/) | Grin Node Toolkit manual — **generated, do not edit the HTML by hand** (only `docs.css` is hand-maintained; see below) |
| `web/grinnode-org-2026/` | [grinnode.org/2026/](https://grinnode.org/2026/) | Archived 2026 edition — published by the grinnode.org deploy, `noindex`, banner to the current site |

---

## Toolkit manual (`docs-src/` → `web/grinnode-org-2027/docs/`)

The manual at grinnode.org/docs/ is written in Markdown under
`docs-src/grinnode-org/`, one file per page, and rendered to static HTML by a
zero-dependency Node script. The rendered HTML **is committed**, so the server
still deploys plain files and nothing runs there. The output edition folder
(`web/grinnode-org-2027/`) is one constant near the top of
`tools/build-docs.mjs` — change it there when a new edition becomes current.

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

### Pages (20, written 2026-09-19 → 09-23, re-checked 2026-11-06)

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

Every page was re-checked against toolkit branch `add-ons` @ `501fb4d` on
2026-11-06, with an independent second reader per group of pages and a final
pass across all 20; each page's `covers` / `updated` says when it was last
checked and changed.

### Writing a page

- **Audience:** someone who can SSH into a VPS and paste commands but has never
  run a Grin node. Second person, plain words, explain a term the first time
  (or link it to the glossary), exact paths/ports/commands everywhere.
- **The code wins.** Every key, path, port, cron cadence and claim comes from
  the script, not the toolkit README or CLAUDE.md — the two were wrong often
  enough to fill a 100-row log (now the toolkit's
  `docs/reference/script00_report_manual_findings.md`). When they disagree,
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

- **Deployed, but the live site serves an older build until redeployed.** On
  2026-11-06 `curl -sI https://grinnode.org/docs/01-build-node` → 200, `….html`
  → 301, `/docs/nope` → 404 (the clean-URL block is in place), but that page
  still shows *Covers 23 Oct 2026* and the live home page still says *Nym
  mixnet*. Deploy grinnode.org (`web/grinnode-org-2027/` with the 2026 edition
  archived under `/2026/`).
- **Warnings that wait on toolkit fixes.** Several pages warn about code bugs
  logged in the toolkit's findings log (*Act on these first*): Drop's `-p`
  passphrase (059 Status), the ufw block order (Warning on 02), the pool's `Z`
  groups that still default to yes (Danger on the pool page), the pool's
  log file and invisible alerts (key rows and Note on the pool page), a block
  "entered by hand" with no tool (Warning on the pool page), a full reinstall
  that deletes before it asks (Warning on 01), Wipe's *Restore* line after a
  failed Renew (Danger on 05), the old ecosystem checker (Warning on 08) and the
  `authorized_keys` rewrite (Warning on 08). When the code is fixed, re-check
  that page and remove its warning. The warnings for Script 03's dead schedules,
  Script 01 `G` → `3` and Super Auto's check order, remote *Upgrade grin binary*
  and the Top 20 bandwidth parser are gone: those bugs are fixed in the code.
  Script 03's Note stays, because a box scheduled earlier keeps its dead lines
  until someone opens Script 03.
- **Nym in the archived grin.money 2026 edition:** `web/grin-money-2026/index.html` still names Nym for
  Goblin (lines 581, 794); it is served only as the `/2026/` archive. The current
  grin.money edition (`web/grin-money-2027/`) and the grinnode.org home page say Tor.
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
| G | Installers | Publish `install.sh` + `install.ps1` at `<domain>/install` and configure nginx for it |

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
# <site_key>          <domain>          [web_dir_override | archive]
grin-money-2027       grin.money
grin-money-2026       grin.money        archive
grinnode-org-2027     grinnode.org
grinnode-org-2026     grinnode.org      archive
some-other-2026       example.org       /var/www/custom/pub
```

- `site_key` matches a subdirectory under `web/` (same key as `analytics.conf`).
- `domain` → web dir `<nginx_root>/<domain>/public` (override column optional;
  it must start with `/`).
- `archive` marks a past edition — see below.
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

### Archived editions (`/<year>/`)

A row whose third column is `archive` is a past edition. It is never deployed
on its own: whenever its domain's current edition deploys, the site is built in
a temp staging dir — the current edition at the root, each archive under
`/<year>/` (the trailing `-YYYY` of its `site_key`) — GA4 is applied to the
staging dir, and **one** rsync publishes it (`--delay-updates --delete-after`).
So the archive is part of every deploy and never deleted by one. For each
archived copy:

- `docs/`, `robots.txt` and `sitemap.xml` are left out — the current
  edition's copies at the root serve the whole domain;
- every `*.html` / `*.htm` gets `<meta name="robots" content="noindex, follow">`
  (replacing the page's own) and its canonical set to `https://<domain>/`;
- relative `href=` / `src=` values become absolute `/<year>/…` —
  `try_files $uri $uri/` can serve `/2026` without a trailing-slash redirect,
  and a relative `favicon.svg` would then load the current edition's file;
- manual links (`docs/…`) go to the current manual, extension-less:
  `docs/getting-started.html` → `/docs/getting-started`;
- a one-line banner after `<body>`: *You're viewing the 2026 edition of
  grinnode.org · see the current site*, a bar fixed to the bottom of the
  viewport (an edition with a fixed header would hide a normal-flow banner),
  with bottom padding added to `<body>` so it never covers the footer.

The rewrite is idempotent, keeps each file's mode, and touches only the staged
copy — `web/` is never modified. A page whose first `<head>` is inside a
comment or `<script>`, or whose robots/canonical tag spans lines, stops the
deploy. Rules, checked on every deploy that reads `sites.conf`: one current
(non-archive) row per domain, an archive needs that row, two archives of a
domain cannot share a year. A broken manifest stops the deploy; any failure
while staging leaves the live web dir untouched.

All four deploy modes assemble archives when the edition being deployed has
them: `ALL`, `git` (single site — archives come from the deployed branch's own
`deploy/sites.conf`, and the sparse clone fetches them too), `local` and
`rsync` when the source is one `web/<site_key>/` folder (its archives are read
from the sibling folders). Deploying an `archive` key on its own is refused. A
direct copy (`ALL`, `git`, `local`) into a web dir that already serves an
archive but has no `archive` row is refused too, rather than deleting it; a
direct `rsync` push to a remote server is first dry-run (`-n --delete -i`) and
refused if it would delete any `<YYYY>/index.html` there.
No vhost change is needed: `/2026/` and `/2026` both reach `2026/index.html`
through `location /` (`try_files $uri $uri/` + `index`). Check with
`curl -sI https://grinnode.org/2026/` after the first deploy.

---

## GA4 Analytics (Option A)

Each site maps to its own GA4 Measurement ID in `deploy/analytics.conf`:

```
grin-money-2026="G-98GRB5MKDT"
grin-money-2027="G-98GRB5MKDT"
grinnode-org-2026="G-EERXEJ55PZ"
grinnode-org-2027="G-EERXEJ55PZ"
```

A new edition keeps its domain's ID so the analytics history continues; an
archived edition is tagged with its current site's ID.

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

## Installers (Option G)

One URL for every platform:

```bash
curl -fsSL https://grinnode.org/install | sudo bash    # Linux → Grin Node Toolkit (install.sh)
```

```powershell
irm https://grinnode.org/install | iex                 # Windows → Grin Node Desktop (install.ps1)
```

nginx answers `/install` by User-Agent: PowerShell gets `install.ps1`, curl/wget
get `install.sh`, anything else (browsers) gets the site's `install.html` help
page (shipped in `web/grinnode-org-2027/`). `/install.sh`, `/install.ps1` and a
`.sha256` beside each are fixed URLs. `grin.money/install` answers 301 to
grinnode.org so the older Windows one-liner keeps working.

Config is in `deploy/installer.conf` (serving domain, redirect domains, one row
per script: repo, branch, path, marker line). Menu option **G**:

1. reads each script from its GitHub branch (bare partial clone), refuses it
   unless the marker line is in its first five lines (and, for `.sh`, it has no
   CRLF), then swaps it into `/var/www/grin-installers/` with its `.sha256`;
2. writes the nginx side itself — `conf.d/grin-installer-map.conf` (the
   User-Agent map), `snippets/grin-installer-{serve,redirect}.conf`, and one
   `include` line after `index index.html;` in each vhost — then `nginx -t`,
   putting every touched file back if the test fails;
3. smoke-tests through DNS/Cloudflare with curl, wget, PowerShell 5.1/7 and
   browser User-Agents, checks each SHA256, the `no-cache` header and the redirect.

Every installer response is `Cache-Control: no-cache`, because `/install`
differs per client. In Cloudflare, also add a cache-bypass rule for `/install*`,
and make sure Bot Fight Mode does not challenge curl or PowerShell there.

Order on a fresh server: add both domains (option 1), deploy the grinnode.org
site (option 3, for the help page), then option G. Option 1 re-adds the include
when it rewrites a listed domain's vhost.

During development only, an hourly cron run with `--auto-confirm` publishes every new commit on the branch automatically — with no review, so leave it off in production:

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
