#!/bin/bash
# Everyday tools from Homebrew. Desktop apps only go on a Mac whose screen
# gets used, directly or through remote desktop.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

FORMULAE="btop just"
# cask:App name, so an app installed by hand (drag to /Applications) counts as
# present; brew would otherwise refuse to install over it.
CASKS="orbstack:OrbStack"
HEADED_CASKS="warp:Warp zed:Zed rustdesk:RustDesk"

module_help() {
    cat <<EOF2
Usage: $0 [-y] [--status] [--phase ...]

Answers can be given up front as environment variables:
  MAC_HEADED   yes | no   install the desktop apps (Warp, Zed, RustDesk)
EOF2
}

cask_present() {
    brew list --cask "${1%%:*}" >/dev/null 2>&1 || [ -d "/Applications/${1#*:}.app" ]
}

wanted_casks() {
    echo "$CASKS"
    [ "${MAC_HEADED:-yes}" = yes ] && echo "$HEADED_CASKS"
    return 0
}

module_status() {
    local f c
    for f in $FORMULAE; do
        if brew list --formula "$f" >/dev/null 2>&1; then status_row "$f" present ""
        else status_row "$f" missing ""; fi
    done
    for c in $CASKS $HEADED_CASKS; do
        if cask_present "$c"; then status_row "${c%%:*}" present ""
        else status_row "${c%%:*}" missing ""; fi
    done
}

module_plan() {
    require_user
    ask_yn MAC_HEADED "Will this Mac's screen be used (directly or by remote desktop)? Adds Warp, Zed, RustDesk" y
}

module_deps() {
    log_step "Apps"
    local f c
    for f in $FORMULAE; do
        if brew list --formula "$f" >/dev/null 2>&1; then
            log_ok "$f"
        else
            brew install "$f" && log_ok "$f installed"
        fi
    done
    for c in $(wanted_casks); do
        if cask_present "$c"; then
            log_ok "${c#*:}"
        else
            brew install --cask "${c%%:*}" && log_ok "${c#*:} installed"
        fi
    done
}

module_main "$@"
