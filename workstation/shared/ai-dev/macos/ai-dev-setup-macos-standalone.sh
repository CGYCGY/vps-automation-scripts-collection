#!/usr/bin/env bash
# AI development toolchain setup for macOS, bundled as a single self-extracting file.
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
mkdir -p "$AI_DEV_TMP/macos" "$AI_DEV_TMP/agent-instructions" "$AI_DEV_TMP/claude" "$AI_DEV_TMP/agent-settings"

cat > "$AI_DEV_TMP/macos/ai-dev-setup-macos.sh" <<'AI_DEV_PAYLOAD_EOF'
#!/usr/bin/env bash
# Bootstraps a Mac with the AI coding-agent toolchain — the macOS counterpart of
# ../ai-dev-setup.sh. Homebrew instead of apt, zsh (~/.zshrc) instead of bash.
#
# Detection-driven: a preflight pass surveys the machine, prints what is already
# present and what it will install, and only then acts. Re-running on a finished
# machine does nothing. A crash mid-run is resumable — progress is recorded, and
# the record is deleted once everything succeeds.
#
# This script only ever INSTALLS what is missing; it never updates what is
# already there. Updating is `upd`'s job.
#
#   ./ai-dev-setup-macos.sh                     survey, show the plan, ask, then install
#   ./ai-dev-setup-macos.sh -y                  same, without the confirmation prompt
#   ./ai-dev-setup-macos.sh --upgrade           also run brew update && brew upgrade
#   ./ai-dev-setup-macos.sh --status            survey only, change nothing
#   ./ai-dev-setup-macos.sh --force             reinstall everything, ignoring detection
#   ./ai-dev-setup-macos.sh --reset             discard a crashed run's saved progress
#
# Versions float to latest by default. Pin by editing the two lines below, or
# per-run:  NODE_VERSION=25.2.1 NVM_VERSION=v0.40.7 ./ai-dev-setup-macos.sh
#
# Written for the bash 3.2 that macOS ships: no associative arrays, and no
# `set -u`, because 3.2 treats "${empty_array[@]}" as an unbound variable.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
INSTRUCTIONS_DIR="${SCRIPT_DIR}/../agent-instructions"

NODE_VERSION="${NODE_VERSION:-node}"   # "node" = latest release; or "24", "25.2.1", "--lts"
NVM_VERSION="${NVM_VERSION:-}"         # empty = resolve nvm's latest tag; or "v0.40.7"

ZSHRC="$HOME/.zshrc"
ZPROFILE="$HOME/.zprofile"

# "name|full definition line". Merged in one at a time: an alias already defined
# in ~/.zshrc is left exactly as the device has it, never rewritten.
ALIAS_DEFS=(
    'cc|alias cc="claude --dangerously-skip-permissions"'
    'aa|alias aa="agy --dangerously-skip-permissions"'
    'pa|alias pa="prime-agent"'
    'upd|alias upd="claude update && codex update && pi update && prime-agent update && herdr update && agy update && agent-browser upgrade"'
    'dc|alias dc="docker compose"'
    'jj|alias jj="just"'
)

# Project navigation (cdp) is maintained in CGYCGY/shell-utils; macOS gets the
# zsh edition. Upstream is fetched first so a new Mac gets the current version;
# the copy beside this script is the offline fallback. Refresh it now and then:
#   curl -fsSL $PN_URL -o workstation/shared/ai-dev/macos/project-navigator.zsh
PN_URL="https://raw.githubusercontent.com/CGYCGY/shell-utils/master/zsh/profile-scripts/project-navigator.zsh"
PN_FALLBACK="${SCRIPT_DIR}/project-navigator.zsh"
PN_FILE="$HOME/.zsh/project-navigator.zsh"

# Shared with the Linux script.
INSTRUCTION_FILES=(
    "CLAUDE.md|$HOME/.claude/CLAUDE.md"
    "AGENTS.md|$HOME/.codex/AGENTS.md"
    "GEMINI.md|$HOME/.gemini/GEMINI.md"
)

# Shared with the Linux script. The script is overwritten whenever it differs
# from the tracked copy; the settings entry is only added when settings.json has
# no statusLine at all, so a device's own status line is never replaced.
STATUSLINE_SRC="${SCRIPT_DIR}/../claude/statusline-command.sh"
STATUSLINE_FILE="$HOME/.claude/statusline-command.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# Defaults merged into each agent's own settings. Only settings chosen on
# purpose; model and effort stay out because they change too often.
CLAUDE_DEFAULTS="${SCRIPT_DIR}/../agent-settings/claude-settings.json"
CODEX_DEFAULTS="${SCRIPT_DIR}/../agent-settings/codex-config.toml"
CODEX_CONFIG="$HOME/.codex/config.toml"
PI_DEFAULTS="${SCRIPT_DIR}/../agent-settings/pi-settings.json"
PI_SETTINGS="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json"

# Both of the above read files that sit beside this script in a checkout or in
# the standalone bundle. A lone copy of this script has neither, and the survey
# says so rather than reporting the step as done.
NO_SOURCES="source files missing — run ai-dev-setup-macos-standalone.sh or a checkout"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/new-device-setup"
STATE_FILE="${STATE_DIR}/in-progress"
LOG_FILE="${STATE_DIR}/setup.log"

# Guards the blocks appended to ~/.zshrc, so the script cannot duplicate them
# even if its saved progress is lost.
MARKER_BEGIN="# >>> new-device-setup >>>"
MARKER_END="# <<< new-device-setup <<<"

STEPS=(homebrew nvm node bun shell-path claude codex pi prime-agent herdr agy npm-allow-scripts agent-browser agent-instructions claude-statusline agent-settings aliases project-navigator)

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

# Vendor installers are saved to a file before running, never piped: macOS
# curl (LibreSSL) drops connections now and then, and a pipe would hand the
# shell a truncated script instead of failing.
fetch() {
    curl -fsSL --retry 3 --retry-delay 2 "$1" -o "$2"
}

run_installer() {
    local url="$1" shell="$2" tmp rc=0
    tmp="$(mktemp)"
    fetch "$url" "$tmp" || { rm -f "$tmp"; return 1; }
    "$shell" "$tmp" || rc=$?
    rm -f "$tmp"
    return "$rc"
}

load_brew() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
    done
    return 1
}

load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    return 0
}

# macOS has no timeout(1); perl ships with the OS and alarm() does the job.
with_timeout() {
    local secs="$1"; shift
    perl -e 'alarm shift; exec @ARGV or exit 127' "$secs" "$@"
}

# macOS has no setsid(1) either. Forks, detaches the child into a new session —
# so it has no controlling terminal and /dev/tty cannot be opened — and waits.
without_tty() {
    perl -MPOSIX -e '
        my $pid = fork; die "fork: $!" unless defined $pid;
        if ($pid) { waitpid($pid, 0); exit($? >> 8) }
        POSIX::setsid(); exec @ARGV or die "exec: $!"' "$@"
}

tool_version() { with_timeout 10 "$1" --version 2>/dev/null | head -1 | tr -d '\r'; }

#############################################
# DETECTION
#   Each detect_* sets DETAIL and returns 0 when the component is already set up.
#   No network, no side effects — safe to run on any machine at any time.
#############################################

DETAIL=""
MISSING_ALIASES=()

# Homebrew's installer also installs the Xcode Command Line Tools (git, make,
# compilers) when they are missing, so the two are one step.
detect_homebrew() {
    if load_brew; then
        DETAIL="$(brew --version 2>/dev/null | head -1)"
        xcode-select -p >/dev/null 2>&1 || { DETAIL="${DETAIL}, no Command Line Tools"; return 1; }
        return 0
    fi
    DETAIL="will install Homebrew (+ Command Line Tools)"
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
    DETAIL="will install ${NODE_VERSION} via nvm"
    return 1
}

detect_bun() {
    if have bun; then
        DETAIL="$(bun --version 2>/dev/null)"
        return 0
    fi
    DETAIL="will brew install bun"
    return 1
}

# Also accepts a hand-configured ~/.zshrc: what matters is that the three paths
# are exported, not that this script was the one to write them.
detect_shell_path() {
    if grep -qF "$MARKER_BEGIN" "$ZSHRC" 2>/dev/null; then
        DETAIL="block present in ~/.zshrc"
        return 0
    fi
    if grep -q 'NVM_DIR' "$ZSHRC" 2>/dev/null \
       && grep -q 'BUN_INSTALL' "$ZSHRC" 2>/dev/null \
       && grep -q '\.local/bin' "$ZSHRC" 2>/dev/null; then
        DETAIL="already configured by hand in ~/.zshrc"
        return 0
    fi
    DETAIL="will append PATH block to ~/.zshrc"
    return 1
}

detect_aliases() {
    MISSING_ALIASES=()
    local entry name
    for entry in "${ALIAS_DEFS[@]}"; do
        name="${entry%%|*}"
        grep -qE "^[[:space:]]*alias[[:space:]]+${name}=" "$ZSHRC" 2>/dev/null \
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
    if [ ! -d "$INSTRUCTIONS_DIR" ]; then
        DETAIL="$NO_SOURCES"
        return 2
    fi
    local entry filename target pending=""
    for entry in "${INSTRUCTION_FILES[@]}"; do
        filename="${entry%%|*}"
        target="${entry#*|}"
        cmp -s "$INSTRUCTIONS_DIR/$filename" "$target" 2>/dev/null || pending+="$filename "
    done
    if [ -z "$pending" ]; then
        DETAIL="all ${#INSTRUCTION_FILES[@]} files match"
        return 0
    fi
    DETAIL="will install/update: ${pending% }"
    return 1
}

# Grep, not jq: jq may not be installed until this step runs.
SL_NEED_FILE=0
SL_NEED_SETTING=0

detect_claude_statusline() {
    if [ ! -f "$STATUSLINE_SRC" ]; then
        DETAIL="$NO_SOURCES"
        return 2
    fi
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
    if [ ! -f "$CLAUDE_DEFAULTS" ] || [ ! -f "$CODEX_DEFAULTS" ] || [ ! -f "$PI_DEFAULTS" ]; then
        DETAIL="$NO_SOURCES"
        return 2
    fi
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

# Two independent halves: the file, and ~/.zshrc sourcing it. Either can already
# be in place on its own, so both are checked and only the missing half is done.
PN_NEED_FILE=0
PN_NEED_SOURCE=0

detect_project_navigator() {
    PN_NEED_FILE=0; PN_NEED_SOURCE=0
    [ -f "$PN_FILE" ] || PN_NEED_FILE=1
    grep -q 'project-navigator\.zsh' "$ZSHRC" 2>/dev/null || PN_NEED_SOURCE=1

    if [ "$PN_NEED_FILE" -eq 0 ] && [ "$PN_NEED_SOURCE" -eq 0 ]; then
        local n
        n="$(grep -c "^[[:space:]]*\['" "$PN_FILE" 2>/dev/null || true)"
        DETAIL="cdp ready, ${n:-0} project(s) registered"
        return 0
    fi

    local what=""
    [ "$PN_NEED_FILE" -eq 1 ]   && what+="install ~/.zsh/project-navigator.zsh "
    [ "$PN_NEED_SOURCE" -eq 1 ] && what+="source it from ~/.zshrc"
    DETAIL="will ${what% }"
    return 1
}

#############################################
# INSTALLERS
#############################################

# NONINTERACTIVE skips Homebrew's "press RETURN" pause (the survey confirmation
# already covered that) but also makes it use `sudo -n`, which fails rather than
# asking for a password, so the password is asked for and cached up front.
install_homebrew() {
    if ! load_brew; then
        sudo -v
        NONINTERACTIVE=1 run_installer https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh bash
        load_brew
    fi
    if ! xcode-select -p >/dev/null 2>&1; then
        log_warn "Command Line Tools missing — run 'xcode-select --install', finish the dialog, then re-run"
        return 1
    fi
    # Login shells get brew on PATH. Apple Silicon needs this; Intel's
    # /usr/local/bin is already on the default PATH, where it is harmless.
    if ! grep -q 'brew shellenv' "$ZPROFILE" 2>/dev/null; then
        backup_once "$ZPROFILE"
        printf '\neval "$(%s shellenv zsh)"\n' "$(command -v brew)" >> "$ZPROFILE"
        log_ok "added brew shellenv to ~/.zprofile"
    fi
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

# PROFILE=/dev/null stops nvm's installer editing ~/.zshrc; shell-path owns that.
install_nvm() {
    local ref
    ref="$(resolve_nvm_ref)"
    log_info "installing nvm ${ref}"
    PROFILE=/dev/null run_installer "https://raw.githubusercontent.com/nvm-sh/nvm/${ref}/install.sh" bash
}

install_node() {
    load_nvm
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    nvm use default
}

# The runtime comes from Homebrew so `brew upgrade` keeps it current; global
# packages (pi) still land in ~/.bun/bin, which shell-path puts on PATH.
install_bun() {
    load_brew
    brew install bun
}

install_shell_path() {
    mkdir -p "$HOME/.local/bin"
    backup_once "$ZSHRC"
    cat >> "$ZSHRC" <<EOF

${MARKER_BEGIN}
export PATH="\$HOME/.local/bin:\$PATH"

export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \\. "\$NVM_DIR/bash_completion"

export BUN_INSTALL="\$HOME/.bun"
export PATH="\$BUN_INSTALL/bin:\$PATH"
${MARKER_END}
EOF
}

install_claude()      { run_installer https://claude.ai/install.sh bash; }
install_codex()       { load_nvm; npm i -g @openai/codex; }
install_pi()          { bun add -g @earendil-works/pi-coding-agent; }

# Prime Intellect's installer asks up to three times (install, prepare the Python
# runtime, and native-binary install) and reads its answers from /dev/tty, so
# neither a pipe nor `yes |` can answer them. Every prompt defaults to yes, and
# when no terminal can be opened each one proceeds as if yes was pressed. So the
# installer runs detached from the terminal (without_tty), which is the same as
# answering yes to everything. The env vars answer the two prompts that have
# overrides. The survey confirmation above is this script's consent point.
# Node must already be on PATH: with none, the installer would offer to install
# its own, and that prompt has no unattended default.
install_prime_agent() {
    load_nvm
    local installer rc=0
    installer="$(mktemp)"
    fetch https://app.primeintellect.ai/prime-agent/install.sh "$installer"
    PRIME_AGENT_INSTALLER_NONINTERACTIVE=1 PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 \
        without_tty sh "$installer" < /dev/null || rc=$?
    rm -f "$installer"
    return "$rc"
}

install_herdr()       { run_installer https://herdr.dev/install.sh sh; }

# `agy install` is skipped on purpose: the curl installer already puts agy in
# ~/.local/bin, and `agy install` would add a second PATH line to ~/.zprofile.
install_agy()         { run_installer https://antigravity.google/cli/install.sh bash; }

# No --with-deps on macOS: Chrome for Testing needs no extra system libraries.
install_agent_browser() {
    load_nvm
    npm i -g agent-browser
    hash -r
    agent-browser install
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

# macOS 15 ships /usr/bin/jq; older releases do not, and the status line runs
# jq on every render, so brew fills the gap.
install_claude_statusline() {
    if ! have jq; then
        load_brew && brew install jq
    fi
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
    have jq || { load_brew && brew install jq; }
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

# The upstream registry is example paths, so it is emptied on the way in —
# populate with `cdp add <name>`, which rewrites the file in place. An existing
# file is never touched: it holds that device's own registry.
install_project_navigator() {
    if [ "$PN_NEED_FILE" -eq 1 ]; then
        local src tmp
        tmp="$(mktemp)"
        if curl -fsSL --retry 3 --max-time 30 "$PN_URL" -o "$tmp" 2>/dev/null; then
            src="$tmp"; log_info "fetched project-navigator.zsh from shell-utils"
        elif [ -f "$PN_FALLBACK" ]; then
            src="$PN_FALLBACK"; log_warn "upstream unreachable — using the bundled copy"
        else
            rm -f "$tmp"; log_error "could not fetch $PN_URL and no bundled copy at $PN_FALLBACK"; return 1
        fi
        grep -q '^typeset -gA PROJECTS=(' "$src" \
            || { rm -f "$tmp"; log_error "no PROJECTS block in project-navigator.zsh — upstream changed shape"; return 1; }
        mkdir -p "$(dirname "$PN_FILE")"
        awk '/^typeset -gA PROJECTS=\(/ { print; inblock=1; next }
             inblock && /^\)/          { print; inblock=0; next }
             inblock                    { next }
                                        { print }' "$src" > "$PN_FILE"
        rm -f "$tmp"
        log_ok "installed ~/.zsh/project-navigator.zsh with an empty registry — add projects with 'cdp add <name>'"
    else
        log_warn "~/.zsh/project-navigator.zsh already exists — left untouched"
    fi

    if [ "$PN_NEED_SOURCE" -eq 1 ]; then
        backup_once "$ZSHRC"
        # cdp registers its tab completion with compdef, which needs compinit.
        # Left out when ~/.zshrc (or a framework like oh-my-zsh) already runs it.
        local compinit_line='autoload -Uz compinit && compinit -C'
        grep -qE 'compinit|oh-my-zsh\.sh' "$ZSHRC" 2>/dev/null && compinit_line=""
        {
            echo
            echo "# >>> new-device-setup: cdp >>>"
            [ -n "$compinit_line" ] && echo "$compinit_line"
            echo '[ -f "$HOME/.zsh/project-navigator.zsh" ] && source "$HOME/.zsh/project-navigator.zsh"'
            echo "# <<< new-device-setup: cdp <<<"
        } >> "$ZSHRC"
        log_ok "~/.zshrc now sources the project navigator"
    fi
}

install_aliases() {
    backup_once "$ZSHRC"
    local entry
    {
        echo
        echo "# >>> new-device-setup: aliases >>>"
        for entry in "${MISSING_ALIASES[@]}"; do
            echo "${entry#*|}"
        done
        echo "# <<< new-device-setup: aliases <<<"
    } >> "$ZSHRC"
    log_ok "merged ${#MISSING_ALIASES[@]} alias(es); existing ones left untouched"
}

#############################################
# PLAN
#############################################

survey() {
    PLAN=()
    echo
    echo "${C_BOLD}Survey${C_RESET} ($(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null), $(uname -m))"
    printf '  %-18s %-9s %s\n' "COMPONENT" "STATUS" "DETAIL"
    local s fn rc
    for s in "${STEPS[@]}"; do
        fn="detect_${s//-/_}"
        DETAIL=""
        # Always run the detector, even under --force: aliases and
        # project-navigator read what it finds (MISSING_ALIASES, PN_NEED_*) to
        # know what to write. Exit 2 means the step cannot run from here.
        rc=0; "$fn" || rc=$?
        if [ "$rc" -eq 2 ]; then
            printf '  %-18s %b%-9s%b %s\n' "$s" "$C_YELLOW" "skipped" "$C_RESET" "$DETAIL"
        elif [ "$OPT_FORCE" -eq 1 ]; then
            PLAN+=("$s")
            printf '  %-18s %b%-9s%b %s\n' "$s" "$C_YELLOW" "forced" "$C_RESET" "reinstall requested"
        elif [ "$rc" -eq 0 ]; then
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
    # Piped into bash (curl ... | bash) stdin carries the script itself, so the
    # answer has to come from the terminal directly.
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
  exec zsh -l     reload the shell
  upd             confirm every tool updates
  cdp add <name>  register this Mac's projects (the registry starts empty)

${C_BOLD}Optional extras (not covered by upd):${C_RESET}
  brew install just gh uv              jj alias needs just
  brew install --cask docker           dc alias needs Docker Desktop
  npm i -g agent-device @cometix/ccline wrangler
  bun add -g dispatch

${C_BOLD}Project navigator:${C_RESET} installed from https://github.com/CGYCGY/shell-utils
EOF
}

#############################################
# MAIN
#############################################

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)            OPT_YES=1 ;;
        --upgrade)           OPT_UPGRADE=1 ;;
        --force)             OPT_FORCE=1 ;;
        --status)            OPT_STATUS=1 ;;
        --with-instructions) ;;  # once opt-in, now the default; still accepted so old commands run
        --reset)             rm -f "$STATE_FILE"; log_ok "saved progress discarded"; exit 0 ;;
        -h|--help)           awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
        *)                   log_error "unknown option: $1"; exit 1 ;;
    esac
    shift
done

if [ "$(uname -s)" != "Darwin" ]; then
    log_error "this is the macOS script — on Linux use ../ai-dev-setup.sh"
    exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
    log_error "run as your normal user, not root — Homebrew refuses to run as root"
    exit 1
fi

mkdir -p "$STATE_DIR"

# The tools install into these; put them on PATH so detection sees them
# on a resumed run, before ~/.zshrc has been reloaded.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
load_brew || true

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
    log_info "brew update && brew upgrade"
    load_brew && brew update && brew upgrade
fi

run_plan

# Everything succeeded, so the crash-recovery record has no further purpose.
rm -f "$STATE_FILE"

report
echo
log_ok "done — log at ${LOG_FILE}"
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/macos/project-navigator.zsh" <<'AI_DEV_PAYLOAD_EOF'
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
AI_DEV_PAYLOAD_EOF

cat > "$AI_DEV_TMP/agent-instructions/CLAUDE.md" <<'AI_DEV_PAYLOAD_EOF'
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

cat > "$AI_DEV_TMP/agent-instructions/AGENTS.md" <<'AI_DEV_PAYLOAD_EOF'
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

cat > "$AI_DEV_TMP/agent-instructions/GEMINI.md" <<'AI_DEV_PAYLOAD_EOF'
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

cat > "$AI_DEV_TMP/claude/statusline-command.sh" <<'AI_DEV_PAYLOAD_EOF'
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

cat > "$AI_DEV_TMP/agent-settings/claude-settings.json" <<'AI_DEV_PAYLOAD_EOF'
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

cat > "$AI_DEV_TMP/agent-settings/codex-config.toml" <<'AI_DEV_PAYLOAD_EOF'
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

cat > "$AI_DEV_TMP/agent-settings/pi-settings.json" <<'AI_DEV_PAYLOAD_EOF'
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

chmod +x "$AI_DEV_TMP/macos/ai-dev-setup-macos.sh"
# Run rather than exec: exec would drop the trap that cleans the unpacked copy.
"$AI_DEV_TMP/macos/ai-dev-setup-macos.sh" "$@"
