# ============================================
# Project Navigation with Tab Completion
# ============================================
# A Zsh utility to quickly navigate between your development projects
# with tab completion and description support.
#
# Author: Community Contribution
# License: MIT
#
# Installation:
#   Add to your ~/.zshrc:
#   source /path/to/project-navigator.zsh
#
# If using oh-my-zsh, you can also place this in:
#   ~/.oh-my-zsh/custom/project-navigator.zsh
#
# Usage:
#   cdp                    list projects
#   cdp <name>             jump to project
#   cdp add <name> [path]  add/update project (default: cwd), saved to this file
#   cdp rm <name>          remove project, saved to this file
# ============================================

# Absolute path of this file; `cdp add`/`cdp rm` rewrite the PROJECTS block in it
_PN_FILE="${${(%):-%x}:A}"

# Define your projects here (or use `cdp add`)
# Format: ['shortname']='/full/path/to/project'
typeset -gA PROJECTS=(
    ['myapp']="$HOME/Projects/my-app"
    ['website']="$HOME/Projects/my-website"
    ['backend']="$HOME/Projects/backend-api"
    ['frontend']="$HOME/Projects/frontend-app"
)

# Rewrite the PROJECTS block in this file (add or remove one entry), then re-source.
# NB: never name a local "path" in zsh, it is tied to $PATH.
# Keeps a single rolling backup at <file>.bak.
_pn_persist() {
    local op="$1" name="$2" dir="$3"
    awk -v op="$op" -v name="$name" -v dir="$dir" '
        /^typeset -gA PROJECTS=\(/ { inblock=1; print; next }
        inblock && /^\)/ {
            if (op == "add") printf "    [\047%s\047]=\"%s\"\n", name, dir
            inblock=0; print; next
        }
        inblock && index($0, "[\047" name "\047]") { next }
        { print }
    ' "$_PN_FILE" > "$_PN_FILE.tmp" || { rm -f "$_PN_FILE.tmp"; return 1; }
    cp "$_PN_FILE" "$_PN_FILE.bak" && mv "$_PN_FILE.tmp" "$_PN_FILE" && source "$_PN_FILE"
}

_pn_list() {
    echo ""
    print -P "%F{cyan}Available Projects:%f"
    for key in ${(ko)PROJECTS}; do
        printf "  %s%-10s -> %s%s\n" $'\e[33m' "$key" "${PROJECTS[$key]}" $'\e[0m'
    done
}

cdp() {
    local cmd="$1"

    case "$cmd" in
        "")
            _pn_list; return 0 ;;
        add)
            local name="$2" dir="${3:-$PWD}"
            if [[ -z "$name" || "$name" == add || "$name" == rm ]]; then
                print -P "%F{red}Usage: cdp add <name> [path]%f"; return 1
            fi
            dir="$(cd "$dir" 2>/dev/null && pwd)" || { print -P "%F{red}✗ Not a directory: ${3:-$PWD}%f"; return 1; }
            local verb="Added"; (( ${+PROJECTS[$name]} )) && verb="Updated"
            _pn_persist add "$name" "$dir" || return 1
            print -P "%F{green}✓ $verb '$name' -> $dir%f"; return 0 ;;
        rm)
            local name="$2"
            if [[ -z "$name" ]] || (( ! ${+PROJECTS[$name]} )); then
                print -P "%F{red}✗ Project '$name' not found%f"; return 1
            fi
            _pn_persist rm "$name" || return 1
            print -P "%F{green}✓ Removed '$name'%f"; return 0 ;;
    esac

    if (( ${+PROJECTS[$cmd]} )); then
        cd "${PROJECTS[$cmd]}" || return 1
        print -P "%F{green}✓ Switched to: $cmd%f"
    else
        print -P "%F{red}✗ Project '$cmd' not found%f"
        print -P "%F{242}Run 'cdp' to see available projects, 'cdp add <name>' to add one%f"
        return 1
    fi
}

# Tab completion for cdp with descriptions
_cdp() {
    local -a project_list
    for key in ${(k)PROJECTS}; do
        project_list+=("$key:${PROJECTS[$key]}")
    done

    if (( CURRENT == 2 )); then
        local -a subcmds=('add:add or update a project' 'rm:remove a project')
        _describe -t commands 'command' subcmds
        _describe -t projects 'project' project_list
    elif [[ "${words[2]}" == rm && CURRENT == 3 ]]; then
        _describe 'project' project_list
    elif [[ "${words[2]}" == add && CURRENT == 4 ]]; then
        _files -/
    fi
}

compdef _cdp cdp
