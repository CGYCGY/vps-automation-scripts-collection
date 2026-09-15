#!/usr/bin/env bash
# Bootstraps a VPS or local box with the AI coding-agent toolchain.
#
# Detection-driven: a preflight pass surveys the machine, prints what is already
# present and what it will install, and only then acts. Re-running on a finished
# machine does nothing. A crash mid-run is resumable — progress is recorded, and
# the record is deleted once everything succeeds.
#
# This script only ever INSTALLS what is missing; it never updates what is
# already there. Updating is `upd`'s job.
#
#   ./ai-dev-setup.sh             survey, show the plan, ask, then install
#   ./ai-dev-setup.sh -y          same, without the confirmation prompt
#   ./ai-dev-setup.sh --upgrade   also run a full apt dist-upgrade
#   ./ai-dev-setup.sh --status    survey only, change nothing
#   ./ai-dev-setup.sh --force     reinstall everything, ignoring detection
#   ./ai-dev-setup.sh --reset     discard a crashed run's saved progress
#
# Versions float to latest by default. Pin by editing the two lines below, or
# per-run:  NODE_VERSION=25.2.1 NVM_VERSION=v0.40.7 ./ai-dev-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTRUCTIONS_DIR="${SCRIPT_DIR}/agent-instructions"

NODE_VERSION="${NODE_VERSION:-node}"   # "node" = latest release; or "24", "25.2.1", "--lts"
NVM_VERSION="${NVM_VERSION:-}"         # empty = resolve nvm's latest tag; or "v0.40.7"

# libatomic1 is not optional: every node build links libatomic.so.1, and minimal
# images ship without it — nvm unpacks fine and the first npm-based agent then
# dies on a linker error that names neither node nor the package.
APT_PACKAGES=(ca-certificates curl gnupg lsb-release git unzip man-db libatomic1)

# "name|full definition line". Merged in one at a time: an alias already defined
# in ~/.bash_aliases is left exactly as the device has it, never rewritten.
ALIAS_DEFS=(
    'cc|alias cc="claude --dangerously-skip-permissions"'
    'aa|alias aa="agy --dangerously-skip-permissions"'
    'pa|alias pa="prime-agent"'
    'upd|alias upd="claude update && codex update && pi update && prime-agent update && herdr update && agy update"'
    'dc|alias dc="docker compose"'
    'jj|alias jj="just"'
)
# Project navigation (cdp) is maintained in CGYCGY/shell-utils. Upstream is
# fetched first so a new box gets the current version; the copy beside this
# script is the offline fallback. Refresh it now and then:
#   curl -fsSL $PN_URL -o ai-dev/project-navigator.sh
PN_URL="https://raw.githubusercontent.com/CGYCGY/shell-utils/master/bash/profile-scripts/project-navigator.sh"
PN_FALLBACK="${SCRIPT_DIR}/project-navigator.sh"
PN_FILE="$HOME/.project-navigator.sh"

# "repository filename|user destination". These stay as separate files because
# each agent needs a different model identifier and may gain tool-specific rules.
INSTRUCTION_FILES=(
    "CLAUDE.md|$HOME/.claude/CLAUDE.md"
    "AGENTS.md|$HOME/.codex/AGENTS.md"
    "GEMINI.md|$HOME/.gemini/GEMINI.md"
)

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/new-device-setup"
STATE_FILE="${STATE_DIR}/in-progress"
LOG_FILE="${STATE_DIR}/setup.log"

# Guards the blocks appended to ~/.bashrc and ~/.bash_aliases, so the script
# cannot duplicate them even if its saved progress is lost.
MARKER_BEGIN="# >>> new-device-setup >>>"
MARKER_END="# <<< new-device-setup <<<"

STEPS=(apt-packages nvm node bun shell-path claude codex pi prime-agent herdr agy agent-instructions aliases project-navigator)

OPT_YES=0; OPT_UPGRADE=0; OPT_FORCE=0; OPT_STATUS=0

#############################################
# OUTPUT
#############################################

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'; C_CYAN=$'\033[0;36m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_DIM=""; C_BOLD=""
fi

log_info()  { echo "${C_CYAN}[ .. ]${C_RESET} $*"; }
log_ok()    { echo "${C_GREEN}[ ok ]${C_RESET} $*"; }
log_warn()  { echo "${C_YELLOW}[warn]${C_RESET} $*"; }
log_error() { echo "${C_RED}[fail]${C_RESET} $*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# One timestamped copy per run, before this script changes an existing user file.
backup_once() {
    local f="$1"
    [ -f "$f" ] || return 0
    local b="${f}.backup.$(date +%Y%m%d_%H%M%S)"
    [ -f "$b" ] || cp "$f" "$b"
    log_warn "backed up $(basename "$f") -> $(basename "$b")"
}

# nvm's scripts trip `set -u`, so every load is fenced.
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    set +u
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    set -u
}

tool_version() { timeout 10 "$1" --version 2>/dev/null | head -1 | tr -d '\r'; }

#############################################
# DETECTION
#   Each detect_* sets DETAIL and returns 0 when the component is already set up.
#   No network, no side effects — safe to run on any machine at any time.
#############################################

DETAIL=""
MISSING_PKGS=()
MISSING_ALIASES=()

detect_apt_packages() {
    MISSING_PKGS=()
    local p
    for p in "${APT_PACKAGES[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || MISSING_PKGS+=("$p")
    done
    if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
        DETAIL="all ${#APT_PACKAGES[@]} present"
        return 0
    fi
    DETAIL="missing: ${MISSING_PKGS[*]}"
    return 1
}

detect_nvm() {
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        DETAIL="$HOME/.nvm"
        return 0
    fi
    DETAIL="will install $( [ -n "$NVM_VERSION" ] && echo "$NVM_VERSION" || echo "latest tag" )"
    return 1
}

detect_node() {
    load_nvm
    if have node; then
        DETAIL="$(node --version 2>/dev/null)"
        return 0
    fi
    DETAIL="will install ${NODE_VERSION}"
    return 1
}

detect_bun() {
    if [ -x "$HOME/.bun/bin/bun" ]; then
        DETAIL="$("$HOME/.bun/bin/bun" --version 2>/dev/null)"
        return 0
    fi
    DETAIL="will install latest"
    return 1
}

# Also accepts a hand-configured ~/.bashrc: what matters is that the three paths
# are exported, not that this script was the one to write them.
detect_shell_path() {
    if grep -qF "$MARKER_BEGIN" "$HOME/.bashrc" 2>/dev/null; then
        DETAIL="block present in ~/.bashrc"
        return 0
    fi
    if grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null \
       && grep -q 'BUN_INSTALL' "$HOME/.bashrc" 2>/dev/null \
       && grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        DETAIL="already configured by hand in ~/.bashrc"
        return 0
    fi
    DETAIL="will append PATH block to ~/.bashrc"
    return 1
}

detect_aliases() {
    MISSING_ALIASES=()
    local entry name
    for entry in "${ALIAS_DEFS[@]}"; do
        name="${entry%%|*}"
        grep -qE "^[[:space:]]*alias[[:space:]]+${name}=" "$HOME/.bash_aliases" 2>/dev/null \
            || MISSING_ALIASES+=("$entry")
    done
    if [ ${#MISSING_ALIASES[@]} -eq 0 ]; then
        DETAIL="all ${#ALIAS_DEFS[@]} present"
        return 0
    fi
    local names=""
    for entry in "${MISSING_ALIASES[@]}"; do names+="${entry%%|*} "; done
    DETAIL="will add: ${names% }"
    return 1
}

# The six tools all detect the same way: on PATH or not.
detect_tool() {
    if have "$1"; then
        DETAIL="$(tool_version "$1")"
        [ -n "$DETAIL" ] || DETAIL="installed"
        return 0
    fi
    DETAIL="not on PATH"
    return 1
}

detect_claude()      { detect_tool claude; }
detect_codex()       { detect_tool codex; }
detect_pi()          { detect_tool pi; }
detect_prime_agent() { detect_tool prime-agent; }
detect_herdr()       { detect_tool herdr; }
detect_agy()         { detect_tool agy; }

detect_agent_instructions() {
    local entry filename target pending=()
    for entry in "${INSTRUCTION_FILES[@]}"; do
        filename="${entry%%|*}"
        target="${entry#*|}"
        cmp -s "$INSTRUCTIONS_DIR/$filename" "$target" 2>/dev/null || pending+=("$filename")
    done
    if [ ${#pending[@]} -eq 0 ]; then
        DETAIL="all ${#INSTRUCTION_FILES[@]} files match"
        return 0
    fi
    DETAIL="will install/update: ${pending[*]}"
    return 1
}

# Two independent halves: the file, and ~/.bashrc sourcing it. Either can already
# be in place on its own, so both are checked and only the missing half is done.
PN_NEED_FILE=0
PN_NEED_SOURCE=0

detect_project_navigator() {
    PN_NEED_FILE=0; PN_NEED_SOURCE=0
    [ -f "$PN_FILE" ] || PN_NEED_FILE=1
    grep -q 'project-navigator\.sh' "$HOME/.bashrc" 2>/dev/null || PN_NEED_SOURCE=1

    if [ "$PN_NEED_FILE" -eq 0 ] && [ "$PN_NEED_SOURCE" -eq 0 ]; then
        local n
        n="$(grep -c "^[[:space:]]*\['" "$PN_FILE" 2>/dev/null || true)"
        DETAIL="cdp ready, ${n:-0} project(s) registered"
        return 0
    fi

    local what=""
    [ "$PN_NEED_FILE" -eq 1 ]   && what+="install ~/.project-navigator.sh "
    [ "$PN_NEED_SOURCE" -eq 1 ] && what+="source it from ~/.bashrc"
    DETAIL="will ${what% }"
    return 1
}

#############################################
# INSTALLERS
#############################################

install_apt_packages() {
    sudo apt update
    [ ${#MISSING_PKGS[@]} -gt 0 ] && sudo apt install -y "${MISSING_PKGS[@]}"
    return 0
}

# Falls back to master when the GitHub API is unreachable or rate-limited,
# so an anonymous API hiccup cannot fail the whole run.
resolve_nvm_ref() {
    if [ -n "$NVM_VERSION" ]; then echo "$NVM_VERSION"; return; fi
    local tag
    tag=$(curl -fsS --max-time 10 https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null \
          | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1) || true
    if [ -n "${tag:-}" ]; then echo "$tag"; else echo "master"; fi
}

install_nvm() {
    local ref
    ref="$(resolve_nvm_ref)"
    log_info "installing nvm ${ref}"
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${ref}/install.sh" | bash
}

install_node() {
    load_nvm
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    nvm use default
}

install_bun() {
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
}

install_shell_path() {
    mkdir -p "$HOME/.local/bin"
    backup_once "$HOME/.bashrc"
    cat >> "$HOME/.bashrc" <<EOF

${MARKER_BEGIN}
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \\. "\$NVM_DIR/bash_completion"

export BUN_INSTALL="\$HOME/.bun"
export PATH="\$BUN_INSTALL/bin:\$PATH"
export PATH="\$HOME/.local/bin:\$PATH"

[ -f "\$HOME/.bash_aliases" ] && . "\$HOME/.bash_aliases"
${MARKER_END}
EOF
}

install_claude()      { curl -fsSL https://claude.ai/install.sh | bash; }
install_codex()       { load_nvm; npm i -g @openai/codex; }
install_pi()          { bun add -g @earendil-works/pi-coding-agent; }
install_prime_agent() { load_nvm; curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | sh; }
install_herdr()       { curl -fsSL https://herdr.dev/install.sh | sh; }

install_agy() {
    curl -fsSL https://antigravity.google/cli/install.sh | bash
    hash -r
    have agy && agy install
}

install_agent_instructions() {
    local entry filename target
    for entry in "${INSTRUCTION_FILES[@]}"; do
        filename="${entry%%|*}"
        target="${entry#*|}"
        if ! cmp -s "$INSTRUCTIONS_DIR/$filename" "$target" 2>/dev/null; then
            backup_once "$target"
            mkdir -p "$(dirname "$target")"
            install -m 0644 "$INSTRUCTIONS_DIR/$filename" "$target"
            log_ok "installed $filename -> $target"
        fi
    done
}

# The upstream registry is example paths, so it is emptied on the way in —
# populate with `cdp add <name>`, which rewrites the file in place. An existing
# file is never touched: it holds that device's own registry.
install_project_navigator() {
    if [ "$PN_NEED_FILE" -eq 1 ]; then
        local src tmp
        tmp="$(mktemp)"
        if curl -fsSL --max-time 30 "$PN_URL" -o "$tmp" 2>/dev/null; then
            src="$tmp"; log_info "fetched project-navigator.sh from shell-utils"
        elif [ -f "$PN_FALLBACK" ]; then
            src="$PN_FALLBACK"; log_warn "upstream unreachable — using the bundled copy"
        else
            rm -f "$tmp"; log_error "could not fetch $PN_URL and no bundled copy at $PN_FALLBACK"; return 1
        fi
        grep -q '^declare -gA PROJECTS=(' "$src" \
            || { rm -f "$tmp"; log_error "no PROJECTS block in project-navigator.sh — upstream changed shape"; return 1; }
        awk '/^declare -gA PROJECTS=\(/ { print; inblock=1; next }
             inblock && /^\)/          { print; inblock=0; next }
             inblock                    { next }
                                        { print }' "$src" > "$PN_FILE"
        rm -f "$tmp"
        log_ok "installed ~/.project-navigator.sh with an empty registry — add projects with 'cdp add <name>'"
    else
        log_warn "~/.project-navigator.sh already exists — left untouched"
    fi

    if [ "$PN_NEED_SOURCE" -eq 1 ]; then
        backup_once "$HOME/.bashrc"
        cat >> "$HOME/.bashrc" <<'EOF'

# >>> new-device-setup: cdp >>>
[ -f "$HOME/.project-navigator.sh" ] && . "$HOME/.project-navigator.sh"
# <<< new-device-setup: cdp <<<
EOF
        log_ok "~/.bashrc now sources the project navigator"
    fi
}

install_aliases() {
    backup_once "$HOME/.bash_aliases"
    local entry
    {
        echo
        echo "${MARKER_BEGIN}"
        for entry in "${MISSING_ALIASES[@]}"; do
            echo "${entry#*|}"
        done
        echo "${MARKER_END}"
    } >> "$HOME/.bash_aliases"
    log_ok "merged ${#MISSING_ALIASES[@]} alias(es); existing ones left untouched"
}

#############################################
# PREFLIGHT
#############################################

PLAN=()

survey() {
    PLAN=()
    echo
    echo "${C_BOLD}Survey${C_RESET}"
    printf '  %-18s %-9s %s\n' "COMPONENT" "STATUS" "DETAIL"
    local s fn
    for s in "${STEPS[@]}"; do
        fn="detect_${s//-/_}"
        DETAIL=""
        if [ "$OPT_FORCE" -eq 1 ]; then
            PLAN+=("$s")
            printf '  %-18s %b%-9s%b %s\n' "$s" "$C_YELLOW" "forced" "$C_RESET" "reinstall requested"
        elif "$fn"; then
            printf '  %-18s %b%-9s%b %s%s%s\n' "$s" "$C_GREEN" "present" "$C_RESET" "$C_DIM" "$DETAIL" "$C_RESET"
        else
            PLAN+=("$s")
            printf '  %-18s %b%-9s%b %s\n' "$s" "$C_YELLOW" "install" "$C_RESET" "$DETAIL"
        fi
    done
    echo
}

confirm() {
    [ "$OPT_YES" -eq 1 ] && return 0
    local ans prompt="Install the ${#PLAN[@]} component(s) above? [y/N] "
    # Piped into bash (curl ... | bash, or the standalone bundle) stdin carries
    # the script itself, so the answer has to come from the terminal directly.
    # /dev/tty passes -r yet fails to open when there is no controlling terminal,
    # so the open is attempted in a subshell that can absorb the failure.
    if [ -t 0 ]; then
        read -r -p "$prompt" ans
    elif ( : < /dev/tty ) 2>/dev/null; then
        read -r -p "$prompt" ans < /dev/tty
    else
        log_error "no terminal to prompt on — re-run with -y to proceed unattended"
        exit 1
    fi
    case "$ans" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) echo "Nothing done."; exit 0 ;;
    esac
}

#############################################
# EXECUTION
#############################################

on_error() {
    local code=$?
    log_error "step failed (exit ${code}). Nothing was rolled back."
    log_error "Progress is saved — fix the cause and re-run; finished work is detected and skipped."
    log_error "Log: ${LOG_FILE}"
    exit "$code"
}

run_plan() {
    trap on_error ERR
    local s
    for s in "${PLAN[@]}"; do
        # Saved progress only short-circuits steps within a crashed run; on a fresh
        # run detection has already decided, so this is a cheap second guard.
        if grep -qxF "$s" "$STATE_FILE" 2>/dev/null; then
            log_warn "$s — already done in the interrupted run, skipping"
            continue
        fi
        log_info "$s"
        "install_${s//-/_}"
        printf '%s\n' "$s" >> "$STATE_FILE"
        hash -r
        log_ok "$s"
    done
    trap - ERR
}

report() {
    echo
    echo "${C_BOLD}Installed:${C_RESET}"
    local t v
    for t in claude codex pi prime-agent herdr agy; do
        if have "$t"; then
            v="$(tool_version "$t")"
            printf '  %b %-12s %s\n' "${C_GREEN}✓${C_RESET}" "$t" "${v:-ok}"
        else
            printf '  %b %-12s %s\n' "${C_RED}✗${C_RESET}" "$t" "not on PATH — open a new shell and re-check"
        fi
    done
    cat <<EOF

${C_BOLD}Still to do by hand — each tool authenticates separately:${C_RESET}
  claude          browser OAuth
  codex login     browser OAuth
  agy             browser OAuth (Google)
  pi              API key
  prime-agent     API key
  herdr           see: herdr --help

${C_BOLD}Then:${C_RESET}
  exec bash -l    reload the shell
  upd             confirm every tool updates
  cdp add <name>  register this device's projects (the registry starts empty)

${C_BOLD}Optional extras (not covered by upd):${C_RESET}
  npm i -g agent-browser agent-device @cometix/ccline wrangler
  bun add -g dispatch
  curl -LsSf https://astral.sh/uv/install.sh | sh
  sudo apt install -y gh

${C_BOLD}Config worth copying from the old device:${C_RESET}
  The shared Claude, Codex, and Antigravity instructions are already installed.
  Copy private credentials and remaining tool state separately when needed.

${C_BOLD}Project navigator:${C_RESET} installed from https://github.com/CGYCGY/shell-utils
EOF
}

#############################################
# MAIN
#############################################

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)   OPT_YES=1 ;;
        --upgrade)  OPT_UPGRADE=1 ;;
        --force)    OPT_FORCE=1 ;;
        --status)   OPT_STATUS=1 ;;
        --reset)    rm -f "$STATE_FILE"; log_ok "saved progress discarded"; exit 0 ;;
        -h|--help)  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
        *)          log_error "unknown option: $1"; exit 1 ;;
    esac
    shift
done

mkdir -p "$STATE_DIR"

# The tools install into these; put them on PATH so detection sees them
# on a resumed run, before ~/.bashrc has been reloaded.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"

if [ -s "$STATE_FILE" ]; then
    log_warn "a previous run was interrupted after: $(tr '\n' ' ' < "$STATE_FILE")"
fi

survey

if [ "$OPT_STATUS" -eq 1 ]; then
    echo "${C_DIM}--status: nothing was changed.${C_RESET}"
    exit 0
fi

if [ ${#PLAN[@]} -eq 0 ] && [ "$OPT_UPGRADE" -eq 0 ]; then
    log_ok "everything is already set up — nothing to do"
    rm -f "$STATE_FILE"
    exit 0
fi

[ ${#PLAN[@]} -gt 0 ] && confirm

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') — installing: ${PLAN[*]:-none} ==="

if [ "$OPT_UPGRADE" -eq 1 ]; then
    log_info "apt dist-upgrade"
    sudo apt update && sudo apt dist-upgrade -y
fi

run_plan

# Everything succeeded, so the crash-recovery record has no further purpose.
rm -f "$STATE_FILE"

report
echo
log_ok "done — log at ${LOG_FILE}"
