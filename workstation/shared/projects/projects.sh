#!/bin/bash
# Clones the repos in projects.json into the same folder layout on every
# machine and registers cdp shortcuts for them. Never pulls, resets or deletes
# anything in a folder that is already there.

set -e

PROJECTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$PROJECTS_DIR/../../.." && pwd)"
if [ "$(uname -s)" = Darwin ]; then
    # shellcheck source=../../macos/macos-lib.sh
    . "$REPO_ROOT/workstation/macos/macos-lib.sh"
    PN_SHELL=zsh
else
    # shellcheck source=../../../shared/lib/setup-lib.sh
    . "$REPO_ROOT/shared/lib/setup-lib.sh"
    PN_SHELL=bash
fi
# shellcheck source=../../../shared/lib/project-navigator-lib.sh
. "$REPO_ROOT/shared/lib/project-navigator-lib.sh"
pn_init "$PN_SHELL"

PROJECTS_FILE="${PROJECTS_FILE:-$PROJECTS_DIR/projects.json}"
ACCESS_TIMEOUT=20

module_help() {
    cat <<EOF
Usage: $0 [-y] [--status] [--phase ...]
       $0 scan [ROOT]
       $0 check

Clones the repos listed in projects.json, creates the plain folders, and
registers their cdp shortcuts. Never pulls, resets or deletes inside a folder
that is already there.

  scan [ROOT]  Print a projects.json for the folders under ROOT (default: the
               list's root, else ~/projects). Read-only.
  check        Check that every repo in the list is reachable. Exits 1 if not.

Answers can be given up front as environment variables:
  PROJECTS_SETUP    yes | no   set up projects (asked only from workstation/setup.sh)
  PROJECTS_SOURCE   URL, file path or JSON text, used when the list is missing
  PROJECTS_ROOT     where projects live, when the list has no root (default ~/projects)
  PROJECTS_FILE     the list's location (default: projects.json beside this script)
EOF
}

tilde() {
    case "$1" in
        "$HOME") echo "~" ;;
        "$HOME"/*) echo "~/${1#"$HOME"/}" ;;
        *) echo "$1" ;;
    esac
}

expand_root() {
    local r="$1"
    case "$r" in
        "~") r="$HOME" ;;
        "~/"*) r="$HOME/${r#"~/"}" ;;
    esac
    [ "$r" = / ] || r="${r%/}"
    echo "$r"
}

# join ROOT REL: REL is relative and already validated.
join_path() {
    local rel="$2"
    while :; do
        case "$rel" in ./*) rel="${rel#./}" ;; *) break ;; esac
    done
    rel="${rel%/}"
    if [ -z "$rel" ] || [ "$rel" = . ]; then echo "$1"; else echo "$1/$rel"; fi
}

# Prints the first problem with the list, nothing when it is valid.
VALIDATE='
def badpath: test("^[/~]") or ([split("/")[] | select(. == "..")] | length > 0);
def badchars: test("[\"$`\\\\\t\n]");
def shortname: test("^[A-Za-z0-9._-]+$");
def cdp_problem:
    if has("cdp") and .cdp != false and (.cdp | type) != "string" then "cdp must be false or a shortcut name"
    elif (.cdp | type) == "string" and (.cdp | shortname | not) then "the cdp name may only use letters, digits, . _ and -"
    else null end;
def entry_checks($w):
    if type != "object" then "\($w): not an object"
    elif (.name | type) != "string" or .name == "" then "\($w): no name"
    elif (.name | shortname | not) then "\($w): the name may only use letters, digits, . _ and -"
    elif cdp_problem then "\($w): \(cdp_problem)"
    elif (.path | type) != "string" or .path == "" then "\($w): no path"
    elif (.path | badpath) then "\($w): the path must be relative to root, without .."
    elif (.path | badchars) then "\($w): the path has a quote, $, backtick, backslash or control character"
    elif has("url") and has("repos") then "\($w): has both url and repos"
    elif has("url") and ((.url | type) != "string" or .url == "") then "\($w): the url is empty"
    elif has("repos") then
        if (.repos | type) != "array" or (.repos | length) == 0 then "\($w): repos must be a non-empty list"
        else
            (.repos | to_entries[] | .key as $j | .value as $m | "\($w), repo \($j + 1)" as $mw |
                if ($m | type) != "object" then "\($mw): not an object"
                elif ($m.path | type) != "string" or $m.path == "" then "\($mw): no path"
                elif ($m.path | badpath) then "\($mw): the path must be relative to the set folder, without .."
                elif ($m.path | badchars) then "\($mw): the path has a quote, $, backtick, backslash or control character"
                elif ($m.url | type) != "string" or $m.url == "" then "\($mw): no url"
                elif ($m | cdp_problem) then "\($mw): \($m | cdp_problem)"
                else empty end)
        end
    else empty end;
[
    if type != "object" then "the list must be a JSON object"
    elif has("root") and ((.root | type) != "string" or (.root | test("^(/|~$|~/)") | not)) then
        "root must be an absolute path or start with ~/"
    elif has("root") and (.root | badchars) then "root has a quote, $, backtick, backslash or control character"
    elif (.projects | type) != "array" then "the list needs a \"projects\" array"
    else
        (.projects | to_entries[] | .key as $i | .value as $e |
            ("project \($i + 1)" + (if ($e | type) == "object" and ($e.name | type) == "string" then " (\($e.name))" else "" end)) as $w |
            $e | entry_checks($w)),
        ([.projects[] | objects | .name | strings] | group_by(.) | map(select(length > 1) | .[0])[] | "the name \"\(.)\" is used twice"),
        ([.projects[] | objects | (if has("cdp") then .cdp else .name end | strings), (.repos | arrays | .[] | objects | .cdp | strings)]
            | group_by(.) | map(select(length > 1) | .[0])[] | "the cdp name \"\(.)\" is used twice")
    end
] | .[0] // empty
'

# Sets LIST_JSON (comments stripped) and LIST_ROOT (expanded, "" when absent),
# or LIST_ERR. LIST_JSON is only replaced by a list that validates.
load_list() {
    local json err
    LIST_ERR=""
    if [ ! -f "$PROJECTS_FILE" ]; then LIST_ERR="no list at $(tilde "$PROJECTS_FILE")"; return 1; fi
    have jq || { LIST_ERR="jq is not installed"; return 1; }
    json="$(jsonc_to_json "$PROJECTS_FILE")"
    if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
        LIST_ERR="$(tilde "$PROJECTS_FILE") is not valid JSON"; return 1
    fi
    err="$(printf '%s' "$json" | jq -r "$VALIDATE")"
    if [ -n "$err" ]; then LIST_ERR="$(tilde "$PROJECTS_FILE"): $err"; return 1; fi
    LIST_JSON="$json"
    LIST_ROOT_RAW="$(printf '%s' "$json" | jq -r '.root // ""')"
    LIST_ROOT=""
    [ -z "$LIST_ROOT_RAW" ] || LIST_ROOT="$(expand_root "$LIST_ROOT_RAW")"
}

q() { printf '%s' "$LIST_JSON" | jq -r "$@"; }

# name <TAB> kind <TAB> path <TAB> shortcut [<TAB> url]. shortcut is the name,
# a cdp string, or "-" for none: never empty, because read collapses empty
# tab-separated fields and the url after it would shift left.
list_entries() {
    q '.projects[] | [.name, (if has("url") then "repo" elif has("repos") then "set" else "folder" end), .path,
        (if has("cdp") then (.cdp | if . == false then "-" else . end) else .name end), (.url // "")] | @tsv'
}

# shortcut <TAB> path from root, for every shortcut the list registers. Set
# members have no name, so only a cdp string gives them one.
list_shortcuts() {
    q '.projects[] | . as $e |
        (if has("cdp") then .cdp else .name end | strings | [., $e.path]),
        ((.repos // [])[] | select(.cdp | type == "string") | [.cdp, "\($e.path)/\(.path)"]) | @tsv'
}

# label <TAB> path from root <TAB> url, one line per clone
list_clones() {
    q '.projects[] |
        if has("url") then [.name, .path, .url]
        elif has("repos") then (.name as $n | .path as $p | .repos[] | ["\($n)/\(.path)", "\($p)/\(.path)", .url])
        else empty end | @tsv'
}

# Folders created up front: plain folders, sets, and the parent of each repo.
list_folders() {
    q '.projects[] |
        if has("url") then (.path | split("/") | .[:-1] | join("/") | if . == "" then "." else . end)
        else .path end'
}

show_list() {
    local name kind path cdp url label marked=""
    echo "Projects in $(tilde "$PROJECTS_FILE") (root ${LIST_ROOT_RAW:-not set}):"
    while IFS=$'\t' read -r name kind path cdp url <&3; do
        label="$name"
        [ "$cdp" = "$name" ] || { label="$name ($cdp)"; marked=1; }
        printf '  %-14s %-7s %-40s %s\n' "$label" "$kind" "$path" "$url"
        if [ "$kind" = set ]; then
            while IFS=$'\t' read -r cdp path url <&4; do
                label="$path"
                [ "$cdp" = - ] || { label="$path ($cdp)"; marked=1; }
                printf '      %-50s %s\n' "$label" "$url"
            done 4< <(q --arg n "$name" '.projects[] | select(.name == $n) | .repos[] | [(.cdp // "-"), .path, .url] | @tsv')
        fi
    done 3< <(list_entries)
    [ -z "$marked" ] || echo "  (x): the cdp shortcut is x, not the name; (-): no shortcut"
}

# Answer is a URL, a file path or the JSON itself. A paste arrives one line per
# read, so after a line that opens a JSON object, lines are read until its
# braces balance.
read_pasted_rest() {
    local text="$1" depth
    while :; do
        depth="$(printf '%s' "$text" | perl -0777 -ne '
            s#"(?:[^"\\]|\\.)*"##gs; s#//[^\n]*##g; s#/\*.*?\*/##gs;
            print tr/{// - tr/}//')"
        [ "$depth" -gt 0 ] || break
        _read_tty || break
        text="$text"$'\n'"$REPLY"
    done
    printf '%s' "$text"
}

import_list() {
    local src tmp path
    ask PROJECTS_SOURCE "Where is your projects list? (URL, file path, or paste the JSON)"
    src="$PROJECTS_SOURCE"
    case "$src" in
        "{"*)
            if [ -z "${ASSUME_YES:-}" ] && _have_tty; then
                src="$(read_pasted_rest "$src")"
                PROJECTS_SOURCE="$src"
                remember PROJECTS_SOURCE
            fi
            ;;
    esac
    if [ -z "$src" ]; then
        log_warn "No projects list given; projects skipped"
        return 1
    fi
    tmp="$(mktemp)"
    case "$src" in
        http://*|https://*)
            curl -fsSL --max-time 30 "$src" -o "$tmp" || { rm -f "$tmp"; die "could not fetch $src"; }
            ;;
        *)
            path="$(expand_root "$src")"
            if [ -f "$path" ]; then cat "$path" > "$tmp"; else printf '%s\n' "$src" > "$tmp"; fi
            ;;
    esac
    mkdir -p "$(dirname "$PROJECTS_FILE")"
    if have jq; then
        jsonc_to_json "$tmp" | jq . > "$PROJECTS_FILE.tmp" 2>/dev/null || {
            rm -f "$tmp" "$PROJECTS_FILE.tmp"
            die "the projects list is not valid JSON"
        }
    else
        # Checked in deps once jq is installed.
        jsonc_to_json "$tmp" > "$PROJECTS_FILE.tmp"
    fi
    rm -f "$tmp"
    mv "$PROJECTS_FILE.tmp" "$PROJECTS_FILE"
    if have jq && ! load_list; then
        rm -f "$PROJECTS_FILE"
        die "$LIST_ERR"
    fi
    log_ok "Projects list saved to $(tilde "$PROJECTS_FILE")"
}

has_root() {
    if have jq; then
        [ -n "$(jsonc_to_json "$PROJECTS_FILE" | jq -r '.root // empty' 2>/dev/null)" ]
    else
        jsonc_to_json "$PROJECTS_FILE" | grep -q '"root"[[:space:]]*:'
    fi
}

write_root() {
    # jq drops comments and trailing commas; keep the original when it had any.
    if ! jq -e . "$PROJECTS_FILE" >/dev/null 2>&1; then
        cp "$PROJECTS_FILE" "$PROJECTS_FILE.bak"
        log_info "The list's comments are dropped by the rewrite; the original is $(tilde "$PROJECTS_FILE").bak"
    fi
    jsonc_to_json "$PROJECTS_FILE" | jq --arg r "$PROJECTS_ROOT" '{root: $r} + .' > "$PROJECTS_FILE.tmp"
    mv "$PROJECTS_FILE.tmp" "$PROJECTS_FILE"
    log_ok "root $PROJECTS_ROOT written to $(tilde "$PROJECTS_FILE")"
}

enabled() { [ "${PROJECTS_SETUP:-yes}" != no ]; }

# For deps onwards: the list is there and valid, or the phase has nothing to do.
ready() {
    enabled && [ -f "$PROJECTS_FILE" ] || return 1
    load_list || die "$LIST_ERR"
    [ -n "$LIST_ROOT" ] || die "$(tilde "$PROJECTS_FILE") has no root"
}

# Reachability without a terminal: BatchMode makes a missing key fail instead
# of prompting, GIT_TERMINAL_PROMPT stops https asking for a password, and
# perl's alarm stands in for timeout(1), which macOS lacks. When it fires, bash
# prints an "Alarm clock" job notice; the subshell's stderr swallows it, and the
# trailing exit stops bash exec'ing perl in place of the subshell.
probe() {
    (
        GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new" \
        GIT_TERMINAL_PROMPT=0 \
            perl -e 'alarm shift; exec @ARGV or exit 127' "$ACCESS_TIMEOUT" \
            git ls-remote --exit-code "$1" HEAD < /dev/null > /dev/null 2> "$2"
        exit $?
    ) 2> /dev/null
}

# Prints one row per repo. Sets ACCESS_TOTAL, ACCESS_FAILED and FAILED_URLS
# (one per line).
check_access() {
    local label rel url errf rc reason
    ACCESS_TOTAL=0; ACCESS_FAILED=0; FAILED_URLS=""
    errf="$(mktemp)"
    while IFS=$'\t' read -r label rel url <&3; do
        ACCESS_TOTAL=$((ACCESS_TOTAL + 1))
        rc=0; probe "$url" "$errf" || rc=$?
        # 2: reachable but no HEAD yet (an empty repo); it clones fine.
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
            printf '  %-32s %s%-4s%s %s\n' "$label" "$C_GREEN" ok "$C_RESET" "$url"
            continue
        fi
        if grep -q 'Permission denied (publickey' "$errf"; then
            reason="your SSH key is not on the git host: add it (workstation/macos/ssh.sh makes one)"
        elif grep -qiE 'Repository not found|not found|does not exist|access denied' "$errf"; then
            reason="no access, or a typo in the URL (GitHub says not found for private repos you can't see)"
        elif [ "$rc" -eq 142 ]; then
            reason="unreachable: no answer in ${ACCESS_TIMEOUT}s"
        else
            reason="unreachable: $(grep -v '^[[:space:]]*$' "$errf" | head -1)"
        fi
        printf '  %-32s %s%-4s%s %s\n' "$label" "$C_RED" fail "$C_RESET" "$url"
        printf '  %-32s      %s\n' "" "$reason"
        ACCESS_FAILED=$((ACCESS_FAILED + 1))
        FAILED_URLS="$FAILED_URLS$url"$'\n'
    done 3< <(list_clones)
    rm -f "$errf"
}

# A clone of URL at DIR. Both URL forms are compared: `remote get-url` applies
# insteadOf (ssh.sh rewrites GitHub https to ssh) and the config value doesn't.
clone_of() {
    [ -e "$1/.git" ] || return 1
    [ "$(git -C "$1" remote get-url origin 2>/dev/null)" = "$2" ] ||
        [ "$(git -C "$1" config --get remote.origin.url 2>/dev/null)" = "$2" ]
}

clone_all() {
    local label rel url dest cloned=0 present=0 left=0 failed=0 skipped=0
    while IFS=$'\t' read -r label rel url <&3; do
        dest="$(join_path "$LIST_ROOT" "$rel")"
        if printf '%s' "$FAILED_URLS" | grep -qxF "$url"; then
            skipped=$((skipped + 1))
        elif clone_of "$dest" "$url"; then
            present=$((present + 1))
        elif [ -e "$dest/.git" ]; then
            log_warn "$label: $(tilde "$dest") is a clone of $(git -C "$dest" remote get-url origin 2>/dev/null || echo "another repo"), left alone"
            left=$((left + 1))
        elif [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
            log_warn "$label: $(tilde "$dest") is not a clone, left alone"
            left=$((left + 1))
        else
            log_info "$label: cloning into $(tilde "$dest")"
            if git clone -q "$url" "$dest" < /dev/null; then
                log_ok "$label cloned"
                cloned=$((cloned + 1))
            else
                log_error "$label: git clone $url failed"
                failed=$((failed + 1))
            fi
        fi
    done 3< <(list_clones)
    log_ok "Repos: $cloned cloned, $present already there, $left left alone, $failed failed, $skipped skipped (no access)"
    [ "$failed" -eq 0 ] || note "- $failed repo(s) failed to clone; see the log above, then run $(tilde "$PROJECTS_DIR")/projects.sh again"
    [ "$skipped" -eq 0 ] || note "- $skipped repo(s) skipped for no access; fix it (projects.sh check), then run projects.sh again"
}

module_status() {
    if [ ! -f "$PROJECTS_FILE" ]; then
        status_row projects-list missing "no $(tilde "$PROJECTS_FILE"); the setup asks where it is"
        status_row projects-repos skipped "no projects list"
        status_row projects-cdp skipped "no projects list"
        return 0
    fi
    if ! load_list; then
        status_row projects-list partial "$LIST_ERR"
        status_row projects-repos skipped "list not readable"
        status_row projects-cdp skipped "list not readable"
        return 0
    fi
    if [ -z "$LIST_ROOT" ]; then
        status_row projects-list partial "$(tilde "$PROJECTS_FILE"), no root yet (the setup asks)"
        status_row projects-repos skipped "no root"
        status_row projects-cdp skipped "no root"
        return 0
    fi
    status_row projects-list present "$(tilde "$PROJECTS_FILE"), root $LIST_ROOT_RAW"

    local label rel url name path n=0 m=0 state registered
    while IFS=$'\t' read -r label rel url <&3; do
        m=$((m + 1))
        clone_of "$(join_path "$LIST_ROOT" "$rel")" "$url" && n=$((n + 1))
    done 3< <(list_clones)
    if [ "$n" -eq "$m" ]; then state=present; elif [ "$n" -eq 0 ]; then state=missing; else state=partial; fi
    status_row projects-repos "$state" "$n of $m cloned"

    if [ ! -f "$PN_FILE" ]; then
        status_row projects-cdp missing "cdp not installed ($PN_SHOW)"
        return 0
    fi
    registered="$(pn_entries)"
    n=0; m=0
    while IFS=$'\t' read -r name path <&3; do
        m=$((m + 1))
        printf '%s\n' "$registered" | grep -qxF "$name"$'\t'"$(join_path "$LIST_ROOT" "$path")" && n=$((n + 1))
    done 3< <(list_shortcuts)
    if [ "$n" -eq "$m" ]; then state=present; elif [ "$n" -eq 0 ]; then state=missing; else state=partial; fi
    status_row projects-cdp "$state" "$n of $m names registered"
}

module_plan() {
    require_user
    if [ -n "$PROJECTS_CHAINED" ]; then
        ask_yn PROJECTS_SETUP "Set up your projects (clone the repos in projects.json)?" y
    fi
    enabled || return 0
    log_step "Projects"
    if [ ! -f "$PROJECTS_FILE" ]; then
        import_list || return 0
    fi
    if ! has_root; then
        ask PROJECTS_ROOT "Where do your projects live?" "~/projects"
        # Without jq yet (a fresh Mac before deps), deps writes it.
        have jq && write_root
    fi
    if have jq; then
        load_list || die "$LIST_ERR"
        show_list
    else
        log_info "jq is not installed yet; the list is checked after the dependencies"
    fi
}

module_deps() {
    enabled && [ -f "$PROJECTS_FILE" ] || return 0
    if [ "$(uname -s)" = Darwin ]; then
        have jq || brew install jq
    else
        have jq || die "jq is needed: sudo apt-get install jq"
    fi
    if ! has_root && [ -n "${PROJECTS_ROOT:-}" ]; then
        write_root
    fi
    ready
}

module_auto() {
    ready || return 0
    log_step "Projects: folders and cdp"
    local rel dir made=0 name path
    [ -d "$LIST_ROOT" ] || { mkdir -p "$LIST_ROOT"; made=1; }
    while IFS= read -r rel <&3; do
        dir="$(join_path "$LIST_ROOT" "$rel")"
        [ -d "$dir" ] || { mkdir -p "$dir"; made=$((made + 1)); }
    done 3< <(list_folders)
    log_ok "Folders under $LIST_ROOT_RAW in place ($made created)"

    if ! pn_detect; then
        pn_install || { log_warn "cdp could not be installed; names not registered"; return 0; }
    fi
    set --
    while IFS=$'\t' read -r name path <&3; do
        set -- "$@" "$name" "$(join_path "$LIST_ROOT" "$path")"
    done 3< <(list_shortcuts)
    pn_register "$@"
}

module_interactive() {
    ready || return 0
    log_step "Projects: repo access"
    while :; do
        check_access
        [ "$ACCESS_FAILED" -eq 0 ] && break
        if [ -n "${ASSUME_YES:-}" ] || ! _have_tty; then
            log_warn "$ACCESS_FAILED of $ACCESS_TOTAL repos are not reachable; continuing without them"
            break
        fi
        printf '%s of %s repos are not reachable. Fix access, or remove them from %s, then press Enter to retry. Type skip to continue without them. ' \
            "$ACCESS_FAILED" "$ACCESS_TOTAL" "$(tilde "$PROJECTS_FILE")" > /dev/tty
        _read_tty || break
        case "$REPLY" in [Ss][Kk][Ii][Pp]) break ;; esac
        while ! load_list; do
            log_error "$LIST_ERR"
            printf 'Fix the list, then press Enter. ' > /dev/tty
            _read_tty || break 2
        done
        [ -n "$LIST_ROOT" ] || die "$(tilde "$PROJECTS_FILE") has no root"
    done
    log_step "Projects: clones"
    clone_all
}

module_summary() {
    enabled && [ -f "$PROJECTS_FILE" ] || return 0
    note "- Projects: edit $(tilde "$PROJECTS_FILE") and run $(tilde "$PROJECTS_DIR")/projects.sh again for new ones. In a new shell, cdp <name> jumps to a project."
}

scan_entry() { jq -nc --arg n "$1" --arg p "$2" --arg u "$3" '{name: $n, path: $p} + (if $u == "" then {} else {url: $u} end)'; }

cmd_scan() {
    have jq || die "jq is needed for scan"
    local lit root cat d m sub url members entries name
    if [ -n "${1:-}" ]; then
        lit="$1"
    elif [ -f "$PROJECTS_FILE" ] && load_list && [ -n "$LIST_ROOT_RAW" ]; then
        lit="$LIST_ROOT_RAW"
    else
        lit="~/projects"
    fi
    root="$(expand_root "$lit")"
    [ -d "$root" ] || die "no folder at $root"
    # Stored as ~/... so the list fits a machine with another user name.
    case "$lit" in "~"|"~/"*) ;; *) lit="$(tilde "$(cd "$root" && pwd)")" ;; esac

    entries="$(scan_entry projects . "")"
    for cat in "$root"/*/; do
        [ -d "$cat" ] || continue
        cat="${cat%/}"
        if [ -e "$cat/.git" ]; then
            url="$(git -C "$cat" config --get remote.origin.url 2>/dev/null || true)"
            entries="$entries"$'\n'"$(scan_entry "${cat##*/}" "${cat##*/}" "$url")"
            continue
        fi
        for d in "$cat"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"
            name="${d##*/}"
            sub="${cat##*/}/$name"
            if [ -e "$d/.git" ]; then
                url="$(git -C "$d" config --get remote.origin.url 2>/dev/null || true)"
                entries="$entries"$'\n'"$(scan_entry "$name" "$sub" "$url")"
                continue
            fi
            members=""
            for m in "$d"/*/; do
                [ -e "${m%/}/.git" ] || continue
                m="${m%/}"
                url="$(git -C "$m" config --get remote.origin.url 2>/dev/null || true)"
                [ -n "$url" ] || continue
                members="$members$(jq -nc --arg p "${m##*/}" --arg u "$url" '{path: $p, url: $u}')"$'\n'
            done
            if [ -n "$members" ]; then
                entries="$entries"$'\n'"$(printf '%s' "$members" | jq -sc --arg n "$name" --arg p "$sub" '{name: $n, path: $p, repos: .}')"
            else
                entries="$entries"$'\n'"$(scan_entry "$name" "$sub" "")"
            fi
        done
    done
    echo "// projects.sh scan of $lit."
    echo "// Names are the folder names: shorten them to what you want to type after cdp."
    echo "// Folders directly under root are categories, not entries. A repo without an"
    echo "// origin is listed as a plain folder."
    printf '%s\n' "$entries" | jq -s --arg root "$lit" '{root: $root, projects: .}'
}

cmd_check() {
    load_list || die "$LIST_ERR"
    check_access
    if [ "$ACCESS_FAILED" -gt 0 ]; then
        log_error "$ACCESS_FAILED of $ACCESS_TOTAL repos are not reachable"
        exit 1
    fi
    log_ok "All $ACCESS_TOTAL repos are reachable"
}

case "${1:-}" in
    scan) shift; cmd_scan "$@"; exit 0 ;;
    check) shift; cmd_check; exit 0 ;;
esac

PROJECTS_CHAINED=""
for arg in "$@"; do
    [ "$arg" = --phase ] && PROJECTS_CHAINED=1
done

module_main "$@"
