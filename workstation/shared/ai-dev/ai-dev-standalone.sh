#!/usr/bin/env bash
# AI development toolchain setup, bundled as a single self-extracting file.
#
# GENERATED FILE — do not edit. Change the sources in the repository's
# workstation/shared/ai-dev/ directory, then run ./build-standalone.sh to
# regenerate this.
#
# Unpacks to a temporary directory and runs the setup from there. Every flag is
# forwarded, so -y, --status, --upgrade, --force and --reset behave as usual.

set -euo pipefail

AI_DEV_TMP="$(mktemp -d)"
trap 'rm -rf "$AI_DEV_TMP"' EXIT
mkdir -p "$AI_DEV_TMP/workstation/shared/ai-dev" "$AI_DEV_TMP/shared/lib" "$AI_DEV_TMP/workstation/shared/ai-dev/agent-instructions" "$AI_DEV_TMP/workstation/shared/ai-dev/claude" "$AI_DEV_TMP/workstation/shared/ai-dev/agent-settings"

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/ai-dev-setup.sh" <<'AI_DEV_PAYLOAD_EOF'
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

# The CLI drives nothing on its own: Chrome for Testing is a separate per-user
# download under ~/.agent-browser/browsers, so a CLI without it counts as absent.
detect_agent_browser() {
    if ! have agent-browser; then
        DETAIL="not on PATH"
        return 1
    fi
    DETAIL="$(tool_version agent-browser)"
    [ -n "$DETAIL" ] || DETAIL="installed"
    if ! compgen -G "$HOME/.agent-browser/browsers/*" >/dev/null; then
        DETAIL="${DETAIL}, no browser binaries"
        return 1
    fi
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
        return 1
    fi
    case ",$(npm config get allow-scripts 2>/dev/null | tr -d ' ')," in
        *,agent-browser,*) DETAIL="agent-browser allowed"; return 0 ;;
    esac
    DETAIL="will add agent-browser to npm allow-scripts"
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
    for t in claude codex pi prime-agent herdr agy agent-browser; do
        if have "$t"; then
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
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/project-navigator.sh" <<'AI_DEV_PAYLOAD_EOF'
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
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/shared/lib/project-navigator-lib.sh" <<'AI_DEV_PAYLOAD_EOF'
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
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/agent-instructions/CLAUDE.md" <<'AI_DEV_PAYLOAD_EOF'
## Commit Style

- Title: `<emoji> <type>(<scope optional>): <description>`, under 70 characters
- Emoji is required; use the mapping below (lobe-commit gitmoji set):
  - ✨ feat — introduce new features
  - 🐛 fix — fix a bug
  - ♻️ refactor — refactor code that neither fixes a bug nor adds a feature
  - ⚡ perf — code change that improves performance
  - 💄 style — add or update style files that do not affect the meaning of the code
  - ✅ test — add missing tests or correct existing tests
  - 📝 docs — documentation only changes
  - 👷 ci — changes to CI configuration files and scripts
  - 🔧 chore — other changes that don't modify src or test files
  - 📦 build — make architectural changes
- Body in point form, not the title
- Body: flat bullets; group under `<section>:` headers when multi-area
- Do not add Co-Authored-By, Claude-Session lines
- Author all commits as me

## Subagents

- Always pass `model: "opus"` when spawning subagents (Agent tool calls and Workflow `agent()` opts), unless I override for a specific task.

## Comments

- A comment must carry what the code can't — the non-obvious *why*, an external fact or gotcha, a constraint an edit could break. Cut the rest (narration, banners, JSDoc echoing the signature). Code is LLM-read, so this overrides match-surrounding-style.
- When delegating, put this in the subagent's spec — don't say "match the existing comment style."
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/agent-instructions/AGENTS.md" <<'AI_DEV_PAYLOAD_EOF'
## Commit Style

- Title: `<emoji> <type>(<scope optional>): <description>`, under 70 characters
- Emoji is required; use the mapping below (lobe-commit gitmoji set):
  - ✨ feat — introduce new features
  - 🐛 fix — fix a bug
  - ♻️ refactor — refactor code that neither fixes a bug nor adds a feature
  - ⚡ perf — code change that improves performance
  - 💄 style — add or update style files that do not affect the meaning of the code
  - ✅ test — add missing tests or correct existing tests
  - 📝 docs — documentation only changes
  - 👷 ci — changes to CI configuration files and scripts
  - 🔧 chore — other changes that don't modify src or test files
  - 📦 build — make architectural changes
- Body in point form, not the title
- Body: flat bullets; group under `<section>:` headers when multi-area
- Do not add agent/session metadata lines
- Author all commits as me

## Subagents

- Use `model: "gpt-5.6-sol"` when spawning subagents, unless I override for a specific task.
- A model override requires `fork_turns: "none"` or a bounded turn count; full-history forks inherit the parent model.

## Comments

- A comment must carry what the code can't — the non-obvious *why*, an external fact or gotcha, a constraint an edit could break. Cut the rest (narration, banners, JSDoc echoing the signature). Code is LLM-read, so this overrides match-surrounding-style.
- When delegating, put this in the subagent's spec — don't say "match the existing comment style."
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/agent-instructions/GEMINI.md" <<'AI_DEV_PAYLOAD_EOF'
## Commit Style

- Title: `<emoji> <type>(<scope optional>): <description>`, under 70 characters
- Emoji is required; use the mapping below (lobe-commit gitmoji set):
  - ✨ feat — introduce new features
  - 🐛 fix — fix a bug
  - ♻️ refactor — refactor code that neither fixes a bug nor adds a feature
  - ⚡ perf — code change that improves performance
  - 💄 style — add or update style files that do not affect the meaning of the code
  - ✅ test — add missing tests or correct existing tests
  - 📝 docs — documentation only changes
  - 👷 ci — changes to CI configuration files and scripts
  - 🔧 chore — other changes that don't modify src or test files
  - 📦 build — make architectural changes
- Body in point form, not the title
- Body: flat bullets; group under `<section>:` headers when multi-area
- Do not add agent/session metadata lines
- Author all commits as me

## Subagents

- Use `model: "gemini-3.8-flash-medium"` when spawning subagents, unless I override for a specific task.

## Comments

- A comment must carry what the code can't — the non-obvious *why*, an external fact or gotcha, a constraint an edit could break. Cut the rest (narration, banners, JSDoc echoing the signature). Code is LLM-read, so this overrides match-surrounding-style.
- When delegating, put this in the subagent's spec — don't say "match the existing comment style."
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/claude/statusline-command.sh" <<'AI_DEV_PAYLOAD_EOF'
#!/usr/bin/env bash
# Claude Code statusLine command
# Format: <model> <effort> | <used>/<total> (<pct%>) | I:<cur>(<total>) O:<cur>(<total>) IC:<cur>(<total>) IW:<cur>(<total>) | $<cost>

input=$(cat)

# --- ANSI color codes ---
RESET='\033[0m'
CYAN_BOLD='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
MAGENTA_BOLD='\033[1;35m'
RED_BOLD='\033[1;31m'
DIM_CYAN='\033[2;36m'
DIM_YELLOW='\033[2;33m'
DIM_GREEN='\033[2;32m'
DIM_WHITE='\033[2;37m'

SEP="${DIM_WHITE} | ${RESET}"

# --- Extract fields from JSON ---
model=$(echo "$input"        | jq -r '.model.display_name // empty')
effort=$(echo "$input"       | jq -r '.effort.level // empty')
ctx_size=$(echo "$input"     | jq -r '.context_window.context_window_size // empty')
used_pct=$(echo "$input"     | jq -r '.context_window.used_percentage // empty')
cur_usage=$(echo "$input"    | jq -r '.context_window.current_usage // empty')
total_input=$(echo "$input"  | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
transcript=$(echo "$input"   | jq -r '.transcript_path // empty')
cost_usd=$(echo "$input"     | jq -r '.cost.total_cost_usd // empty')

input_tokens=0
output_tokens=0
cache_read_tokens=0
cache_write_tokens=0

if [ -n "$cur_usage" ] && [ "$cur_usage" != "null" ]; then
    input_tokens=$(echo "$input"       | jq -r '.context_window.current_usage.input_tokens // 0')
    output_tokens=$(echo "$input"      | jq -r '.context_window.current_usage.output_tokens // 0')
    cache_read_tokens=$(echo "$input"  | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
    cache_write_tokens=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
fi

# --- Parse transcript for cumulative IC/IW totals (with delta cache) ---
# Cache file keyed by transcript path. Stores "size:ic:iw" so subsequent
# renders only parse newly-appended bytes instead of re-slurping the whole
# transcript. Self-heals on parse failure or transcript truncation.
total_ic=0
total_iw=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    # wc/cksum rather than stat -c/md5sum: the same file is installed on macOS,
    # whose BSD stat takes different flags and which ships no md5sum.
    current_size=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ' || echo 0)
    cache_key=$(printf '%s' "$transcript" | cksum | awk '{print $1}')
    cache_file="/tmp/statusline-cache-${cache_key}"

    cached_size=0
    cached_ic=0
    cached_iw=0
    if [ -f "$cache_file" ]; then
        IFS=: read -r cached_size cached_ic cached_iw < "$cache_file" || true
        cached_size=${cached_size:-0}
        cached_ic=${cached_ic:-0}
        cached_iw=${cached_iw:-0}
    fi

    sum_jq='
        map(select(.message.usage != null) | .message.usage) |
        {
            ic: ([.[].cache_read_input_tokens // 0] | add // 0),
            iw: ([.[].cache_creation_input_tokens // 0] | add // 0)
        }
    '

    if [ "$current_size" = "$cached_size" ] && [ "$cached_size" -gt 0 ]; then
        total_ic=$cached_ic
        total_iw=$cached_iw
    else
        scan_ok=0
        # Incremental: parse only the new tail bytes
        if [ "$current_size" -gt "$cached_size" ] && [ "$cached_size" -gt 0 ]; then
            delta=$((current_size - cached_size))
            tail_totals=$(head -c "$current_size" "$transcript" 2>/dev/null | tail -c "$delta" | jq -s "$sum_jq" 2>/dev/null)
            if [ -n "$tail_totals" ]; then
                new_ic=$(echo "$tail_totals" | jq -r '.ic // 0')
                new_iw=$(echo "$tail_totals" | jq -r '.iw // 0')
                total_ic=$((cached_ic + new_ic))
                total_iw=$((cached_iw + new_iw))
                scan_ok=1
            fi
        fi
        # Fallback: full rescan (no cache, transcript shrank, or tail parse failed)
        if [ "$scan_ok" = "0" ]; then
            full_totals=$(head -c "$current_size" "$transcript" 2>/dev/null | jq -s "$sum_jq" 2>/dev/null)
            if [ -n "$full_totals" ]; then
                total_ic=$(echo "$full_totals" | jq -r '.ic // 0')
                total_iw=$(echo "$full_totals" | jq -r '.iw // 0')
                scan_ok=1
            fi
        fi
        # Atomic cache write (only on successful scan)
        if [ "$scan_ok" = "1" ]; then
            tmp_cache="${cache_file}.tmp.$$"
            if printf '%s:%s:%s\n' "$current_size" "$total_ic" "$total_iw" > "$tmp_cache" 2>/dev/null; then
                mv "$tmp_cache" "$cache_file" 2>/dev/null || rm -f "$tmp_cache"
            fi
        fi
    fi
fi

# --- Helper: abbreviate token number to K/M ---
fmt_tokens() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" = "null" ]; then echo "0"; return; fi
    awk -v n="$n" 'BEGIN {
        if (n >= 1000000)   { printf "%.2fM\n", n/1000000 }
        else if (n >= 1000) { printf "%.2fK\n", n/1000 }
        else                { printf "%d\n", n }
    }'
}

# --- Build output ---

# Model name: bold cyan
if [ -n "$model" ]; then
    out="${CYAN_BOLD}${model}${RESET}"
else
    out="${CYAN_BOLD}(no model)${RESET}"
fi

# Effort: small tag after model. Ascending intensity ramp across the
# Claude Code levels: low < medium < high < xhigh < max, plus the
# session-only `ultracode` mode (xhigh reasoning + dynamic workflows).
if [ -n "$effort" ]; then
    case "$effort" in
        low)       eff_color="$DIM_WHITE" ;;
        medium)    eff_color="$GREEN" ;;
        high)      eff_color="$YELLOW" ;;
        xhigh)     eff_color="$MAGENTA" ;;
        max)       eff_color="$RED_BOLD" ;;
        ultracode) eff_color="$MAGENTA_BOLD" ;;
        *)         eff_color="$DIM_WHITE" ;;
    esac
    out="${out} ${eff_color}${effort}${RESET}"
fi

# Context: used/total (pct%)  — green, yellow when >75%
if [ -n "$ctx_size" ] && [ "$ctx_size" != "0" ]; then
    cur_ctx=$(( input_tokens + cache_read_tokens + cache_write_tokens ))
    used_fmt=$(fmt_tokens "$cur_ctx")
    total_fmt=$(fmt_tokens "$ctx_size")
    ctx_color="$GREEN"
    if [ -n "$used_pct" ]; then
        used_int=${used_pct%.*}
        [ "$used_int" -gt 75 ] 2>/dev/null && ctx_color="$YELLOW"
        pct_str=" (${used_int}%)"
    else
        pct_str=""
    fi
    out="${out}${SEP}${ctx_color}${used_fmt}/${total_fmt}${pct_str}${RESET}"
fi

# Token detail: I O IC IW — each with current(total)
if [ -n "$cur_usage" ] && [ "$cur_usage" != "null" ]; then
    i_fmt=$(fmt_tokens  "$input_tokens")
    it_fmt=$(fmt_tokens "$total_input")
    o_fmt=$(fmt_tokens  "$output_tokens")
    ot_fmt=$(fmt_tokens "$total_output")
    ic_fmt=$(fmt_tokens "$cache_read_tokens")
    ict_fmt=$(fmt_tokens "$total_ic")
    iw_fmt=$(fmt_tokens "$cache_write_tokens")
    iwt_fmt=$(fmt_tokens "$total_iw")

    detail="${BLUE}I:${i_fmt}(${it_fmt})${RESET}"
    detail="${detail}${DIM_WHITE}, ${RESET}${MAGENTA}O:${o_fmt}(${ot_fmt})${RESET}"
    detail="${detail}${DIM_WHITE}, ${RESET}\033[0;36mIC:${ic_fmt}(${ict_fmt})${RESET}"
    detail="${detail}${DIM_WHITE}, ${RESET}${YELLOW}IW:${iw_fmt}(${iwt_fmt})${RESET}"
    out="${out}${SEP}${detail}"
fi

# Cost: $X.XX — dim green
if [ -n "$cost_usd" ] && [ "$cost_usd" != "null" ]; then
    cost_fmt=$(awk -v c="$cost_usd" 'BEGIN { printf "$%.2f\n", c }')
    out="${out}${SEP}${DIM_GREEN}${cost_fmt}${RESET}"
fi

printf '%b\n' "$out"
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/agent-settings/claude-settings.json" <<'AI_DEV_PAYLOAD_EOF'
{
  "permissions": {
    "defaultMode": "auto"
  },
  "enableWorkflows": false,
  "workflowKeywordTriggerEnabled": false,
  "feedbackDrafts": "off",
  "promptSuggestionEnabled": false,
  "awaySummaryEnabled": false,
  "skipDangerousModePermissionPrompt": true,
  "theme": "dark",
  "autoCompactEnabled": false,
  "agentPushNotifEnabled": true,
  "enabledPlugins": {
    "warp@claude-code-warp": true
  },
  "extraKnownMarketplaces": {
    "claude-code-warp": {
      "source": {
        "source": "github",
        "repo": "warpdotdev/claude-code-warp"
      }
    }
  }
}
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/agent-settings/codex-config.toml" <<'AI_DEV_PAYLOAD_EOF'
personality = "pragmatic"
model_verbosity = "medium"

[features]
fast_mode = false
daemon_auto_start = false

[tui]
status_line = ["model-with-reasoning", "run-state", "context-window-size", "context-used", "total-input-tokens", "total-output-tokens", "used-tokens", "task-progress", "estimated-thread-cost"]
status_line_use_colors = true
show_tooltips = false
screen_reader_detection_done = true
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/workstation/shared/ai-dev/agent-settings/pi-settings.json" <<'AI_DEV_PAYLOAD_EOF'
{
  "compaction": {
    "enabled": false
  },
  "enableInstallTelemetry": false,
  "treeFilterMode": "all",
  "theme": "dark",
  "terminal": {
    "showTerminalProgress": true
  }
}
AI_DEV_PAYLOAD_EOF

chmod +x "$AI_DEV_TMP/workstation/shared/ai-dev/ai-dev-setup.sh"
# Run rather than exec: exec would drop the trap that cleans the unpacked copy.
"$AI_DEV_TMP/workstation/shared/ai-dev/ai-dev-setup.sh" "$@"
