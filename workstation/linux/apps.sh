#!/bin/bash
# Everyday command-line tools from apt.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/linux-lib.sh"

PACKAGES="git-crypt qrencode stow lefthook"

# lefthook is in neither Debian's nor Ubuntu's archive; its upstream apt repo is.
LEFTHOOK_REPO=https://dl.cloudsmith.io/public/evilmartians/lefthook
LEFTHOOK_KEYRING=/usr/share/keyrings/evilmartians-lefthook-archive-keyring.gpg
LEFTHOOK_LIST=/etc/apt/sources.list.d/evilmartians-lefthook.list

# Not from apt: Ubuntu's gitleaks is 8.16, too old for the top-level
# [[allowlists]] that repos' .gitleaks.toml use. Installed once, then left alone.
GITLEAKS_RELEASES=https://github.com/gitleaks/gitleaks/releases

module_status() {
    local p
    for p in $PACKAGES; do
        if pkg_installed "$p"; then status_row "$p" present ""
        else status_row "$p" missing ""; fi
    done
    if have gitleaks; then status_row gitleaks present "$(gitleaks version 2>/dev/null)"
    else status_row gitleaks missing "latest GitHub release"; fi
}

module_plan() { require_user; }

add_lefthook_repo() {
    [ -f "$LEFTHOOK_LIST" ] && return 0
    apt_install ca-certificates curl gnupg
    local id codename tmp
    id="$(. /etc/os-release && echo "$ID")"
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    log_info "Adding the lefthook apt repository"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/key.asc" "$LEFTHOOK_REPO/gpg.A05F5DDE3A0BB1D2.key"
    gpg --dearmor -o "$tmp/key.gpg" "$tmp/key.asc"
    curl -fsSL -o "$tmp/lefthook.list" "$LEFTHOOK_REPO/config.deb.txt?distro=$id&codename=$codename&component=main"
    sudo install -m 644 "$tmp/key.gpg" "$LEFTHOOK_KEYRING"
    sudo install -m 644 "$tmp/lefthook.list" "$LEFTHOOK_LIST"
    rm -rf "$tmp"
    # apt_install only refreshes the index when a package is missing, and a
    # machine that already has lefthook from elsewhere would never see this repo.
    sudo apt-get update -qq
}

install_gitleaks() {
    if have gitleaks; then
        log_ok "gitleaks $(gitleaks version 2>/dev/null)"
        return 0
    fi
    local arch tag version tarball tmp
    case "$(uname -m)" in
        x86_64) arch=x64 ;;
        aarch64|arm64) arch=arm64 ;;
        armv7l) arch=armv7 ;;
        *) die "no gitleaks release for $(uname -m)" ;;
    esac
    # The releases/latest redirect names the tag; the API would cap us at 60
    # unauthenticated requests an hour.
    tag="$(curl -fsSI "$GITLEAKS_RELEASES/latest" | tr -d '\r' | sed -n 's#^location: .*/tag/##Ip')"
    [ -n "$tag" ] || die "could not resolve the latest gitleaks release"
    version="${tag#v}"
    tarball="gitleaks_${version}_linux_${arch}.tar.gz"
    log_info "Installing gitleaks $version"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$tarball" "$GITLEAKS_RELEASES/download/$tag/$tarball"
    curl -fsSL -o "$tmp/checksums.txt" "$GITLEAKS_RELEASES/download/$tag/gitleaks_${version}_checksums.txt"
    (cd "$tmp" && grep " $tarball\$" checksums.txt | sha256sum -c --quiet -) || die "gitleaks $tag failed its checksum"
    tar -xzf "$tmp/$tarball" -C "$tmp" gitleaks
    sudo install -m 755 "$tmp/gitleaks" /usr/local/bin/gitleaks
    rm -rf "$tmp"
    log_ok "gitleaks $version installed"
}

module_deps() {
    log_step "Apps"
    add_lefthook_repo
    # shellcheck disable=SC2086
    apt_install $PACKAGES
    log_ok "$PACKAGES"
    install_gitleaks
}

module_main "$@"
