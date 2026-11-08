#!/usr/bin/env bash
################################################################################
# site_manager.sh — Static Site Deployment Manager
# Part of: Grin Landing Page  (https://github.com/noobvie/grin-landing-page)
################################################################################
#
# PURPOSE
#   Manages nginx virtual hosts for a static landing page.
#   Handles SSL (Let's Encrypt), security hardening, file deployment,
#   and optional fail2ban / IP filtering.
#
# MENU OPTIONS
#   1) Add Domain         — Configure nginx vhost + certbot SSL + security headers
#   2) Remove Domain      — Remove nginx vhost and revoke/delete SSL cert
#   3) Deploy Site        — Push or pull static files to web directory
#   4) List Sites         — Show all configured nginx sites
#   5) Security Hardening — Apply / audit nginx security headers
#   6) Install fail2ban   — Install & configure fail2ban for nginx
#   7) fail2ban Mgmt      — Status, ban/unban IPs
#   8) IP Filtering       — Block / Unblock IPs via ufw or iptables
#   9) Update Script      — Self-update site_manager.sh via git pull (fast-forward only)
#
#   A) Analytics (GA4)    — Inject / update GA4 tracking in a submitted directory (any web server)
#   G) Grin-Money Desktop — Deploy install.ps1 from GitHub to <domain>/install (reads deploy/installer.conf)
#
#   0) Exit
#
# PLATFORMS
#   Linux  : apt (Debian/Ubuntu) or yum (RHEL/CentOS) — production server use
#   macOS  : Homebrew — local development only (certbot limited, see notes)
#
# NON-INTERACTIVE MODE
#   Set ACTION at the top (or use --action flag) to skip the menu.
#   Valid ACTION values:
#     add | remove | deploy | list | security |
#     fail2ban_install | fail2ban_mgmt | ip_filter |
#     self_update | analytics_ga4 | deploy_installer
#   Hyphen aliases also accepted: analytics-ga4 | deploy-installer
#
# DEPLOY MODES
#   local  — Copy local web/ files directly to WEB_DIR (same machine)
#   rsync  — Push files from local to remote over SSH (tags a temp staging copy)
#   git    — Pull/clone repo on the server
#   all    — Batch-publish every site in deploy/sites.conf from this clone
#
#   All four apply the GA4 tag from deploy/analytics.conf to the PUBLISHED
#   copy only — the git source tree is never modified.
#
#   A site whose domain has 'archive' rows in deploy/sites.conf is assembled in
#   a staging dir in every mode (current edition at the root, each past edition
#   under /<year>/, marked noindex with a banner) and published with one rsync.
#
# LOG FILE
#   /opt/grin-landing/logs/site_<action>_YYYYMMDD_HHMMSS.log
#
################################################################################

set -euo pipefail

# ── Non-interactive configuration ────────────────────────────────────────────
# Set ACTION here, or leave empty for interactive menu.
# Options: add | remove | deploy | list | security |
#          fail2ban_install | fail2ban_mgmt | ip_filter
ACTION=""

# Domain configuration
DOMAIN=""                    # e.g., "grin.money"
EMAIL=""                     # e.g., "admin@grin.money"
WEB_DIR=""                   # Web root (default: /var/www/DOMAIN/public)

# Deploy configuration
DEPLOY_MODE=""               # local | rsync | git
LOCAL_SRC=""                 # Source path for local/rsync (e.g., ./web)
REMOTE_USER=""               # SSH user@host for rsync (e.g., ubuntu@1.2.3.4)
REMOTE_PATH=""               # Remote path for rsync (e.g., /var/www/grin.money/public)
GIT_REPO=""                  # Git repo URL for git deploy mode
GIT_BRANCH=""                # Git branch (default: from custom_repo.conf or "main")
SITE_NAME=""                 # Site subdirectory name under web/ (e.g. "grin-money-2026")
SPARSE_CHECKOUT=""           # "yes" to sparse-clone only web/<SITE_NAME>/
DEPLOY_ALL=""                # "yes" to batch-deploy every site in deploy/sites.conf (git mode)

# Removal configuration
DOMAIN_TO_REMOVE=""          # Domain to remove
DELETE_FILES=""              # "yes" to also delete web files

# Deploy state
DEPLOY_OWNER=""              # user:group for chown after deploy (saved/loaded from state file)
DEPLOY_STATE_FILE=""         # Set after SCRIPT_DIR is known (see bottom of system vars block)

# Auto-confirm — for use by cron / unattended invocations of deploy-installer.
# When "yes": skip the y/N confirmation prompt and exit cleanly if upstream
# has no new commits since the last deploy. Set via --auto-confirm.
AUTO_CONFIRM=""

#############################################################################
# System Variables — DO NOT EDIT
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_STATE_FILE="$SCRIPT_DIR/deploy/deploy_state.conf"
SITES_CONF_FILE="$SCRIPT_DIR/deploy/sites.conf"   # manifest of all hosted sites (batch git deploy)
LOG_DIR="/opt/grin-landing/logs"
LOG_FILE=""
_LOG_INIT_DONE=false    # guard — only init_log once per session

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

OS=""                        # Populated by detect_os()
FIREWALL=""                  # Populated by detect_firewall()
NGINX_CONF_DIR=""            # Populated by detect_nginx_paths()
NGINX_AVAILABLE=""
NGINX_ENABLED=""
NGINX_DEFAULT_ROOT=""

FAIL2BAN_JAIL="/etc/fail2ban/jail.d/nginx-landing.conf"
BLOCKED_LIST="/etc/grin-landing/blocked_ips.list"

#############################################################################
# Platform Detection
#############################################################################

detect_os() {
    case "$(uname -s)" in
        Darwin*) OS="macos" ;;
        Linux*)  OS="linux" ;;
        MINGW*|CYGWIN*|MSYS*)
            print_error "Run this script inside WSL (Windows Subsystem for Linux) on Windows."
            exit 1
            ;;
        *) print_error "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac
}

detect_nginx_paths() {
    if [[ "$OS" == "macos" ]]; then
        # Apple Silicon or Intel Mac Homebrew paths
        if [[ -d "/opt/homebrew/etc/nginx" ]]; then
            NGINX_CONF_DIR="/opt/homebrew/etc/nginx"
            NGINX_DEFAULT_ROOT="/opt/homebrew/var/www"
        else
            NGINX_CONF_DIR="/usr/local/etc/nginx"
            NGINX_DEFAULT_ROOT="/usr/local/var/www"
        fi
        # macOS Homebrew nginx uses a flat "servers/" directory
        NGINX_AVAILABLE="$NGINX_CONF_DIR/servers"
        NGINX_ENABLED="$NGINX_CONF_DIR/servers"
    else
        NGINX_CONF_DIR="/etc/nginx"
        NGINX_AVAILABLE="/etc/nginx/sites-available"
        NGINX_ENABLED="/etc/nginx/sites-enabled"
        NGINX_DEFAULT_ROOT="/var/www"
    fi
}

#############################################################################
# Helper Functions
#############################################################################

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_section() { echo -e "\n${BOLD}=========================================\n $1\n=========================================${NC}"; }
print_cmd()     { echo -e "${DIM}  \$${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

validate_domain() {
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_ip() {
    local ip="$1" IFS='.'
    read -r -a octets <<< "$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

domain_safe() {
    # Convert domain to a safe identifier (dots → underscores)
    echo "$1" | tr '.' '_' | tr '-' '_'
}

init_log() {
    [[ "$_LOG_INIT_DONE" == "true" ]] && return 0   # never stack tee processes
    local action="$1"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/site_${action}_$(date +%Y%m%d_%H%M%S).log"
    # stdbuf -o0 forces tee to write to the terminal unbuffered.
    # Without it, once stdout becomes a pipe glibc switches tee to 8 KB
    # block-buffering, so the interactive menu never appears until the
    # buffer fills — users have to press Enter several times to see anything.
    if command -v stdbuf &>/dev/null; then
        exec > >(stdbuf -o0 tee -a "$LOG_FILE") 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1   # macOS fallback — minor display lag acceptable
    fi
    _LOG_INIT_DONE=true
    print_info "Logging to: $LOG_FILE"
}

ask() {
    # Replacement for 'read -r -p "prompt" VARNAME'.
    # Routes the prompt text through stdout (same tee pipe as echo) so it
    # appears AFTER preceding echo output in the correct display order.
    # Without this, bash's readline writes prompts via /dev/tty directly,
    # which renders on screen before the echo lines still sitting in the
    # tee pipe buffer — prompt appears above the menu instead of below it.
    printf "%s" "$1"
    read -r "$2"
}

#############################################################################
# Package Management
#############################################################################

pkg_install() {
    local pkg="$1"
    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew &>/dev/null; then
            print_error "Homebrew not found. Install from https://brew.sh first."
            exit 1
        fi
        brew install "$pkg"
    elif [[ -f /etc/debian_version ]]; then
        apt-get update -qq && apt-get install -y "$pkg"
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y epel-release 2>/dev/null || true
        yum install -y "$pkg"
    else
        print_error "Cannot install $pkg: unsupported package manager."
        exit 1
    fi
}

ensure_nginx() {
    command -v nginx &>/dev/null && return 0
    print_info "nginx not found. Installing..."
    if [[ "$OS" == "macos" ]]; then
        pkg_install nginx
        brew services start nginx
    else
        pkg_install nginx
        systemctl enable nginx && systemctl start nginx
    fi
    print_info "nginx installed and started."
}

ensure_certbot() {
    command -v certbot &>/dev/null && return 0

    if [[ "$OS" == "macos" ]]; then
        print_warn "On macOS, certbot is for local testing only."
        print_warn "For production SSL, run this script on your Linux VPS."
        ask "Install certbot via Homebrew anyway? (y/N) " _c
        [[ "${_c,,}" == "y" ]] || return 1
        pkg_install certbot
        pkg_install certbot-nginx 2>/dev/null || true
    else
        print_info "Installing certbot..."
        if [[ -f /etc/debian_version ]]; then
            apt-get install -y certbot python3-certbot-nginx
        else
            pkg_install certbot
            pkg_install python3-certbot-nginx
        fi
    fi
    print_info "certbot installed."
}

nginx_reload() {
    if nginx -t &>/dev/null; then
        if [[ "$OS" == "macos" ]]; then
            brew services reload nginx
        else
            systemctl reload nginx
        fi
        print_info "nginx reloaded."
    else
        print_error "nginx config test failed:"
        nginx -t
        return 1
    fi
}

detect_firewall() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        FIREWALL="ufw"
    elif command -v iptables &>/dev/null; then
        FIREWALL="iptables"
    elif command -v firewall-cmd &>/dev/null; then
        FIREWALL="firewalld"
    else
        FIREWALL="none"
    fi
}

open_firewall_ports() {
    detect_firewall
    case "$FIREWALL" in
        ufw)
            ufw allow 80/tcp  &>/dev/null || true
            ufw allow 443/tcp &>/dev/null || true
            print_info "ufw: ports 80 and 443 opened."
            ;;
        iptables)
            iptables -I INPUT -p tcp --dport 80  -j ACCEPT 2>/dev/null || true
            iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
            print_info "iptables: ports 80 and 443 opened."
            ;;
        firewalld)
            firewall-cmd --permanent --add-service=http  &>/dev/null || true
            firewall-cmd --permanent --add-service=https &>/dev/null || true
            firewall-cmd --reload &>/dev/null || true
            print_info "firewalld: http and https services enabled."
            ;;
        none) print_warn "No firewall detected. Ensure ports 80/443 are open manually." ;;
    esac
}

#############################################################################
# Menu
#############################################################################

show_main_menu() {
    clear 2>/dev/null || true
    cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     site_manager.sh  —  Static Site Deployment Manager         ║
║                    V.20260927                                  ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo ""
    echo "  1) Add Domain         — Configure nginx vhost + SSL + security"
    echo "  2) Remove Domain      — Remove nginx config and SSL cert"
    echo "  3) Deploy Site        — Push / pull static files to web dir"
    echo "  4) List Sites         — Show all configured nginx sites"
    echo "  5) Security Hardening — Apply security headers to all sites"
    echo ""
    echo "  6) Install fail2ban   — Install & configure fail2ban for nginx"
    echo "  7) fail2ban Mgmt      — Status, ban/unban IPs"
    echo "  8) IP Filtering       — Block / Unblock IPs"
    echo ""
    echo "  9) Update Script      — git pull latest site_manager.sh from GitHub"
    echo ""
    echo "  A) Analytics (GA4)         — Inject/refresh GA4 in a directory you submit (any web server)"
    echo "  G) Grin-Money Desktop      — Deploy install.ps1 to <domain>/install"
    echo ""
    echo "  0) Exit"
    echo ""
}

get_action() {
    [[ -n "$ACTION" ]] && return 0

    while true; do
        show_main_menu
        ask "Enter choice [0-9 / A / G]: " choice
        case "${choice,,}" in
            1) ACTION="add"              ; break ;;
            2) ACTION="remove"           ; break ;;
            3) ACTION="deploy"           ; break ;;
            4) ACTION="list"             ; break ;;
            5) ACTION="security"         ; break ;;
            6) ACTION="fail2ban_install" ; break ;;
            7) ACTION="fail2ban_mgmt"    ; break ;;
            8) ACTION="ip_filter"        ; break ;;
            9) ACTION="self_update"      ; break ;;
            a) ACTION="analytics_ga4"    ; break ;;
            g) ACTION="deploy_installer" ; break ;;
            0) print_info "Exiting."; exit 0 ;;
            "") ;;
            *) print_error "Invalid choice. Please enter 0-9, A or G." ; sleep 1 ;;
        esac
    done
}

#############################################################################
# Input Helpers
#############################################################################

get_domain_input() {
    echo ""
    echo -e "${YELLOW}[DNS]${NC} Ensure your A record points to this server before continuing."
    echo -e "      Cloudflare: set to ${GREEN}DNS only${NC} (grey cloud) so certbot can validate."
    echo ""
    while true; do
        if [[ -z "$DOMAIN" ]]; then
            ask "Enter domain (e.g. grin.money) or 0 to cancel: " DOMAIN
            [[ "$DOMAIN" == "0" ]] && return 1
        fi
        if validate_domain "$DOMAIN"; then
            print_info "Domain: $DOMAIN"
            break
        else
            print_error "Invalid domain format."
            DOMAIN=""
        fi
    done
}

get_email_input() {
    while true; do
        if [[ -z "$EMAIL" ]]; then
            ask "Enter email for SSL notifications or 0 to cancel: " EMAIL
            [[ "$EMAIL" == "0" ]] && return 1
        fi
        if validate_email "$EMAIL"; then
            print_info "Email: $EMAIL"
            break
        else
            print_error "Invalid email format."
            EMAIL=""
        fi
    done
}

get_web_dir() {
    if [[ -z "$WEB_DIR" ]]; then
        local default_dir="$NGINX_DEFAULT_ROOT/$DOMAIN/public"
        ask "Web directory [default: $default_dir]: " WEB_DIR
        WEB_DIR="${WEB_DIR:-$default_dir}"
    fi
    print_info "Web directory: $WEB_DIR"
}

#############################################################################
# 1. Add Domain
#############################################################################

# Generate nginx config for a static site with security hardening
generate_nginx_config() {
    local domain="$1"
    local web_dir="$2"
    local cert_mode="${3:-letsencrypt}"   # letsencrypt | selfsigned
    local domain_id
    domain_id=$(domain_safe "$domain")

    # Build the SSL directive block to match where the cert actually lives.
    # certbot puts certs (and the shared options/dhparam files) under
    # /etc/letsencrypt; the self-signed fallback writes to /etc/ssl/<domain>/
    # and those shared includes do NOT exist — referencing them would make
    # `nginx -t` fail and the whole site never come up.
    local ssl_block
    if [[ "$cert_mode" == "selfsigned" ]]; then
        ssl_block=$(cat << SSL_EOF
    # SSL — self-signed fallback (certbot unavailable). Re-run option 1 once
    # DNS resolves to this server to replace with a real Let's Encrypt cert.
    ssl_certificate     /etc/ssl/${domain}/fullchain.pem;
    ssl_certificate_key /etc/ssl/${domain}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
SSL_EOF
)
    else
        ssl_block=$(cat << SSL_EOF
    # SSL — managed by certbot
    ssl_certificate     /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;
SSL_EOF
)
    fi

    cat << NGINX_EOF
# Rate limiting zone
limit_req_zone \$binary_remote_addr zone=landing_${domain_id}:10m rate=10r/s;

server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${domain} www.${domain};

    root ${web_dir};
    index index.html;

$ssl_block

    # Security headers
    server_tokens off;
    add_header Strict-Transport-Security  "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options            "SAMEORIGIN"                                   always;
    add_header X-Content-Type-Options     "nosniff"                                      always;
    add_header X-XSS-Protection           "1; mode=block"                                always;
    add_header Referrer-Policy            "strict-origin-when-cross-origin"              always;
    add_header Permissions-Policy         "camera=(), microphone=(), geolocation=()"     always;
    add_header Content-Security-Policy    "default-src 'self'; script-src 'self' 'unsafe-inline' https://www.googletagmanager.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https:; connect-src 'self' https://world.grin.money https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com https://*.google.com;" always;

    # Rate limiting
    limit_req zone=landing_${domain_id} burst=30 nodelay;

    # Static site routing
    location / {
        try_files \$uri \$uri/ /index.html =404;
        expires 1h;
    }

    # Toolkit manual (grinnode.org/docs/) — clean URLs. Pages are <slug>.html on disk
    # but every link, canonical and sitemap entry is extension-less (tools/build-docs.mjs),
    # so try_files adds the .html. The .html spelling and /docs/index are 301'd to the
    # one indexed URL; testing \$request_uri (never rewritten) instead of \$uri keeps the
    # internal index/try_files rewrites from looping back into the redirect. A miss is a
    # real 404 here, not the site's home page. Harmless on a site with no docs/ folder.
    location /docs/ {
        if (\$request_uri ~ "^/docs/index(\.html)?(\?.*)?\$") { return 301 /docs/\$2; }
        if (\$request_uri ~ "^(/docs/[^?]+)\.html(\?.*)?\$")  { return 301 \$1\$2; }
        try_files \$uri \$uri.html \$uri/ =404;
        expires 1h;
    }

    # Immutable cache for hashed assets
    location ~* \.(css|js|woff2?|ttf|eot|svg|png|jpg|jpeg|gif|ico|webp)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Block server-side script extensions
    location ~* \.(php|asp|aspx|jsp|cgi|pl|py|rb|sh|bash)\$ {
        return 403;
    }

    # Block dotfiles and sensitive files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    location ~* \.(git|env|htaccess|htpasswd|config|conf|log|bak|backup|sql|swp)\$ {
        deny all;
        access_log off;
        log_not_found off;
    }

    access_log /var/log/nginx/${domain}_access.log;
    error_log  /var/log/nginx/${domain}_error.log warn;
}
NGINX_EOF
}

action_add_domain() {
    print_section "Add Domain"

    if [[ "$OS" == "macos" ]]; then
        print_warn "macOS mode: nginx config will be written but certbot SSL requires a public VPS."
    fi

    get_domain_input  || return 1
    get_email_input   || return 1
    get_web_dir

    # Check if already configured
    local conf_file="$NGINX_AVAILABLE/$DOMAIN"
    if [[ -f "$conf_file" ]]; then
        print_warn "A config for '$DOMAIN' already exists at: $conf_file"
        ask "Overwrite? (y/N): " _ow
        [[ "${_ow,,}" != "y" ]] && return 1
    fi

    ensure_nginx
    ensure_certbot || true   # Non-fatal on macOS
    [[ "$OS" == "macos" ]] && mkdir -p "$NGINX_AVAILABLE" 2>/dev/null || true

    # Create web directory
    mkdir -p "$WEB_DIR"
    print_info "Web directory created: $WEB_DIR"

    # Write placeholder index.html if empty
    if [[ ! -f "$WEB_DIR/index.html" ]]; then
        cat > "$WEB_DIR/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Coming Soon</title></head>
<body style="background:#0a0a0a;color:#00ff41;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
<pre>> Site deploying... stand by_</pre>
</body></html>
HTML_EOF
        print_info "Placeholder index.html created."
    fi

    # Open firewall ports
    open_firewall_ports

    # Track which cert the final vhost should point at. Flipped to "selfsigned"
    # only if certbot fails below, so generate_nginx_config emits matching paths.
    local cert_mode="letsencrypt"

    if [[ "$OS" == "linux" ]]; then
        # Get SSL cert first (needs port 80 open, nginx must not be running on 80 yet)
        # Use --nginx plugin so certbot auto-configures nginx
        print_section "Obtaining SSL Certificate"

        # Write a temporary HTTP-only config so certbot can validate
        cat > "$conf_file" << TMP_NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${WEB_DIR};
    location /.well-known/acme-challenge/ { root ${WEB_DIR}; }
    location / { return 301 https://\$host\$request_uri; }
}
TMP_NGINX

        [[ "$OS" == "linux" ]] && ln -sf "$conf_file" "$NGINX_ENABLED/$DOMAIN" 2>/dev/null || true
        nginx_reload || true

        certbot certonly --nginx \
            --non-interactive \
            --agree-tos \
            --expand \
            --email "$EMAIL" \
            --domains "$DOMAIN,www.$DOMAIN" 2>&1 || {
            # A live site must never be downgraded to self-signed just because a
            # re-run failed to ISSUE: keep the existing Let's Encrypt cert if it
            # is still valid for at least a day.
            if openssl x509 -checkend 86400 -noout \
                    -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null; then
                print_warn "certbot failed, but a valid existing certificate was found — keeping it."
                print_warn "It may not cover www.$DOMAIN; check DNS and re-run to expand it."
            else
                print_warn "certbot failed. Generating self-signed cert for testing..."
                mkdir -p "/etc/ssl/$DOMAIN"
                openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                    -keyout "/etc/ssl/$DOMAIN/privkey.pem" \
                    -out    "/etc/ssl/$DOMAIN/fullchain.pem" \
                    -subj   "/CN=$DOMAIN" 2>/dev/null
                cert_mode="selfsigned"
                print_warn "Self-signed cert generated. Replace with Let's Encrypt for production."
            fi
        }
    fi

    # Write final nginx config (SSL paths follow whichever cert we ended up with)
    print_section "Writing nginx Configuration"
    generate_nginx_config "$DOMAIN" "$WEB_DIR" "$cert_mode" > "$conf_file"

    if [[ "$OS" == "linux" ]]; then
        ln -sf "$conf_file" "$NGINX_ENABLED/$DOMAIN" 2>/dev/null || true
        # Remove default site if it blocks port 443
        [[ -L "$NGINX_ENABLED/default" ]] && rm -f "$NGINX_ENABLED/default" && \
            print_warn "Removed nginx default site symlink to prevent port 443 conflicts."
    fi

    nginx_reload

    echo ""
    print_info "Domain configured successfully!"
    echo ""
    echo -e "  ${GREEN}URL:${NC}     https://$DOMAIN"
    echo -e "  ${GREEN}Web dir:${NC} $WEB_DIR"
    echo -e "  ${GREEN}Config:${NC}  $conf_file"
    echo ""
    echo -e "  ${YELLOW}Next step:${NC} Run option 3 to deploy your site files."
    echo ""
}

#############################################################################
# 2. Remove Domain
#############################################################################

action_remove_domain() {
    print_section "Remove Domain"

    # Use DOMAIN_TO_REMOVE if set, otherwise prompt
    if [[ -z "$DOMAIN_TO_REMOVE" ]]; then
        action_list_sites
        echo ""
        ask "Enter domain to remove or 0 to cancel: " DOMAIN_TO_REMOVE
        [[ "$DOMAIN_TO_REMOVE" == "0" ]] && return 0
    fi

    local conf_file="$NGINX_AVAILABLE/$DOMAIN_TO_REMOVE"
    if [[ ! -f "$conf_file" ]]; then
        print_error "No nginx config found for: $DOMAIN_TO_REMOVE"
        return 1
    fi

    # Find web dir from existing config
    local web_dir
    web_dir=$(grep -oP 'root\s+\K[^;]+' "$conf_file" | head -1 || echo "")

    echo ""
    echo -e "  Config:  ${YELLOW}$conf_file${NC}"
    [[ -n "$web_dir" ]] && echo -e "  Web dir: ${YELLOW}$web_dir${NC}"
    echo ""

    if [[ -z "$DELETE_FILES" ]]; then
        ask "Also delete web files ($web_dir)? (y/N): " _df
        DELETE_FILES="${_df,,}"
    fi

    # Remove nginx config
    rm -f "$conf_file"
    rm -f "$NGINX_ENABLED/$DOMAIN_TO_REMOVE" 2>/dev/null || true
    print_info "Removed nginx config: $conf_file"

    # Revoke and delete SSL cert
    if command -v certbot &>/dev/null && \
       [[ -d "/etc/letsencrypt/live/$DOMAIN_TO_REMOVE" ]]; then
        ask "Revoke and delete SSL cert for $DOMAIN_TO_REMOVE? (y/N): " _rc
        if [[ "${_rc,,}" == "y" ]]; then
            certbot revoke --cert-name "$DOMAIN_TO_REMOVE" --non-interactive 2>/dev/null || true
            certbot delete --cert-name "$DOMAIN_TO_REMOVE" --non-interactive 2>/dev/null || true
            print_info "SSL cert removed."
        fi
    fi

    # Delete web files
    if [[ "${DELETE_FILES,,}" == "y" ]] && [[ -n "$web_dir" ]] && [[ -d "$web_dir" ]]; then
        ask "CONFIRM: Permanently delete $web_dir and all its contents? (yes/N): " _confirm
        if [[ "$_confirm" == "yes" ]]; then
            rm -rf "${web_dir:?web_dir is empty — refusing to delete}"
            print_info "Web files deleted: $web_dir"
        else
            print_info "Web files kept."
        fi
    fi

    nginx_reload
    print_info "Domain '$DOMAIN_TO_REMOVE' removed."
}

#############################################################################
# 3. Deploy Site
#############################################################################

action_deploy() {
    print_section "Deploy Site"

    # Unattended / explicit batch: --all (or DEPLOY_MODE=all) deploys every
    # site in deploy/sites.conf in one pass — no menu, ideal for cron.
    if [[ "$DEPLOY_ALL" == "yes" || "$DEPLOY_MODE" == "all" ]]; then
        DEPLOY_MODE="all"
        _deploy_all
        return $?
    fi

    # Auto-detect a multi-site server: if deploy/sites.conf lists ≥2 sites, offer
    # to batch them all BEFORE the saved single-site state can short-circuit the
    # menu — this is the "deploy every site on this box" fast path.
    # Archive rows are published inside their current site, so only current
    # rows count as sites to deploy.
    local _k _ndeploy=0
    if [[ -f "$SITES_CONF_FILE" ]] && _load_sites_conf >/dev/null 2>&1; then
        for (( _k=0; _k<${#_SITE_KEYS[@]}; _k++ )); do
            [[ -n "${_SITE_ARCHIVED[$_k]}" ]] || _ndeploy=$(( _ndeploy + 1 ))
        done
    fi
    if (( _ndeploy >= 2 )); then
        echo ""
        print_info "Detected ${_ndeploy} sites in deploy/sites.conf:"
        for (( _k=0; _k<${#_SITE_KEYS[@]}; _k++ )); do
            if [[ -n "${_SITE_ARCHIVED[$_k]}" ]]; then
                echo "    - ${_SITE_KEYS[$_k]}  (archive → ${_SITE_DOMAINS[$_k]}/$(_site_archive_year "${_SITE_KEYS[$_k]}")/)"
            else
                echo "    - ${_SITE_KEYS[$_k]}"
            fi
        done
        ask "  Deploy ALL ${_ndeploy} sites now? (Y/n): " _all
        if [[ "${_all,,}" != "n" ]]; then
            DEPLOY_MODE="all"
            _deploy_all
            return $?
        fi
        print_info "Skipping batch — choose a single-site mode below."
    fi

    _load_deploy_state

    echo ""
    echo "Deploy modes:"
    echo "  1) local  — Copy files on this machine to a local nginx web dir"
    echo "  2) rsync  — Push files from this machine to a remote server via SSH"
    echo "  3) git    — Run git pull on the server (one site; must run on the server)"
    echo "  4) ALL    — Batch-deploy every site in deploy/sites.conf (from this clone)"
    echo ""

    if [[ -z "$DEPLOY_MODE" ]]; then
        ask "Choose deploy mode [1-4] or 0 to cancel: " _dm
        case "$_dm" in
            1) DEPLOY_MODE="local"  ;;
            2) DEPLOY_MODE="rsync"  ;;
            3) DEPLOY_MODE="git"    ;;
            4) DEPLOY_MODE="all"    ;;
            0) return 0 ;;
            *) print_error "Invalid choice."; return 1 ;;
        esac
    fi

    case "$DEPLOY_MODE" in
        local)  _deploy_local  ;;
        rsync)  _deploy_rsync  ;;
        git)    _deploy_git    ;;
        all)    _deploy_all    ;;
        *) print_error "Unknown DEPLOY_MODE: $DEPLOY_MODE"; return 1 ;;
    esac
}

_prompt_ownership() {
    local target_dir="$1"
    echo ""
    local prompt_hint="e.g. www-data:www-data"
    [[ -n "$DEPLOY_OWNER" ]] && prompt_hint="last used: $DEPLOY_OWNER"
    ask "  Set ownership of deployed files ($prompt_hint, Enter to skip): " _owner
    _owner="${_owner:-$DEPLOY_OWNER}"
    if [[ -n "$_owner" ]]; then
        chown -R "$_owner" "$target_dir"
        DEPLOY_OWNER="$_owner"
        print_info "Ownership set to ${_owner} on ${target_dir}"
    fi
}

_load_deploy_state() {
    [[ -f "$DEPLOY_STATE_FILE" ]] || return 0
    local _mode _src _remote _rpath _repo _branch _site _dir _sparse _owner
    _mode=$(   grep -E '^DEPLOY_MODE='       "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _src=$(    grep -E '^LOCAL_SRC='         "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _remote=$( grep -E '^REMOTE_USER='       "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _rpath=$(  grep -E '^REMOTE_PATH='       "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _repo=$(   grep -E '^GIT_REPO='          "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _branch=$( grep -E '^GIT_BRANCH='        "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _site=$(   grep -E '^SITE_NAME='         "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _dir=$(    grep -E '^WEB_DIR='           "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _sparse=$( grep -E '^SPARSE_CHECKOUT='   "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )
    _owner=$(  grep -E '^DEPLOY_OWNER='      "$DEPLOY_STATE_FILE" | head -1 | cut -d= -f2- | tr -d '"' )

    echo ""
    echo -e "  ${BLUE}[SAVED]${NC} Last deploy settings:"
    [[ -n "$_mode"   ]] && echo "    Mode:    $_mode"
    [[ -n "$_src"    ]] && echo "    Source:  $_src"
    [[ -n "$_remote" ]] && echo "    Remote:  $_remote"
    [[ -n "$_rpath"  ]] && echo "    R.path:  $_rpath"
    [[ -n "$_repo"   ]] && echo "    Repo:    $_repo"
    [[ -n "$_branch" ]] && echo "    Branch:  $_branch"
    [[ -n "$_site"   ]] && echo "    Site:    $_site"
    [[ -n "$_dir"    ]] && echo "    Web dir: $_dir"
    [[ -n "$_owner"  ]] && echo "    Owner:   $_owner"
    echo ""
    ask "  Use saved settings? (Y/n) " _use
    if [[ "${_use,,}" == "n" ]]; then
        # User declined the saved settings — clear any in-memory values so the
        # deploy prompts ask for everything fresh. The downstream prompts are
        # all guarded by `[[ -z "$VAR" ]]`, so leaving stale globals here would
        # silently reuse old values (env vars, a prior deploy this session, or
        # parsed --flags) instead of re-prompting.
        DEPLOY_MODE=""; LOCAL_SRC=""; REMOTE_USER=""; REMOTE_PATH=""
        GIT_REPO=""; GIT_BRANCH=""; SITE_NAME=""; WEB_DIR=""
        SPARSE_CHECKOUT=""; DEPLOY_OWNER=""
        print_info "Saved settings ignored — entering values manually."
        return 0
    fi

    [[ -n "$_mode"   && -z "$DEPLOY_MODE"   ]] && DEPLOY_MODE="$_mode"
    [[ -n "$_src"    && -z "$LOCAL_SRC"     ]] && LOCAL_SRC="$_src"
    [[ -n "$_remote" && -z "$REMOTE_USER"   ]] && REMOTE_USER="$_remote"
    [[ -n "$_rpath"  && -z "$REMOTE_PATH"   ]] && REMOTE_PATH="$_rpath"
    [[ -n "$_repo"   && -z "$GIT_REPO"      ]] && GIT_REPO="$_repo"
    [[ -n "$_branch" && -z "$GIT_BRANCH"    ]] && GIT_BRANCH="$_branch"
    [[ -n "$_site"   && -z "$SITE_NAME"     ]] && SITE_NAME="$_site"
    [[ -n "$_dir"    && -z "$WEB_DIR"       ]] && WEB_DIR="$_dir"
    [[ -n "$_sparse"                        ]] && SPARSE_CHECKOUT="$_sparse"
    [[ -n "$_owner"                         ]] && DEPLOY_OWNER="$_owner"
    print_info "Saved settings loaded."
}

_save_deploy_state() {
    mkdir -p "$(dirname "$DEPLOY_STATE_FILE")"
    cat > "$DEPLOY_STATE_FILE" << EOF
DEPLOY_MODE="$DEPLOY_MODE"
LOCAL_SRC="$LOCAL_SRC"
REMOTE_USER="$REMOTE_USER"
REMOTE_PATH="$REMOTE_PATH"
GIT_REPO="$GIT_REPO"
GIT_BRANCH="$GIT_BRANCH"
SITE_NAME="$SITE_NAME"
WEB_DIR="$WEB_DIR"
SPARSE_CHECKOUT="${SPARSE_CHECKOUT:-no}"
DEPLOY_OWNER="$DEPLOY_OWNER"
EOF
    print_info "Deploy settings saved → $DEPLOY_STATE_FILE"
}

_deploy_local() {
    # Default source: web/ directory at the repo root
    if [[ -z "$LOCAL_SRC" ]]; then
        local default_src
        default_src="$SCRIPT_DIR/web"
        ask "Source directory [default: $default_src]: " LOCAL_SRC
        LOCAL_SRC="${LOCAL_SRC:-$default_src}"
    fi

    if [[ ! -d "$LOCAL_SRC" ]]; then
        print_error "Source directory not found: $LOCAL_SRC"
        return 1
    fi

    get_web_dir

    # Source is one web/<site_key>/ whose domain has archived editions in
    # sites.conf: stage it with the sibling archive folders and publish once.
    local _src_dir _src_key _prc=0
    _src_dir="$(cd "$LOCAL_SRC" && pwd)" || { print_error "Cannot resolve $LOCAL_SRC"; return 1; }
    _src_key="$(basename "$_src_dir")"
    _site_archive_plan "$_src_key" || _prc=$?
    [[ $_prc -eq 2 ]] && return 1
    if [[ $_prc -eq 0 ]]; then
        _deploy_staged "$(dirname "$_src_dir")" "$_src_key" "$_PLAN_DOMAIN" "$WEB_DIR" local "${_PLAN_ARCHIVES[@]}" || return 1
        _prompt_ownership "$WEB_DIR"
        _save_deploy_state
        print_info "Deploy complete."
        return 0
    fi

    if _target_holds_archive "$WEB_DIR"; then return 1; fi
    print_info "Copying $LOCAL_SRC → $WEB_DIR"
    mkdir -p "$WEB_DIR"
    rsync -av --delete "$LOCAL_SRC/" "$WEB_DIR/"
    _ga4_apply_after_deploy "$WEB_DIR" "$LOCAL_SRC"
    _prompt_ownership "$WEB_DIR"
    _save_deploy_state
    print_info "Deploy complete."
}

_deploy_rsync() {
    # Default source: web/ directory at the repo root
    if [[ -z "$LOCAL_SRC" ]]; then
        local default_src
        default_src="$SCRIPT_DIR/web"
        ask "Source directory [default: $default_src]: " LOCAL_SRC
        LOCAL_SRC="${LOCAL_SRC:-$default_src}"
    fi

    if [[ ! -d "$LOCAL_SRC" ]]; then
        print_error "Source directory not found: $LOCAL_SRC"
        return 1
    fi

    if [[ -z "$REMOTE_USER" ]]; then
        ask "Remote SSH target (e.g. ubuntu@1.2.3.4): " REMOTE_USER
    fi

    if [[ -z "$REMOTE_PATH" ]]; then
        ask "Remote web directory (e.g. /var/www/grin.money/public): " REMOTE_PATH
    fi

    # Source is one web/<site_key>/ whose domain has archived editions in
    # sites.conf: push a staged tree (current + /<year>/ archives, tagged).
    # Unlike the GA4-only staging below, a failed stage aborts — pushing the
    # bare edition with --delete would remove the remote archive.
    local _src_dir _src_key _prc=0
    _src_dir="$(cd "$LOCAL_SRC" && pwd)" || { print_error "Cannot resolve $LOCAL_SRC"; return 1; }
    _src_key="$(basename "$_src_dir")"
    _site_archive_plan "$_src_key" || _prc=$?
    [[ $_prc -eq 2 ]] && return 1
    if [[ $_prc -eq 0 ]]; then
        _deploy_staged "$(dirname "$_src_dir")" "$_src_key" "$_PLAN_DOMAIN" \
            "$REMOTE_USER:$REMOTE_PATH" remote "${_PLAN_ARCHIVES[@]}" || return 1
        _save_deploy_state
        print_info "rsync deploy complete."
        return 0
    fi

    # ── GA4 via a local staging copy ──────────────────────────────────────────
    # local/git/all deploys inject into the *published* dir after the copy; over
    # SSH there is no local published dir to post-process, and injecting into
    # $LOCAL_SRC would dirty the git clone (the one rule _ga4_inject_dir exists
    # to protect). So: copy → tag the copy → push the copy. Without this the
    # remote gets pages whose <script src="js/ga4.js"> 404s, i.e. gtag.js loads
    # but no page_view is ever sent.
    local _stage="" _push_src="$LOCAL_SRC" _rc=0
    if _stage="$(mktemp -d 2>/dev/null)" && [[ -n "$_stage" ]]; then
        if rsync -a "$LOCAL_SRC/" "$_stage/"; then
            _ga4_apply_after_deploy "$_stage" "$LOCAL_SRC"
            _push_src="$_stage"
        else
            print_warn "GA4: staging copy failed — pushing source tree untagged."
            rm -rf "$_stage"; _stage=""
        fi
    else
        _stage=""
        print_warn "GA4: could not create a staging dir — pushing source tree untagged."
    fi

    if [[ -n "$_stage" ]]; then
        print_info "Pushing $LOCAL_SRC (GA4-tagged staging copy) → $REMOTE_USER:$REMOTE_PATH"
    else
        print_info "Pushing $LOCAL_SRC → $REMOTE_USER:$REMOTE_PATH"
    fi
    # No archive rows are known for this source, but the remote web dir may
    # already serve one under /<year>/: a dry run lists what --delete would
    # remove, and the push is refused if that includes a <YYYY>/index.html
    # (or if the dry run itself fails, since nothing could be checked).
    local _dry="" _drc=0
    _dry="$(rsync -anz --delete -i "$_push_src/" "$REMOTE_USER:$REMOTE_PATH/" 2>&1)" || _drc=$?
    if [[ $_drc -ne 0 ]]; then
        if [[ -n "$_stage" ]]; then rm -rf "$_stage"; fi
        print_error "rsync dry run failed (exit $_drc) — nothing pushed."
        printf '%s\n' "$_dry" | tail -n 5
        return "$_drc"
    fi
    if printf '%s\n' "$_dry" | grep -qE '^\*deleting +[0-9]{4}/index\.html$'; then
        if [[ -n "$_stage" ]]; then rm -rf "$_stage"; fi
        print_error "$REMOTE_USER:$REMOTE_PATH serves an archived edition this push would delete:"
        printf '%s\n' "$_dry" | grep -E '^\*deleting +[0-9]{4}/index\.html$' | sed 's/^/    /'
        print_warn "Add '<site_key> <domain> archive' to deploy/sites.conf, or remove that folder on the server by hand to retire it."
        return 1
    fi

    print_cmd "rsync -avz --delete $_push_src/ $REMOTE_USER:$REMOTE_PATH/"
    rsync -avz --delete "$_push_src/" "$REMOTE_USER:$REMOTE_PATH/" || _rc=$?

    if [[ -n "$_stage" ]]; then rm -rf "$_stage"; fi

    if [[ $_rc -ne 0 ]]; then
        print_error "rsync push failed (exit $_rc) — nothing saved."
        return "$_rc"
    fi

    _save_deploy_state
    print_info "rsync deploy complete."
}

_deploy_git() {
    # ── Load custom_repo.conf if it exists ────────────────────────────────────
    local conf_file
    conf_file="$SCRIPT_DIR/deploy/custom_repo.conf"
    if [[ -f "$conf_file" ]]; then
        print_info "Loading deploy config: $conf_file"
        # Source safely — only read known variables
        local _site _repo _branch _target _sparse
        _site=$(   grep -E '^SITE_NAME='          "$conf_file" | head -1 | cut -d= -f2- | tr -d '"' )
        _repo=$(   grep -E '^GIT_REPO='           "$conf_file" | head -1 | cut -d= -f2- | tr -d '"' )
        _branch=$( grep -E '^GIT_BRANCH='         "$conf_file" | head -1 | cut -d= -f2- | tr -d '"' )
        _target=$( grep -E '^DEPLOY_TARGET_DIR='  "$conf_file" | head -1 | cut -d= -f2- | tr -d '"' )
        _sparse=$( grep -E '^SPARSE_CHECKOUT='    "$conf_file" | head -1 | cut -d= -f2- | tr -d '"' )

        [[ -n "$_site"   && -z "$SITE_NAME"   ]] && SITE_NAME="$_site"
        [[ -n "$_repo"   && -z "$GIT_REPO"    ]] && GIT_REPO="$_repo"
        [[ -n "$_branch" && -z "$GIT_BRANCH"  ]] && GIT_BRANCH="$_branch"
        [[ -n "$_target" && -z "$WEB_DIR"     ]] && WEB_DIR="$_target"
        [[ -n "$_sparse"                      ]] && SPARSE_CHECKOUT="$_sparse"
    fi

    # ── Prompt for any still-missing values ───────────────────────────────────
    if [[ -z "$GIT_REPO" ]]; then
        ask "Git repo URL: " GIT_REPO
    fi

    # Branch selection — always offer a chance to override for testing
    echo ""
    echo -e "  Current branch: ${GREEN}${GIT_BRANCH:-main}${NC}"
    ask "  Deploy branch [press Enter to keep, or type another branch/tag]: " _branch_override
    [[ -n "$_branch_override" ]] && GIT_BRANCH="$_branch_override"
    GIT_BRANCH="${GIT_BRANCH:-main}"

    # ── Determine site subdirectory and web dir ────────────────────────────────
    # If SITE_NAME is set, source is web/<SITE_NAME>/ inside a temp clone
    local use_subdir=false
    [[ -n "${SITE_NAME:-}" ]] && use_subdir=true

    # Determine target web dir
    if [[ -z "$WEB_DIR" ]]; then
        if [[ -n "${DOMAIN:-}" ]]; then
            WEB_DIR="$NGINX_DEFAULT_ROOT/$DOMAIN/public"
        else
            ask "Target web directory on this server: " WEB_DIR
        fi
    fi
    print_info "Target: $WEB_DIR  branch: $GIT_BRANCH"

    # ── Clone or pull ──────────────────────────────────────────────────────────
    local tmp_clone="" staged=false _prc=0 _sparse_dirs _ak

    if $use_subdir; then
        # Clone to a temp dir, then rsync just the site subdir into WEB_DIR
        tmp_clone="$(mktemp -d)"
        _STAGE_CLONE_DIR="$tmp_clone"
        print_info "Cloning $GIT_REPO ($GIT_BRANCH) into temp dir..."

        if [[ "${SPARSE_CHECKOUT:-no}" == "yes" ]]; then
            # Sparse clone — only fetch web/<SITE_NAME>/ and deploy/ (the
            # branch's own sites.conf); archived editions are added below.
            git clone --filter=blob:none --no-checkout --depth 1 \
                --branch "$GIT_BRANCH" "$GIT_REPO" "$tmp_clone"
            git -C "$tmp_clone" sparse-checkout init --cone
            git -C "$tmp_clone" sparse-checkout set "web/$SITE_NAME" deploy
            git -C "$tmp_clone" checkout
        else
            git clone --depth 1 --branch "$GIT_BRANCH" "$GIT_REPO" "$tmp_clone"
        fi

        local site_src="$tmp_clone/web/$SITE_NAME"
        if [[ ! -d "$site_src" ]]; then
            print_error "Site directory not found in repo: web/$SITE_NAME"
            rm -rf "$tmp_clone"; _STAGE_CLONE_DIR=""
            return 1
        fi

        # Archived editions come from the DEPLOYED branch's sites.conf — the
        # one that matches the web/ folders being published — not from this
        # server's copy, which may be older.
        _site_archive_plan "$SITE_NAME" "$tmp_clone/deploy/sites.conf" || _prc=$?
        if [[ $_prc -eq 2 ]]; then rm -rf "$tmp_clone"; _STAGE_CLONE_DIR=""; return 1; fi
        if [[ $_prc -eq 0 && "${SPARSE_CHECKOUT:-no}" == "yes" ]]; then
            _sparse_dirs=("web/$SITE_NAME" deploy)
            for _ak in "${_PLAN_ARCHIVES[@]}"; do _sparse_dirs+=("web/$_ak"); done
            if ! git -C "$tmp_clone" sparse-checkout set "${_sparse_dirs[@]}"; then
                print_error "Could not add the archived editions to the sparse checkout."
                rm -rf "$tmp_clone"; _STAGE_CLONE_DIR=""
                return 1
            fi
        fi

        if [[ $_prc -eq 0 ]]; then
            if ! _deploy_staged "$tmp_clone/web" "$SITE_NAME" "$_PLAN_DOMAIN" "$WEB_DIR" local "${_PLAN_ARCHIVES[@]}"; then
                rm -rf "$tmp_clone"; _STAGE_CLONE_DIR=""
                return 1
            fi
            staged=true
        else
            if _target_holds_archive "$WEB_DIR"; then rm -rf "$tmp_clone"; _STAGE_CLONE_DIR=""; return 1; fi
            mkdir -p "$WEB_DIR"
            print_info "Syncing web/$SITE_NAME → $WEB_DIR"
            rsync -av --delete "$site_src/" "$WEB_DIR/"
        fi
        rm -rf "$tmp_clone"; _STAGE_CLONE_DIR=""

    elif [[ -d "$WEB_DIR/.git" ]]; then
        # Full repo already on server — just pull
        print_info "Pulling $GIT_BRANCH in $WEB_DIR"
        git -C "$WEB_DIR" fetch origin
        git -C "$WEB_DIR" checkout "$GIT_BRANCH"
        git -C "$WEB_DIR" pull origin "$GIT_BRANCH"
    else
        # Fresh full clone
        print_info "Cloning $GIT_REPO ($GIT_BRANCH) into $WEB_DIR"
        git clone --depth 1 --branch "$GIT_BRANCH" "$GIT_REPO" "$WEB_DIR"
    fi

    # A staged deploy was tagged before it was published.
    $staged || _ga4_apply_after_deploy "$WEB_DIR" "${SITE_NAME:-}"
    _prompt_ownership "$WEB_DIR"
    _save_deploy_state
    print_info "Git deploy complete  →  $WEB_DIR  [branch: $GIT_BRANCH]"
}

# Load deploy/sites.conf into the parallel arrays _SITE_KEYS / _SITE_DOMAINS /
# _SITE_WEBDIRS / _SITE_ARCHIVED. Web dir is derived from the domain unless a
# row gives an explicit override column (a third column starting with "/"). A
# third column of the literal word "archive" marks a past edition ("yes" in
# _SITE_ARCHIVED): it is published under /<year>/ of its domain's current site
# and never deployed on its own. Returns 1 if the manifest is missing/empty or
# the archive rules are broken (see _sites_conf_check) — a deploy that cannot
# tell which editions belong under a domain would wipe them with --delete.
_load_sites_conf() {
    _SITE_KEYS=(); _SITE_DOMAINS=(); _SITE_WEBDIRS=(); _SITE_ARCHIVED=()

    if [[ ! -f "$SITES_CONF_FILE" ]]; then
        print_error "Missing site manifest: $SITES_CONF_FILE"
        print_warn  "Create it (one row per site: <site_key> <domain> [web_dir|archive])."
        return 1
    fi

    local line _key _domain _third _webdir _archived _idx=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"                     # a CRLF-edited file
        line="${line%%#*}"                       # strip inline/full comments
        [[ -z "${line//[[:space:]]/}" ]] && continue   # skip blank / whitespace-only lines
        # Word-split on whitespace with globbing off, so a '*' in a row is
        # never expanded against the current directory.
        set -f
        # shellcheck disable=SC2086
        set -- $line
        set +f
        _key="${1:-}"; _domain="${2:-}"; _third="${3:-}"
        if [[ $# -gt 3 ]]; then
            print_warn "sites.conf: skipping row with $# columns (expected <site_key> <domain> [web_dir|archive]): $line"
            continue
        fi
        if [[ -z "$_key" || -z "$_domain" ]]; then
            print_warn "sites.conf: skipping malformed row: $line"
            continue
        fi
        _webdir="$NGINX_DEFAULT_ROOT/$_domain/public"; _archived=""
        if [[ "$_third" == "archive" ]]; then
            _archived="yes"
        elif [[ "$_third" == /* ]]; then
            _webdir="$_third"
        elif [[ -n "$_third" ]]; then
            print_error "sites.conf: third column must be an absolute web dir or 'archive': $line"
            return 1
        fi
        _SITE_KEYS[$_idx]="$_key"
        _SITE_DOMAINS[$_idx]="$_domain"
        _SITE_WEBDIRS[$_idx]="$_webdir"
        _SITE_ARCHIVED[$_idx]="$_archived"
        _idx=$(( _idx + 1 ))
    done < "$SITES_CONF_FILE"

    if [[ ${#_SITE_KEYS[@]} -eq 0 ]]; then
        print_warn "sites.conf has no usable site rows."
        return 1
    fi
    _sites_conf_check || return 1
    return 0
}

# Validate the loaded manifest: keys are unique; a domain has at most one
# current (non-archive) row; every archive row has a current row on its domain,
# a site_key ending in -YYYY, and a year no other archive of that domain uses.
_sites_conf_check() {
    local i j n=${#_SITE_KEYS[@]} bad=0 cur first
    for (( i=0; i<n; i++ )); do
        for (( j=i+1; j<n; j++ )); do
            if [[ "${_SITE_KEYS[$i]}" == "${_SITE_KEYS[$j]}" ]]; then
                print_error "sites.conf: site_key '${_SITE_KEYS[$i]}' is listed twice."
                bad=1
            fi
        done
        cur=0; first=""
        for (( j=0; j<n; j++ )); do
            if [[ "${_SITE_DOMAINS[$j]}" == "${_SITE_DOMAINS[$i]}" && -z "${_SITE_ARCHIVED[$j]}" ]]; then
                cur=$(( cur + 1 ))
                [[ -n "$first" ]] || first="$j"
            fi
        done
        if [[ -z "${_SITE_ARCHIVED[$i]}" ]]; then
            if (( cur > 1 )) && [[ "$first" == "$i" ]]; then
                print_error "sites.conf: domain '${_SITE_DOMAINS[$i]}' has $cur current rows — mark past editions 'archive' so exactly one is current."
                bad=1
            fi
            continue
        fi
        if (( cur == 0 )); then
            print_error "sites.conf: '${_SITE_KEYS[$i]}' is an archive of '${_SITE_DOMAINS[$i]}', but that domain has no current (non-archive) row."
            bad=1
        fi
        if ! _site_archive_year "${_SITE_KEYS[$i]}" >/dev/null; then
            print_error "sites.conf: archive '${_SITE_KEYS[$i]}' has no trailing -YYYY to publish it under /<year>/."
            bad=1
            continue
        fi
        for (( j=i+1; j<n; j++ )); do
            if [[ -n "${_SITE_ARCHIVED[$j]}" && "${_SITE_DOMAINS[$j]}" == "${_SITE_DOMAINS[$i]}" ]] \
               && [[ "$(_site_archive_year "${_SITE_KEYS[$j]}" 2>/dev/null || true)" == "$(_site_archive_year "${_SITE_KEYS[$i]}")" ]]; then
                print_error "sites.conf: '${_SITE_KEYS[$i]}' and '${_SITE_KEYS[$j]}' would both publish under /$(_site_archive_year "${_SITE_KEYS[$i]}")/ of ${_SITE_DOMAINS[$i]}."
                bad=1
            fi
        done
    done
    (( bad == 0 ))
}

# Print the year of an archive edition (the trailing -YYYY of its site_key).
_site_archive_year() {
    if [[ "$1" =~ -([0-9]{4})$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Look up which past editions belong under a current site.
#   $1 = site_key of the edition being deployed
#   $2 = manifest to read (default: this clone's deploy/sites.conf; git mode
#        passes the deployed branch's own copy)
# Fills _PLAN_DOMAIN and _PLAN_ARCHIVES (site_keys of that domain's archive
# rows). Returns 0 when the site has archives to assemble, 1 when it has none
# (no manifest, key not listed, or no archive rows), 2 when the deploy must
# not go ahead: the manifest is broken, or $1 is itself an archive row (its
# folder belongs under /<year>/, publishing it at the root would replace the
# current edition). A return of 1 still leaves the target to be checked with
# _target_holds_archive before a direct --delete copy.
_site_archive_plan() {
    local _manifest="${2:-$SITES_CONF_FILE}"
    local SITES_CONF_FILE="$_manifest"
    _PLAN_DOMAIN=""; _PLAN_ARCHIVES=()
    [[ -f "$SITES_CONF_FILE" ]] || return 1
    if ! _load_sites_conf; then
        print_error "$SITES_CONF_FILE is invalid — fix it before deploying (archived editions depend on it)."
        return 2
    fi
    _site_archive_plan_loaded "$1"
}

# Return 0 (and explain) when a web dir already serves an archived edition:
# some <dir>/<name>/index.html carries the banner/marker this script adds. A
# direct rsync --delete into it would remove that archive, so the legacy
# copy paths refuse instead.
#   $1 = target web dir
_target_holds_archive() {
    local dir="$1" f
    [[ -d "$dir" ]] || return 1
    for f in "$dir"/*/index.html; do
        [[ -f "$f" ]] || continue
        if grep -q 'data-archive-edition=' "$f" 2>/dev/null; then
            print_error "$dir serves an archived edition at /$(basename "$(dirname "$f")")/, but deploy/sites.conf has no 'archive' row for this site."
            print_warn  "A direct copy would delete it. Add '<site_key> <domain> archive' to sites.conf, or remove that folder by hand to retire the archive."
            return 0
        fi
    done
    return 1
}

# Return 0 when a publish target is an absolute path of at least two
# components with no empty, '.' or '..' component (so never '/', '/var',
# '//', '/.', or a relative path).
#   $1 = path
_safe_target_path() {
    local p="$1" c n=0
    [[ "$p" == /* ]] || return 1
    p="${p%/}"
    [[ "$p" != *//* ]] || return 1
    local IFS=/
    set -f
    # shellcheck disable=SC2086
    set -- ${p#/}
    set +f
    for c in "$@"; do
        [[ -n "$c" && "$c" != "." && "$c" != ".." ]] || return 1
        n=$(( n + 1 ))
    done
    (( n >= 2 ))
}

# _site_archive_plan against the manifest already in the _SITE_* arrays (the
# batch deploy iterates those arrays, so it must not reload them mid-loop).
_site_archive_plan_loaded() {
    local key="$1" i found=""
    _PLAN_DOMAIN=""; _PLAN_ARCHIVES=()
    for (( i=0; i<${#_SITE_KEYS[@]}; i++ )); do
        if [[ "${_SITE_KEYS[$i]}" == "$key" ]]; then found="$i"; break; fi
    done
    [[ -n "$found" ]] || return 1
    if [[ -n "${_SITE_ARCHIVED[$found]}" ]]; then
        print_error "'$key' is marked 'archive' in sites.conf — it is published under /$(_site_archive_year "$key")/ when its domain's current edition deploys."
        return 2
    fi
    _PLAN_DOMAIN="${_SITE_DOMAINS[$found]}"
    for (( i=0; i<${#_SITE_KEYS[@]}; i++ )); do
        if [[ -n "${_SITE_ARCHIVED[$i]}" && "${_SITE_DOMAINS[$i]}" == "$_PLAN_DOMAIN" ]]; then
            _PLAN_ARCHIVES+=("${_SITE_KEYS[$i]}")
        fi
    done
    (( ${#_PLAN_ARCHIVES[@]} > 0 ))
}

#############################################################################
# Archived editions — staged build
#############################################################################
# A domain's current edition is published at the web root and each archived
# edition under /<year>/. Everything is assembled in a staging dir and pushed
# with ONE rsync (--delay-updates --delete-after), so a deploy never removes
# the archive and a failure at any step leaves the live web dir untouched.

# Rewrite one HTML file of an archived edition in place (idempotent):
#   - relative href=/src= values become absolute /<year>/<value>: nginx's
#     `try_files $uri $uri/` can serve /<year> (no slash) without redirecting,
#     and a relative favicon.svg would then load the CURRENT edition's file.
#     Values starting with /, #, // or a scheme (https:, mailto:, data:, …)
#     are left alone;
#   - manual links (docs, docs/…, ./docs/…) go to the current manual at
#     /docs/…, extension-less as the /docs/ vhost block serves them (the
#     archive carries no docs/);
#   - robots meta → "noindex, follow"; canonical → https://<domain>/;
#   - a one-line banner right after <body …> linking to the current site.
# Lines this adds are exact strings, deleted and re-added on every run;
# existing robots/canonical tags are replaced in place. Fails (returns 1) when
# the page has no <head>, when the first <head> sits inside a comment or a
# <script>, or when a robots/canonical tag spans lines (it cannot be replaced
# safely, and adding a second one would leave the page's own in force).
# The file keeps its own mode: the rewrite is copied back into it.
#   $1 = html file  $2 = domain  $3 = year
_archive_transform_html() {
    local f="$1" domain="$2" year="$3" tmp rc=0
    if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ || ! "$year" =~ ^[0-9]{4}$ ]]; then
        print_error "Archive: refusing domain '$domain' / year '$year'"
        return 1
    fi
    tmp="${f}.archive-tmp"
    ARCH_YEAR="$year" \
    ARCH_ROBOTS="  <meta name=\"robots\" content=\"noindex, follow\" data-archive-edition=\"${year}\">" \
    ARCH_CANON="  <link rel=\"canonical\" href=\"https://${domain}/\" data-archive-edition=\"${year}\">" \
    ARCH_ROBOTS_INPLACE="<meta name=\"robots\" content=\"noindex, follow\">" \
    ARCH_CANON_INPLACE="<link rel=\"canonical\" href=\"https://${domain}/\">" \
    ARCH_BANNER="<div data-archive-edition=\"${year}\" role=\"note\" style=\"display:block;box-sizing:border-box;width:100%;margin:0;padding:6px 16px;background:#15181b;color:#f3f5f7;border-bottom:1px solid #3d444b;font:13px/1.45 system-ui,sans-serif;text-align:center;position:relative;z-index:40\">You&rsquo;re viewing the ${year} edition of ${domain} &middot; <a href=\"/\" style=\"color:#ffd86b;text-decoration:underline;font-weight:600\">see the current site</a></div>" \
    awk '
        # Replace every match of re (matched case-insensitively) in s: the
        # first one in the file with NEW[kind], later ones with nothing.
        function sub_tag(s, re, kind,    out, l) {
            out = ""
            while (1) {
                l = tolower(s)
                if (!match(l, re)) break
                out = out substr(s, 1, RSTART - 1)
                if (!(kind in done)) { out = out NEW[kind]; done[kind] = 1 }
                s = substr(s, RSTART + RLENGTH)
            }
            return out s
        }
        # Position of the last occurrence of t in s (0 when absent).
        function lastidx(s, t,    p, r, k) {
            r = 0; p = 0
            while ((k = index(substr(s, p + 1), t)) > 0) { p += k; r = p }
            return r
        }
        # Map one attribute value of an archived page to its absolute URL.
        function rewrite_url(v,    p, rest, tail, k, c) {
            c = substr(v, 1, 1)
            if (v == "" || c == "/" || c == "#") return v
            if (tolower(v) ~ /^[a-z][a-z0-9+.-]*:/) return v
            p = v
            while (substr(p, 1, 2) == "./") p = substr(p, 3)
            if (p == "docs" || substr(p, 1, 5) == "docs/" || p ~ /^docs[?#]/) {
                rest = substr(p, 5)
                if (substr(rest, 1, 1) == "/") rest = substr(rest, 2)
                tail = ""
                k = match(rest, /[?#]/)
                if (k) { tail = substr(rest, k); rest = substr(rest, 1, k - 1) }
                if (rest == "index.html" || rest == "index.htm" || rest == "index") rest = ""
                else sub(/\.html?$/, "", rest)
                return "/docs/" rest tail
            }
            return "/" YEAR "/" p
        }
        # Rewrite every quoted href=/src= value on a line. The attribute name
        # must follow whitespace (or start the line), so data-href= and the
        # like never match. A value whose closing quote is on a later line is
        # left as it is.
        function rewrite_attrs(s,    t, out, q, e) {
            t = " " s; out = ""
            while (match(tolower(t), RE_ATTR)) {
                out = out substr(t, 1, RSTART + RLENGTH - 1)
                q = substr(t, RSTART + RLENGTH - 1, 1)
                t = substr(t, RSTART + RLENGTH)
                e = index(t, q)
                if (e == 0) break
                out = out rewrite_url(substr(t, 1, e - 1)) q
                t = substr(t, e + 1)
            }
            return substr(out t, 2)
        }
        BEGIN {
            YEAR = ENVIRON["ARCH_YEAR"]
            q = "[\"\047]?"
            RE_ROBOTS = "<meta[^>]*name=" q "robots" q "[^>]*>"
            RE_CANON  = "<link[^>]*rel=" q "canonical" q "[^>]*>"
            RE_HEAD   = "<head>|<head[ \t][^>]*>"
            RE_BODY   = "<body>|<body[ \t][^>]*>"
            RE_ATTR   = "[ \t](href|src)[ \t]*=[ \t]*[\"\047]"
            RE_ML     = "[ \t](name[ \t]*=[ \t]*" q "robots|rel[ \t]*=[ \t]*" q "canonical)"
            NEW["robots"] = ENVIRON["ARCH_ROBOTS_INPLACE"]
            NEW["canon"]  = ENVIRON["ARCH_CANON_INPLACE"]
        }
        { L[NR] = $0 }
        END {
            # A <meta>/<link> left open at the end of a line: if the tag
            # (up to its ">") has name=robots or rel=canonical, refuse.
            for (i = 1; i <= NR; i++) {
                l = tolower(L[i])
                p = lastidx(l, "<meta"); k = lastidx(l, "<link")
                if (k > p) p = k
                if (p == 0 || index(substr(l, p), ">") > 0) continue
                tag = substr(l, p)
                for (j = i + 1; j <= NR; j++) {
                    e = index(tolower(L[j]), ">")
                    if (e > 0) { tag = tag " " substr(tolower(L[j]), 1, e); break }
                    tag = tag " " tolower(L[j])
                }
                if (tag ~ RE_ML) exit 6
            }
            m = 0
            for (i = 1; i <= NR; i++) {
                s = L[i]
                if (s == ENVIRON["ARCH_ROBOTS"] || s == ENVIRON["ARCH_CANON"] || s == ENVIRON["ARCH_BANNER"]) continue
                o = s
                s = sub_tag(s, RE_ROBOTS, "robots")
                s = sub_tag(s, RE_CANON,  "canon")
                s = rewrite_attrs(s)
                if (o ~ /[^ \t\r]/ && s !~ /[^ \t\r]/) continue
                O[++m] = s
            }
            hd = 0; bd = 0; seen = ""
            for (i = 1; i <= m; i++) {
                s = O[i]
                if (!hd && match(tolower(s), RE_HEAD)) {
                    pre = seen tolower(substr(s, 1, RSTART - 1))
                    if (lastidx(pre, "<!--") > lastidx(pre, "-->")) exit 5
                    if (lastidx(pre, "<script") > lastidx(pre, "</script")) exit 5
                    print substr(s, 1, RSTART + RLENGTH - 1)
                    if (!("robots" in done)) print ENVIRON["ARCH_ROBOTS"]
                    if (!("canon"  in done)) print ENVIRON["ARCH_CANON"]
                    hd = 1
                    s = substr(s, RSTART + RLENGTH)
                    if (s !~ /[^ \t\r]/) continue
                }
                if (!hd) seen = seen tolower(s) "\n"
                if (hd && !bd && match(tolower(s), RE_BODY)) {
                    print substr(s, 1, RSTART + RLENGTH - 1)
                    print ENVIRON["ARCH_BANNER"]
                    bd = 1
                    s = substr(s, RSTART + RLENGTH)
                    if (s !~ /[^ \t\r]/) continue
                }
                print s
            }
            if (!hd) exit 3
            if (!bd) exit 4
        }
    ' "$f" > "$tmp" || rc=$?
    case "$rc" in
        0) ;;
        4) print_warn "Archive: no <body> in ${f##*/} — banner NOT added (noindex/canonical applied)" ;;
        3) rm -f -- "$tmp"; print_error "Archive: no <head> in $f — cannot mark it noindex"; return 1 ;;
        5) rm -f -- "$tmp"; print_error "Archive: the first <head> in $f is inside a comment or <script> — rewrite it by hand"; return 1 ;;
        6) rm -f -- "$tmp"; print_error "Archive: a robots/canonical tag in $f spans lines — put it on one line"; return 1 ;;
        *) rm -f -- "$tmp"; print_error "Archive: rewriting $f failed (awk exit $rc)"; return 1 ;;
    esac
    if [[ ! -s "$tmp" ]]; then
        rm -f -- "$tmp"; print_error "Archive: rewrite of $f came out empty"; return 1
    fi
    # Copy back into the original file (not mv) so its mode is kept.
    cat -- "$tmp" > "$f" || { rm -f -- "$tmp"; print_error "Archive: could not rewrite $f"; return 1; }
    rm -f -- "$tmp" || { print_error "Archive: could not remove $tmp"; return 1; }
    return 0
}

# Copy one archived edition into the staging tree and rewrite its pages
# (*.html and *.htm, every depth). docs/, robots.txt and sitemap.xml stay out:
# the manual and the crawl files belong to the current edition at the root.
#   $1 = edition source dir  $2 = destination (<stage>/<year>)  $3 = domain  $4 = year
_archive_stage_edition() {
    local src="$1" dest="$2" domain="$3" year="$4" f n=0 found=0 list
    [[ -d "$src" && -f "$src/index.html" ]] || { print_error "Archive: $src has no index.html"; return 1; }
    rsync -a --exclude='/docs/' --exclude='/robots.txt' --exclude='/sitemap.xml' "$src/" "$dest/" \
        || { print_error "Archive: copying $src → $dest failed"; return 1; }
    list="$(mktemp 2>/dev/null)" || list=""
    [[ -n "$list" && -f "$list" ]] || { print_error "Archive: could not create a temp file"; return 1; }
    if ! find "$dest" -type f \( -name '*.html' -o -name '*.htm' \) -print0 > "$list"; then
        rm -f -- "$list"; print_error "Archive: listing pages in $dest failed"; return 1
    fi
    found="$(tr -cd '\000' < "$list" | wc -c)" || found=-1
    found="${found//[[:space:]]/}"
    while IFS= read -r -d '' f; do
        if ! _archive_transform_html "$f" "$domain" "$year"; then
            rm -f -- "$list"; return 1
        fi
        n=$(( n + 1 ))
    done < "$list"
    rm -f -- "$list"
    if [[ "$n" != "$found" || "$n" -eq 0 ]]; then
        print_error "Archive: rewrote $n of ${found} page(s) in $dest — refusing a partial archive"
        return 1
    fi
    [[ -f "$dest/index.html" ]] || { print_error "Archive: $dest/index.html missing after copy"; return 1; }
    print_info "  Archive: $(basename "$src") → /$year/ ($n page(s) marked noindex + banner)"
    return 0
}

# Tag a staged tree with the GA4 ID of site_key from analytics.conf. A site
# with no mapping deploys untagged, as every other deploy path does; a mapping
# that fails to apply aborts the deploy. Verified on the pages _ga4_inject_dir
# covers (top level and one directory down — an archive's /<year>/ pages
# included) that have a </head>: each must carry the loader with this ID.
#   $1 = staged dir  $2 = site_key
_stage_apply_ga4() {
    local dir="$1" key="$2" i id="" f bad=0
    if ! _load_analytics_conf; then
        print_warn "GA4: no analytics.conf mappings — skipping injection."
        return 0
    fi
    for (( i=0; i<${#_GA4_SITES[@]}; i++ )); do
        if [[ "${_GA4_SITES[$i]}" == "$key" ]]; then id="${_GA4_IDS[$i]}"; break; fi
    done
    if [[ -z "$id" ]]; then
        print_warn "GA4: no analytics.conf entry for $key — deploying untagged."
        return 0
    fi
    print_info "GA4: applying $id to staged site ($key)"
    _ga4_inject_dir "$dir" "$id" || return 1
    [[ -s "$dir/js/ga4.js" ]] || { print_error "GA4: $dir/js/ga4.js was not written"; return 1; }
    for f in "$dir"/*.html "$dir"/*/*.html; do
        [[ -f "$f" ]] || continue
        # Same skip rule as _ga4_inject_dir: a page with no </head> (e.g. a
        # Search Console verification file) is never tagged.
        grep -q "</head>" "$f" 2>/dev/null || continue
        if ! grep -q "googletagmanager.com/gtag/js?id=${id}\"" "$f" 2>/dev/null; then
            print_error "GA4: ${f#"$dir"/} is not tagged with $id"
            bad=1
        fi
    done
    (( bad == 0 ))
}

# Assemble <stage> = current edition + archives under /<year>/, tagged.
#   $1 = source root holding the <site_key>/ folders  $2 = current site_key
#   $3 = domain  $4 = stage dir to create (must not exist)
#   remaining args = archive site_keys
_stage_site_build() {
    local src_root="$1" key="$2" domain="$3" st="$4" akey year
    shift 4
    [[ -n "$st" && ! -e "$st" ]] || { print_error "Staging: bad staging path '$st'"; return 1; }
    [[ -f "$src_root/$key/index.html" ]] || { print_error "Staging: $src_root/$key has no index.html"; return 1; }
    rsync -a "$src_root/$key/" "$st/" || { print_error "Staging: copying web/$key failed"; return 1; }
    for akey in "$@"; do
        year="$(_site_archive_year "$akey")" || { print_error "Staging: '$akey' has no trailing -YYYY"; return 1; }
        [[ -d "$src_root/$akey" ]] || { print_error "Staging: archived edition web/$akey is not in the source"; return 1; }
        if [[ -e "$st/$year" ]]; then
            print_error "Staging: web/$key already has a '$year' entry — it would collide with the $akey archive"
            return 1
        fi
        _archive_stage_edition "$src_root/$akey" "$st/$year" "$domain" "$year" || return 1
    done
    _stage_apply_ga4 "$st" "$key" || return 1
    [[ -f "$st/index.html" ]] || { print_error "Staging: $st/index.html missing"; return 1; }
    return 0
}

# Staging dir of the deploy in progress, read by the INT/TERM trap.
_STAGE_DIR=""

# Temp git clone of the single-site git deploy in progress (set and cleared by
# _deploy_git), removed by the same INT/TERM trap as the staging dir.
_STAGE_CLONE_DIR=""

# Remove the staging dir; with "all" (the INT/TERM trap) the registered git
# clone too.
_stage_cleanup() {
    if [[ -n "$_STAGE_DIR" && -d "$_STAGE_DIR" ]]; then rm -rf -- "$_STAGE_DIR"; fi
    _STAGE_DIR=""
    if [[ "${1:-}" == "all" && -n "$_STAGE_CLONE_DIR" && -d "$_STAGE_CLONE_DIR" ]]; then
        rm -rf -- "$_STAGE_CLONE_DIR"
        _STAGE_CLONE_DIR=""
    fi
}

# Build the staged site and push it with one rsync. The live target is only
# touched by that final rsync, after every staging step succeeded; it runs
# with --delay-updates --delete-after, so files are swapped in at the end and
# removals happen only once the new tree is in place.
#   $1 = source root  $2 = current site_key  $3 = domain
#   $4 = target: a local web dir, or user@host:/path when $5 = "remote"
#   $5 = "local" | "remote"
#   remaining args = archive site_keys
# The staging dir is removed on success, on failure, and on INT/TERM (the
# caller's INT/TERM traps are restored afterwards). Staging runs under umask
# 022 so files it creates (js/ga4.js and its dir) are readable by nginx.
_deploy_staged() {
    local src_root="$1" key="$2" domain="$3" target="$4" how="$5" rc=0
    local old_int old_term old_umask
    shift 5
    case "$how" in
        local)  if ! _safe_target_path "$target"; then
                    print_error "Refusing to publish into web dir '${target:-<empty>}'"; return 1
                fi ;;
        remote) if [[ "$target" != *:* ]] || [[ "${target%%:*}" == "" ]] || ! _safe_target_path "${target#*:}"; then
                    print_error "Refusing to publish into remote path '${target:-<empty>}'"; return 1
                fi ;;
        *)      print_error "_deploy_staged: unknown mode '$how'"; return 1 ;;
    esac
    _STAGE_DIR="$(mktemp -d 2>/dev/null)" || _STAGE_DIR=""
    if [[ -z "$_STAGE_DIR" || ! -d "$_STAGE_DIR" ]]; then
        _STAGE_DIR=""
        print_error "Staging: could not create a temp dir — live site left untouched."
        return 1
    fi
    old_int="$(trap -p INT)"; old_term="$(trap -p TERM)"; old_umask="$(umask)"
    trap '_stage_cleanup all; exit 130' INT
    trap '_stage_cleanup all; exit 143' TERM
    umask 022

    _deploy_staged_run "$src_root" "$key" "$domain" "$target" "$how" "$@" || rc=$?

    umask "$old_umask"
    _stage_cleanup
    if [[ -n "$old_int" ]]; then eval "$old_int"; else trap - INT; fi
    if [[ -n "$old_term" ]]; then eval "$old_term"; else trap - TERM; fi
    return "$rc"
}

# Body of _deploy_staged, run with $_STAGE_DIR created and cleaned up by it.
_deploy_staged_run() {
    local src_root="$1" key="$2" domain="$3" target="$4" how="$5" rc=0
    shift 5
    print_info "Staging $key + ${#} archive(s) in $_STAGE_DIR"
    if ! _stage_site_build "$src_root" "$key" "$domain" "$_STAGE_DIR/site" "$@"; then
        print_error "Staging failed for $key — live site left untouched."
        return 1
    fi
    if [[ "$how" == "local" ]]; then
        mkdir -p -- "$target" || { print_error "Could not create $target"; return 1; }
        print_info "Publishing staged $key → $target"
        rsync -a --delay-updates --delete-after "$_STAGE_DIR/site/" "$target/" || rc=$?
    else
        print_info "Pushing staged $key → $target"
        print_cmd "rsync -avz --delay-updates --delete-after <staging>/ $target/"
        rsync -avz --delay-updates --delete-after "$_STAGE_DIR/site/" "$target/" || rc=$?
    fi
    if [[ $rc -ne 0 ]]; then
        print_error "rsync to $target failed (exit $rc)."
        return "$rc"
    fi
    return 0
}

# Batch git deploy: pull every site in deploy/sites.conf in a single clone.
# Repo + branch come from custom_repo.conf (or --git-repo/--git-branch); each
# site's web/<key>/ subdir is rsynced to its derived web dir, GA4 is applied,
# and ownership (DEPLOY_OWNER) is reapplied. Non-interactive friendly: with
# --all nothing is prompted, so it drops cleanly into cron.
# Batch deploy: publish EVERY site in deploy/sites.conf in one pass, copying
# each web/<key>/ straight out of THIS clone ($SCRIPT_DIR/web) to its web dir.
# No re-clone — the repo is already on the server (refresh it first with option
# 9 / git pull). Web dir per site is derived from its domain unless the manifest
# row overrides it. Non-interactive friendly: with --all nothing is prompted.
# A domain with 'archive' rows is staged first (current edition + /<year>/
# copies, see _deploy_staged) so the archive survives every --delete.
_deploy_all() {
    _load_sites_conf || return 1

    local src_root="$SCRIPT_DIR/web"
    if [[ ! -d "$src_root" ]]; then
        print_error "Local source not found: $src_root"
        print_info  "Run this on the server inside the cloned repo (option 9 pulls latest content)."
        return 1
    fi

    print_info "Batch deploy — ${#_SITE_KEYS[@]} site(s) from $src_root"
    print_warn "Publishing whatever is in this clone now. Run option 9 (or 'git pull') first to refresh content."

    # Ask for ownership once (interactive only) so every site gets the same owner.
    if [[ -z "$DEPLOY_OWNER" && "$DEPLOY_ALL" != "yes" ]]; then
        ask "  Set ownership for all deployed sites (e.g. www-data:www-data, Enter to skip): " _owner
        DEPLOY_OWNER="${_owner:-}"
    fi

    local i ok=0 fail=0 site_src target _prc
    for (( i=0; i<${#_SITE_KEYS[@]}; i++ )); do
        site_src="$src_root/${_SITE_KEYS[$i]}"
        target="${_SITE_WEBDIRS[$i]}"
        echo ""
        # Archive rows are published inside their domain's current site below.
        if [[ -n "${_SITE_ARCHIVED[$i]}" ]]; then
            print_info "[${_SITE_KEYS[$i]}] archived edition — published under ${_SITE_DOMAINS[$i]}/$(_site_archive_year "${_SITE_KEYS[$i]}")/"
            continue
        fi
        print_info "[${_SITE_KEYS[$i]}] → $target"
        if [[ ! -d "$site_src" ]]; then
            print_error "  Not in clone: web/${_SITE_KEYS[$i]} — skipping"
            fail=$(( fail + 1 )); continue
        fi
        # A site with archived editions is assembled in a staging dir and
        # pushed in one rsync; one without keeps the direct copy below.
        _prc=0; _site_archive_plan_loaded "${_SITE_KEYS[$i]}" || _prc=$?
        if [[ $_prc -eq 0 ]]; then
            if ! _deploy_staged "$src_root" "${_SITE_KEYS[$i]}" "$_PLAN_DOMAIN" "$target" local "${_PLAN_ARCHIVES[@]}"; then
                fail=$(( fail + 1 )); continue
            fi
            if [[ -n "$DEPLOY_OWNER" ]]; then
                if ! chown -R "$DEPLOY_OWNER" "$target"; then
                    print_error "  Ownership $DEPLOY_OWNER could not be set on $target"
                    fail=$(( fail + 1 )); continue
                fi
                print_info "  Ownership: $DEPLOY_OWNER"
            fi
            ok=$(( ok + 1 ))
            continue
        elif [[ $_prc -ne 1 ]]; then
            fail=$(( fail + 1 )); continue
        fi
        if _target_holds_archive "$target"; then fail=$(( fail + 1 )); continue; fi
        mkdir -p "$target"
        if rsync -a --delete "$site_src/" "$target/"; then
            _ga4_apply_after_deploy "$target" "${_SITE_KEYS[$i]}"
            if [[ -n "$DEPLOY_OWNER" ]]; then
                chown -R "$DEPLOY_OWNER" "$target" \
                    && print_info "  Ownership: $DEPLOY_OWNER"
            fi
            ok=$(( ok + 1 ))
        else
            print_error "  rsync failed for ${_SITE_KEYS[$i]}"
            fail=$(( fail + 1 ))
        fi
    done

    echo ""
    print_info "Batch deploy complete — $ok deployed, $fail skipped/failed."
    [[ $fail -eq 0 ]]
}

#############################################################################
# 4. List Sites
#############################################################################

action_list_sites() {
    print_section "Configured nginx Sites"

    local count=0
    for conf in "$NGINX_AVAILABLE"/*; do
        [[ -f "$conf" ]] || continue
        local name
        name="$(basename "$conf")"
        [[ "$name" == "default" || "$name" == "default-ssl" ]] && continue

        local enabled=""
        if [[ -L "$NGINX_ENABLED/$name" ]] || [[ "$NGINX_AVAILABLE" == "$NGINX_ENABLED" ]]; then
            enabled="${GREEN}[enabled]${NC}"
        else
            enabled="${YELLOW}[disabled]${NC}"
        fi

        local root_dir
        root_dir=$(grep -oP 'root\s+\K[^;]+' "$conf" 2>/dev/null | head -1 || echo "—")
        local ssl_status="no SSL"
        grep -q "ssl_certificate" "$conf" 2>/dev/null && ssl_status="${GREEN}SSL${NC}"

        printf "  %-35s %s  %b  root: %s\n" "$name" "$ssl_status" "$enabled" "$root_dir"
        count=$(( count + 1 ))
    done

    [[ $count -eq 0 ]] && echo "  (no sites configured)"
    echo ""
}

#############################################################################
# 5. Security Hardening
#############################################################################

action_security() {
    print_section "Security Hardening"

    echo "Options:"
    echo "  1) Audit existing sites     — check for missing security headers"
    echo "  2) Inject global nginx.conf hardening  (server_tokens, TLS params)"
    echo "  3) Auto-renew SSL check     — test certbot renewal dry-run"
    echo "  0) Back"
    echo ""
    ask "Choose [0-3]: " _sc

    case "$_sc" in
        1) _security_audit ;;
        2) _security_harden_global ;;
        3) _security_ssl_renew_test ;;
        0) return 0 ;;
    esac
}

_security_audit() {
    print_section "Security Audit"
    local headers=("Strict-Transport-Security" "X-Frame-Options" "X-Content-Type-Options"
                   "Referrer-Policy" "Content-Security-Policy" "Permissions-Policy")

    for conf in "$NGINX_AVAILABLE"/*; do
        [[ -f "$conf" ]] || continue
        local name; name="$(basename "$conf")"
        [[ "$name" == "default" ]] && continue
        echo ""
        echo -e "  ${BOLD}$name${NC}"
        for header in "${headers[@]}"; do
            if grep -q "$header" "$conf" 2>/dev/null; then
                echo -e "    ${GREEN}✓${NC} $header"
            else
                echo -e "    ${RED}✗${NC} $header  ${DIM}(missing)${NC}"
            fi
        done
    done
    echo ""
}

_security_harden_global() {
    local global_conf="$NGINX_CONF_DIR/conf.d/grin-hardening.conf"
    mkdir -p "$(dirname "$global_conf")"

    cat > "$global_conf" << 'HARD_EOF'
# Grin Landing Page — Global nginx Security Hardening
# Managed by site_manager.sh

# Hide nginx version
server_tokens off;

# TLS configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;

# OCSP stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;

# Limit request size (prevents large upload attacks)
client_max_body_size 1m;
client_body_timeout 10;
client_header_timeout 10;
keepalive_timeout 5 5;
send_timeout 10;
HARD_EOF

    print_info "Global hardening config written: $global_conf"
    nginx_reload
}

_security_ssl_renew_test() {
    if ! command -v certbot &>/dev/null; then
        print_error "certbot not installed."
        return 1
    fi
    print_info "Running certbot renewal dry-run..."
    certbot renew --dry-run
    print_info "Dry-run complete. Cron job for auto-renewal:"
    echo ""
    print_cmd "0 0,12 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'"
    echo ""
    ask "Add this cron job now? (y/N): " _cron
    if [[ "${_cron,,}" == "y" ]]; then
        if [[ -f /etc/cron.d/certbot-renew ]]; then
            print_warn "Cron job already exists at /etc/cron.d/certbot-renew — skipping."
        else
            echo "0 0,12 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" \
                > /etc/cron.d/certbot-renew
            print_info "Cron job added: /etc/cron.d/certbot-renew"
        fi
    fi
}

#############################################################################
# 6. Install fail2ban
#############################################################################

action_fail2ban_install() {
    print_section "Install fail2ban"

    if ! command -v fail2ban-server &>/dev/null; then
        print_info "Installing fail2ban..."
        pkg_install fail2ban
    else
        print_info "fail2ban is already installed."
    fi

    # Write nginx jail config
    mkdir -p "$(dirname "$FAIL2BAN_JAIL")"
    cat > "$FAIL2BAN_JAIL" << 'F2B_EOF'
# fail2ban jail for nginx — managed by site_manager.sh
[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = %(nginx_error_log)s

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = %(nginx_access_log)s
maxretry = 2

[nginx-req-limit]
enabled  = true
filter   = nginx-req-limit
port     = http,https
logpath  = %(nginx_error_log)s
maxretry = 10
findtime = 600
bantime  = 7200
F2B_EOF

    # nginx-req-limit filter (rate limit ban)
    mkdir -p /etc/fail2ban/filter.d
    cat > /etc/fail2ban/filter.d/nginx-req-limit.conf << 'FILTER_EOF'
[Definition]
failregex = limiting requests, excess:.* by zone.*client: <HOST>
ignoreregex =
FILTER_EOF

    if [[ "$OS" == "linux" ]]; then
        systemctl enable fail2ban
        systemctl restart fail2ban
    fi

    print_info "fail2ban configured with nginx jails."
    print_info "Config: $FAIL2BAN_JAIL"
}

#############################################################################
# 7. fail2ban Management
#############################################################################

action_fail2ban_mgmt() {
    print_section "fail2ban Management"

    if ! command -v fail2ban-client &>/dev/null; then
        print_error "fail2ban not installed. Run option 6 first."
        return 1
    fi

    echo "  1) Show status (all jails)"
    echo "  2) List banned IPs"
    echo "  3) Unban an IP"
    echo "  0) Back"
    echo ""
    ask "Choose [0-3]: " _f2b

    case "$_f2b" in
        1) fail2ban-client status ;;
        2)
            echo ""
            for jail in nginx-http-auth nginx-botsearch nginx-req-limit; do
                echo -e "  ${YELLOW}[$jail]${NC}"
                fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP" || echo "  (not active)"
            done
            ;;
        3)
            ask "Enter IP to unban: " _ip
            ask "Enter jail name [nginx-req-limit]: " _jail
            _jail="${_jail:-nginx-req-limit}"
            fail2ban-client set "$_jail" unbanip "$_ip"
            print_info "Unbanned: $_ip from $_jail"
            ;;
        0) return 0 ;;
    esac
}

#############################################################################
# 8. IP Filtering
#############################################################################

action_ip_filter() {
    print_section "IP Filtering"

    detect_firewall
    print_info "Firewall: $FIREWALL"
    mkdir -p /etc/grin-landing
    touch "$BLOCKED_LIST" 2>/dev/null || true

    echo ""
    echo "  1) Block an IP"
    echo "  2) Unblock an IP"
    echo "  3) List blocked IPs"
    echo "  0) Back"
    echo ""
    ask "Choose [0-3]: " _ipf

    case "$_ipf" in
        1)
            ask "Enter IP to block: " _ip
            validate_ip "$_ip" || { print_error "Invalid IP: $_ip"; return 1; }
            _firewall_block "$_ip"
            grep -qxF "$_ip" "$BLOCKED_LIST" || echo "$_ip" >> "$BLOCKED_LIST"
            print_info "Blocked: $_ip"
            ;;
        2)
            ask "Enter IP to unblock: " _ip
            validate_ip "$_ip" || { print_error "Invalid IP: $_ip"; return 1; }
            _firewall_unblock "$_ip"
            grep -vxF "$_ip" "$BLOCKED_LIST" > "${BLOCKED_LIST}.tmp" && mv "${BLOCKED_LIST}.tmp" "$BLOCKED_LIST" || true
            print_info "Unblocked: $_ip"
            ;;
        3)
            echo ""
            if [[ -s "$BLOCKED_LIST" ]]; then
                echo "  Blocked IPs ($BLOCKED_LIST):"
                while IFS= read -r ip; do echo "    $ip"; done < "$BLOCKED_LIST"
            else
                echo "  (no IPs blocked)"
            fi
            ;;
        0) return 0 ;;
    esac
}

_firewall_block() {
    local ip="$1"
    case "$FIREWALL" in
        ufw)       ufw insert 1 deny from "$ip" to any ;;
        iptables)  iptables -I INPUT -s "$ip" -j DROP ;;
        firewalld) firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$ip reject" && firewall-cmd --reload ;;
        none) print_warn "No firewall — cannot block IP $ip at OS level." ;;
    esac
}

_firewall_unblock() {
    local ip="$1"
    case "$FIREWALL" in
        ufw)       ufw delete deny from "$ip" to any ;;
        iptables)  iptables -D INPUT -s "$ip" -j DROP 2>/dev/null || true ;;
        firewalld) firewall-cmd --permanent --remove-rich-rule="rule family=ipv4 source address=$ip reject" && firewall-cmd --reload ;;
        none) print_warn "No firewall configured." ;;
    esac
}

#############################################################################
# A. Analytics (GA4) — config-driven, multi-site
#############################################################################

_GA4_SITES=()
_GA4_IDS=()

_load_analytics_conf() {
    local conf="$SCRIPT_DIR/deploy/analytics.conf"

    _GA4_SITES=()
    _GA4_IDS=()

    if [[ ! -f "$conf" ]]; then
        print_error "Missing: $conf"
        return 1
    fi

    local _idx=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        local _key _val
        _key="${line%%=*}"
        _val="${line#*=}"
        _key="$(echo "$_key" | tr -d '[:space:]')"
        _val="$(echo "$_val" | tr -d '"' | tr -d "'" | tr -d '[:space:]')"
        if [[ -n "$_key" && -n "$_val" ]]; then
            _GA4_SITES[$_idx]="$_key"
            _GA4_IDS[$_idx]="$_val"
            _idx=$(( _idx + 1 ))
        fi
    done < "$conf"

    if [[ ${#_GA4_SITES[@]} -eq 0 ]]; then
        print_warn "analytics.conf is empty (no site mappings found)."
        return 1
    fi
    return 0
}

# Inject (or refresh) GA4 into all top-level *.html in an arbitrary directory.
# Idempotent: (re)writes js/ga4.js, inserts the loader before </head> when
# absent, and corrects a stale measurement ID when present. Operates on
# whatever directory it is given — used against the *deployed* web root, never
# the git source tree, so the repo stays raw and never collides on pull.
_ga4_inject_dir() {
    local target_dir="$1"
    local ga4_id="$2"
    local js_dir="$target_dir/js"
    local ga4_js="$js_dir/ga4.js"

    if [[ ! "$ga4_id" =~ ^G-[A-Z0-9]+$ ]]; then
        print_error "Invalid GA4 ID format: $ga4_id (expected G-XXXXXXXXXX)"
        return 1
    fi
    if [[ ! -d "$target_dir" ]]; then
        print_error "Target directory not found: $target_dir"
        return 1
    fi

    mkdir -p "$js_dir"
    cat > "$ga4_js" << GA4_EOF
window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());
gtag('config', '$ga4_id');
GA4_EOF
    chmod 644 "$ga4_js"

    # Top-level pages plus one level of sub-pages (web/<site>/docs/*.html — the
    # generated manual). A sub-page loads the shared ga4.js via a relative
    # "../js/" so the same file serves both depths; nothing is duplicated.
    local html_file basename_f html_id js_rel
    for html_file in "$target_dir"/*.html "$target_dir"/*/*.html; do
        [[ -f "$html_file" ]] || continue
        basename_f="${html_file#"$target_dir"/}"
        js_rel="js/ga4.js"
        [[ "$basename_f" == */* ]] && js_rel="../js/ga4.js"

        # Detect our loader specifically — not the loose word "gtag", which can
        # legitimately appear in page copy and would fool the check.
        if grep -q "googletagmanager.com/gtag/js" "$html_file" 2>/dev/null; then
            # Already tagged — read the ID from the loader URL itself so a stale
            # ID is corrected regardless of what ga4.js currently holds.
            html_id=$(grep -oE 'id=G-[A-Z0-9]+' "$html_file" | grep -oE 'G-[A-Z0-9]+' | head -1 || true)
            if [[ -n "$html_id" && "$html_id" != "$ga4_id" ]]; then
                sed -i.bak "s|$html_id|$ga4_id|g" "$html_file"
                rm -f "${html_file}.bak"
                print_info "GA4: corrected ID in $basename_f ($html_id -> $ga4_id)"
            fi
            continue
        fi

        # Not yet tagged — require a </head> anchor so we never silently
        # "succeed" on a file that has none.
        if ! grep -q "</head>" "$html_file" 2>/dev/null; then
            print_warn "GA4: no </head> in $basename_f — tag NOT injected"
            continue
        fi
        sed -i.bak "s|</head>|  <!-- Google tag (gtag.js) -->\n  <script async src=\"https://www.googletagmanager.com/gtag/js?id=${ga4_id}\"></script>\n  <script src=\"${js_rel}\"></script>\n</head>|" "$html_file"
        rm -f "${html_file}.bak"
        print_info "GA4: injected into $basename_f"
    done
}

# Apply GA4 to a freshly-deployed web root, mapping analytics.conf entries onto
# the deployed layout. Called at the end of every local/git deploy so the
# published site always carries the correct tag while the git source stays raw.
#   $1 = deployed web root (WEB_DIR)
#   $2 = source path / site name that was deployed; if its basename matches an
#        analytics.conf key it is treated as a single-site deploy.
_ga4_apply_after_deploy() {
    local web_dir="$1"
    local src_dir="${2:-}"
    [[ -d "$web_dir" ]] || return 0

    if ! _load_analytics_conf; then
        print_warn "GA4: no analytics.conf mappings — skipping injection."
        return 0
    fi

    local src_base=""
    [[ -n "$src_dir" ]] && src_base="$(basename "$src_dir")"

    local i matched=false
    # Single-site deploy: the deployed web_dir IS one site's published root.
    if [[ -n "$src_base" ]]; then
        for (( i=0; i<${#_GA4_SITES[@]}; i++ )); do
            if [[ "${_GA4_SITES[$i]}" == "$src_base" ]]; then
                print_info "GA4: applying ${_GA4_IDS[$i]} to deployed site ($src_base)"
                _ga4_inject_dir "$web_dir" "${_GA4_IDS[$i]}" && matched=true
                break
            fi
        done
    fi
    $matched && return 0

    # Multi-site deploy: web_dir contains per-site subdirectories.
    for (( i=0; i<${#_GA4_SITES[@]}; i++ )); do
        if [[ -d "$web_dir/${_GA4_SITES[$i]}" ]]; then
            print_info "GA4: applying ${_GA4_IDS[$i]} to $web_dir/${_GA4_SITES[$i]}"
            _ga4_inject_dir "$web_dir/${_GA4_SITES[$i]}" "${_GA4_IDS[$i]}" && matched=true
        fi
    done

    $matched || print_warn "GA4: no analytics.conf site matched deploy target ($web_dir); nothing injected."
}

action_analytics_ga4() {
    print_section "Analytics (GA4)"

    print_info "Injects / refreshes the GA4 tag in the directory you submit."
    print_info "Directory-driven — works for ANY web server (nginx, apache,"
    print_info "caddy, a static host…), not just nginx vhosts. It edits the"
    print_info "published files in place, never the git source."
    echo ""

    # ── 1. Target directory — the folder that holds the .html files. ──────
    # The user submits the path directly; we never resolve it from the saved
    # nginx deploy state, so landing pages on a custom web server work too.
    local target_dir=""
    ask "  Web directory to tag (folder containing the .html files): " target_dir
    target_dir="${target_dir%/}"   # strip trailing slash
    if [[ -z "$target_dir" || ! -d "$target_dir" ]]; then
        print_error "Directory not found: ${target_dir:-<empty>}"
        return 1
    fi

    # ── 2. GA4 measurement ID. ────────────────────────────────────────────
    # Prefer a match from analytics.conf (by the folder's basename), but
    # always allow a manual ID so an arbitrary directory can be tagged.
    local ga4_id="" i
    if [[ -f "$SCRIPT_DIR/deploy/analytics.conf" ]] && _load_analytics_conf; then
        echo ""
        echo "  Known GA4 IDs from analytics.conf:"
        for (( i=0; i<${#_GA4_SITES[@]}; i++ )); do
            echo -e "    ${_GA4_SITES[$i]}  ->  ${_GA4_IDS[$i]}"
        done
        local base suggest=""
        base="$(basename "$target_dir")"
        for (( i=0; i<${#_GA4_SITES[@]}; i++ )); do
            if [[ "${_GA4_SITES[$i]}" == "$base" ]]; then
                suggest="${_GA4_IDS[$i]}"; break
            fi
        done
        echo ""
        if [[ -n "$suggest" ]]; then
            ask "  GA4 ID [Enter for $suggest]: " ga4_id
            ga4_id="${ga4_id:-$suggest}"
        else
            ask "  GA4 ID to inject (G-XXXXXXXXXX): " ga4_id
        fi
    else
        ask "  GA4 ID to inject (G-XXXXXXXXXX): " ga4_id
    fi

    if [[ ! "$ga4_id" =~ ^G-[A-Z0-9]+$ ]]; then
        print_error "Invalid GA4 ID: ${ga4_id:-<empty>} (expected G-XXXXXXXXXX)"
        return 1
    fi

    # ── 3. Inject / refresh the tag in the submitted directory. ───────────
    _ga4_inject_dir "$target_dir" "$ga4_id" || return 1

    # ── 4. Ownership — arbitrary user:group, NOT assumed www-data. ────────
    # Custom web servers often run as a different user; ask explicitly and
    # default to skipping so we never clobber permissions silently.
    echo ""
    local owner=""
    ask "  Set ownership on $target_dir (user:group, Enter to skip): " owner
    if [[ -n "$owner" ]]; then
        if chown -R "$owner" "$target_dir"; then
            print_info "Ownership set to $owner on $target_dir"
        else
            print_warn "Could not set ownership to $owner (does the user/group exist?)."
        fi
    fi

    echo ""
    print_info "GA4 refresh complete  →  $target_dir"
    echo ""
}

#############################################################################
# Argument Parsing
#############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action)      ACTION="$2";           shift 2 ;;
            --domain)      DOMAIN="$2"; DOMAIN_TO_REMOVE="$2"; shift 2 ;;
            --email)       EMAIL="$2";            shift 2 ;;
            --dir)         WEB_DIR="$2";          shift 2 ;;
            --deploy-mode) DEPLOY_MODE="$2";      shift 2 ;;
            --src)         LOCAL_SRC="$2";        shift 2 ;;
            --remote)      REMOTE_USER="$2";      shift 2 ;;
            --remote-path) REMOTE_PATH="$2";      shift 2 ;;
            --git-repo)    GIT_REPO="$2";         shift 2 ;;
            --git-branch)  GIT_BRANCH="$2";       shift 2 ;;
            --site)        SITE_NAME="$2";        shift 2 ;;
            --delete-files) DELETE_FILES="yes";   shift   ;;
            --all)          DEPLOY_ALL="yes";     shift   ;;
            --auto-confirm) AUTO_CONFIRM="yes";   shift   ;;
            -h|--help)     show_help; exit 0      ;;
            *) print_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done

    # Normalise hyphenated CLI form to the internal underscore form
    if [[ "$ACTION" == "deploy-installer" ]]; then
        ACTION="deploy_installer"
    elif [[ "$ACTION" == "analytics-ga4" ]]; then
        ACTION="analytics_ga4"
    fi
}

show_help() {
    cat << 'HELP_EOF'
Usage: sudo ./site_manager.sh [OPTIONS]

Static Site Deployment Manager — Part of Grin Landing Page

ACTIONS:
    --action add              Configure nginx + SSL for a domain
    --action remove           Remove nginx config and SSL cert
    --action deploy           Push / pull static files
    --action list             List all configured sites
    --action security         Security hardening and audit
    --action fail2ban_install Install fail2ban
    --action fail2ban_mgmt    Manage fail2ban
    --action ip_filter        Block / unblock IPs
    --action analytics_ga4    Inject/refresh GA4 in a directory you submit (any web server)
    --action deploy-installer Deploy Grin-Money Desktop install.ps1 to <domain>/install
                              (reads deploy/installer.conf)

DEPLOY-INSTALLER OPTIONS:
    --auto-confirm            Skip the y/N prompt and exit cleanly when nothing
                              has changed. Use from cron during development:
                              0 * * * * /path/to/site_manager.sh \
                                  --action deploy-installer --auto-confirm \
                                  >> /var/log/grin-installer-deploy.log 2>&1

ADD OPTIONS:
    --domain DOMAIN           Domain (e.g. grin.money)
    --email  EMAIL            Email for Let's Encrypt
    --dir    PATH             Web root directory

DEPLOY OPTIONS:
    --deploy-mode  local|rsync|git
    --src          PATH           Local source directory
    --remote       user@host      SSH target (rsync mode)
    --remote-path  PATH           Remote web dir (rsync mode)
    --git-repo     URL            Git repo URL (git mode)
    --git-branch   BRANCH         Git branch (default: main)
    --all                         Batch-deploy EVERY site in deploy/sites.conf in
                                  one pass, copying each web/<key>/ from THIS clone
                                  to its web dir (no re-clone — refresh content
                                  first with option 9 / git pull). Web dir per site
                                  is derived from its domain (<nginx_root>/<domain>/
                                  public) unless the manifest row gives an override.
                                  Non-interactive — ideal for cron:
                                  */30 * * * * /path/to/site_manager.sh \
                                      --action deploy --all \
                                      >> /var/log/grin-sites-deploy.log 2>&1

REMOVE OPTIONS:
    --domain DOMAIN           Domain to remove
    --delete-files            Also delete web files

ANALYTICS (GA4):
    GA4 is applied automatically by every deploy mode: the tag from
    deploy/analytics.conf is injected into the *published* files in the
    web dir, never into the git source — so the repo stays raw and pulls
    never collide on generated files. local/git/all tag the web dir after
    the copy; rsync has no local published dir, so it copies the source to
    a temp staging dir, tags that, and pushes it.

    The standalone analytics_ga4 action is directory-driven: you submit the
    target folder (works on ANY web server, not just nginx vhosts),
    pick/enter the GA4 ID, and optionally set an arbitrary user:group
    ownership on the tagged files.

EXAMPLES:
    # Interactive menu:
    sudo ./deploy/site_manager.sh

    # Add domain:
    sudo ./deploy/site_manager.sh --action add --domain grin.money --email admin@grin.money

    # Deploy via rsync:
    ./deploy/site_manager.sh --action deploy --deploy-mode rsync \
        --src ./web --remote ubuntu@1.2.3.4 --remote-path /var/www/grin.money/public

    # Deploy via git (run on server):
    sudo ./deploy/site_manager.sh --action deploy --deploy-mode git \
        --git-repo https://github.com/youruser/grin-landing-page \
        --dir /var/www/grin.money/public

    # Deploy ALL sites in deploy/sites.conf in one pass (run on server):
    sudo ./deploy/site_manager.sh --action deploy --all

    # List sites:
    sudo ./deploy/site_manager.sh --action list

    # GA4: re-apply the tag to the already-deployed web dir (no full redeploy):
    ./site_manager.sh --action analytics_ga4

HELP_EOF
}

#############################################################################
# 9. Self-Update
#############################################################################

action_self_update() {
    print_section "Update site_manager.sh from GitHub"

    if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
        print_error "No .git directory found at: $SCRIPT_DIR"
        print_info "Clone the repo first:"
        print_cmd "git clone https://github.com/noobvie/Grin-Landing-Pages.git"
        return 1
    fi

    # Detect the current branch (handles main/master/etc.)
    local branch
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        branch=$(git -C "$SCRIPT_DIR" ls-remote --symref origin HEAD 2>/dev/null \
            | awk '/^ref:/ {sub("refs/heads/",""); print $2; exit}')
    fi
    branch="${branch:-master}"
    print_info "Branch: $branch"

    # Check for local modifications — stash them so pull doesn't fail
    local stashed=false
    local dirty
    dirty=$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null)
    if [[ -n "$dirty" ]]; then
        print_warn "Local modifications detected:"
        echo "$dirty" | while IFS= read -r line; do echo "    $line"; done
        echo ""
        ask "  Stash local changes before pulling? (Y/n): " _st
        if [[ "${_st,,}" != "n" ]]; then
            git -C "$SCRIPT_DIR" stash push -m "site_manager auto-stash before self-update" || {
                print_error "git stash failed. Resolve local changes manually and retry."
                return 1
            }
            stashed=true
            print_info "Changes stashed."
        else
            print_warn "Proceeding without stash — pull may fail if files conflict."
        fi
    fi

    # Test connectivity before attempting pull
    print_info "Checking connectivity to GitHub..."
    if ! git -C "$SCRIPT_DIR" fetch origin "$branch" 2>&1; then
        print_error "Cannot reach GitHub. Check network connection or SSH/HTTPS credentials."
        if $stashed; then
            git -C "$SCRIPT_DIR" stash pop 2>/dev/null || true
            print_info "Stash restored."
        fi
        return 1
    fi

    # Merge fetched changes (fast-forward only — no surprise merges)
    print_info "Merging..."
    if git -C "$SCRIPT_DIR" merge --ff-only "origin/$branch" 2>&1; then
        if $stashed; then
            git -C "$SCRIPT_DIR" stash pop 2>/dev/null && print_info "Stash re-applied." || \
                print_warn "Stash pop had conflicts — check: git stash list"
        fi
        echo ""
        print_info "Update complete."
        echo -e "  ${YELLOW}Exiting now — re-run the script to use the latest version:${NC}"
        echo ""
        echo -e "    ${GREEN}sudo ./site_manager.sh${NC}"
        echo ""
        exit 0
    else
        print_error "Merge failed (branch may have diverged). Try manually:"
        print_cmd "git -C $SCRIPT_DIR reset --hard origin/$branch"
        if $stashed; then
            git -C "$SCRIPT_DIR" stash pop 2>/dev/null || true
        fi
        return 1
    fi
}

#############################################################################
# G. Deploy Grin-Money Desktop installer (install.ps1)
#
# Pulls install.ps1 from the Grin-Money-Desktop GitHub repo, verifies the
# signature line, atomically copies to the nginx-served path, and smoke
# tests the URL. Kept SEPARATE from action_deploy() so the installer's
# weekly cadence and the landing-page's yearly cadence never collide.
#
# Reads config from deploy/installer.conf.
#############################################################################

action_deploy_installer() {
    print_section "Deploy Grin-Money Desktop Installer"

    local conf="$SCRIPT_DIR/deploy/installer.conf"

    # ── 1. Load config ─────────────────────────────────────────────────────
    if [[ ! -f "$conf" ]]; then
        print_error "Missing: $conf"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$conf"

    # ── 2. Validate config ──────────────────────────────────────────────────
    local required=(INSTALLER_SOURCE_REPO INSTALLER_SOURCE_BRANCH \
                    INSTALLER_SOURCE_FILE INSTALLER_CACHE_DIR \
                    INSTALLER_TARGET_DIR INSTALLER_TARGET_FILE \
                    INSTALLER_SERVING_DOMAIN INSTALLER_OWNER \
                    INSTALLER_PERMS INSTALLER_SIGNATURE_LINE)
    local missing=()
    for v in "${required[@]}"; do
        [[ -z "${!v:-}" ]] && missing+=("$v")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "installer.conf missing keys: ${missing[*]}"
        return 1
    fi

    # ── 3. Show current state ───────────────────────────────────────────────
    local current_target="$INSTALLER_TARGET_DIR/$INSTALLER_TARGET_FILE"
    local current_ref_file="$INSTALLER_TARGET_DIR/.deployed_ref"
    print_info "Source: $INSTALLER_SOURCE_REPO ($INSTALLER_SOURCE_BRANCH)"
    print_info "Target: $current_target"
    print_info "URL:    https://$INSTALLER_SERVING_DOMAIN/install"
    if [[ -f "$current_ref_file" ]]; then
        local deployed_ref deployed_at
        deployed_ref=$(awk '/^ref:/  {print $2}' "$current_ref_file" 2>/dev/null)
        deployed_at=$(awk  '/^when:/ {print $2}' "$current_ref_file" 2>/dev/null)
        print_info "Currently deployed: ${deployed_ref:0:12} (at $deployed_at)"
    else
        print_info "No prior deployment recorded."
    fi
    echo ""

    # ── 4. Clone or fetch the source repo into cache ────────────────────────
    # Full clone (no --depth 1) — we want history available so step 4a can
    # show the operator (or the cron log) what's actually changing.
    if [[ ! -d "$INSTALLER_CACHE_DIR/.git" ]]; then
        print_info "Cloning source repo to $INSTALLER_CACHE_DIR …"
        mkdir -p "$(dirname "$INSTALLER_CACHE_DIR")"
        git clone --branch "$INSTALLER_SOURCE_BRANCH" \
            "$INSTALLER_SOURCE_REPO" "$INSTALLER_CACHE_DIR" || {
            print_error "git clone failed."
            return 1
        }
    else
        print_info "Fetching latest in $INSTALLER_CACHE_DIR …"
        git -C "$INSTALLER_CACHE_DIR" fetch origin "$INSTALLER_SOURCE_BRANCH" || {
            print_error "git fetch failed."
            return 1
        }
        git -C "$INSTALLER_CACHE_DIR" reset --hard "origin/$INSTALLER_SOURCE_BRANCH" || {
            print_error "git reset failed."
            return 1
        }
    fi

    local new_ref
    new_ref=$(git -C "$INSTALLER_CACHE_DIR" rev-parse HEAD)
    print_info "Source commit: ${new_ref:0:12}"

    # ── 4a. Compare against last deployed ref ───────────────────────────────
    local deployed_ref=""
    if [[ -f "$current_ref_file" ]]; then
        deployed_ref=$(awk '/^ref:/ {print $2}' "$current_ref_file" 2>/dev/null)
    fi

    if [[ -n "$deployed_ref" && "$deployed_ref" == "$new_ref" ]]; then
        print_info "Already up to date (deployed = upstream = ${new_ref:0:12})."
        if [[ "$AUTO_CONFIRM" == "yes" ]]; then
            return 0                                       # cron-quiet: nothing to do
        fi
        ask "  Redeploy anyway? (y/N): " _re
        if [[ "${_re,,}" != "y" ]]; then
            print_info "Nothing to deploy. Done."
            return 0
        fi
    elif [[ -n "$deployed_ref" ]] && \
         git -C "$INSTALLER_CACHE_DIR" cat-file -e "$deployed_ref^{commit}" 2>/dev/null; then
        # Upstream has new commits AND the deployed commit is reachable in our
        # cache — show the actual diff.
        local count
        count=$(git -C "$INSTALLER_CACHE_DIR" rev-list --count "${deployed_ref}..${new_ref}" 2>/dev/null || echo "?")
        echo ""
        print_info "Upstream is $count commit(s) ahead of currently deployed."
        echo ""
        echo "  Commits since last deploy:"
        git -C "$INSTALLER_CACHE_DIR" log --oneline --no-decorate \
            "${deployed_ref}..${new_ref}" 2>/dev/null | head -20 | sed 's/^/    /'
        echo ""
    elif [[ -n "$deployed_ref" ]]; then
        # Deployed ref isn't in our cache (force-pushed branch, perhaps).
        print_warn "Last deployed ref ${deployed_ref:0:12} not reachable from upstream."
        print_warn "Branch may have been force-pushed. Showing recent upstream history:"
        echo ""
        git -C "$INSTALLER_CACHE_DIR" log --oneline --no-decorate -n 10 \
            "$new_ref" 2>/dev/null | sed 's/^/    /'
        echo ""
    else
        # First deploy.
        print_info "First deploy — showing 10 most recent upstream commits for context:"
        echo ""
        git -C "$INSTALLER_CACHE_DIR" log --oneline --no-decorate -n 10 \
            "$new_ref" 2>/dev/null | sed 's/^/    /'
        echo ""
    fi

    # ── 5. Locate + verify install.ps1 ──────────────────────────────────────
    local src="$INSTALLER_CACHE_DIR/$INSTALLER_SOURCE_FILE"
    if [[ ! -f "$src" ]]; then
        print_error "Source file not found: $src"
        return 1
    fi

    local first_line
    first_line=$(head -n 1 "$src")
    if [[ "$first_line" != "$INSTALLER_SIGNATURE_LINE"* ]]; then
        print_error "Signature line mismatch."
        print_error "  Expected: $INSTALLER_SIGNATURE_LINE"
        print_error "  Got     : $first_line"
        print_error "Refusing to deploy — wrong file or corrupted repo?"
        return 1
    fi
    print_info "Signature line OK."

    # ── 6. Confirm before write ─────────────────────────────────────────────
    if [[ "$AUTO_CONFIRM" != "yes" ]]; then
        echo ""
        ask "  Deploy this commit to $current_target? (y/N): " _go
        if [[ "${_go,,}" != "y" ]]; then
            print_info "Aborted by user."
            return 0
        fi
    else
        print_info "--auto-confirm set — proceeding without prompt."
    fi

    # ── 7. Atomic copy ──────────────────────────────────────────────────────
    # chown/chmod failures are surfaced as warnings (not fatal). The smoke
    # test in §8 will catch any nginx-serving fallout downstream and tell
    # the operator what to fix.
    mkdir -p "$INSTALLER_TARGET_DIR"
    local tmp="$current_target.new"
    cp "$src" "$tmp"
    chown "$INSTALLER_OWNER" "$tmp" || \
        print_warn "chown $INSTALLER_OWNER on $tmp failed — user/group may not exist"
    chmod "$INSTALLER_PERMS" "$tmp" || \
        print_warn "chmod $INSTALLER_PERMS on $tmp failed — invalid mode?"
    mv -f "$tmp" "$current_target"
    print_info "Wrote $current_target"

    # Record the deployed ref for next time
    {
        echo "ref:  $new_ref"
        echo "when: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "by:   ${SUDO_USER:-$(whoami)}"
    } > "$current_ref_file"
    chown "$INSTALLER_OWNER" "$current_ref_file" || \
        print_warn "chown $INSTALLER_OWNER on $current_ref_file failed"

    # ── 8. Check that the nginx vhost serves it ─────────────────────────────
    echo ""
    print_info "Smoke testing https://$INSTALLER_SERVING_DOMAIN/install …"
    local probe
    probe=$(curl -fsS --max-time 10 "https://$INSTALLER_SERVING_DOMAIN/install" 2>/dev/null | head -n 1)
    if [[ "$probe" == "$INSTALLER_SIGNATURE_LINE"* ]]; then
        print_info "Smoke test OK — irm | iex one-liner is live."
        echo ""
        echo -e "    ${GREEN}irm https://$INSTALLER_SERVING_DOMAIN/install | iex${NC}"
        echo ""

        # In manual mode, suggest a cron line if one isn't already set up.
        # Skip the hint when --auto-confirm is in effect (we ARE the cron).
        if [[ "$AUTO_CONFIRM" != "yes" ]] && \
           ! crontab -l 2>/dev/null | grep -q 'site_manager.sh.*deploy-installer.*--auto-confirm'; then
            print_info "Tip — to auto-pull every hour during development, add to root's crontab:"
            echo -e "    ${DIM}# crontab -e${NC}"
            echo -e "    ${GREEN}0 * * * * $SCRIPT_DIR/site_manager.sh --action deploy-installer --auto-confirm >> /var/log/grin-installer-deploy.log 2>&1${NC}"
            echo ""
            print_info "Remove the line once you're back to gating every deploy manually."
            echo ""
        fi
    else
        print_warn "Smoke test failed — the file is on disk but the URL"
        print_warn "doesn't return it. Likely missing nginx location block."
        print_warn ""
        print_warn "Add this to your $INSTALLER_SERVING_DOMAIN vhost:"
        echo ""
        cat <<NGINX_EOF
    location = /install {
        default_type text/plain;
        alias $current_target;
        add_header Cache-Control "public, max-age=300";
        add_header X-Content-Type-Options "nosniff";
    }
    location = /install.ps1 {
        default_type text/plain;
        alias $current_target;
    }
NGINX_EOF
        echo ""
        print_warn "Then: sudo nginx -t && sudo systemctl reload nginx"
        print_warn "Then re-run this action (G) to re-test."
    fi
}

#############################################################################
# Action Dispatcher (shared by interactive loop and non-interactive path)
#############################################################################

_dispatch_action() {
    case "$ACTION" in
        add)              action_add_domain       ;;
        remove)           action_remove_domain    ;;
        deploy)           action_deploy           ;;
        list)             action_list_sites       ;;
        security)         action_security         ;;
        fail2ban_install) action_fail2ban_install ;;
        fail2ban_mgmt)    action_fail2ban_mgmt    ;;
        ip_filter)        action_ip_filter        ;;
        self_update)      action_self_update      ;;
        analytics_ga4)    action_analytics_ga4    ;;
        deploy_installer) action_deploy_installer ;;
        *)
            print_error "Unknown ACTION: $ACTION"
            show_help
            return 1
            ;;
    esac
}

#############################################################################
# Main
#############################################################################

main() {
    parse_arguments "$@"
    detect_os
    detect_nginx_paths

    # ── Non-interactive: --action was passed on the command line ──────────────
    if [[ -n "$ACTION" ]]; then
        # Root check: only skip for read-only / local-only actions
        case "$ACTION" in
            deploy|list|self_update|analytics_ga4) ;;
            *) check_root ;;
        esac
        [[ $EUID -eq 0 ]] && { init_log "$ACTION" 2>/dev/null || true; }
        _dispatch_action
        exit $?
    fi

    # ── Interactive menu loop ─────────────────────────────────────────────────
    # Log the whole session to a single file (init_log guards against re-init).
    [[ $EUID -eq 0 ]] && { init_log "session" 2>/dev/null || true; }

    while true; do
        # get_action shows the menu, sets ACTION, and calls exit 0 on "0".
        get_action

        # Run the chosen action; || true prevents set -e from killing the loop
        # when an action cancels (return 1) or encounters a non-fatal error.
        _dispatch_action || true

        echo ""
        ask "  Press Enter to return to the menu..." _pause

        # Reset per-action state so each menu pick starts clean. Anything left
        # populated here is silently reused by the next action (every input
        # helper only prompts when its var is empty), which is the classic
        # "it didn't ask me" bug. So we clear ALL per-action inputs and keep
        # only genuine cross-domain conveniences: EMAIL (same Let's Encrypt
        # address) and DEPLOY_OWNER (same ownership). Deploy inputs are
        # repopulated from the saved-state FILE via _load_deploy_state, so
        # clearing them here costs nothing and prevents cross-domain bleed.
        ACTION=""             # show menu on next get_action call
        DOMAIN=""             # add: always re-prompt for the new domain
        DOMAIN_TO_REMOVE=""   # remove: always re-prompt for domain
        DELETE_FILES=""       # remove: always re-prompt for file deletion
        SITE_NAME=""          # analytics/deploy: always re-prompt for site
        WEB_DIR=""            # add: re-derive from the new domain, not the old
        DEPLOY_MODE=""        # deploy: re-prompt / reload from saved state
        LOCAL_SRC=""          # deploy: re-prompt / reload from saved state
        REMOTE_USER=""        # deploy: re-prompt / reload from saved state
        REMOTE_PATH=""        # deploy: re-prompt / reload from saved state
        GIT_REPO=""           # deploy: re-prompt / reload from saved state
        GIT_BRANCH=""         # deploy: re-prompt / reload from saved state
        SPARSE_CHECKOUT=""    # deploy: re-prompt / reload from saved state
        DEPLOY_ALL=""         # deploy: batch flag is per-invocation only
    done
}

main "$@"
