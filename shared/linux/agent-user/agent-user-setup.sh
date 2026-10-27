#!/bin/bash
# A local user for an automation agent that logs in over Tailscale SSH:
# regular account, password locked, passwordless sudo from one drop-in.
# Tested on: Ubuntu 22.04, 24.04, Debian 12, 13

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/setup-lib.sh
. "$SCRIPT_DIR/../../lib/setup-lib.sh"

AGENT_SHELL=/bin/bash

module_help() {
    cat <<EOF
Usage: sudo $0 [--user NAME] [-y] [--status] [--phase plan|deps|auto|interactive|summary]

  --user NAME   the account to create (default: agent)

Answers can be given up front as environment variables:
  AGENT_USER            the account name, same as --user
  AGENT_LOCK_PASSWORD   yes | no    lock the password of an existing account that has one
EOF
}

# No dots: sudo skips files in sudoers.d whose name contains one, and the
# drop-in is named after the user.
valid_name() {
    case "$1" in ''|[!a-z_]*|*[!a-z0-9_-]*) return 1 ;; esac
    [ "${#1}" -le 32 ]
}

AGENT_USER="${AGENT_USER:-agent}"
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --user) [ -n "${2:-}" ] || die "--user needs a name"; AGENT_USER="$2"; shift ;;
        --user=*) AGENT_USER="${1#--user=}" ;;
        *) args+=("$1") ;;
    esac
    shift
done
valid_name "$AGENT_USER" || die "not a usable account name: $AGENT_USER (lowercase letters, digits, _ and -)"
export AGENT_USER

AGENT_HOME="/home/$AGENT_USER"
SUDOERS_FILE="/etc/sudoers.d/$AGENT_USER"
SUDOERS_LINE="$AGENT_USER ALL=(ALL) NOPASSWD: ALL"

is_linux() { [ "$(uname -s)" = Linux ]; }
require_linux() { is_linux || die "agent user: not supported, Linux only (this is $(uname -s))"; }

user_exists() { getent passwd "$AGENT_USER" >/dev/null 2>&1; }
user_field() { getent passwd "$AGENT_USER" | cut -d: -f"$1"; }

uid_min() {
    local min
    min="$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs 2>/dev/null)"
    echo "${min:-1000}"
}

# passwd -S field 2: P = usable password, L = locked, NP = empty. Needs root
# for any account but your own.
password_state() { passwd -S "$AGENT_USER" 2>/dev/null | awk '{print $2}'; }

sudoers_valid() {
    [ "$(stat -c %a:%u "$SUDOERS_FILE" 2>/dev/null)" = 440:0 ] &&
        visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1
}

sudoers_done() { [ "$(cat "$SUDOERS_FILE" 2>/dev/null)" = "$SUDOERS_LINE" ] && sudoers_valid; }

# A valid file with other content is an allowlist someone narrowed it to;
# putting NOPASSWD: ALL back on a re-run would undo that.
sudoers_custom() { [ -f "$SUDOERS_FILE" ] && ! sudoers_done && sudoers_valid; }

module_status() {
    if ! is_linux; then
        status_row agent-user skipped "not supported, Linux only (this is $(uname -s))"
        return 0
    fi

    local shell
    if ! user_exists; then
        status_row agent-user missing "will create $AGENT_USER, home $AGENT_HOME, shell $AGENT_SHELL"
    else
        shell="$(user_field 7)"
        if [ "$shell" = "$AGENT_SHELL" ]; then
            status_row agent-user present "$AGENT_USER (uid $(user_field 3)), home $(user_field 6), shell $shell"
        else
            status_row agent-user partial "$AGENT_USER exists, shell ${shell:-none}; will set $AGENT_SHELL"
        fi
    fi

    if ! user_exists; then
        status_row agent-password missing "created locked"
    else
        case "$(password_state)" in
            L)  status_row agent-password present "locked" ;;
            P)  status_row agent-password partial "$AGENT_USER has a password; the setup offers to lock it" ;;
            NP) status_row agent-password missing "empty password; will lock it" ;;
            *)  status_row agent-password unknown "needs sudo to check" ;;
        esac
    fi

    if [ ! -e "$SUDOERS_FILE" ]; then
        status_row agent-sudo missing "will add $SUDOERS_FILE"
    elif ! is_root; then
        status_row agent-sudo unknown "$SUDOERS_FILE exists; needs sudo to check it"
    elif sudoers_done; then
        status_row agent-sudo present "passwordless, $SUDOERS_FILE, valid"
    elif sudoers_custom; then
        status_row agent-sudo present "customized $SUDOERS_FILE, valid; left as is"
    else
        status_row agent-sudo partial "$SUDOERS_FILE fails visudo or isn't root-owned 0440; will replace it"
    fi
}

module_plan() {
    require_linux
    require_root
    [ "$AGENT_USER" != root ] || die "the agent user can't be root"
    # The run would lock this account's password and hand it NOPASSWD sudo.
    [ "$AGENT_USER" != "$(invoking_user)" ] || die "$AGENT_USER is you; pick another name with --user"

    if ! user_exists; then
        log_info "Agent user: would create $AGENT_USER with passwordless sudo"
        return 0
    fi
    [ "$(user_field 3)" -ge "$(uid_min)" ] ||
        die "$AGENT_USER is a system account (uid $(user_field 3)); pick another name with --user"
    if { sudoers_done || sudoers_custom; } && [ "$(password_state)" = L ] && [ "$(user_field 7)" = "$AGENT_SHELL" ]; then
        log_info "Agent user: $AGENT_USER already set up"
        return 0
    fi
    log_info "Agent user: $AGENT_USER exists; would finish its setup"
    if [ "$(password_state)" = P ]; then
        ask_yn AGENT_LOCK_PASSWORD "$AGENT_USER has a password, which Tailscale SSH doesn't need. Lock it?" y
    fi
}

module_deps() {
    require_linux
    log_step "Agent user: packages"
    # Minimal images run as root without sudo; visudo comes with it.
    if pkg_installed sudo; then
        log_ok "sudo already installed"
        return 0
    fi
    have apt-get || die "apt-get not found; install sudo yourself"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq sudo >/dev/null
    log_ok "Installed sudo"
}

create_user() {
    if user_exists; then
        log_ok "User $AGENT_USER exists"
    else
        # Without -p, useradd leaves the password field as "!": locked, not
        # empty. Tailscale SSH doesn't check it.
        useradd -m -d "$AGENT_HOME" -s "$AGENT_SHELL" "$AGENT_USER"
        log_ok "User $AGENT_USER created ($AGENT_HOME, $AGENT_SHELL)"
    fi
    if [ "$(user_field 7)" != "$AGENT_SHELL" ]; then
        usermod -s "$AGENT_SHELL" "$AGENT_USER"
        log_ok "$AGENT_USER: shell set to $AGENT_SHELL"
    fi
}

# passwd -l, never -d: -d empties the password, which lets anyone at the
# console or in `su` log in as the agent without one.
lock_password() {
    case "$(password_state)" in
        L) log_ok "$AGENT_USER: password locked" ;;
        NP)
            passwd -l "$AGENT_USER" >/dev/null
            log_ok "$AGENT_USER: empty password locked"
            ;;
        P)
            if [ "${AGENT_LOCK_PASSWORD:-no}" = yes ]; then
                passwd -l "$AGENT_USER" >/dev/null
                log_ok "$AGENT_USER: password locked"
            else
                log_warn "$AGENT_USER keeps its password"
            fi
            ;;
        *) log_warn "$AGENT_USER: couldn't read the password state" ;;
    esac
}

install_sudoers() {
    if sudoers_done; then
        log_ok "$AGENT_USER already has passwordless sudo ($SUDOERS_FILE)"
        return 0
    fi
    if sudoers_custom; then
        log_ok "$SUDOERS_FILE is customized and valid; left as is"
        return 0
    fi
    # One bad file in sudoers.d breaks sudo for everyone, so the new one is
    # checked first and moved into place in one step. The staging name has a
    # dot, so sudo ignores it while it sits there.
    local tmp
    tmp="$(mktemp "$SUDOERS_FILE.XXXXXX")"
    echo "$SUDOERS_LINE" > "$tmp"
    chown root:root "$tmp"
    chmod 440 "$tmp"
    if ! visudo -cf "$tmp" >/dev/null; then
        rm -f "$tmp"
        log_error "sudoers entry for $AGENT_USER failed validation; not installed"
        return 1
    fi
    mv -f "$tmp" "$SUDOERS_FILE"
    log_ok "$AGENT_USER: passwordless sudo ($SUDOERS_FILE)"
}

module_auto() {
    require_linux
    log_step "Agent user: $AGENT_USER"
    create_user
    lock_password
    install_sudoers
}

module_summary() {
    { is_linux && user_exists; } || return 0
    note "- The agent logs in from your tailnet with: ssh $AGENT_USER@$(hostname). The policy's autogroup:nonroot rules already cover it; see docs/tailscale-tailnet.md."
    note "- To narrow the agent's sudo later: sudo visudo -f $SUDOERS_FILE"
}

module_main "${args[@]}"
