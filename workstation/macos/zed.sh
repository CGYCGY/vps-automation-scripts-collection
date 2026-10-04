#!/bin/bash
# Merges zed-settings.json into Zed's settings. Only values that differ from
# Zed's defaults are tracked; every other key the Mac has stays.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

ZED_DEFAULTS="$MACOS_DIR/zed-settings.json"
ZED_SETTINGS="$HOME/.config/zed/settings.json"

zed_installed() { [ -d /Applications/Zed.app ] || brew list --cask zed >/dev/null 2>&1; }

defaults_set() {
    [ -s "$ZED_SETTINGS" ] && have jq &&
        jsonc_to_json "$ZED_SETTINGS" | jq -e --slurpfile d "$ZED_DEFAULTS" '. == (. * $d[0])' >/dev/null 2>&1
}

module_status() {
    if ! zed_installed; then status_row zed-settings skipped "Zed not installed"
    elif defaults_set; then status_row zed-settings present "defaults set"
    else status_row zed-settings missing "will merge defaults into $ZED_SETTINGS"; fi
}

module_plan() { require_user; }

module_auto() {
    log_step "Zed settings"
    if ! zed_installed; then
        log_ok "Zed not installed, skipped"
        return 0
    fi
    if defaults_set; then
        log_ok "Zed defaults already set"
        return 0
    fi
    have jq || brew install jq
    local tmp
    tmp="$(mktemp)"
    if [ -s "$ZED_SETTINGS" ]; then
        jsonc_to_json "$ZED_SETTINGS" | jq --slurpfile d "$ZED_DEFAULTS" '. * $d[0]' > "$tmp" || {
            rm -f "$tmp"
            log_error "$ZED_SETTINGS could not be parsed, left untouched"
            return 1
        }
        # The rewrite drops the file's comments, so keep the original.
        cp "$ZED_SETTINGS" "$ZED_SETTINGS.backup.$(date +%Y%m%d%H%M%S)"
    else
        mkdir -p "$(dirname "$ZED_SETTINGS")"
        jq . "$ZED_DEFAULTS" > "$tmp"
    fi
    cat "$tmp" > "$ZED_SETTINGS"
    rm -f "$tmp"
    log_ok "Merged Zed defaults into $ZED_SETTINGS"
}

module_main "$@"
