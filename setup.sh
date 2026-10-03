#!/bin/bash

#===============================================================================
# Machine Setup - picks the setup for this machine's type
#===============================================================================
#
# Usage:
#   sudo ./setup.sh server [options]   Linux VPS hosting Coolify (root)
#   ./setup.sh workstation [options]   machine used for work (normal user)
#   ./setup.sh                         ask which one
#
# Must stay bash 3.2 compatible: it is the first thing run on a fresh Mac.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

type="${1:-}"
[ $# -gt 0 ] && shift

if [ -z "$type" ]; then
    echo "What is this machine?"
    echo "  1) Server       Linux VPS hosting Coolify (run with sudo)"
    echo "  2) Workstation  machine used for work, Linux or macOS (run without sudo)"
    printf "Select [1-2]: "
    read -r choice
    case "$choice" in
        1) type=server ;;
        2) type=workstation ;;
        *) echo "Invalid option." >&2; exit 1 ;;
    esac
fi

case "$type" in
    server)      exec bash "$SCRIPT_DIR/server/setup.sh" "$@" ;;
    workstation) exec bash "$SCRIPT_DIR/workstation/setup.sh" "$@" ;;
    -h|--help)   sed -n '7,10p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
        echo "Unknown type: $type (use server or workstation)" >&2
        exit 1
        ;;
esac
