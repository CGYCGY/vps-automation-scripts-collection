#!/bin/bash
# Phase runner shared by every setup module. Source it, define the module_*
# functions you need, then call `module_main "$@"`.
#
# Phases, always in this order:
#   plan         ask every question that decides what runs; nothing changes
#   deps         things the later steps depend on (packages, installers)
#   auto         changes that need no input
#   interactive  steps that need the user (browser login, typing a password)
#   summary      what to do next; nothing changes
# plus `status`, run alone by --status: report what is in place, change nothing.
#
# A menu that runs several modules calls each with `--phase <name>`, one phase
# at a time across all modules, so every question comes first and every
# interactive step comes last. Answers survive between those separate
# processes through the SETUP_STATE file.
#
# Must stay bash 3.2 compatible: macOS modules use it too.

if [ -t 1 ]; then
    C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'
    C_CYAN=$'\033[0;36m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi

log_info()  { echo "${C_CYAN}[ .. ]${C_RESET} $*"; }
log_ok()    { echo "${C_GREEN}[ ok ]${C_RESET} $*"; }
log_warn()  { echo "${C_YELLOW}[warn]${C_RESET} $*"; }
log_error() { echo "${C_RED}[fail]${C_RESET} $*" >&2; }
log_step()  { echo; echo "${C_BOLD}== $* ==${C_RESET}"; }

have() { command -v "$1" >/dev/null 2>&1; }

die() { log_error "$*"; exit 1; }

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run this with sudo"
}

require_user() {
    [ "$(id -u)" -ne 0 ] || die "run this as your normal user, not with sudo"
}

# Asks for the password once, then keeps sudo's timestamp fresh until this
# shell exits, so no step stops halfway to ask again.
sudo_keepalive() {
    sudo -v || die "sudo is needed"
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
}

# status_row NAME STATE DETAIL, for module_status
status_row() { printf '  %-18s %-9s %s\n' "$1" "$2" "$3"; }

# The human behind sudo, for things like their password or home directory.
invoking_user() { echo "${SUDO_USER:-$(id -un)}"; }

# --- answers -----------------------------------------------------------------

SETUP_STATE="${SETUP_STATE:-}"
if [ -z "$SETUP_STATE" ]; then
    SETUP_STATE="$(mktemp "${TMPDIR:-/tmp}/setup-state.XXXXXX")"
    trap 'rm -f "$SETUP_STATE" "${SETUP_STATE}.notes"' EXIT
fi
export SETUP_STATE
# shellcheck disable=SC1090
[ -s "$SETUP_STATE" ] && . "$SETUP_STATE"

remember() {
    local var="$1" val
    eval "val=\${$var}"
    printf '%s=%q\n' "$var" "$val" >> "$SETUP_STATE"
    export "$var"
}

# Prompts go to /dev/tty so a module still asks when its stdout is piped.
_read_tty() {
    if [ -r /dev/tty ]; then
        IFS= read -r REPLY < /dev/tty
    else
        REPLY=""
    fi
}

_can_prompt() { [ -z "${ASSUME_YES:-}" ] && [ -r /dev/tty ]; }

# ask VAR "question" [default]: free text. Skipped when VAR is already set,
# from the environment or an earlier module.
ask() {
    local var="$1" question="$2" default="${3:-}" current
    eval "current=\${$var+set}"
    [ -n "$current" ] && return 0
    if _can_prompt; then
        if [ -n "$default" ]; then
            printf '%s [%s]: ' "$question" "$default" > /dev/tty
        else
            printf '%s: ' "$question" > /dev/tty
        fi
        _read_tty
        [ -z "$REPLY" ] && REPLY="$default"
    else
        REPLY="$default"
    fi
    eval "$var=\$REPLY"
    remember "$var"
}

# ask_yn VAR "question" y|n: stores yes or no.
ask_yn() {
    local var="$1" question="$2" default="$3" current hint
    eval "current=\${$var+set}"
    [ -n "$current" ] && return 0
    if [ "$default" = y ]; then hint="Y/n"; else hint="y/N"; fi
    REPLY=""
    if _can_prompt; then
        while :; do
            printf '%s [%s]: ' "$question" "$hint" > /dev/tty
            _read_tty
            case "$REPLY" in
                [Yy]|[Yy][Ee][Ss]) REPLY=yes; break ;;
                [Nn]|[Nn][Oo])     REPLY=no; break ;;
                "")                break ;;
            esac
        done
    fi
    if [ -z "$REPLY" ]; then
        if [ "$default" = y ]; then REPLY=yes; else REPLY=no; fi
    fi
    eval "$var=\$REPLY"
    remember "$var"
}

# ask_choice VAR "question" default "value|label" ...
ask_choice() {
    local var="$1" question="$2" default="$3" current i opt
    shift 3
    eval "current=\${$var+set}"
    [ -n "$current" ] && return 0
    REPLY="$default"
    if _can_prompt; then
        echo "$question" > /dev/tty
        i=1
        for opt in "$@"; do
            printf '  %d) %s\n' "$i" "${opt#*|}" > /dev/tty
            i=$((i + 1))
        done
        while :; do
            printf 'Select [1-%d]: ' "$#" > /dev/tty
            _read_tty
            if [ -z "$REPLY" ]; then REPLY="$default"; break; fi
            case "$REPLY" in *[!0-9]*) continue ;; esac
            if [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$#" ]; then
                i=1
                for opt in "$@"; do
                    [ "$i" -eq "$REPLY" ] && REPLY="${opt%%|*}" && break
                    i=$((i + 1))
                done
                break
            fi
        done
    fi
    eval "$var=\$REPLY"
    remember "$var"
}

# --- machine role --------------------------------------------------------------

# Shared by tailscale, coolify and the menus, so whichever asks first decides.
ask_server_role() {
    ask_choice MACHINE_ROLE "What does this server do?" managed \
        "dashboard|Coolify dashboard (runs Coolify itself)" \
        "managed|Managed server (deployed to by a Coolify dashboard)"
}

# --- notes for the summary -----------------------------------------------------

# note "text": collected in any phase, printed by the menu's summary at the end.
note() { echo "$*" >> "${SETUP_STATE}.notes"; }

print_notes() {
    [ -s "${SETUP_STATE}.notes" ] || return 0
    log_step "Next steps"
    cat "${SETUP_STATE}.notes"
}

# --- runners --------------------------------------------------------------------

_run_phase() {
    local fn="module_$1"
    if [ "$(type -t "$fn" 2>/dev/null)" = function ]; then
        "$fn"
    fi
}

# module_main [--phase plan|deps|auto|interactive|summary|status] [--status] [-y]
# With no --phase, runs every phase itself, for running one module alone.
module_main() {
    local phase=all
    while [ $# -gt 0 ]; do
        case "$1" in
            --phase) phase="$2"; shift ;;
            --status) phase=status ;;
            -y|--yes) ASSUME_YES=1; export ASSUME_YES ;;
            -h|--help)
                if [ "$(type -t module_help 2>/dev/null)" = function ]; then
                    module_help
                else
                    echo "Usage: $0 [-y] [--phase plan|deps|auto|interactive|summary]"
                fi
                exit 0
                ;;
            *) die "unknown option: $1" ;;
        esac
        shift
    done

    case "$phase" in
        all)
            local p
            _run_phase plan
            ask_yn SETUP_GO "Questions done. Start the setup?" y
            [ "$SETUP_GO" = yes ] || { log_warn "Nothing was changed."; return 0; }
            for p in deps auto interactive summary; do
                _run_phase "$p"
            done
            print_notes
            ;;
        plan|deps|auto|interactive|summary|status) _run_phase "$phase" ;;
        *) die "unknown phase: $phase" ;;
    esac
}

# run_modules MODULE_PATH... : the menu side. Every module goes through each
# phase before the next phase starts. Answers the menu already gave (with ask*)
# are in the same state file, so modules don't ask them again.
run_modules() {
    local p m
    for p in plan deps auto interactive summary; do
        if [ "$p" = deps ]; then
            ask_yn SETUP_GO "Questions done. Start the setup?" y
            if [ "$SETUP_GO" != yes ]; then
                log_warn "Nothing was changed."
                _clear_state
                return 0
            fi
        fi
        for m in "$@"; do
            bash "$m" --phase "$p" || {
                log_error "$(basename "$m") failed during the $p phase"
                _clear_state
                return 1
            }
        done
    done
    print_notes
    _clear_state
}

# status_modules MODULE_PATH...: the read-only survey behind --status.
status_modules() {
    local m
    status_row COMPONENT STATUS DETAIL
    for m in "$@"; do
        bash "$m" --phase status
    done
    echo
    echo "--status: nothing was changed."
}

_clear_state() {
    rm -f "$SETUP_STATE" "${SETUP_STATE}.notes"
    unset SETUP_GO
}
