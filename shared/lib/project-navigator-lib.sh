#!/bin/bash
# The cdp project navigator from CGYCGY/shell-utils: installing it, and
# registering projects in its PROJECTS block. Sourced by the ai-dev setups and
# the projects module; the caller provides log_info, log_ok, log_warn and
# log_error.
#
# Must stay bash 3.2 compatible and safe under `set -euo pipefail`.

PN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# pn_init zsh|bash. macOS gets the zsh edition, Linux the bash one. Upstream is
# fetched first so a new machine gets the current version; the copies in
# workstation/shared/ai-dev/ are the offline fallback, and the standalone
# bundles carry them at the same relative path. Refresh them now and then:
#   curl -fsSL $PN_URL -o $PN_FALLBACK
pn_init() {
    local ai_dev="$PN_LIB_DIR/../../workstation/shared/ai-dev"
    case "$1" in
        zsh)
            PN_URL="https://raw.githubusercontent.com/CGYCGY/shell-utils/master/zsh/profile-scripts/project-navigator.zsh"
            PN_FALLBACK="$ai_dev/macos/project-navigator.zsh"
            PN_FILE="$HOME/.zsh/project-navigator.zsh"
            PN_SHOW="~/.zsh/project-navigator.zsh"
            PN_RC="$HOME/.zshrc"
            PN_RC_SHOW="~/.zshrc"
            PN_DECL="typeset -gA PROJECTS=("
            ;;
        bash)
            PN_URL="https://raw.githubusercontent.com/CGYCGY/shell-utils/master/bash/profile-scripts/project-navigator.sh"
            PN_FALLBACK="$ai_dev/project-navigator.sh"
            PN_FILE="$HOME/.project-navigator.sh"
            PN_SHOW="~/.project-navigator.sh"
            PN_RC="$HOME/.bashrc"
            PN_RC_SHOW="~/.bashrc"
            PN_DECL="declare -gA PROJECTS=("
            ;;
        *) log_error "pn_init: unknown flavour '$1'"; return 1 ;;
    esac
    PN_FLAVOUR="$1"
    PN_NEED_FILE=0
    PN_NEED_SOURCE=0
}

# Two independent halves: the file, and the shell rc sourcing it. Either can
# already be in place on its own, so both are checked and pn_install only does
# the missing half. True when both are in place.
pn_detect() {
    PN_NEED_FILE=0; PN_NEED_SOURCE=0
    [ -f "$PN_FILE" ] || PN_NEED_FILE=1
    grep -qF "$(basename "$PN_FILE")" "$PN_RC" 2>/dev/null || PN_NEED_SOURCE=1
    [ "$PN_NEED_FILE" -eq 0 ] && [ "$PN_NEED_SOURCE" -eq 0 ]
}

pn_count() {
    local n
    n="$(grep -c "^[[:space:]]*\['" "$PN_FILE" 2>/dev/null || true)"
    echo "${n:-0}"
}

# The upstream registry is example paths, so it is emptied on the way in. An
# existing file is never replaced: it holds that machine's own registry.
pn_install() {
    if [ "$PN_NEED_FILE" -eq 1 ]; then
        local src tmp
        tmp="$(mktemp)"
        if curl -fsSL --retry 3 --max-time 30 "$PN_URL" -o "$tmp" 2>/dev/null; then
            src="$tmp"; log_info "fetched $(basename "$PN_FILE") from shell-utils"
        elif [ -f "$PN_FALLBACK" ]; then
            src="$PN_FALLBACK"; log_warn "upstream unreachable — using the bundled copy"
        else
            rm -f "$tmp"; log_error "could not fetch $PN_URL and no bundled copy at $PN_FALLBACK"; return 1
        fi
        grep -qF "$PN_DECL" "$src" \
            || { rm -f "$tmp"; log_error "no PROJECTS block in $(basename "$PN_FILE") — upstream changed shape"; return 1; }
        mkdir -p "$(dirname "$PN_FILE")"
        awk -v decl="$PN_DECL" '
            index($0, decl) == 1 { print; inblock=1; next }
            inblock && /^\)/      { print; inblock=0; next }
            inblock               { next }
                                  { print }' "$src" > "$PN_FILE"
        rm -f "$tmp"
        log_ok "installed $PN_SHOW with an empty registry — add projects with 'cdp add <name>'"
    else
        log_warn "$PN_SHOW already exists — left untouched"
    fi

    if [ "$PN_NEED_SOURCE" -eq 1 ]; then
        _pn_backup "$PN_RC"
        if [ "$PN_FLAVOUR" = zsh ]; then
            # cdp registers its tab completion with compdef, which needs compinit.
            # Left out when ~/.zshrc (or a framework like oh-my-zsh) already runs it.
            local compinit_line='autoload -Uz compinit && compinit -C'
            grep -qE 'compinit|oh-my-zsh\.sh' "$PN_RC" 2>/dev/null && compinit_line=""
            {
                echo
                echo "# >>> new-device-setup: cdp >>>"
                [ -n "$compinit_line" ] && echo "$compinit_line"
                echo '[ -f "$HOME/.zsh/project-navigator.zsh" ] && source "$HOME/.zsh/project-navigator.zsh"'
                echo "# <<< new-device-setup: cdp <<<"
            } >> "$PN_RC"
        else
            cat >> "$PN_RC" <<'EOF'

# >>> new-device-setup: cdp >>>
[ -f "$HOME/.project-navigator.sh" ] && . "$HOME/.project-navigator.sh"
# <<< new-device-setup: cdp <<<
EOF
        fi
        log_ok "$PN_RC_SHOW now sources the project navigator"
    fi
}

_pn_backup() {
    local f="$1" b
    [ -f "$f" ] || return 0
    b="${f}.backup.$(date +%Y%m%d_%H%M%S)"
    [ -f "$b" ] || cp "$f" "$b"
    log_warn "backed up $(basename "$f") -> $(basename "$b")"
}

# Prints "name<TAB>path" for each registered project, as written in the file.
pn_entries() {
    [ -f "$PN_FILE" ] || return 0
    awk -v decl="$PN_DECL" '
        index($0, decl) == 1 { inblock=1; next }
        inblock && /^\)/      { inblock=0; next }
        inblock && match($0, /^[ \t]*\[\047[^\047]*\047\]=/) {
            name = substr($0, RSTART, RLENGTH)
            sub(/^[ \t]*\[\047/, "", name); sub(/\047\]=$/, "", name)
            val = substr($0, RSTART + RLENGTH)
            if (val ~ /^".*"$/ || val ~ /^\047.*\047$/) val = substr(val, 2, length(val) - 2)
            print name "\t" val
        }' "$PN_FILE"
}

# pn_register NAME PATH [NAME PATH ...]: one rewrite of the PROJECTS block for
# the whole batch. Entries not in the batch stay as they are; a name whose path
# changed is updated in place; missing names are appended. Nothing is written
# when nothing changes. Keeps a single rolling <file>.bak, like `cdp add`.
pn_register() {
    [ $# -ge 2 ] || return 0
    [ -f "$PN_FILE" ] || { log_error "$PN_SHOW is not installed"; return 1; }
    grep -qF "$PN_DECL" "$PN_FILE" || { log_error "no PROJECTS block in $PN_SHOW"; return 1; }
    local batch counts
    batch="$(mktemp)"; counts="$(mktemp)"
    while [ $# -ge 2 ]; do
        printf '%s\t%s\n' "$1" "$2" >> "$batch"
        shift 2
    done
    awk -F'\t' -v decl="$PN_DECL" -v counts="$counts" '
        NR == FNR { want[$1] = $2; order[++n] = $1; next }
        index($0, decl) == 1 { inblock=1; print; next }
        inblock && /^\)/ {
            for (i = 1; i <= n; i++)
                if (!(order[i] in seen)) {
                    printf "    [\047%s\047]=\"%s\"\n", order[i], want[order[i]]; added++
                }
            inblock=0; print; next
        }
        inblock && match($0, /^[ \t]*\[\047[^\047]*\047\]=/) {
            name = substr($0, RSTART, RLENGTH)
            sub(/^[ \t]*\[\047/, "", name); sub(/\047\]=$/, "", name)
            if (name in want) {
                seen[name] = 1
                if (substr($0, RSTART + RLENGTH) != "\"" want[name] "\"") {
                    printf "    [\047%s\047]=\"%s\"\n", name, want[name]; updated++
                    next
                }
            }
        }
        { print }
        END { print added + 0, updated + 0 > counts }
    ' "$batch" "$PN_FILE" > "$PN_FILE.tmp" || { rm -f "$batch" "$counts" "$PN_FILE.tmp"; return 1; }
    local added updated
    read -r added updated < "$counts"
    rm -f "$batch" "$counts"
    if cmp -s "$PN_FILE.tmp" "$PN_FILE"; then
        rm -f "$PN_FILE.tmp"
        log_ok "cdp names already registered in $PN_SHOW"
        return 0
    fi
    cp "$PN_FILE" "$PN_FILE.bak" && mv "$PN_FILE.tmp" "$PN_FILE"
    log_ok "cdp names in $PN_SHOW: $added added, $updated updated (previous copy: $(basename "$PN_FILE").bak)"
}
