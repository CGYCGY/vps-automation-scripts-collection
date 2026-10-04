#!/bin/bash
# RAM-based swap: a 4GB /swapfile plus swappiness and vfs_cache_pressure tuned
# to the machine's memory. Skips machines that already have enough swap.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/setup-lib.sh
. "$SCRIPT_DIR/../../lib/setup-lib.sh"

SWAPFILE="/swapfile"
SWAP_SIZE_MB=4096
MIN_SWAP_MB=2048
MIN_FREE_KB=8388608
SYSCTL_FILE="/etc/sysctl.d/99-swap.conf"

module_help() {
    cat <<EOF
Usage: sudo $0 [-y] [--status] [--phase plan|deps|auto|interactive|summary]

Answers can be given up front as environment variables:
  SWAP_CREATE   yes | no    create the 4GB swap file when one is needed
EOF
}

ram_mb()     { free -m | awk '/^Mem:/ {print $2}'; }
swap_mb()    { free -m | awk '/^Swap:/ {print $2}'; }
free_kb()    { df -Pk / | awk 'NR==2 {print $4}'; }

swapfile_active() { awk -v f="$SWAPFILE" '$1 == f {found = 1} END {exit !found}' /proc/swaps; }

swapfile_done() {
    swapfile_active && [ "$(stat -c %s "$SWAPFILE")" -ge $((SWAP_SIZE_MB * 1024 * 1024)) ]
}

fstab_done() { grep -q "^$SWAPFILE[[:space:]]" /etc/fstab; }

# Reads /proc rather than `sysctl`, which is outside a normal user's PATH on Debian.
sysctl_done() {
    pick_profile
    [ "$(cat "$SYSCTL_FILE" 2>/dev/null)" = "$(sysctl_conf)" ] &&
        [ "$(cat /proc/sys/vm/swappiness)" = "$SWAPPINESS" ] &&
        [ "$(cat /proc/sys/vm/vfs_cache_pressure)" = "$CACHE_PRESSURE" ] &&
        ! grep -qE '^[[:space:]]*vm\.(swappiness|vfs_cache_pressure)[[:space:]]*=' /etc/sysctl.conf 2>/dev/null
}

swap_done() { swapfile_done && fstab_done && sysctl_done; }

# Prints why no swap file is needed, or nothing when one should be created.
# A full-size /swapfile counts as ours, so its own swap doesn't make a rerun
# skip the fstab and sysctl steps a crash may have left undone.
skip_reason() {
    local swap free
    swapfile_done && return 0
    swap="$(swap_mb)"
    free="$(free_kb)"
    if [ "$swap" -ge "$MIN_SWAP_MB" ]; then
        echo "enough swap already (${swap}MB)"
    elif [ "$free" -lt "$MIN_FREE_KB" ]; then
        echo "less than 8GB free on / ($((free / 1024 / 1024))GB)"
    fi
}

# Sets SWAPPINESS, CACHE_PRESSURE and PROFILE from the RAM size.
pick_profile() {
    local ram
    ram="$(ram_mb)"
    if [ "$ram" -ge 16384 ]; then
        SWAPPINESS=10; CACHE_PRESSURE=50;  PROFILE="optimal performance, minimal swap"
    elif [ "$ram" -ge 12288 ]; then
        SWAPPINESS=10; CACHE_PRESSURE=60;  PROFILE="good performance, light swap"
    elif [ "$ram" -ge 8192 ]; then
        SWAPPINESS=20; CACHE_PRESSURE=80;  PROFILE="balanced, moderate swap"
    else
        SWAPPINESS=30; CACHE_PRESSURE=100; PROFILE="survival mode, active swap"
    fi
}

sysctl_conf() { printf 'vm.swappiness=%s\nvm.vfs_cache_pressure=%s' "$SWAPPINESS" "$CACHE_PRESSURE"; }

module_status() {
    local reason
    reason="$(skip_reason)"
    if [ -n "$reason" ]; then
        status_row swapfile skipped "$reason"
        status_row swap-fstab skipped "no swap file to manage"
        status_row swap-sysctl skipped "settings only change with the swap file"
        return 0
    fi
    if swapfile_done; then
        status_row swapfile present "$SWAPFILE active, $(($(stat -c %s "$SWAPFILE") / 1024 / 1024))MB"
    elif [ -f "$SWAPFILE" ]; then
        status_row swapfile partial "$SWAPFILE too small or off; will replace it with ${SWAP_SIZE_MB}MB"
    else
        status_row swapfile missing "will create a ${SWAP_SIZE_MB}MB $SWAPFILE"
    fi
    if fstab_done; then status_row swap-fstab present "$SWAPFILE in /etc/fstab"
    else status_row swap-fstab missing "will add $SWAPFILE to /etc/fstab"; fi
    if sysctl_done; then
        status_row swap-sysctl present "swappiness $SWAPPINESS, vfs_cache_pressure $CACHE_PRESSURE ($PROFILE)"
    else
        status_row swap-sysctl missing "will set swappiness $SWAPPINESS, vfs_cache_pressure $CACHE_PRESSURE in $SYSCTL_FILE"
    fi
}

module_plan() {
    require_root
    local reason
    reason="$(skip_reason)"
    if [ -n "$reason" ]; then
        log_info "Swap: skipping, $reason"
        return 0
    fi
    if swap_done; then
        log_info "Swap: $SWAPFILE already set up"
        return 0
    fi
    pick_profile
    if swapfile_done; then
        log_info "Swap: $SWAPFILE is active; would finish its fstab entry and settings ($PROFILE)"
        ask_yn SWAP_CREATE "Finish setting up the swap file?" y
        return 0
    fi
    log_info "Swap: RAM $(ram_mb)MB, swap $(swap_mb)MB; would add a 4GB swap file ($PROFILE)"
    ask_yn SWAP_CREATE "Create a 4GB swap file tuned for this RAM?" y
}

create_swapfile() {
    if swapfile_done; then
        log_ok "$SWAPFILE already active"
        return 0
    fi
    if [ -f "$SWAPFILE" ]; then
        swapoff "$SWAPFILE" 2>/dev/null || true
        rm -f "$SWAPFILE"
        log_info "Removed the old $SWAPFILE"
    fi
    # fallocate'd files are rejected by swapon on some filesystems (older XFS,
    # btrfs without nocow), so fall back to writing the blocks out.
    if ! fallocate -l "${SWAP_SIZE_MB}M" "$SWAPFILE" 2>/dev/null; then
        dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MB" status=none
    fi
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE" >/dev/null
    if ! swapon "$SWAPFILE" 2>/dev/null; then
        rm -f "$SWAPFILE"
        dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MB" status=none
        chmod 600 "$SWAPFILE"
        mkswap "$SWAPFILE" >/dev/null
        swapon "$SWAPFILE"
    fi
    log_ok "$SWAPFILE active"
}

add_to_fstab() {
    if fstab_done; then
        log_ok "$SWAPFILE already in /etc/fstab"
    else
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
        log_ok "Added to /etc/fstab"
    fi
}

tune_sysctl() {
    if sysctl_done; then
        log_ok "Swap settings already set: swappiness $SWAPPINESS, vfs_cache_pressure $CACHE_PRESSURE"
        return 0
    fi
    echo "$(sysctl_conf)" > "$SYSCTL_FILE"
    # /etc/sysctl.conf is applied after sysctl.d (Debian/Ubuntu link it in as
    # 99-sysctl.conf, which sorts after 99-swap.conf), so old values there would win.
    if [ -f /etc/sysctl.conf ]; then
        sed -i -E 's/^[[:space:]]*(vm\.(swappiness|vfs_cache_pressure)[[:space:]]*=.*)$/# \1  # moved to 99-swap.conf/' /etc/sysctl.conf
    fi
    sysctl -q -w vm.swappiness="$SWAPPINESS" vm.vfs_cache_pressure="$CACHE_PRESSURE"
    log_ok "swappiness $SWAPPINESS, vfs_cache_pressure $CACHE_PRESSURE ($PROFILE)"
}

module_auto() {
    log_step "Swap"
    local reason
    reason="$(skip_reason)"
    if [ -n "$reason" ]; then
        log_ok "Skipped: $reason"
        return 0
    fi
    if swap_done; then
        log_ok "$SWAPFILE already set up"
        return 0
    fi
    if [ "${SWAP_CREATE:-no}" != yes ]; then
        log_info "Skipped: swap file not wanted"
        return 0
    fi
    create_swapfile
    add_to_fstab
    tune_sysctl
}

module_main "$@"
