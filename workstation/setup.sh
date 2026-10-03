#!/bin/bash

#===============================================================================
# Workstation Setup - entry point for machines used for work (Linux or macOS)
#===============================================================================
#
# Usage:
#   ./workstation/setup.sh [ai-dev flags]   e.g. --status, -y, --upgrade
#
# Must stay bash 3.2 compatible: it is the first thing run on a fresh Mac.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_DEV_DIR="$SCRIPT_DIR/shared/ai-dev"

if [ "$(id -u)" -eq 0 ]; then
    echo "Error: workstation setup must run as your normal user, not root." >&2
    echo "Run without sudo: $0" >&2
    exit 1
fi

case "$(uname -s)" in
    Darwin) exec bash "$AI_DEV_DIR/macos/ai-dev-setup-macos.sh" "$@" ;;
    Linux)  exec bash "$AI_DEV_DIR/ai-dev-setup.sh" "$@" ;;
    *)
        echo "Error: unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac
