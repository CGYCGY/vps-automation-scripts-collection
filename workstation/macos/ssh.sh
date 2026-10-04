#!/bin/bash
# Git identity and a GitHub SSH key, and Apple's Remote Login turned off once
# Tailscale SSH can take over remote access.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"
# shellcheck source=../shared/ssh/ssh-lib.sh
. "$MACOS_DIR/../shared/ssh/ssh-lib.sh"

SSH_CONFIG="$HOME/.ssh/config"

module_help() { ssh_help; }

github_block_present() { grep -qsE '^Host +github\.com' "$SSH_CONFIG"; }

module_status() {
    git_status_rows
    if [ -f "$KEY" ] && github_block_present; then status_row github-key present "$KEY, in Keychain via ~/.ssh/config"
    elif [ -f "$KEY" ]; then status_row github-key partial "$KEY, no github.com block in ~/.ssh/config"
    else status_row github-key missing ""; fi
    if remote_login_on; then status_row remote-login partial "on; Tailscale SSH makes it unnecessary"
    else status_row remote-login present "off"; fi
}

module_plan() {
    require_user
    ask_git_plan
}

module_auto() {
    apply_git_settings

    if ! github_block_present; then
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        [ -f "$SSH_CONFIG" ] && cp "$SSH_CONFIG" "$SSH_CONFIG.backup.$(date +%Y%m%d%H%M%S)"
        printf '\nHost github.com\n  AddKeysToAgent yes\n  UseKeychain yes\n  IdentityFile %s\n' "$KEY" >> "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
        log_ok "github.com block added to ~/.ssh/config"
    fi
}

create_github_key() {
    log_step "GitHub SSH key"
    log_info "Choose a passphrase; macOS Keychain remembers it after this"
    ssh-keygen -t ed25519 -C "$(key_comment)" -f "$KEY"
    ssh-add --apple-use-keychain "$KEY"
    pbcopy < "$KEY.pub"
    add_key_to_github "Copied to the clipboard. "
}

remote_login_off() {
    remote_login_on || return 0
    if [ "$(ts_backend_state)" != Running ]; then
        note "- Remote Login left on: Tailscale isn't connected, and turning it off now could lock you out."
        return 0
    fi
    if ! has_fda; then
        note "- Remote Login is still on. It needs Full Disk Access to turn off from a script; after granting it, re-run, or turn it off in System Settings → General → Sharing."
        return 0
    fi
    sudo systemsetup -f -setremotelogin off >/dev/null
    log_ok "Remote Login off; remote access is through Tailscale SSH"
}

module_interactive() {
    if [ "${GH_SSH_KEY:-no}" = yes ] && [ ! -f "$KEY" ]; then
        create_github_key
    fi
    remote_login_off
}

module_main "$@"
