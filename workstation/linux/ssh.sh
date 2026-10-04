#!/bin/bash
# Git identity and a GitHub SSH key. Remote access is Tailscale SSH, set up
# separately as root by shared/linux/tailscale/tailscale-setup.sh.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/linux-lib.sh"
# shellcheck source=../shared/ssh/ssh-lib.sh
. "$LINUX_DIR/../shared/ssh/ssh-lib.sh"

module_help() { ssh_help; }

# No ~/.ssh/config block, unlike macOS: ssh already tries id_ed25519, and
# UseKeychain is an Apple option Linux OpenSSH rejects.
module_status() {
    git_status_rows
    if [ -f "$KEY" ]; then status_row github-key present "$KEY"
    else status_row github-key missing ""; fi
}

module_plan() {
    require_user
    ask_git_plan
}

module_deps() { apt_install git openssh-client; }

module_auto() { apply_git_settings; }

module_interactive() {
    [ "${GH_SSH_KEY:-no}" = yes ] && [ ! -f "$KEY" ] || return 0
    log_step "GitHub SSH key"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    # No passphrase: there is no Keychain to remember one, so every clone and
    # push would ask for it. The key is only ever added to GitHub.
    ssh-keygen -q -t ed25519 -N "" -C "$(key_comment)" -f "$KEY"
    log_ok "Created $KEY, without a passphrase"
    note "- ~/.ssh/id_ed25519 has no passphrase (no Keychain on Linux to remember one). To add one: ssh-keygen -p -f ~/.ssh/id_ed25519"
    add_key_to_github
}

module_main "$@"
