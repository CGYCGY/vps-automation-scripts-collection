#!/bin/bash
# Tailscale SSH on a Mac. Only the open-source tailscaled from Homebrew can
# accept Tailscale SSH; the App Store and standalone apps can't.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

POLICY_GUIDE="docs/tailscale-tailnet.md"

ssh_on() { tailscale debug prefs 2>/dev/null | grep -q '"RunSSH": true'; }

module_status() {
    if ! brew list --formula tailscale >/dev/null 2>&1; then
        status_row tailscale missing "brew formula not installed"
    elif [ "$(ts_backend_state)" != Running ]; then
        status_row tailscale partial "installed, not logged in"
    elif ! ssh_on; then
        status_row tailscale partial "logged in, Tailscale SSH off"
    else
        status_row tailscale present "logged in, Tailscale SSH on"
    fi
}

module_plan() {
    require_user
    if [ -d /Applications/Tailscale.app ]; then
        log_warn "The Tailscale app is installed. It can't accept Tailscale SSH and conflicts with the brew daemon; quit and remove it before continuing."
    fi
}

module_deps() {
    log_step "Tailscale"
    if brew list --formula tailscale >/dev/null 2>&1; then
        log_ok "tailscale (brew)"
    else
        brew install tailscale && log_ok "tailscale installed"
    fi
}

module_auto() {
    # A system service (sudo), so it starts at boot before anyone logs in.
    if sudo brew services list 2>/dev/null | grep -qE '^tailscale +started'; then
        log_ok "tailscaled running as a system service"
    else
        sudo brew services start tailscale >/dev/null
        log_ok "tailscaled started as a system service"
    fi
}

module_interactive() {
    log_step "Tailscale: log in"
    if [ "$(ts_backend_state)" = Running ]; then
        sudo tailscale set --ssh
        log_ok "Already logged in; Tailscale SSH on"
    else
        log_info "Open the link Tailscale prints to log this Mac in"
        if sudo tailscale up --ssh; then
            log_ok "Logged in with Tailscale SSH on"
        else
            note "- Tailscale didn't connect. Run: sudo tailscale up --ssh"
        fi
    fi
}

module_summary() {
    note "- Connect from your tailnet: ssh $(id -un)@$(hostname -s)"
    note "- Workstations stay untagged. See $POLICY_GUIDE for the tailnet's SSH rules."
}

module_main "$@"
