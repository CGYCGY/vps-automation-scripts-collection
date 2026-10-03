#!/bin/bash
# Tailscale SSH for a Linux server or workstation: install Tailscale, log in
# with Tailscale SSH on, then lock SSH to the tailnet with UFW.
# Tested on: Ubuntu 22.04, 24.04, Debian 11, 12, 13

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/setup-lib.sh
. "$SCRIPT_DIR/../../lib/setup-lib.sh"

TAILNET_V4="100.64.0.0/10"
SSHD_DROPIN="/etc/ssh/sshd_config.d/00-tailscale-ssh.conf"
POLICY_GUIDE="docs/tailscale-tailnet.md"

module_help() {
    cat <<EOF
Usage: sudo $0 [-y] [--phase plan|deps|auto|interactive|summary]

Answers can be given up front as environment variables:
  MACHINE_ROLE      dashboard | managed | workstation
  TS_PUBLIC_WEB     yes | no    open 80 and 443 to the internet
  TS_PUBLIC_PORTS   e.g. "3000 5000/udp"   more ports open to the internet
  TS_TAILNET_PORTS  e.g. "5432"            ports open to the tailnet only
  TS_UFW_RESET      yes | no    drop existing UFW rules first
  TS_SET_PASSWORD   yes | no    set a password for the provider's console
  TS_AUTHKEY        log in with an auth key instead of the browser
  TS_ACCESS_OK      yes: you checked Tailscale SSH works, so lock SSH down
EOF
}

is_oracle() {
    [ -f /etc/oracle-cloud-agent/agent.yml ] ||
        grep -qi oracle /sys/class/dmi/id/board_vendor 2>/dev/null ||
        grep -qi oraclecloud /sys/class/dmi/id/chassis_asset_tag 2>/dev/null
}

role_tags() {
    case "$MACHINE_ROLE" in
        dashboard) echo "tag:vps,tag:coolify" ;;
        managed)   echo "tag:vps" ;;
        *)         echo "" ;;
    esac
}

ts_state() {
    tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' 2>/dev/null
}

ts_tags() {
    tailscale status --json 2>/dev/null | jq -r '(.Self.Tags // []) | sort | join(",")' 2>/dev/null
}

sorted_tags() { echo "$1" | tr ',' '\n' | sort | paste -sd, -; }

ufw_active() { ufw status 2>/dev/null | grep -q "Status: active"; }

user_has_password() {
    # passwd -S field 2: P = usable password, L = locked, NP = none
    [ "$(passwd -S "$1" 2>/dev/null | awk '{print $2}')" = P ]
}

ufw_allow_ports() {
    local from="$1" ports="$2" comment="$3" p
    for p in $ports; do
        case "$p" in
            */*) ;;
            *) p="$p/tcp" ;;
        esac
        if [ "$from" = any ]; then
            ufw allow "$p" comment "$comment" >/dev/null
        else
            ufw allow from "$from" to any port "${p%/*}" proto "${p#*/}" comment "$comment" >/dev/null
        fi
        log_ok "UFW: $p from $from"
    done
}

# Checked in plan, because a typo would otherwise make ufw fail halfway
# through the run, after the confirmation.
valid_ports() {
    local p n proto
    for p in $1; do
        n="${p%/*}"; proto=tcp
        case "$p" in */*) proto="${p#*/}" ;; esac
        case "$n" in ''|*[!0-9]*) return 1 ;; esac
        [ "$n" -ge 1 ] && [ "$n" -le 65535 ] || return 1
        case "$proto" in tcp|udp) ;; *) return 1 ;; esac
    done
}

ask_ports() {
    local var="$1" question="$2" val
    while :; do
        ask "$var" "$question" ""
        eval "val=\${$var}"
        valid_ports "$val" && return 0
        _can_prompt || die "$var: not a list of ports: $val"
        log_warn "Use port numbers, optionally with /tcp or /udp, separated by spaces"
        unset "$var"
    done
}

module_plan() {
    require_root
    if [ -z "${MACHINE_ROLE:-}" ]; then
        ask_choice MACHINE_ROLE "What is this machine?" managed \
            "dashboard|Coolify dashboard (runs Coolify itself)" \
            "managed|Managed server (deployed to by a Coolify dashboard)" \
            "workstation|Workstation (a machine you work on)"
    fi

    local web_default=n
    [ "$MACHINE_ROLE" = managed ] && web_default=y
    ask_yn TS_PUBLIC_WEB "Open HTTP and HTTPS (80, 443) to the internet?" "$web_default"
    ask_ports TS_PUBLIC_PORTS "Other ports to open to the internet (e.g. 3000 5000/udp, blank for none)"
    ask_ports TS_TAILNET_PORTS "Ports to open to your tailnet only (e.g. 5432, blank for none)"

    if have ufw && ufw_active; then
        ask_yn TS_UFW_RESET "UFW is already active. Drop its current rules first?" n
    fi

    local user pw_default=n
    user="$(invoking_user)"
    if ! user_has_password "$user"; then
        is_oracle && pw_default=y
        ask_yn TS_SET_PASSWORD "$user has no password. Set one for the provider's emergency console?" "$pw_default"
    fi
}

module_deps() {
    log_step "Tailscale: packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl ufw jq >/dev/null
    log_ok "curl, ufw, jq"

    if have tailscale; then
        log_ok "Tailscale already installed ($(tailscale version | head -1))"
    else
        local installer
        installer="$(mktemp)"
        # Downloaded first so a dropped connection can't run half a script.
        curl -fsSL https://tailscale.com/install.sh -o "$installer"
        sh "$installer"
        rm -f "$installer"
        log_ok "Tailscale installed"
    fi
    systemctl enable --now tailscaled >/dev/null 2>&1 || true
}

configure_ufw() {
    if [ "${TS_UFW_RESET:-no}" = yes ]; then
        ufw --force reset >/dev/null
        log_ok "UFW rules reset"
    fi
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null

    ufw_allow_ports "$TAILNET_V4" 22 "SSH from Tailscale"
    if [ "$MACHINE_ROLE" = dashboard ]; then
        ufw_allow_ports "$TAILNET_V4" "8000 6001 6002" "Coolify dashboard from Tailscale"
    fi
    if [ "${TS_PUBLIC_WEB:-no}" = yes ]; then
        ufw_allow_ports any "80 443" "Web"
    fi
    ufw_allow_ports any "${TS_PUBLIC_PORTS:-}" "Custom"
    ufw_allow_ports "$TAILNET_V4" "${TS_TAILNET_PORTS:-}" "Custom from Tailscale"
}

module_auto() {
    log_step "Tailscale: firewall rules"
    # On an active UFW, a reset or "deny incoming" takes effect at once, so
    # that waits for lock_down, after Tailscale is connected.
    if ufw_active; then
        log_info "UFW is active; its rules change after Tailscale connects"
    else
        configure_ufw
    fi
}

ts_check_tags() {
    local tags="$1" current
    current="$(ts_tags)"
    if [ -n "$tags" ] && [ "$current" != "$(sorted_tags "$tags")" ]; then
        note "- Tag this machine $tags (now: ${current:-none}) in the admin console: Machines → … → Edit ACL tags. See $POLICY_GUIDE."
    fi
}

ts_login() {
    local tags state
    tags="$(role_tags)"
    state="$(ts_state)"

    case "$state" in
        Running)
            tailscale set --ssh
            log_ok "Already logged in; Tailscale SSH on"
            ts_check_tags "$tags"
            return 0
            ;;
        NeedsLogin|NoState|"") ;;
        *)
            # Logged in but not running (e.g. Stopped). --reset would wipe its
            # settings, and `up` with other flags refuses to drop saved ones.
            tailscale set --ssh
            note "- Tailscale is $state. Bring it up with: sudo tailscale up, then re-run this script."
            return 1
            ;;
    esac

    local args="--ssh"
    [ -n "${TS_AUTHKEY:-}" ] && args="$args --auth-key=$TS_AUTHKEY"
    [ -z "${TS_AUTHKEY:-}" ] && log_info "Open the link Tailscale prints to log this machine in"

    # shellcheck disable=SC2086
    if [ -n "$tags" ] && tailscale up $args --advertise-tags="$tags"; then
        log_ok "Logged in, tagged $tags"
    # --reset: the failed attempt left its flags saved, and `up` refuses to
    # drop saved flags silently. Safe here, as the machine isn't logged in yet.
    elif tailscale up --reset $args; then
        log_ok "Logged in"
        if [ -n "$tags" ]; then
            log_warn "Tailscale refused the tags $tags; the policy probably doesn't define them yet"
            note "- Add $tags to your tailnet policy, then tag this machine in the admin console. See $POLICY_GUIDE."
        fi
    else
        return 1
    fi
}

# Lock-down closes every other way in, so make sure this one works first: a
# root-only VPS that ended up untagged, for example, has no rule letting root in.
access_confirmed() {
    local user host
    user="$(invoking_user)"
    host="$(hostname)"
    log_info "SSH is about to be limited to the tailnet."
    # Every answer may have come from the environment; no terminal then means
    # nobody can confirm, which must not abort the other modules' last steps.
    _have_tty || TS_ACCESS_OK="${TS_ACCESS_OK:-no}"
    ask_yn TS_ACCESS_OK "From another device on your tailnet, does 'ssh $user@$host' connect?" n
    if [ "$TS_ACCESS_OK" != yes ]; then
        log_warn "Not confirmed, so SSH was not locked down"
        note "- SSH is not locked down yet. Once 'ssh $user@$host' works over the tailnet, re-run with TS_ACCESS_OK=yes."
        return 1
    fi
}

lock_down() {
    local backup=""
    log_step "Tailscale: locking SSH to the tailnet"
    ufw_active && configure_ufw
    local rule
    for rule in 22/tcp 22 OpenSSH; do
        ufw delete allow "$rule" >/dev/null 2>&1 || true
    done
    ufw --force enable >/dev/null
    log_ok "UFW on; SSH only from $TAILNET_V4"

    if grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
        # 00- sorts first and sshd keeps the first value it reads, so this wins
        # over cloud-init's 50-cloud-init.conf, which turns passwords back on.
        printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > "$SSHD_DROPIN"
    else
        backup="/etc/ssh/sshd_config.backup.$(date +%F-%H%M%S)"
        cp /etc/ssh/sshd_config "$backup"
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        grep -q '^PasswordAuthentication' /etc/ssh/sshd_config ||
            echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
    fi
    if sshd -t; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        log_ok "SSH password login off"
    else
        log_error "sshd rejected the new config; password login left unchanged"
        rm -f "$SSHD_DROPIN"
        [ -n "$backup" ] && cp "$backup" /etc/ssh/sshd_config
    fi
}

module_interactive() {
    log_step "Tailscale: log in"
    if ! ts_login || [ "$(ts_state)" != Running ]; then
        log_warn "Tailscale is not connected, so SSH was not locked down"
        note "- Tailscale didn't connect. Fix it, then re-run this script to lock SSH to the tailnet."
        return 0
    fi

    if [ "${TS_SET_PASSWORD:-no}" = yes ]; then
        if [ -z "${ASSUME_YES:-}" ] && _have_tty; then
            log_step "Console password for $(invoking_user)"
            passwd "$(invoking_user)" || log_warn "Password not set"
        else
            note "- Console password not set (no terminal to type it). Run: sudo passwd $(invoking_user)"
        fi
    fi

    access_confirmed && lock_down
    return 0
}

module_summary() {
    local host
    host="$(hostname)"
    note "- Connect from your tailnet: ssh $(invoking_user)@$host"
    if [ "$MACHINE_ROLE" != workstation ]; then
        note "- Docker-published ports (Coolify's 80, 443, 8000, 6001, 6002) skip UFW. Close them in your provider's firewall unless they should be public."
        if is_oracle; then
            note "- Oracle Cloud: Networking → Virtual Cloud Networks → your subnet → Security List. Remove the 0.0.0.0/0 rule for port 22; add 80 and 443 only if this server serves the web."
        else
            note "- If your provider has a cloud firewall (security group), remove public port 22 there too."
        fi
    fi
}

module_main "$@"
