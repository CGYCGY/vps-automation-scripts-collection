#!/bin/bash
# Tailscale SSH on a Mac. Only the open-source tailscaled from Homebrew can
# accept Tailscale SSH; the App Store and standalone apps can't.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

POLICY_GUIDE="docs/tailscale-tailnet.md"
# tailscaled reads this file itself at startup (envknob.ApplyDiskConfig), so
# it survives brew regenerating the launchd plist on every restart and upgrade.
TS_ENV_FILE="/etc/tailscale/tailscaled-env.txt"
# Tailscale SSH forwards ports, unix sockets and the agent as root inside
# tailscaled. This knob (in every release since 1.60) refuses all of it.
FWD_OFF="TS_SSH_DISABLE_FORWARDING=1"

ssh_on() { tailscale debug prefs 2>/dev/null | grep -q '"RunSSH": true'; }
fwd_off() { grep -qx "$FWD_OFF" "$TS_ENV_FILE" 2>/dev/null; }

tailscaled_pid() { pgrep -x tailscaled 2>/dev/null | head -1; }
# No /proc on macOS to read the daemon's environment, so: the line is on disk
# and the daemon started after the file last changed. Equal seconds count as
# after: the module writes the file, then starts the service.
fwd_off_live() {
    local pid started
    pid="$(tailscaled_pid)"
    [ -n "$pid" ] && fwd_off || return 1
    started="$(date -j -f '%a %b %e %T %Y' "$(ps -o lstart= -p "$pid")" +%s 2>/dev/null)"
    [ -n "$started" ] && [ "$started" -ge "$(stat -f %m "$TS_ENV_FILE")" ]
}

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
    if ! fwd_off; then status_row ts-forwarding missing "will turn SSH forwarding off"
    elif [ -z "$(tailscaled_pid)" ] || fwd_off_live; then status_row ts-forwarding present "off ($TS_ENV_FILE)"
    else status_row ts-forwarding partial "off in $TS_ENV_FILE; applies when tailscaled restarts"; fi
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
    # Before the daemon starts, so a fresh Mac never needs the restart.
    if fwd_off; then
        log_ok "Tailscale SSH forwarding off"
    else
        sudo mkdir -p "$(dirname "$TS_ENV_FILE")"
        # Rewritten whole, via grep: appending to a file with no final newline
        # would glue the key onto the last line.
        { sudo grep -v '^TS_SSH_DISABLE_FORWARDING=' "$TS_ENV_FILE" 2>/dev/null || true
          echo "$FWD_OFF"; } | sudo tee "$TS_ENV_FILE.tmp" >/dev/null
        sudo mv "$TS_ENV_FILE.tmp" "$TS_ENV_FILE"
        log_ok "Tailscale SSH forwarding off ($TS_ENV_FILE)"
    fi

    # A system service (sudo), so it starts at boot before anyone logs in.
    if ! sudo brew services list 2>/dev/null | grep -qE '^tailscale +started'; then
        sudo brew services start tailscale >/dev/null
        log_ok "tailscaled started as a system service"
    elif fwd_off_live; then
        log_ok "tailscaled running as a system service"
    elif over_tailscale_ssh; then
        log_warn "tailscaled still allows forwarding until it restarts; that would cut this session"
        note "- Restart tailscaled to apply forwarding off: sudo brew services restart tailscale (drops Tailscale SSH sessions)"
    else
        sudo brew services restart tailscale >/dev/null
        log_ok "tailscaled restarted"
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
