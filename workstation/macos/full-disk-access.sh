#!/bin/bash
# Full Disk Access for the terminal apps. macOS only lets a person grant it in
# System Settings, and an app only picks it up after it restarts.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

PANE="x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

module_status() {
    if has_fda; then status_row full-disk-access present "$(terminal_app) has it"
    else status_row full-disk-access missing "$(terminal_app) doesn't have it"; fi
}

module_plan() { require_user; }

# In deps, after the apps are installed, because later steps (turning Remote
# Login off) need it and the terminal must restart before it applies.
module_deps() {
    log_step "Full Disk Access"
    if has_fda; then
        log_ok "$(terminal_app) has Full Disk Access"
        return 0
    fi
    open "$PANE" 2>/dev/null || true
    log_warn "$(terminal_app) has no Full Disk Access. System Settings is open at the list."
    note "- Full Disk Access: turn on Terminal and Warp in System Settings → Privacy & Security → Full Disk Access (use + if one is missing), quit and reopen them, then run this setup again to finish the steps that need it."
}

module_main "$@"
