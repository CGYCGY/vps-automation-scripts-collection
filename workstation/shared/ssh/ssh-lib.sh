#!/bin/bash
# The git identity and GitHub key steps that macos/ssh.sh and linux/ssh.sh
# share. Source it after macos-lib.sh or linux-lib.sh.

KEY="$HOME/.ssh/id_ed25519"

ssh_help() {
    cat <<EOF2
Usage: $0 [-y] [--status] [--phase ...]

Answers can be given up front as environment variables:
  GIT_NAME, GIT_EMAIL   git identity (default: what git already has)
  GH_SSH_KEY            yes | no   create a GitHub SSH key when none exists
EOF2
}

# On Linux git may not be installed yet when the questions are asked.
git_global() { have git && git config --global --get "$1"; }

insteadof_set() { [ "$(git_global url.git@github.com:.insteadOf)" = "https://github.com/" ]; }

git_status_rows() {
    local name email
    name="$(git_global user.name || true)"
    email="$(git_global user.email || true)"
    if [ -n "$name" ] && [ -n "$email" ]; then status_row git-identity present "$name <$email>"
    else status_row git-identity missing ""; fi
    if insteadof_set; then status_row git-ssh-urls present "GitHub https URLs use SSH"
    else status_row git-ssh-urls missing ""; fi
}

ask_git_plan() {
    ask GIT_NAME "Git name" "$(git_global user.name || true)"
    ask GIT_EMAIL "Git email" "$(git_global user.email || true)"
    if [ ! -f "$KEY" ]; then
        ask_yn GH_SSH_KEY "Create an SSH key for GitHub (you'll add it to your account)?" y
    fi
}

apply_git_settings() {
    log_step "Git"
    [ -n "${GIT_NAME:-}" ] && git config --global user.name "$GIT_NAME"
    [ -n "${GIT_EMAIL:-}" ] && git config --global user.email "$GIT_EMAIL"
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    log_ok "Identity ${GIT_NAME:-?} <${GIT_EMAIL:-?}>; GitHub https URLs use SSH"
}

key_comment() { echo "${GIT_EMAIL:-$(id -un)@$(hostname -s)}"; }

# add_key_to_github [PREFIX]: shows the new key, waits for the user to add it,
# then checks it. PREFIX goes before "Add it at ...".
add_key_to_github() {
    echo
    cat "$KEY.pub"
    echo
    log_info "${1:-}Add it at https://github.com/settings/ssh/new"
    if ! _have_tty; then
        note "- Add the GitHub key (cat ~/.ssh/id_ed25519.pub) at https://github.com/settings/ssh/new, then check it: ssh -T git@github.com"
        return 0
    fi
    printf 'Press Enter once it is added... ' > /dev/tty
    _read_tty || true
    # GitHub answers a working key with exit status 1 and a greeting.
    if ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log_ok "GitHub accepts the key"
    else
        note "- GitHub didn't accept the key yet. Check https://github.com/settings/keys, then: ssh -T git@github.com"
    fi
}
