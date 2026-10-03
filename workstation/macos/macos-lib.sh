#!/bin/bash
# macOS helpers on top of the shared phase runner. Modules run as the normal
# user (Homebrew refuses root) and use sudo for the system parts; the menu
# primes sudo once up front.

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../shared/lib/setup-lib.sh
. "$MACOS_DIR/../../shared/lib/setup-lib.sh"

[ "$(uname -s)" = Darwin ] || die "this is a macOS module"

load_brew() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then
            eval "$("$b" shellenv)"
            return 0
        fi
    done
    return 1
}
load_brew || true

is_laptop() { pmset -g batt 2>/dev/null | grep -q InternalBattery; }

# TCC.db is world-readable on disk but macOS blocks reads without Full Disk
# Access, so a read attempt is the only reliable check. It tests the app this
# script runs in (Terminal, Warp, ...), which is the one that needs it.
has_fda() { head -c1 "/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1; }

terminal_app() {
    case "${TERM_PROGRAM:-}" in
        Apple_Terminal) echo Terminal ;;
        WarpTerminal)   echo Warp ;;
        iTerm.app)      echo iTerm ;;
        vscode)         echo "your editor" ;;
        *)              echo "your terminal app" ;;
    esac
}

ts_backend_state() {
    tailscale status --json 2>/dev/null |
        sed -n 's/.*"BackendState": *"\([A-Za-z]*\)".*/\1/p' | head -1
}

remote_login_on() { netstat -anp tcp 2>/dev/null | grep -qE '[.*]\.22 .*LISTEN'; }
