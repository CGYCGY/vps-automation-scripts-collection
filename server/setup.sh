#!/bin/bash
# Server Setup - entry point for a Linux VPS hosting Coolify

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/../shared" && pwd)"
# shellcheck source=../shared/lib/setup-lib.sh
. "$SHARED_DIR/lib/setup-lib.sh"

SWAP="$SHARED_DIR/linux/swap/swap-setup.sh"
TAILSCALE="$SHARED_DIR/linux/tailscale/tailscale-setup.sh"
COOLIFY="$SCRIPT_DIR/coolify/coolify-setup.sh"

show_help() {
    cat <<EOF
Usage: sudo $0 [option] [-y]

Setup (needs sudo):
  --full            Swap, Tailscale SSH and Coolify, in one run
  --tailscale       Tailscale SSH and firewall only
  --coolify         Coolify only (dashboard or managed server)
  --coolify-remote  Coolify as a managed server, without asking the role
  --swap            Swap only

Tools (no sudo needed):
  --minio           MinIO migration tool
  --minio-users     MinIO user & bucket manager
  --postgres        PostgreSQL manager

  -y, --yes         Take the default answer for every question
  -h, --help        Show this help

Without an option, a menu is shown. Every setup asks all of its questions
first, then installs, and leaves steps that need you (like the Tailscale
login) for the end.
EOF
}

setup() {
    require_root
    case "$1" in
        full|tailscale|coolify) ask_server_role ;;
    esac
    case "$1" in
        full)      run_modules "$SWAP" "$TAILSCALE" "$COOLIFY" ;;
        tailscale) run_modules "$TAILSCALE" ;;
        coolify)   run_modules "$COOLIFY" ;;
        swap)      run_modules "$SWAP" ;;
    esac
}

tool() { bash "$SCRIPT_DIR/$1"; }

run_choice() {
    case "$1" in
        --full|1)        setup full ;;
        --tailscale|2)   setup tailscale ;;
        --coolify|3)     setup coolify ;;
        --coolify-remote) MACHINE_ROLE=managed; export MACHINE_ROLE; setup coolify ;;
        --swap|4)        setup swap ;;
        --minio|5)       tool minio/minio_migration.sh ;;
        --minio-users|6) tool minio/minio_user_bucket_manager.sh ;;
        --postgres|7)    tool postgres/postgres_manager.sh ;;
        *) return 2 ;;
    esac
}

menu() {
    while :; do
        cat <<EOF

${C_BOLD}Server Setup${C_RESET} - Linux VPS hosting Coolify

  1) Full setup (swap + Tailscale SSH + Coolify)
  2) Tailscale SSH and firewall
  3) Coolify (dashboard or managed server)
  4) Swap
  5) MinIO migration tool
  6) MinIO user & bucket manager
  7) PostgreSQL manager
  q) Quit

EOF
        printf 'Select [1-7, q]: '
        read -r choice
        case "$choice" in
            q|Q) exit 0 ;;
        esac
        # A subshell, so answers from one run aren't reused by the next.
        ( run_choice "$choice" ) || [ $? -ne 2 ] || log_warn "Invalid option"
    done
}

choice=""
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1; export ASSUME_YES ;;
        -h|--help) show_help; exit 0 ;;
        *) [ -z "$choice" ] && choice="$arg" ;;
    esac
done

if [ -z "$choice" ]; then
    menu
fi

run_choice "$choice" || {
    [ $? -eq 2 ] && { log_error "unknown option: $choice"; show_help; exit 1; }
    exit 1
}
