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
# already there. Updating is `upd`'s job, which a LaunchAgent runs daily at
# 09:00. After a successful run it offers to set up the agent skills (workstation/shared/skills/skills.sh).
#
#   ./ai-dev-setup-macos.sh                     survey, show the plan, ask, then install
#   ./ai-dev-setup-macos.sh -y                  same, without the confirmation prompt
#   ./ai-dev-setup-macos.sh --upgrade           also run brew update && brew upgrade
#   ./ai-dev-setup-macos.sh --status            survey only, change nothing
#   ./ai-dev-setup-macos.sh --force             reinstall everything, ignoring detection
#   ./ai-dev-setup-macos.sh --reset             discard a crashed run's saved progress
#   ./ai-dev-setup-macos.sh --no-skills         don't offer the agent skills at the end
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
    'dc|alias dc="docker compose"'
    'jj|alias jj="just"'
)

# Project navigation (cdp): install and fallback copy live in the shared helper,
# which the projects module uses too. A lone copy of this script has no helper;
# detect_project_navigator reports that below.
PN_LIB="${SCRIPT_DIR}/../../../../shared/lib/project-navigator-lib.sh"
if [ -f "$PN_LIB" ]; then
    # shellcheck source=../../../../shared/lib/project-navigator-lib.sh
    . "$PN_LIB"
    pn_init zsh
fi

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

# The updater, installed as a command (not an alias) so the LaunchAgent can run
# it: launchd reads no ~/.zshrc. Hardcoded to 09:00 daily; launchd runs a missed
# slot on wake.
UPD_SRC="${SCRIPT_DIR}/upd.sh"
UPD_FILE="$HOME/.local/bin/upd"
UPD_LABEL="local.ai-dev.upd"
UPD_PLIST="$HOME/Library/LaunchAgents/${UPD_LABEL}.plist"
UPD_LOG="$HOME/Library/Logs/upd.log"

# All of the above, and the project navigator, read files that sit beside this
# script in a checkout or in the standalone bundle. A lone copy of this script
# has none of them, and the survey says so rather than reporting the step as done.
NO_SOURCES="source files missing — run ai-dev-setup-macos-standalone.sh or a checkout"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/new-device-setup"
STATE_FILE="${STATE_DIR}/in-progress"
LOG_FILE="${STATE_DIR}/setup.log"

# Guards the blocks appended to ~/.zshrc, so the script cannot duplicate them
# even if its saved progress is lost.
MARKER_BEGIN="# >>> new-device-setup >>>"
MARKER_END="# <<< new-device-setup <<<"

STEPS=(homebrew nvm node bun shell-path claude codex pi prime-agent herdr agy npm-allow-scripts agent-browser agent-instructions claude-statusline agent-settings aliases upd upd-schedule project-navigator)

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

detect_upd() {
    if [ ! -f "$UPD_SRC" ]; then
        DETAIL="$NO_SOURCES"
        return 2
    fi
    if cmp -s "$UPD_SRC" "$UPD_FILE" 2>/dev/null; then
        DETAIL="~/.local/bin/upd matches"
        return 0
    fi
    DETAIL="will install/update ~/.local/bin/upd"
    return 1
}

upd_plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${UPD_LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>${UPD_FILE}</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>${UPD_LOG}</string>
  <key>StandardErrorPath</key><string>${UPD_LOG}</string>
</dict>
</plist>
EOF
}

detect_upd_schedule() {
    if [ ! -f "$UPD_SRC" ]; then
        DETAIL="$NO_SOURCES"
        return 2
    fi
    if upd_plist | cmp -s - "$UPD_PLIST" 2>/dev/null \
       && launchctl print "gui/$(id -u)/${UPD_LABEL}" >/dev/null 2>&1; then
        DETAIL="daily 09:00, loaded"
        return 0
    fi
    DETAIL="will install and load the 09:00 LaunchAgent"
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

detect_project_navigator() {
    if [ ! -f "$PN_LIB" ]; then
        DETAIL="$NO_SOURCES"
        return 2
    fi
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

# Populate the registry with `cdp add <name>` or the projects module.
install_project_navigator() { pn_install; }

install_upd() {
    mkdir -p "$(dirname "$UPD_FILE")"
    install -m 0755 "$UPD_SRC" "$UPD_FILE"
    log_ok "installed upd.sh -> $UPD_FILE"
}

# bootstrap refuses a label that is already loaded, so unload any old copy first.
install_upd_schedule() {
    local domain="gui/$(id -u)"
    mkdir -p "$(dirname "$UPD_PLIST")" "$(dirname "$UPD_LOG")"
    upd_plist > "$UPD_PLIST"
    launchctl bootout "${domain}/${UPD_LABEL}" 2>/dev/null || true
    launchctl bootstrap "$domain" "$UPD_PLIST"
    log_ok "upd scheduled daily at 09:00 ($UPD_PLIST), log at $UPD_LOG"
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
  upd             confirm every tool updates (also runs daily at 09:00,
                  log at ~/Library/Logs/upd.log)
  cdp add <name>  register this Mac's projects (the registry starts empty)

${C_BOLD}Optional extras (not covered by upd):${C_RESET}
  brew install just gh uv              jj alias needs just
  brew install --cask docker           dc alias needs Docker Desktop
  npm i -g agent-device @cometix/ccline wrangler
  bun add -g dispatch

${C_BOLD}Project navigator:${C_RESET} installed from https://github.com/CGYCGY/shell-utils
EOF
}

# Not in the standalone bundle: skills.sh needs the rest of the repository.
SKILLS_SCRIPT="${SCRIPT_DIR}/../../skills/skills.sh"

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
        -y|--yes)            OPT_YES=1 ;;
        --upgrade)           OPT_UPGRADE=1 ;;
        --force)             OPT_FORCE=1 ;;
        --status)            OPT_STATUS=1 ;;
        --no-skills)         OPT_SKILLS=0 ;;
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
    offer_skills
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
offer_skills
