#!/bin/bash
# Coolify for a Linux server: install the dashboard, or prepare a server the
# dashboard manages. Optional: ghcr.io login and a Cloudflare origin cert.
# Tested on: Ubuntu 22.04, 24.04, Debian 12, 13

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../shared/lib/setup-lib.sh
. "$SCRIPT_DIR/../../shared/lib/setup-lib.sh"

COOLIFY_USER="coolify"
COOLIFY_DATA="/data/coolify"
PROXY_DIR="$COOLIFY_DATA/proxy"
POLICY_GUIDE="docs/tailscale-tailnet.md"

module_help() {
    cat <<EOF
Usage: sudo $0 [-y] [--phase plan|deps|auto|interactive|summary]

Answers can be given up front as environment variables:
  MACHINE_ROLE        dashboard | managed
  COOLIFY_REINSTALL   yes | no    rerun Coolify's installer on a dashboard that has it
  COOLIFY_GHCR        yes | no    log Docker in to ghcr.io
  GHCR_USER           GitHub username for ghcr.io
  GHCR_TOKEN          GitHub token with read:packages (asked for if unset)
  COOLIFY_CF_CERT     yes | no    install a Cloudflare origin certificate
  CF_DOMAIN           domain the certificate covers, e.g. example.com
  CF_TRAEFIK_CONFIG   yes | no    write the Traefik config that loads it
  CF_CERT_FILE        path to the certificate (pasted if unset)
  CF_KEY_FILE         path to the private key (pasted if unset)
EOF
}

coolify_installed() { [ -d "$COOLIFY_DATA/source" ] || [ -d "$COOLIFY_DATA" ]; }

# Tailscale name Coolify should use to reach this machine, best available.
tailnet_name() {
    local name=""
    if have tailscale && have jq; then
        name="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
        [ -z "$name" ] && name="$(tailscale ip -4 2>/dev/null | head -1)"
    fi
    echo "${name:-$(hostname)}"
}

read_secret() {
    printf '%s: ' "$1" > /dev/tty
    IFS= read -rs REPLY < /dev/tty
    echo > /dev/tty
}

module_plan() {
    require_root
    [ -n "${MACHINE_ROLE:-}" ] || ask_server_role
    case "$MACHINE_ROLE" in
        dashboard|managed) ;;
        *) die "Coolify setup is for servers (role: dashboard or managed), not $MACHINE_ROLE" ;;
    esac

    if [ "$MACHINE_ROLE" = dashboard ] && coolify_installed; then
        ask_yn COOLIFY_REINSTALL "Coolify is already installed. Run its installer again (it upgrades)?" n
    fi

    ask_yn COOLIFY_GHCR "Log Docker in to GitHub Container Registry (ghcr.io) for private images?" n
    if [ "$COOLIFY_GHCR" = yes ]; then
        ask GHCR_USER "GitHub username" ""
    fi

    ask_yn COOLIFY_CF_CERT "Install a Cloudflare origin certificate for HTTPS?" n
    if [ "$COOLIFY_CF_CERT" = yes ]; then
        ask CF_DOMAIN "Domain the certificate covers (e.g. example.com)" ""
        [ -n "$CF_DOMAIN" ] || die "a domain is needed for the Cloudflare certificate"
        ask_yn CF_TRAEFIK_CONFIG "Write the Traefik config that loads the certificate?" y
    fi
}

install_docker() {
    if have docker; then
        log_ok "Docker already installed ($(docker --version))"
    else
        local installer
        installer="$(mktemp)"
        # Downloaded first so a dropped connection can't run half a script.
        curl -fsSL https://get.docker.com -o "$installer"
        sh "$installer"
        rm -f "$installer"
        log_ok "Docker installed"
    fi
    systemctl enable --now docker >/dev/null 2>&1 || true
}

module_deps() {
    log_step "Coolify: packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl wget git jq openssl ca-certificates >/dev/null
    log_ok "curl, wget, git, jq, openssl"

    # The dashboard's own installer brings Docker, pinned to versions it supports.
    if [ "$MACHINE_ROLE" = managed ]; then
        install_docker
    fi
}

setup_coolify_user() {
    if id "$COOLIFY_USER" >/dev/null 2>&1; then
        log_ok "User $COOLIFY_USER exists"
    else
        useradd -m -s /bin/bash "$COOLIFY_USER"
        log_ok "User $COOLIFY_USER created"
    fi
    getent group docker >/dev/null || groupadd docker
    usermod -aG docker,sudo "$COOLIFY_USER"

    # Coolify runs docker and apt through sudo and can't answer a password prompt.
    local sudoers="/etc/sudoers.d/$COOLIFY_USER" tmp
    tmp="$(mktemp)"
    echo "$COOLIFY_USER ALL=(ALL) NOPASSWD:ALL" > "$tmp"
    if visudo -cf "$tmp" >/dev/null; then
        install -m 440 "$tmp" "$sudoers"
        log_ok "$COOLIFY_USER: docker and sudo groups, passwordless sudo"
    else
        log_error "sudoers entry for $COOLIFY_USER failed validation; not installed"
    fi
    rm -f "$tmp"
}

install_coolify() {
    if coolify_installed && [ "${COOLIFY_REINSTALL:-no}" != yes ]; then
        log_ok "Coolify already installed"
        return 0
    fi
    local installer
    installer="$(mktemp)"
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh -o "$installer"
    bash "$installer"
    rm -f "$installer"
    log_ok "Coolify installed"
}

module_auto() {
    log_step "Coolify: $MACHINE_ROLE"
    if [ "$MACHINE_ROLE" = managed ]; then
        setup_coolify_user
        if [ "${COOLIFY_CF_CERT:-no}" = yes ]; then
            mkdir -p "$PROXY_DIR/certs" "$PROXY_DIR/dynamic"
        fi
    else
        install_coolify
    fi
}

setup_ghcr() {
    log_step "Coolify: GitHub Container Registry"
    if [ -z "${GHCR_TOKEN:-}" ]; then
        if [ ! -r /dev/tty ]; then
            log_warn "No terminal to ask for the GitHub token; skipped"
            note "- ghcr.io login skipped. Re-run with GHCR_TOKEN set, or from a terminal."
            return 0
        fi
        echo "Create a token at GitHub → Settings → Developer settings → Personal access tokens (classic), scope read:packages."
        [ -n "${GHCR_USER:-}" ] || { printf 'GitHub username: ' > /dev/tty; IFS= read -r GHCR_USER < /dev/tty; }
        read_secret "GitHub token for $GHCR_USER (hidden)"
        GHCR_TOKEN="$REPLY"
    fi
    if [ -z "${GHCR_USER:-}" ] || [ -z "$GHCR_TOKEN" ]; then
        log_warn "GitHub username or token empty; ghcr.io login skipped"
        return 0
    fi

    if ! echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin; then
        log_error "ghcr.io login failed; check the username and token"
        note "- ghcr.io login failed. Re-run this script to try again."
        return 0
    fi
    log_ok "Logged in to ghcr.io"

    # Coolify pulls as root on the dashboard but as coolify on a managed server.
    if id "$COOLIFY_USER" >/dev/null 2>&1 && [ -f /root/.docker/config.json ]; then
        local home
        home="$(getent passwd "$COOLIFY_USER" | cut -d: -f6)"
        mkdir -p "$home/.docker"
        cp /root/.docker/config.json "$home/.docker/config.json"
        chown -R "$COOLIFY_USER:$COOLIFY_USER" "$home/.docker"
        chmod 600 "$home/.docker/config.json"
        log_ok "ghcr.io credentials copied to $COOLIFY_USER"
    fi
}

# read_pem LABEL SOURCE_FILE DEST: copy SOURCE_FILE if given, else take a paste.
read_pem() {
    local label="$1" src="$2" dest="$3"
    if [ -n "$src" ]; then
        cp "$src" "$dest"
        return 0
    fi
    [ -r /dev/tty ] || return 1
    echo "Paste the $label (including the BEGIN/END lines), then press Ctrl+D:" > /dev/tty
    cat < /dev/tty > "$dest"
    [ -s "$dest" ]
}

setup_cloudflare_cert() {
    log_step "Coolify: Cloudflare origin certificate"
    if [ ! -d "$PROXY_DIR" ]; then
        log_error "$PROXY_DIR not found; Coolify's proxy isn't set up"
        note "- Cloudflare certificate skipped: $PROXY_DIR is missing. Install Coolify first, then re-run."
        return 0
    fi
    local certs="$PROXY_DIR/certs"
    local cert="$certs/$CF_DOMAIN.cert" key="$certs/$CF_DOMAIN.key"
    mkdir -p "$certs"

    if [ -z "${CF_CERT_FILE:-}" ]; then
        echo "Create the certificate first: Cloudflare → $CF_DOMAIN → SSL/TLS → Origin Server → Create Certificate"
        echo "  RSA (2048), hostnames *.$CF_DOMAIN and $CF_DOMAIN, validity 15 years. Keep the page open."
    fi
    if ! read_pem "Origin Certificate" "${CF_CERT_FILE:-}" "$cert" ||
       ! read_pem "Private Key" "${CF_KEY_FILE:-}" "$key"; then
        log_error "Certificate or key missing; nothing installed"
        rm -f "$cert" "$key"
        note "- Cloudflare certificate not installed. Re-run with CF_CERT_FILE and CF_KEY_FILE, or from a terminal."
        return 0
    fi
    chmod 644 "$cert"
    chmod 600 "$key"

    if ! openssl x509 -in "$cert" -noout 2>/dev/null; then
        log_error "$cert is not a valid certificate"
        return 0
    fi
    if ! openssl pkey -in "$key" -noout 2>/dev/null; then
        log_error "$key is not a valid private key"
        return 0
    fi
    log_ok "Certificate and key saved in $certs"
    openssl x509 -in "$cert" -noout -subject -enddate | sed 's/^/    /'

    # /traefik/certs is where Coolify's proxy container mounts $PROXY_DIR/certs.
    local traefik_yaml="tls:
  certificates:
    - certFile: /traefik/certs/$CF_DOMAIN.cert
      keyFile: /traefik/certs/$CF_DOMAIN.key"
    if [ "${CF_TRAEFIK_CONFIG:-yes}" = yes ]; then
        mkdir -p "$PROXY_DIR/dynamic"
        echo "$traefik_yaml" > "$PROXY_DIR/dynamic/cloudflare-origin-cert.yaml"
        log_ok "Traefik config written to $PROXY_DIR/dynamic/cloudflare-origin-cert.yaml"
    else
        note "- Add this in Coolify → Servers → this server → Proxy → Dynamic Configuration:"
        note "$(echo "$traefik_yaml" | sed 's/^/    /')"
    fi
    note "- Cloudflare: SSL/TLS → Overview → Full (strict); Edge Certificates → Always Use HTTPS."
    note "- Restart the proxy (Coolify → Servers → this server → Proxy → Restart), then redeploy apps."
}

module_interactive() {
    [ "${COOLIFY_GHCR:-no}" = yes ] && setup_ghcr
    [ "${COOLIFY_CF_CERT:-no}" = yes ] && setup_cloudflare_cert
    return 0
}

verify_managed() {
    local ok=1
    if id "$COOLIFY_USER" >/dev/null 2>&1; then
        id -nG "$COOLIFY_USER" | grep -qw docker || { log_warn "$COOLIFY_USER is not in the docker group"; ok=0; }
        sudo -n -u "$COOLIFY_USER" sudo -n true 2>/dev/null || { log_warn "$COOLIFY_USER has no passwordless sudo"; ok=0; }
    else
        log_warn "User $COOLIFY_USER is missing"; ok=0
    fi
    if ! systemctl is-active --quiet docker; then
        log_warn "Docker is not running"; ok=0
    fi
    [ "$ok" = 1 ] && log_ok "Ready for Coolify: user $COOLIFY_USER, passwordless sudo, Docker running"
    return 0
}

module_summary() {
    local name
    name="$(tailnet_name)"
    if [ "$MACHINE_ROLE" = managed ]; then
        log_step "Coolify: check"
        verify_managed
        note "- In Coolify: Servers → Add Server. IP/domain: $name, user: $COOLIFY_USER, port: 22. Then Validate Server."
        note "- Coolify still makes you pick a private key there. Any key works; Tailscale SSH ignores it."
        note "- The dashboard gets in through the tag:coolify → tag:vps rule for user $COOLIFY_USER. See $POLICY_GUIDE."
    else
        note "- Open the dashboard over your tailnet: http://$name:8000, and create the admin account right away."
        note "- Tag this machine tag:vps and tag:coolify, but only once the policy has the tag:coolify rule, or Coolify loses its servers. See $POLICY_GUIDE."
    fi
}

module_main "$@"
