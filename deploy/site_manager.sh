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
#   0) Exit
#
# PLATFORMS
#   Linux  : apt (Debian/Ubuntu) or yum (RHEL/CentOS) — production server use
#   macOS  : Homebrew — local development only (certbot limited, see notes)
#
# NON-INTERACTIVE MODE
#   Set ACTION at the top (or use --action flag) to skip the menu.
#   Valid ACTION values:
#     add | remove | deploy | list | security | fail2ban_install |
#     fail2ban_mgmt | ip_filter
#
# DEPLOY MODES
#   local  — Copy local web/ files directly to WEB_DIR (same machine)
#   rsync  — Push files from local to remote over SSH
#   git    — Pull/clone repo on the server
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

# Removal configuration
DOMAIN_TO_REMOVE=""          # Domain to remove
DELETE_FILES=""              # "yes" to also delete web files

#############################################################################
# System Variables — DO NOT EDIT
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/opt/grin-landing/logs"
LOG_FILE=""

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
        mkdir -p "$NGINX_AVAILABLE"
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
print_blue()    { echo -e "${BLUE}[INFO]${NC} $1"; }
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
    local action="$1"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/site_${action}_$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    print_info "Logging to: $LOG_FILE"
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
        read -r -p "Install certbot via Homebrew anyway? (y/N) " _c
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
    clear
    cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     site_manager.sh  —  Static Site Deployment Manager        ║
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
    echo "  0) Exit"
    echo ""
}

get_action() {
    [[ -n "$ACTION" ]] && return 0

    while true; do
        show_main_menu
        read -r -p "Enter choice [0-8]: " choice
        case "$choice" in
            1) ACTION="add"              ; break ;;
            2) ACTION="remove"           ; break ;;
            3) ACTION="deploy"           ; break ;;
            4) ACTION="list"             ; break ;;
            5) ACTION="security"         ; break ;;
            6) ACTION="fail2ban_install" ; break ;;
            7) ACTION="fail2ban_mgmt"    ; break ;;
            8) ACTION="ip_filter"        ; break ;;
            0) print_info "Exiting."; exit 0 ;;
            "") ;;
            *) print_error "Invalid choice. Please enter 0-8." ; sleep 1 ;;
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
            read -r -p "Enter domain (e.g. grin.money) or 0 to cancel: " DOMAIN
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
            read -r -p "Enter email for SSL notifications or 0 to cancel: " EMAIL
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
        read -r -p "Web directory [default: $default_dir]: " WEB_DIR
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
    local domain_id
    domain_id=$(domain_safe "$domain")

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
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain} www.${domain};

    root ${web_dir};
    index index.html;

    # SSL — managed by certbot
    ssl_certificate     /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    server_tokens off;
    add_header Strict-Transport-Security  "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options            "SAMEORIGIN"                                   always;
    add_header X-Content-Type-Options     "nosniff"                                      always;
    add_header X-XSS-Protection           "1; mode=block"                                always;
    add_header Referrer-Policy            "strict-origin-when-cross-origin"              always;
    add_header Permissions-Policy         "camera=(), microphone=(), geolocation=()"     always;
    add_header Content-Security-Policy    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https:; connect-src 'self';" always;

    # Rate limiting
    limit_req zone=landing_${domain_id} burst=30 nodelay;

    # Static site routing
    location / {
        try_files \$uri \$uri/ /index.html =404;
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
        read -r -p "Overwrite? (y/N): " _ow
        [[ "${_ow,,}" != "y" ]] && return 1
    fi

    ensure_nginx
    ensure_certbot || true   # Non-fatal on macOS

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
            --email "$EMAIL" \
            --domains "$DOMAIN,www.$DOMAIN" 2>&1 || {
            print_warn "certbot failed. Generating self-signed cert for testing..."
            mkdir -p "/etc/ssl/$DOMAIN"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "/etc/ssl/$DOMAIN/privkey.pem" \
                -out    "/etc/ssl/$DOMAIN/fullchain.pem" \
                -subj   "/CN=$DOMAIN" 2>/dev/null
            print_warn "Self-signed cert generated. Replace with Let's Encrypt for production."
        }
    fi

    # Write final nginx config
    print_section "Writing nginx Configuration"
    generate_nginx_config "$DOMAIN" "$WEB_DIR" > "$conf_file"

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
        read -r -p "Enter domain to remove or 0 to cancel: " DOMAIN_TO_REMOVE
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
        read -r -p "Also delete web files ($web_dir)? (y/N): " _df
        DELETE_FILES="${_df,,}"
    fi

    # Remove nginx config
    rm -f "$conf_file"
    rm -f "$NGINX_ENABLED/$DOMAIN_TO_REMOVE" 2>/dev/null || true
    print_info "Removed nginx config: $conf_file"

    # Revoke and delete SSL cert
    if command -v certbot &>/dev/null && \
       [[ -d "/etc/letsencrypt/live/$DOMAIN_TO_REMOVE" ]]; then
        read -r -p "Revoke and delete SSL cert for $DOMAIN_TO_REMOVE? (y/N): " _rc
        if [[ "${_rc,,}" == "y" ]]; then
            certbot revoke --cert-name "$DOMAIN_TO_REMOVE" --non-interactive 2>/dev/null || true
            certbot delete --cert-name "$DOMAIN_TO_REMOVE" --non-interactive 2>/dev/null || true
            print_info "SSL cert removed."
        fi
    fi

    # Delete web files
    if [[ "${DELETE_FILES,,}" == "y" ]] && [[ -n "$web_dir" ]] && [[ -d "$web_dir" ]]; then
        read -r -p "CONFIRM: Permanently delete $web_dir and all its contents? (yes/N): " _confirm
        if [[ "$_confirm" == "yes" ]]; then
            rm -rf "$web_dir"
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

    echo ""
    echo "Deploy modes:"
    echo "  1) local  — Copy files on this machine to a local nginx web dir"
    echo "  2) rsync  — Push files from this machine to a remote server via SSH"
    echo "  3) git    — Run git pull on the server (must be run on the server)"
    echo ""

    if [[ -z "$DEPLOY_MODE" ]]; then
        read -r -p "Choose deploy mode [1-3] or 0 to cancel: " _dm
        case "$_dm" in
            1) DEPLOY_MODE="local"  ;;
            2) DEPLOY_MODE="rsync"  ;;
            3) DEPLOY_MODE="git"    ;;
            0) return 0 ;;
            *) print_error "Invalid choice."; return 1 ;;
        esac
    fi

    case "$DEPLOY_MODE" in
        local)  _deploy_local  ;;
        rsync)  _deploy_rsync  ;;
        git)    _deploy_git    ;;
        *) print_error "Unknown DEPLOY_MODE: $DEPLOY_MODE"; return 1 ;;
    esac
}

_deploy_local() {
    # Default source: sibling web/ directory relative to this script
    if [[ -z "$LOCAL_SRC" ]]; then
        local default_src
        default_src="$(dirname "$SCRIPT_DIR")/web"
        read -r -p "Source directory [default: $default_src]: " LOCAL_SRC
        LOCAL_SRC="${LOCAL_SRC:-$default_src}"
    fi

    if [[ ! -d "$LOCAL_SRC" ]]; then
        print_error "Source directory not found: $LOCAL_SRC"
        return 1
    fi

    get_web_dir

    print_info "Copying $LOCAL_SRC → $WEB_DIR"
    mkdir -p "$WEB_DIR"
    rsync -av --delete "$LOCAL_SRC/" "$WEB_DIR/"
    print_info "Deploy complete."
}

_deploy_rsync() {
    # Default source: sibling web/ directory
    if [[ -z "$LOCAL_SRC" ]]; then
        local default_src
        default_src="$(dirname "$SCRIPT_DIR")/web"
        read -r -p "Source directory [default: $default_src]: " LOCAL_SRC
        LOCAL_SRC="${LOCAL_SRC:-$default_src}"
    fi

    if [[ ! -d "$LOCAL_SRC" ]]; then
        print_error "Source directory not found: $LOCAL_SRC"
        return 1
    fi

    if [[ -z "$REMOTE_USER" ]]; then
        read -r -p "Remote SSH target (e.g. ubuntu@1.2.3.4): " REMOTE_USER
    fi

    if [[ -z "$REMOTE_PATH" ]]; then
        read -r -p "Remote web directory (e.g. /var/www/grin.money/public): " REMOTE_PATH
    fi

    print_info "Pushing $LOCAL_SRC → $REMOTE_USER:$REMOTE_PATH"
    print_cmd "rsync -avz --delete $LOCAL_SRC/ $REMOTE_USER:$REMOTE_PATH/"
    rsync -avz --delete "$LOCAL_SRC/" "$REMOTE_USER:$REMOTE_PATH/"
    print_info "rsync deploy complete."
}

_deploy_git() {
    # ── Load custom_repo.conf if it exists ────────────────────────────────────
    local conf_file
    conf_file="$SCRIPT_DIR/custom_repo.conf"
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
        read -r -p "Git repo URL: " GIT_REPO
    fi

    # Branch selection — always offer a chance to override for testing
    echo ""
    echo -e "  Current branch: ${GREEN}${GIT_BRANCH:-main}${NC}"
    read -r -p "  Deploy branch [press Enter to keep, or type another branch/tag]: " _branch_override
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
            read -r -p "Target web directory on this server: " WEB_DIR
        fi
    fi
    print_info "Target: $WEB_DIR  branch: $GIT_BRANCH"

    # ── Clone or pull ──────────────────────────────────────────────────────────
    local tmp_clone=""

    if $use_subdir; then
        # Clone to a temp dir, then rsync just the site subdir into WEB_DIR
        tmp_clone="$(mktemp -d)"
        print_info "Cloning $GIT_REPO ($GIT_BRANCH) into temp dir..."

        if [[ "${SPARSE_CHECKOUT:-no}" == "yes" ]]; then
            # Sparse clone — only fetch web/<SITE_NAME>/
            git clone --filter=blob:none --no-checkout --depth 1 \
                --branch "$GIT_BRANCH" "$GIT_REPO" "$tmp_clone"
            git -C "$tmp_clone" sparse-checkout init --cone
            git -C "$tmp_clone" sparse-checkout set "web/$SITE_NAME"
            git -C "$tmp_clone" checkout
        else
            git clone --depth 1 --branch "$GIT_BRANCH" "$GIT_REPO" "$tmp_clone"
        fi

        local site_src="$tmp_clone/web/$SITE_NAME"
        if [[ ! -d "$site_src" ]]; then
            print_error "Site directory not found in repo: web/$SITE_NAME"
            rm -rf "$tmp_clone"
            return 1
        fi

        mkdir -p "$WEB_DIR"
        print_info "Syncing web/$SITE_NAME → $WEB_DIR"
        rsync -av --delete "$site_src/" "$WEB_DIR/"
        rm -rf "$tmp_clone"

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

    print_info "Git deploy complete  →  $WEB_DIR  [branch: $GIT_BRANCH]"
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
    read -r -p "Choose [0-3]: " _sc

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
    read -r -p "Add this cron job now? (y/N): " _cron
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
    read -r -p "Choose [0-3]: " _f2b

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
            read -r -p "Enter IP to unban: " _ip
            read -r -p "Enter jail name [nginx-req-limit]: " _jail
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
    read -r -p "Choose [0-3]: " _ipf

    case "$_ipf" in
        1)
            read -r -p "Enter IP to block: " _ip
            validate_ip "$_ip" || { print_error "Invalid IP: $_ip"; return 1; }
            _firewall_block "$_ip"
            grep -qxF "$_ip" "$BLOCKED_LIST" || echo "$_ip" >> "$BLOCKED_LIST"
            print_info "Blocked: $_ip"
            ;;
        2)
            read -r -p "Enter IP to unblock: " _ip
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
            --delete-files) DELETE_FILES="yes";   shift   ;;
            -h|--help)     show_help; exit 0      ;;
            *) print_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
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

REMOVE OPTIONS:
    --domain DOMAIN           Domain to remove
    --delete-files            Also delete web files

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

    # List sites:
    sudo ./deploy/site_manager.sh --action list

HELP_EOF
}

#############################################################################
# Main
#############################################################################

main() {
    parse_arguments "$@"
    detect_os
    detect_nginx_paths

    # Deploy and list don't require root (rsync runs as current user)
    if [[ "$ACTION" != "deploy" && "$ACTION" != "list" && "$ACTION" != "" ]]; then
        check_root
    fi

    get_action

    # Initialize log (requires LOG_DIR to be writable — skip if not root)
    if [[ $EUID -eq 0 ]]; then
        init_log "$ACTION" 2>/dev/null || true
    fi

    case "$ACTION" in
        add)              action_add_domain      ;;
        remove)           action_remove_domain   ;;
        deploy)           action_deploy          ;;
        list)             action_list_sites      ;;
        security)         action_security        ;;
        fail2ban_install) action_fail2ban_install ;;
        fail2ban_mgmt)    action_fail2ban_mgmt   ;;
        ip_filter)        action_ip_filter       ;;
        *)
            print_error "Unknown ACTION: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
