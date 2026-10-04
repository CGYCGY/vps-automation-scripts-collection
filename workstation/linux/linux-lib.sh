#!/bin/bash
# Linux helpers on top of the shared phase runner. Modules run as the normal
# user; sudo is only used to install missing apt packages, as ai-dev-setup.sh
# does.

LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../shared/lib/setup-lib.sh
. "$LINUX_DIR/../../shared/lib/setup-lib.sh"

[ "$(uname -s)" = Linux ] || die "this is a Linux module"

# apt_install PKG...: installs the ones not installed yet.
apt_install() {
    local missing
    missing="$(missing_pkgs "$@")"
    [ -n "$missing" ] || return 0
    have apt-get || die "apt-get not found; install $missing yourself"
    log_info "Installing $missing"
    sudo apt-get update -qq
    # shellcheck disable=SC2086
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing
}
