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
Usage: sudo $0 [-y] [--status] [--phase plan|deps|auto|interactive|summary]

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

PACKAGES="curl wget git jq openssl ca-certificates"
SUDOERS_LINE="$COOLIFY_USER ALL=(ALL) NOPASSWD:ALL"

# Not $COOLIFY_DATA: the installer creates it before anything can fail, and a
# dashboard creates it on every server it manages. The container only exists
# once the install got through.
coolify_installed() { have docker && docker container inspect coolify >/dev/null 2>&1; }

user_in_groups() {
    local groups
    groups=" $(id -nG "$COOLIFY_USER" 2>/dev/null) "
    case "$groups" in *" docker "*) ;; *) return 1 ;; esac
    case "$groups" in *" sudo "*) ;; *) return 1 ;; esac
}

sudoers_done() {
    local f="/etc/sudoers.d/$COOLIFY_USER"
    [ "$(cat "$f" 2>/dev/null)" = "$SUDOERS_LINE" ] && [ "$(stat -c %a "$f")" = 440 ]
}

ghcr_logged_in() { grep -q '"ghcr.io"' /root/.docker/config.json 2>/dev/null; }

coolify_home() { getent passwd "$COOLIFY_USER" | cut -d: -f6; }

ghcr_copied() { cmp -s /root/.docker/config.json "$(coolify_home)/.docker/config.json"; }

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

# The role for --status, which asks nothing: MACHINE_ROLE if given, else what
# the machine shows. Prints nothing when it can't tell.
detected_role() {
    if [ -n "${MACHINE_ROLE:-}" ]; then echo "$MACHINE_ROLE"
    elif coolify_installed; then echo dashboard
    elif id "$COOLIFY_USER" >/dev/null 2>&1; then echo managed
    fi
}

# Root can always ask Docker; a normal user only from the docker group.
docker_readable() { is_root || docker info >/dev/null 2>&1; }

module_status() {
    local role missing prefix="" want tags certs
    role="$(detected_role)"
    case "$role" in
        dashboard|managed|"") ;;
        *) status_row coolify skipped "not a server (role: $role)"; return 0 ;;
    esac

    # shellcheck disable=SC2086
    missing="$(missing_pkgs $PACKAGES)"
    if [ -z "$missing" ]; then status_row coolify-packages present "curl, wget, git, jq, openssl"
    else status_row coolify-packages missing "will apt install $missing"; fi

    if have docker; then
        if service_up docker; then status_row docker present "$(docker --version 2>/dev/null), running"
        elif [ "$role" = managed ]; then status_row docker partial "installed, not running; will enable and start it"
        else status_row docker partial "installed, not running"; fi
    else
        case "$role" in
            dashboard) status_row docker missing "comes with Coolify's installer" ;;
            managed)   status_row docker missing "will install from get.docker.com" ;;
            *)         status_row docker missing "dashboard: comes with Coolify's installer; managed: from get.docker.com" ;;
        esac
    fi

    [ -z "$role" ] && prefix="dashboard: "
    if [ "$role" != managed ]; then
        if coolify_installed; then status_row coolify present "coolify container exists"
        elif have docker && ! docker_readable; then status_row coolify unknown "${prefix}needs sudo to check"
        else status_row coolify missing "${prefix}will run Coolify's installer"; fi
    fi

    [ -z "$role" ] && prefix="managed: "
    if [ "$role" != dashboard ]; then
        if ! id "$COOLIFY_USER" >/dev/null 2>&1; then
            status_row coolify-user missing "${prefix}will create $COOLIFY_USER in the docker and sudo groups"
        elif user_in_groups; then status_row coolify-user present "in the docker and sudo groups"
        else status_row coolify-user partial "exists; will add it to the docker and sudo groups"; fi
        if sudoers_done; then status_row coolify-sudo present "passwordless, /etc/sudoers.d/$COOLIFY_USER"
        elif ! is_root; then status_row coolify-sudo unknown "${prefix}needs sudo to check"
        else status_row coolify-sudo missing "${prefix}will add /etc/sudoers.d/$COOLIFY_USER"; fi
    fi

    if ! is_root; then
        status_row ghcr-login unknown "needs sudo to check"
    elif ! ghcr_logged_in; then
        status_row ghcr-login skipped "not logged in; optional, asked during setup"
    elif id "$COOLIFY_USER" >/dev/null 2>&1 && ! ghcr_copied; then
        status_row ghcr-login partial "root logged in; credentials not copied to $COOLIFY_USER"
    else
        status_row ghcr-login present "Docker logged in to ghcr.io"
    fi

    if [ ! -d "$COOLIFY_DATA" ]; then
        status_row cf-cert skipped "none; optional, asked during setup"
    elif ! is_root; then
        status_row cf-cert unknown "needs sudo to check"
    else
        certs="$(cd "$PROXY_DIR/certs" 2>/dev/null && ls -- *.cert 2>/dev/null | tr '\n' ' ')"
        if [ -n "$certs" ]; then status_row cf-cert present "${certs% } in $PROXY_DIR/certs"
        else status_row cf-cert skipped "none; optional, asked during setup"; fi
    fi

    # The summary's tag reminder, as a row.
    case "$role" in
        dashboard) want="tag:coolify,tag:vps" ;;
        managed)   want="tag:vps" ;;
        *)         want="" ;;
    esac
    if [ -z "$want" ]; then
        status_row tailnet-tags unknown "role unknown; set MACHINE_ROLE to check"
    elif ! have tailscale || [ "$(ts_state)" != Running ]; then
        status_row tailnet-tags skipped "Tailscale not connected"
    elif ! have jq; then
        status_row tailnet-tags unknown "jq needed to read the tags; the setup installs it"
    else
        tags="$(tailscale status --json 2>/dev/null | jq -r '(.Self.Tags // []) | sort | join(",")' 2>/dev/null || true)"
        if [ "$tags" = "$want" ]; then status_row tailnet-tags present "$tags"
        else status_row tailnet-tags missing "a $role needs $want (now: ${tags:-none}); see $POLICY_GUIDE"; fi
    fi
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
    if service_up docker; then
        log_ok "Docker already enabled and running"
    else
        systemctl enable --now docker >/dev/null 2>&1 || true
    fi
}

module_deps() {
    log_step "Coolify: packages"
    local missing
    # shellcheck disable=SC2086
    missing="$(missing_pkgs $PACKAGES)"
    if [ -z "$missing" ]; then
        log_ok "curl, wget, git, jq, openssl already installed"
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        # shellcheck disable=SC2086
        apt-get install -y -qq $missing >/dev/null
        log_ok "Installed $missing"
    fi

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
    if user_in_groups; then
        log_ok "$COOLIFY_USER already in the docker and sudo groups"
    else
        getent group docker >/dev/null || groupadd docker
        usermod -aG docker,sudo "$COOLIFY_USER"
        log_ok "$COOLIFY_USER added to the docker and sudo groups"
    fi

    # Coolify runs docker and apt through sudo and can't answer a password prompt.
    if sudoers_done; then
        log_ok "$COOLIFY_USER already has passwordless sudo"
        return 0
    fi
    local sudoers="/etc/sudoers.d/$COOLIFY_USER" tmp
    tmp="$(mktemp)"
    echo "$SUDOERS_LINE" > "$tmp"
    if visudo -cf "$tmp" >/dev/null; then
        install -m 440 "$tmp" "$sudoers"
        log_ok "$COOLIFY_USER: passwordless sudo"
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
    if [ -z "${GHCR_TOKEN:-}" ] && ghcr_logged_in; then
        log_ok "Docker already logged in to ghcr.io (set GHCR_TOKEN to log in again)"
        copy_ghcr_creds
        return 0
    fi
    if [ -z "${GHCR_TOKEN:-}" ]; then
        if ! _have_tty; then
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
    copy_ghcr_creds
}

# Coolify pulls as root on the dashboard but as coolify on a managed server.
copy_ghcr_creds() {
    if id "$COOLIFY_USER" >/dev/null 2>&1 && [ -f /root/.docker/config.json ]; then
        if ghcr_copied; then
            log_ok "ghcr.io credentials already copied to $COOLIFY_USER"
            return 0
        fi
        local home
        home="$(coolify_home)"
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
    _have_tty || return 1
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

    if cf_cert_installed "$cert" "$key" &&
       { [ -z "${CF_CERT_FILE:-}" ] || cmp -s "$CF_CERT_FILE" "$cert"; } &&
       { [ -z "${CF_KEY_FILE:-}" ] || cmp -s "$CF_KEY_FILE" "$key"; }; then
        log_ok "Certificate and key for $CF_DOMAIN already in $certs (delete them to replace)"
    else
        install_cf_cert "$cert" "$key" || return 0
    fi
    write_traefik_config
}

cf_cert_installed() {
    openssl x509 -in "$1" -noout 2>/dev/null && openssl pkey -in "$2" -noout 2>/dev/null
}

install_cf_cert() {
    local cert="$1" key="$2" certs="$PROXY_DIR/certs"
    if [ -z "${CF_CERT_FILE:-}" ]; then
        echo "Create the certificate first: Cloudflare → $CF_DOMAIN → SSL/TLS → Origin Server → Create Certificate"
        echo "  RSA (2048), hostnames *.$CF_DOMAIN and $CF_DOMAIN, validity 15 years. Keep the page open."
    fi
    if ! read_pem "Origin Certificate" "${CF_CERT_FILE:-}" "$cert" ||
       ! read_pem "Private Key" "${CF_KEY_FILE:-}" "$key"; then
        log_error "Certificate or key missing; nothing installed"
        rm -f "$cert" "$key"
        note "- Cloudflare certificate not installed. Re-run with CF_CERT_FILE and CF_KEY_FILE, or from a terminal."
        return 1
    fi
    chmod 644 "$cert"
    chmod 600 "$key"

    if ! openssl x509 -in "$cert" -noout 2>/dev/null; then
        log_error "$cert is not a valid certificate"
        return 1
    fi
    if ! openssl pkey -in "$key" -noout 2>/dev/null; then
        log_error "$key is not a valid private key"
        return 1
    fi
    log_ok "Certificate and key saved in $certs"
    openssl x509 -in "$cert" -noout -subject -enddate | sed 's/^/    /'
}

write_traefik_config() {
    local file="$PROXY_DIR/dynamic/cloudflare-origin-cert.yaml"
    # /traefik/certs is where Coolify's proxy container mounts $PROXY_DIR/certs.
    local traefik_yaml="tls:
  certificates:
    - certFile: /traefik/certs/$CF_DOMAIN.cert
      keyFile: /traefik/certs/$CF_DOMAIN.key"
    if [ "${CF_TRAEFIK_CONFIG:-yes}" != yes ]; then
        note "- Add this in Coolify → Servers → this server → Proxy → Dynamic Configuration:"
        note "$(echo "$traefik_yaml" | sed 's/^/    /')"
    elif [ "$(cat "$file" 2>/dev/null)" = "$traefik_yaml" ]; then
        log_ok "Traefik config already in $file"
    else
        mkdir -p "$PROXY_DIR/dynamic"
        echo "$traefik_yaml" > "$file"
        log_ok "Traefik config written to $file"
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
        note "- This machine needs tag:vps and tag:coolify, and the policy needs the tag:coolify rule before them, or Coolify loses its servers. See $POLICY_GUIDE."
    fi
}

module_main "$@"
