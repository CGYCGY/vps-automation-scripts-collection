# ============================================
# Project Navigation with Tab Completion
# ============================================
# A Bash utility to quickly navigate between your development projects
# with tab completion support.
#
# Author: Community Contribution
# License: MIT
#
# Requirements: Bash 4.0+ (for associative arrays)
#
# Installation:
#   Add to your ~/.bashrc:
#   source /path/to/project-navigator.sh
#
# Usage:
#   cdp                    list projects
#   cdp <name>             jump to project
#   cdp add <name> [path]  add/update project (default: cwd), saved to this file
#   cdp rm <name>          remove project, saved to this file
# ============================================

# Absolute path of this file; `cdp add`/`cdp rm` rewrite the PROJECTS block in it
_PN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Define your projects here (or use `cdp add`)
# Format: ['shortname']='/full/path/to/project'
declare -gA PROJECTS=(
    ['myapp']="$HOME/Projects/my-app"
    ['website']="$HOME/Projects/my-website"
    ['backend']="$HOME/Projects/backend-api"
    ['frontend']="$HOME/Projects/frontend-app"
)

# Rewrite the PROJECTS block in this file (add or remove one entry), then re-source.
# Keeps a single rolling backup at <file>.bak.
_pn_persist() {
    local op="$1" name="$2" path="$3"
    awk -v op="$op" -v name="$name" -v path="$path" '
        /^declare -gA PROJECTS=\(/ { inblock=1; print; next }
        inblock && /^\)/ {
            if (op == "add") printf "    [\047%s\047]=\"%s\"\n", name, path
            inblock=0; print; next
        }
        inblock && index($0, "[\047" name "\047]") { next }
        { print }
    ' "$_PN_FILE" > "$_PN_FILE.tmp" || { rm -f "$_PN_FILE.tmp"; return 1; }
    cp "$_PN_FILE" "$_PN_FILE.bak" && mv "$_PN_FILE.tmp" "$_PN_FILE" && source "$_PN_FILE"
}

_pn_list() {
    echo ""
    echo -e "\033[36mAvailable Projects:\033[0m"
    for key in $(echo "${!PROJECTS[@]}" | tr ' ' '\n' | sort); do
        printf "  \033[33m%-10s -> %s\033[0m\n" "$key" "${PROJECTS[$key]}"
    done
}

cdp() {
    local cmd="$1"

    case "$cmd" in
        "")
            _pn_list; return 0 ;;
        add)
            local name="$2" path="${3:-$PWD}"
            if [[ -z "$name" || "$name" == add || "$name" == rm ]]; then
                echo -e "\033[31mUsage: cdp add <name> [path]\033[0m"; return 1
            fi
            path="$(cd "$path" 2>/dev/null && pwd)" || { echo -e "\033[31m✗ Not a directory: ${3:-$PWD}\033[0m"; return 1; }
            local verb="Added"; [[ -v PROJECTS[$name] ]] && verb="Updated"
            _pn_persist add "$name" "$path" || return 1
            echo -e "\033[32m✓ $verb '$name' -> $path\033[0m"; return 0 ;;
        rm)
            local name="$2"
            if [[ -z "$name" || ! -v PROJECTS[$name] ]]; then
                echo -e "\033[31m✗ Project '$name' not found\033[0m"; return 1
            fi
            _pn_persist rm "$name" || return 1
            echo -e "\033[32m✓ Removed '$name'\033[0m"; return 0 ;;
    esac

    if [[ -v PROJECTS[$cmd] ]]; then
        cd "${PROJECTS[$cmd]}" || return 1
        echo -e "\033[32m✓ Switched to: $cmd\033[0m"
    else
        echo -e "\033[31m✗ Project '$cmd' not found\033[0m"
        echo -e "\033[90mRun 'cdp' to see available projects, 'cdp add <name>' to add one\033[0m"
        return 1
    fi
}

# Tab completion for cdp
_cdp_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if (( COMP_CWORD == 1 )); then
        COMPREPLY=($(compgen -W "add rm ${!PROJECTS[*]}" -- "$cur"))
    elif [[ "${COMP_WORDS[1]}" == rm && COMP_CWORD == 2 ]]; then
        COMPREPLY=($(compgen -W "${!PROJECTS[*]}" -- "$cur"))
    elif [[ "${COMP_WORDS[1]}" == add && COMP_CWORD == 3 ]]; then
        COMPREPLY=($(compgen -d -- "$cur"))
    fi
}

complete -F _cdp_completions cdp
