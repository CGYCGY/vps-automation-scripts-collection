#!/bin/bash
# Everyday command-line tools from apt.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/linux-lib.sh"

PACKAGES="git-crypt qrencode stow"

module_status() {
    local p
    for p in $PACKAGES; do
        if pkg_installed "$p"; then status_row "$p" present ""
        else status_row "$p" missing ""; fi
    done
}

module_plan() { require_user; }

module_deps() {
    log_step "Apps"
    # shellcheck disable=SC2086
    apt_install $PACKAGES
    log_ok "$PACKAGES"
}

module_main "$@"
