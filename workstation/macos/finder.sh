#!/bin/bash
# Finder shows hidden files (dotfiles such as .env and .ssh).

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

shown() { [ "$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)" = 1 ]; }

module_status() {
    if shown; then status_row finder present "hidden files shown"
    else status_row finder missing "hidden files not shown"; fi
}

module_plan() { require_user; }

module_auto() {
    log_step "Finder"
    if shown; then
        log_ok "Hidden files already shown"
        return 0
    fi
    defaults write com.apple.finder AppleShowAllFiles -bool true
    killall Finder 2>/dev/null || true
    log_ok "Hidden files shown"
}

module_main "$@"
