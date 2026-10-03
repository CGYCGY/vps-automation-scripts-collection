#!/bin/bash
# Keeps a desktop Mac reachable: no sleep on power, back on after a power cut.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

# -c: only while on power, so a laptop on battery still sleeps.
SETTINGS="sleep=0 disksleep=0 displaysleep=0 autorestart=1"

module_help() {
    cat <<EOF2
Usage: $0 [-y] [--status] [--phase ...]

Answers can be given up front as environment variables:
  MAC_ALWAYS_ON   yes | no   never sleep on power; restart after a power cut
EOF2
}

current() { pmset -g custom | awk -v k="$1" '/^AC Power/{ac=1;next} /^[A-Za-z].*:$/{ac=0} ac && $1==k {print $2; exit}'; }

all_set() {
    local kv
    for kv in $SETTINGS; do
        [ "$(current "${kv%%=*}")" = "${kv#*=}" ] || return 1
    done
}

module_status() {
    if all_set; then status_row power present "never sleeps on power, restarts after power loss"
    else status_row power missing "sleeps on power, or no auto-restart"; fi
}

module_plan() {
    require_user
    local default=y
    is_laptop && default=n
    ask_yn MAC_ALWAYS_ON "Keep this Mac always on (no sleep on power, restart after a power cut)?" "$default"
}

module_auto() {
    [ "${MAC_ALWAYS_ON:-no}" = yes ] || return 0
    log_step "Power"
    if all_set; then
        log_ok "Already always on"
        return 0
    fi
    local kv
    for kv in $SETTINGS; do
        sudo pmset -c "${kv%%=*}" "${kv#*=}"
    done
    log_ok "Never sleeps on power; restarts after a power cut"
}

module_main "$@"
