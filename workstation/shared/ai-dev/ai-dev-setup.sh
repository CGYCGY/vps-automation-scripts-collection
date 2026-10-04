#!/usr/bin/env bash
# Bootstraps a VPS or local box with the AI coding-agent toolchain.
#
# Detection-driven: a preflight pass surveys the machine, prints what is already
# present and what it will install, and only then acts. Re-running on a finished
# machine does nothing. A crash mid-run is resumable — progress is recorded, and
# the record is deleted once everything succeeds.
#
# This script only ever INSTALLS what is missing; it never updates what is
# already there. Updating is `upd`'s job. After a successful run it offers to
# set up the agent skills (workstation/shared/skills/skills.sh).
#
#   ./ai-dev-setup.sh               survey, show the plan, ask, then install
#   ./ai-dev-setup.sh -y            same, without the confirmation prompt
#   ./ai-dev-setup.sh --upgrade     also run a full apt dist-upgrade
#   ./ai-dev-setup.sh --status      survey only, change nothing
#   ./ai-dev-setup.sh --force       reinstall everything, ignoring detection
#   ./ai-dev-setup.sh --reset       discard a crashed run's saved progress
#   ./ai-dev-setup.sh --no-skills   don't offer the agent skills at the end
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
# jq: the Claude status line parses every render with it, and the settings merge
# below needs it to edit settings.json without clobbering the other keys.
APT_PACKAGES=(ca-certificates curl gnupg lsb-release git unzip man-db libatomic1 jq)

# "name|full definition line". Merged in one at a time: an alias already defined
# in ~/.bash_aliases is left exactly as the device has it, never rewritten.
ALIAS_DEFS=(
    'cc|alias cc="claude --dangerously-skip-permissions"'
    'aa|alias aa="agy --dangerously-skip-permissions"'
    'pa|alias pa="prime-agent"'
    'upd|alias upd="claude update && codex update && pi update && prime-agent update && herdr update && agy update && agent-browser upgrade"'
    'dc|alias dc="docker compose"'
    'jj|alias jj="just"'
)
# Project navigation (cdp): install and fallback copy live in the shared helper,
# which the projects module uses too.
# shellcheck source=../../../shared/lib/project-navigator-lib.sh
. "${SCRIPT_DIR}/../../../shared/lib/project-navigator-lib.sh"
pn_init bash

# "repository filename|user destination". These stay as separate files because
# each agent needs a different model identifier and may gain tool-specific rules.
INSTRUCTION_FILES=(
    "CLAUDE.md|$HOME/.claude/CLAUDE.md"
    "AGENTS.md|$HOME/.codex/AGENTS.md"
    "GEMINI.md|$HOME/.gemini/GEMINI.md"
)

# The script is overwritten whenever it differs from the tracked copy, like the
# instruction files; the settings entry is only added when settings.json has no
# statusLine at all, so a device's own status line is never replaced.
STATUSLINE_SRC="${SCRIPT_DIR}/claude/statusline-command.sh"
STATUSLINE_FILE="$HOME/.claude/statusline-command.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# Defaults merged into each agent's own settings. Only settings chosen on
# purpose; model and effort stay out because they change too often.
CLAUDE_DEFAULTS="${SCRIPT_DIR}/agent-settings/claude-settings.json"
CODEX_DEFAULTS="${SCRIPT_DIR}/agent-settings/codex-config.toml"
CODEX_CONFIG="$HOME/.codex/config.toml"
PI_DEFAULTS="${SCRIPT_DIR}/agent-settings/pi-settings.json"
PI_SETTINGS="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/new-device-setup"
STATE_FILE="${STATE_DIR}/in-progress"
LOG_FILE="${STATE_DIR}/setup.log"

# Guards the blocks appended to ~/.bashrc and ~/.bash_aliases, so the script
# cannot duplicate them even if its saved progress is lost.
MARKER_BEGIN="# >>> new-device-setup >>>"
MARKER_END="# <<< new-device-setup <<<"

STEPS=(apt-packages nvm node bun shell-path claude codex pi prime-agent herdr agy npm-allow-scripts agent-browser agent-instructions claude-statusline agent-settings aliases project-navigator)

OPT_YES=0; OPT_UPGRADE=0; OPT_FORCE=0; OPT_STATUS=0; OPT_SKILLS=1

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

# Chrome for Testing publishes no Linux ARM64 build, so `agent-browser install`
# has nothing to download there and would stop the whole run. The step, and the
# npm allow-scripts entry that exists only for it, are skipped instead, unless
# agent-browser is already fully installed.
AB_SKIP_REASON="Chrome for Testing has no Linux ARM64 build"
AB_SKIP_NOTE="agent-browser skipped: ${AB_SKIP_REASON}. Install a browser yourself if you need it (see https://github.com/vercel-labs/agent-browser)"

no_browser_build() {
    [ "$(uname -s)" = Linux ] || return 1
    case "$(uname -m)" in aarch64|arm64) return 0 ;; esac
    return 1
}

agent_browser_installed() {
    have agent-browser && compgen -G "$HOME/.agent-browser/browsers/*" >/dev/null
}

skip_agent_browser() { no_browser_build && ! agent_browser_installed; }

#############################################
# DETECTION
#   Each detect_* sets DETAIL and returns 0 when the component is already set up,
#   2 when it is skipped on this machine, 1 when it needs installing.
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

# The CLI drives nothing on its own: Chrome for Testing is a separate per-user
# download under ~/.agent-browser/browsers, so a CLI without it counts as absent.
detect_agent_browser() {
    if ! have agent-browser; then
        DETAIL="not on PATH"
    else
        DETAIL="$(tool_version agent-browser)"
        [ -n "$DETAIL" ] || DETAIL="installed"
        compgen -G "$HOME/.agent-browser/browsers/*" >/dev/null && return 0
        DETAIL="${DETAIL}, no browser binaries"
    fi
    if skip_agent_browser; then
        DETAIL="$AB_SKIP_REASON"
        return 2
    fi
    return 1
}

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

# Grep, not jq: detection runs before the apt step that installs jq.
SL_NEED_FILE=0
SL_NEED_SETTING=0

detect_claude_statusline() {
    SL_NEED_FILE=0; SL_NEED_SETTING=0
    cmp -s "$STATUSLINE_SRC" "$STATUSLINE_FILE" 2>/dev/null || SL_NEED_FILE=1
    grep -q '"statusLine"' "$CLAUDE_SETTINGS" 2>/dev/null || SL_NEED_SETTING=1

    if [ "$SL_NEED_FILE" -eq 0 ] && [ "$SL_NEED_SETTING" -eq 0 ]; then
        DETAIL="script matches, statusLine set"
        return 0
    fi
    local what=""
    [ "$SL_NEED_FILE" -eq 1 ]    && what+="install/update the script, "
    [ "$SL_NEED_SETTING" -eq 1 ] && what+="add statusLine to settings.json"
    DETAIL="will ${what%, }"
    return 1
}

# npm 11 skips install scripts of global packages not on this list, and
# agent-browser's sets up its native binary. Comma-separated.
detect_npm_allow_scripts() {
    load_nvm
    if ! have npm; then
        DETAIL="will allow agent-browser's install script"
    else
        case ",$(npm config get allow-scripts 2>/dev/null | tr -d ' ')," in
            *,agent-browser,*) DETAIL="agent-browser allowed"; return 0 ;;
        esac
        DETAIL="will add agent-browser to npm allow-scripts"
    fi
    if skip_agent_browser; then
        DETAIL="only for agent-browser; $AB_SKIP_REASON"
        return 2
    fi
    return 1
}

# Line-based merge of the tracked Codex defaults into ~/.codex/config.toml,
# printed to stdout: no TOML writer can be assumed on a fresh device. Our keys
# replace the device's (a multi-line array value is replaced whole), missing
# keys go at the end of their table, missing tables at the end of the file,
# and every other line — tables Codex adds itself included — is left as is.
merge_codex_config() {
    local target="$2"
    [ -f "$target" ] || target=/dev/null
    awk '
        function key_of(s) {
            if (s !~ /^[ \t]*[A-Za-z0-9_-]+[ \t]*=/) return ""
            sub(/^[ \t]*/, "", s); sub(/[ \t]*=.*/, "", s); return s
        }
        function table_of(s) {
            sub(/^[ \t]*\[+[ \t]*/, "", s); sub(/[ \t]*\]+[ \t]*(#.*)?$/, "", s); return s
        }
        function is_header(s) { return s ~ /^[ \t]*\[/ }
        NR == FNR {
            if (is_header($0)) { tbl = table_of($0); if (!(tbl in seen)) { seen[tbl] = 1; tbls[++ntbl] = tbl }; next }
            k = key_of($0); if (k == "") next
            if (!(tbl in seen)) { seen[tbl] = 1; tbls[++ntbl] = tbl }
            def[tbl, k] = $0; order[tbl, ++nk[tbl]] = k
            next
        }
        FNR == 1 { tbl = "" }
        {
            line[++n] = $0
            if (skipping) { drop[n] = 1; if ($0 ~ /\]/) skipping = 0; next }
            if (is_header($0)) { tbl = table_of($0); has[tbl] = 1; anchor[tbl] = n; next }
            k = key_of($0); if (k == "") next
            anchor[tbl] = n
            if ((tbl, k) in def) {
                line[n] = def[tbl, k]; done[tbl, k] = 1
                v = $0; sub(/^[^=]*=[ \t]*/, "", v)
                if (v ~ /^\[/ && v !~ /\]/) skipping = 1
            }
        }
        END {
            for (i = 1; i <= ntbl; i++) {
                t = tbls[i]; pend[t] = ""
                for (j = 1; j <= nk[t]; j++) { k = order[t, j]; if (!((t, k) in done)) pend[t] = pend[t] def[t, k] "\n" }
            }
            if (pend[""] != "" && !("" in anchor)) { printf "%s", pend[""]; if (n > 0) print "" }
            for (i = 1; i <= n; i++) {
                if (!(i in drop)) print line[i]
                for (t in anchor) if (anchor[t] == i && pend[t] != "") printf "%s", pend[t]
            }
            for (i = 1; i <= ntbl; i++) {
                t = tbls[i]
                if (t != "" && !(t in has) && pend[t] != "") printf "\n[%s]\n%s", t, pend[t]
            }
        }
    ' "$1" "$target"
}

AS_NEED_CLAUDE=0
AS_NEED_CODEX=0
AS_NEED_PI=0

# True when merging the JSON defaults $1 into $2 would change nothing. Without
# jq this can't be checked, so it counts as pending; the merge is a no-op then.
json_defaults_set() {
    have jq && [ -s "$2" ] && jq -e --slurpfile d "$1" '. == (. * $d[0])' "$2" >/dev/null 2>&1
}

# Present when merging the defaults in would change nothing.
detect_agent_settings() {
    AS_NEED_CLAUDE=0; AS_NEED_CODEX=0; AS_NEED_PI=0
    json_defaults_set "$CLAUDE_DEFAULTS" "$CLAUDE_SETTINGS" || AS_NEED_CLAUDE=1
    json_defaults_set "$PI_DEFAULTS" "$PI_SETTINGS" || AS_NEED_PI=1
    merge_codex_config "$CODEX_DEFAULTS" "$CODEX_CONFIG" | cmp -s - "$CODEX_CONFIG" 2>/dev/null || AS_NEED_CODEX=1

    if [ "$AS_NEED_CLAUDE" -eq 0 ] && [ "$AS_NEED_CODEX" -eq 0 ] && [ "$AS_NEED_PI" -eq 0 ]; then
        DETAIL="Claude, Codex and pi defaults set"
        return 0
    fi
    local what=""
    [ "$AS_NEED_CLAUDE" -eq 1 ] && what+="Claude settings.json, "
    [ "$AS_NEED_CODEX" -eq 1 ]  && what+="Codex config.toml, "
    [ "$AS_NEED_PI" -eq 1 ]     && what+="pi settings.json"
    DETAIL="will merge defaults into ${what%, }"
    return 1
}

detect_project_navigator() {
    if pn_detect; then
        DETAIL="cdp ready, $(pn_count) project(s) registered"
        return 0
    fi
    local what=""
    [ "$PN_NEED_FILE" -eq 1 ]   && what+="install $PN_SHOW "
    [ "$PN_NEED_SOURCE" -eq 1 ] && what+="source it from $PN_RC_SHOW"
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
# Prime Intellect's installer asks twice, and its prompts read /dev/tty directly,
# so neither a pipe nor an env var can answer them: PRIME_AGENT_INSTALLER_
# NONINTERACTIVE covers only the native-binary path, and the npm confirmation has
# no override at all. Taking the controlling terminal away is the supported way
# through — each prompt reports no terminal and proceeds with its default. The
# survey confirmation above is this script's consent point; re-asking per vendor
# is noise. Run through a file, not a pipe: redirecting stdin to /dev/null would
# otherwise leave sh reading an empty script. setsid needs -w or it forks and the
# next step races this one.
install_prime_agent() {
    load_nvm
    local installer rc=0
    installer="$(mktemp)"
    curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh -o "$installer"
    if have setsid; then
        PRIME_AGENT_INSTALLER_NONINTERACTIVE=1 PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 \
            setsid -w sh "$installer" < /dev/null || rc=$?
    else
        PRIME_AGENT_INSTALLER_NONINTERACTIVE=1 PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 \
            sh "$installer" || rc=$?
    fi
    rm -f "$installer"
    return "$rc"
}
install_herdr()       { curl -fsSL https://herdr.dev/install.sh | sh; }

install_agy() {
    curl -fsSL https://antigravity.google/cli/install.sh | bash
    hash -r
    have agy && agy install
}

install_agent_browser() {
    load_nvm
    npm i -g agent-browser
    hash -r
    # Chrome for Testing downloads into ~/.agent-browser, but headless Chrome also
    # needs shared libraries a minimal server image omits; --with-deps installs
    # them and fails loudly rather than leaving a browser that cannot start.
    agent-browser install --with-deps
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

install_claude_statusline() {
    mkdir -p "$(dirname "$STATUSLINE_FILE")"
    if [ "$SL_NEED_FILE" -eq 1 ]; then
        backup_once "$STATUSLINE_FILE"
        install -m 0755 "$STATUSLINE_SRC" "$STATUSLINE_FILE"
        log_ok "installed statusline-command.sh -> $STATUSLINE_FILE"
    fi
    if [ "$SL_NEED_SETTING" -eq 1 ]; then
        local cmd="bash $STATUSLINE_FILE" tmp
        tmp="$(mktemp)"
        if [ -s "$CLAUDE_SETTINGS" ]; then
            backup_once "$CLAUDE_SETTINGS"
            jq --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd, padding: 0}' \
                "$CLAUDE_SETTINGS" > "$tmp" \
                || { rm -f "$tmp"; log_error "$CLAUDE_SETTINGS is not valid JSON — left untouched"; return 1; }
        else
            jq -n --arg cmd "$cmd" '{statusLine: {type: "command", command: $cmd, padding: 0}}' > "$tmp"
        fi
        mv "$tmp" "$CLAUDE_SETTINGS"
        log_ok "statusLine added to $CLAUDE_SETTINGS"
    fi
}

install_npm_allow_scripts() {
    load_nvm
    local cur
    cur="$(npm config get allow-scripts --location=user 2>/dev/null | tr -d ' ')"
    case ",$cur," in *,agent-browser,*) return 0 ;; esac
    backup_once "$HOME/.npmrc"
    npm config set "allow-scripts=${cur:+$cur,}agent-browser" --location=user
    log_ok "npm allow-scripts: ${cur:+$cur,}agent-browser"
}

# Our keys win; every other key the device has stays. Written with cat, not
# mv, so the file keeps its permissions. $1 defaults, $2 target, $3 agent name.
merge_json_defaults() {
    local tmp
    tmp="$(mktemp)"
    if [ -s "$2" ]; then
        jq --slurpfile d "$1" '. * $d[0]' "$2" > "$tmp" \
            || { rm -f "$tmp"; log_error "$2 is not valid JSON — left untouched"; return 1; }
    else
        jq . "$1" > "$tmp"
    fi
    if ! cmp -s "$tmp" "$2"; then
        backup_once "$2"
        mkdir -p "$(dirname "$2")"
        cat "$tmp" > "$2"
        log_ok "merged $3 defaults into $2"
    fi
    rm -f "$tmp"
}

install_agent_settings() {
    merge_json_defaults "$CLAUDE_DEFAULTS" "$CLAUDE_SETTINGS" Claude || return 1
    merge_json_defaults "$PI_DEFAULTS" "$PI_SETTINGS" pi || return 1

    local tmp
    tmp="$(mktemp)"
    merge_codex_config "$CODEX_DEFAULTS" "$CODEX_CONFIG" > "$tmp"
    if ! cmp -s "$tmp" "$CODEX_CONFIG"; then
        backup_once "$CODEX_CONFIG"
        mkdir -p "$(dirname "$CODEX_CONFIG")"
        cat "$tmp" > "$CODEX_CONFIG"
        log_ok "merged Codex defaults into $CODEX_CONFIG"
    fi
    rm -f "$tmp"
}

# Populate the registry with `cdp add <name>` or the projects module.
install_project_navigator() { pn_install; }

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
SKIPPED=()

is_skipped() { case " ${SKIPPED[*]:-} " in *" $1 "*) return 0 ;; esac; return 1; }

survey() {
    PLAN=()
    SKIPPED=()
    echo
    echo "${C_BOLD}Survey${C_RESET}"
    printf '  %-18s %-9s %s\n' "COMPONENT" "STATUS" "DETAIL"
    local s fn rc
    for s in "${STEPS[@]}"; do
        fn="detect_${s//-/_}"
        DETAIL=""
        rc=0
        if [ "$OPT_FORCE" -eq 1 ]; then
            # A reinstall would hit the same missing download.
            case "$s" in
                agent-browser|npm-allow-scripts) no_browser_build && { rc=2; DETAIL="$AB_SKIP_REASON"; } ;;
            esac
            [ "$rc" -eq 2 ] || rc=3
        else
            "$fn" || rc=$?
        fi
        case "$rc" in
            0)  printf '  %-18s %b%-9s%b %s%s%s\n' "$s" "$C_GREEN" "present" "$C_RESET" "$C_DIM" "$DETAIL" "$C_RESET" ;;
            2)  SKIPPED+=("$s")
                printf '  %-18s %b%-9s%b %s\n' "$s" "$C_DIM" "skipped" "$C_RESET" "$DETAIL" ;;
            3)  PLAN+=("$s")
                printf '  %-18s %b%-9s%b %s\n' "$s" "$C_YELLOW" "forced" "$C_RESET" "reinstall requested" ;;
            *)  PLAN+=("$s")
                printf '  %-18s %b%-9s%b %s\n' "$s" "$C_YELLOW" "install" "$C_RESET" "$DETAIL" ;;
        esac
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
    for t in claude codex pi prime-agent herdr agy agent-browser; do
        if is_skipped "$t"; then
            printf '  %b %-14s %s\n' "${C_DIM}-${C_RESET}" "$t" "skipped: $AB_SKIP_REASON"
        elif have "$t"; then
            v="$(tool_version "$t")"
            printf '  %b %-14s %s\n' "${C_GREEN}✓${C_RESET}" "$t" "${v:-ok}"
        else
            printf '  %b %-14s %s\n' "${C_RED}✗${C_RESET}" "$t" "not on PATH — open a new shell and re-check"
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
  npm i -g agent-device @cometix/ccline wrangler
  bun add -g dispatch
  curl -LsSf https://astral.sh/uv/install.sh | sh
  sudo apt install -y gh

${C_BOLD}Config worth copying from the old device:${C_RESET}
  The shared Claude, Codex, and Antigravity instructions and the Claude status
  line are already installed.
  Copy private credentials and remaining tool state separately when needed.

${C_BOLD}Project navigator:${C_RESET} installed from https://github.com/CGYCGY/shell-utils
EOF
}

skip_notes() {
    is_skipped agent-browser || return 0
    echo
    log_warn "$AB_SKIP_NOTE"
}

# Not in the standalone bundle: skills.sh needs the rest of the repository.
SKILLS_SCRIPT="${SCRIPT_DIR}/../skills/skills.sh"

offer_skills() {
    [ "$OPT_SKILLS" -eq 1 ] || return 0
    if [ ! -f "$SKILLS_SCRIPT" ]; then
        log_info "agent skills are set up by workstation/shared/skills/skills.sh, from a checkout of the repository"
        return 0
    fi
    local ans=y
    if [ "$OPT_YES" -ne 1 ]; then
        if [ -t 0 ]; then
            read -r -p "Set up the agent skills too? [Y/n] " ans || ans=n
        elif ( : < /dev/tty ) 2>/dev/null; then
            read -r -p "Set up the agent skills too? [Y/n] " ans < /dev/tty || ans=n
        else
            log_info "no terminal to ask about the agent skills; run workstation/shared/skills/skills.sh later"
            return 0
        fi
    fi
    case "$ans" in [nN]|[nN][oO]) return 0 ;; esac
    set --
    [ "$OPT_YES" -eq 1 ] && set -- -y
    # SETUP_GO answers skills.sh's own "Start the setup?": the user just said yes.
    SETUP_GO=yes bash "$SKILLS_SCRIPT" "$@" ||
        log_warn "the agent skills setup failed; run workstation/shared/skills/skills.sh again"
}

#############################################
# MAIN
#############################################

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)    OPT_YES=1 ;;
        --upgrade)   OPT_UPGRADE=1 ;;
        --force)     OPT_FORCE=1 ;;
        --status)    OPT_STATUS=1 ;;
        --no-skills) OPT_SKILLS=0 ;;
        --reset)     rm -f "$STATE_FILE"; log_ok "saved progress discarded"; exit 0 ;;
        -h|--help)   awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
        *)           log_error "unknown option: $1"; exit 1 ;;
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
    skip_notes
    offer_skills
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
skip_notes
offer_skills
