#!/bin/bash
# Homebrew, which every other macOS module installs through.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

module_status() {
    if have brew; then
        status_row homebrew present "$(brew --version | head -1)"
    else
        status_row homebrew missing ""
    fi
}

module_plan() { require_user; }

module_deps() {
    log_step "Homebrew"
    if have brew; then
        log_ok "$(brew --version | head -1)"
    else
        local installer
        installer="$(mktemp)"
        # Downloaded first: macOS curl (LibreSSL) sometimes drops the
        # connection, and a piped script would then run half-written.
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
        # NONINTERACTIVE skips Homebrew's own "press RETURN"; it still needs
        # sudo, which the menu already primed.
        NONINTERACTIVE=1 /bin/bash "$installer"
        rm -f "$installer"
        load_brew || die "Homebrew installed but brew isn't where expected"
        log_ok "Homebrew installed"
    fi
    local line
    line="eval \"\$($(command -v brew) shellenv zsh)\""
    if ! grep -qs 'brew shellenv' "$HOME/.zprofile"; then
        printf '\n%s\n' "$line" >> "$HOME/.zprofile"
        log_ok "brew shellenv added to ~/.zprofile"
    fi
}

module_main "$@"
