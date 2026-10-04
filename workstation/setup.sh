#!/bin/bash
# Workstation Setup - entry point for machines used for work (Linux or macOS)
#
# Must stay bash 3.2 compatible: it is the first thing run on a fresh Mac.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../shared/lib/setup-lib.sh
. "$SCRIPT_DIR/../shared/lib/setup-lib.sh"

MAC="$SCRIPT_DIR/macos"
# Order matters within each phase: Full Disk Access comes after the apps it
# applies to are installed, and ssh after tailscale, because Remote Login only
# goes off once Tailscale SSH is connected.
MACOS_MODULES="$MAC/homebrew.sh $MAC/apps.sh $MAC/tailscale.sh $MAC/full-disk-access.sh
$MAC/ai-dev.sh $MAC/power.sh $MAC/finder.sh $MAC/zed.sh $MAC/ssh.sh"

show_help() {
    cat <<EOF
Usage: $0 [--status] [-y]

  --status    Survey this machine without changing anything
  -y, --yes   Take the default answer for every question

macOS: asks for sudo once, asks every question, installs, then leaves the
steps that need you (Tailscale login, GitHub key) for the end.
Linux: runs the AI dev toolchain setup; its flags are passed through.
EOF
}

require_user

case "$(uname -s)" in
    Linux)
        exec bash "$SCRIPT_DIR/shared/ai-dev/ai-dev-setup.sh" "$@"
        ;;
    Darwin) ;;
    *) die "unsupported OS: $(uname -s)" ;;
esac

status=""
for arg in "$@"; do
    case "$arg" in
        --status) status=1 ;;
        -y|--yes) ASSUME_YES=1; export ASSUME_YES ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "unknown option: $arg"; show_help; exit 1 ;;
    esac
done

# shellcheck disable=SC2086
if [ -n "$status" ]; then
    status_modules $MACOS_MODULES
else
    sudo_keepalive
    run_modules $MACOS_MODULES
fi
