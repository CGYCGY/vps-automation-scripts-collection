#!/bin/bash
# Git identity and a GitHub SSH key, and Apple's Remote Login turned off once
# Tailscale SSH can take over remote access.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

KEY="$HOME/.ssh/id_ed25519"
SSH_CONFIG="$HOME/.ssh/config"

module_help() {
    cat <<EOF2
Usage: $0 [-y] [--status] [--phase ...]

Answers can be given up front as environment variables:
  GIT_NAME, GIT_EMAIL   git identity (default: what git already has)
  GH_SSH_KEY            yes | no   create a GitHub SSH key when none exists
EOF2
}

github_block_present() { grep -qsE '^Host +github\.com' "$SSH_CONFIG"; }
insteadof_set() { [ "$(git config --global --get url.git@github.com:.insteadOf)" = "https://github.com/" ]; }

module_status() {
    local name email
    name="$(git config --global user.name || true)"
    email="$(git config --global user.email || true)"
    if [ -n "$name" ] && [ -n "$email" ]; then status_row git-identity present "$name <$email>"
    else status_row git-identity missing ""; fi
    if insteadof_set; then status_row git-ssh-urls present "GitHub https URLs use SSH"
    else status_row git-ssh-urls missing ""; fi
    if [ -f "$KEY" ] && github_block_present; then status_row github-key present "$KEY, in Keychain via ~/.ssh/config"
    elif [ -f "$KEY" ]; then status_row github-key partial "$KEY, no github.com block in ~/.ssh/config"
    else status_row github-key missing ""; fi
    if remote_login_on; then status_row remote-login partial "on; Tailscale SSH makes it unnecessary"
    else status_row remote-login present "off"; fi
}

module_plan() {
    require_user
    ask GIT_NAME "Git name" "$(git config --global user.name || true)"
    ask GIT_EMAIL "Git email" "$(git config --global user.email || true)"
    if [ ! -f "$KEY" ]; then
        ask_yn GH_SSH_KEY "Create an SSH key for GitHub (you'll add it to your account)?" y
    fi
}

module_auto() {
    log_step "Git"
    [ -n "${GIT_NAME:-}" ] && git config --global user.name "$GIT_NAME"
    [ -n "${GIT_EMAIL:-}" ] && git config --global user.email "$GIT_EMAIL"
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    log_ok "Identity ${GIT_NAME:-?} <${GIT_EMAIL:-?}>; GitHub https URLs use SSH"

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
    ssh-keygen -t ed25519 -C "${GIT_EMAIL:-$(id -un)@$(hostname -s)}" -f "$KEY"
    ssh-add --apple-use-keychain "$KEY"
    pbcopy < "$KEY.pub"
    echo
    cat "$KEY.pub"
    echo
    log_info "Copied to the clipboard. Add it at https://github.com/settings/ssh/new"
    printf 'Press Enter once it is added... ' > /dev/tty
    _read_tty || true
    # GitHub answers a working key with exit status 1 and a greeting.
    if ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log_ok "GitHub accepts the key"
    else
        note "- GitHub didn't accept the key yet. Check https://github.com/settings/keys, then: ssh -T git@github.com"
    fi
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
