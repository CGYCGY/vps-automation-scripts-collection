#!/bin/bash
# Puts the agent skills in skills.json into ~/.claude/skills. A link-mode
# skill is a link into its repo's checkout: the projects checkout when
# projects.json lists the repo, else a clone in ~/.gylab/<repo>. A clone-mode
# skill is a clone of its repo at ~/.claude/skills/<name> itself. Never
# replaces a real folder or a link it doesn't own, and never pulls or resets a
# clone. A skill's setup runs in the checkout root while
# ~/.gylab/<repo>/config.json is absent: the repo's setup.sh writes it.

set -e

SKILLS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SKILLS_HOME/../../.." && pwd)"
if [ "$(uname -s)" = Darwin ]; then
    # shellcheck source=../../macos/macos-lib.sh
    . "$REPO_ROOT/workstation/macos/macos-lib.sh"
else
    # shellcheck source=../../../shared/lib/setup-lib.sh
    . "$REPO_ROOT/shared/lib/setup-lib.sh"
fi

SKILLS_FILE="${SKILLS_FILE:-$SKILLS_HOME/skills.json}"
PROJECTS_FILE="${PROJECTS_FILE:-$REPO_ROOT/workstation/shared/projects/projects.json}"
SKILLS_DIR="$HOME/.claude/skills"
GYLAB="$HOME/.gylab"
ACCESS_TIMEOUT=20

module_help() {
    cat <<EOF
Usage: $0 [-y] [--status] [--phase ...]

Puts every skill in skills.json (gitignored; copy skills.example.json) into
~/.claude/skills, in one of two modes:
  link (default)  a link into the repo: your projects checkout when
                  projects.json lists it, else a clone in ~/.gylab/<repo>
  clone           the repo itself cloned to ~/.claude/skills/<name>
A real folder, or a link the mode doesn't own, is never replaced, and a clone
is never pulled. A skill's setup command, if it has one, runs in the checkout
root when the link or clone is new or ~/.gylab/<repo>/config.json is missing.

Answers can be given up front as environment variables:
  SKILLS_SETUP    yes | no   set up the skills (asked only from workstation/setup.sh)
  SKILLS_FILE     the skills list (default: skills.json beside this script)
  PROJECTS_FILE   the projects list searched for checkouts
                  (default: ../projects/projects.json; it may be missing)
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

# Prints the first problem with the list, nothing when it is valid. Fields are
# read back through @tsv, which escapes tabs and backslashes, hence those bans.
VALIDATE='
def badpath: test("^[/~]") or ([split("/")[] | select(. == "..")] | length > 0);
def badchars: test("[\"$`\\\\\t\n]");
def basename: sub("/+$"; "") | split("/") | last | split(":") | last | sub("\\.git$"; "");
[
    if type != "object" then "the list must be a JSON object"
    elif (.skills | type) != "array" then "the list needs a \"skills\" array"
    else
        (.skills | to_entries[] | .key as $i | .value as $e |
            ("skill \($i + 1)" + (if ($e | type) == "object" and ($e.name | type) == "string" then " (\($e.name))" else "" end)) as $w |
            $e |
            if type != "object" then "\($w): not an object"
            elif (.name | type) != "string" or .name == "" then "\($w): no name"
            elif (.name | test("^[A-Za-z0-9._-]+$") | not) then "\($w): the name may only use letters, digits, . _ and -"
            elif .name == "." or .name == ".." then "\($w): the name cannot be . or .."
            elif (.repo | type) != "string" or .repo == "" then "\($w): no repo"
            elif (.repo | test("[\\\\\t\n]")) then "\($w): the repo has a backslash or control character"
            elif (.repo | basename | . == "" or . == "." or . == "..") then "\($w): the repo URL ends without a repo name"
            elif has("install") and .install != "link" and .install != "clone" then "\($w): install must be \"link\" or \"clone\""
            elif .install == "clone" and has("path") then "\($w): path does not apply to install \"clone\", which clones the whole repo to ~/.claude/skills/\(.name)"
            elif .install != "clone" and ((.path | type) != "string" or .path == "") then "\($w): no path"
            elif .install != "clone" and (.path | badpath) then "\($w): the path must be relative to the repo, without .."
            elif .install != "clone" and (.path | badchars) then "\($w): the path has a quote, $, backtick, backslash or control character"
            elif has("setup") and ((.setup | type) != "string" or .setup == "") then "\($w): setup must be a non-empty string"
            elif has("setup") and (.setup | test("[\\\\\t\n]")) then "\($w): setup has a backslash or control character"
            else empty end),
        ([.skills[] | objects | .name | strings] | group_by(.) | map(select(length > 1) | .[0])[] | "the name \"\(.)\" is used twice")
    end
] | .[0] // empty
'

# Sets LIST_JSON (comments stripped), or LIST_ERR.
load_list() {
    local json err
    LIST_ERR=""
    if [ ! -f "$SKILLS_FILE" ]; then LIST_ERR="no list at $(tilde "$SKILLS_FILE")"; return 1; fi
    have jq || { LIST_ERR="jq is not installed"; return 1; }
    json="$(jsonc_to_json "$SKILLS_FILE")"
    if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
        LIST_ERR="$(tilde "$SKILLS_FILE") is not valid JSON"; return 1
    fi
    err="$(printf '%s' "$json" | jq -r "$VALIDATE")"
    if [ -n "$err" ]; then LIST_ERR="$(tilde "$SKILLS_FILE"): $err"; return 1; fi
    LIST_JSON="$json"
}

# name <TAB> repo <TAB> install <TAB> path <TAB> setup; setup last because
# read drops empty tab-separated fields in the middle, which is also why a
# clone-mode skill gets a placeholder path it never uses.
list_skills() {
    printf '%s' "$LIST_JSON" | jq -r '.skills[] | [.name, .repo, (.install // "link"), (.path // "."), (.setup // "")] | @tsv'
}

# Sets PROJ_CLONES, "dir <TAB> url" per clone the projects list names. Empty
# when that list is missing, unreadable or has no root: projects.sh owns it and
# reports its problems.
load_projects() {
    local json root rel url
    PROJ_CLONES=""
    [ -f "$PROJECTS_FILE" ] && have jq || return 0
    json="$(jsonc_to_json "$PROJECTS_FILE")"
    root="$(printf '%s' "$json" | jq -r 'if type == "object" then (.root // "" | strings) else "" end' 2>/dev/null)" || return 0
    [ -n "$root" ] || return 0
    root="$(expand_root "$root")"
    while IFS=$'\t' read -r rel url; do
        [ -n "$url" ] || continue
        PROJ_CLONES="$PROJ_CLONES$(join_path "$root" "$rel")"$'\t'"$url"$'\n'
    done < <(printf '%s' "$json" | jq -r '.projects[]? | objects |
        if (.url | type) == "string" then [.path, .url]
        elif (.repos | type) == "array" then (.path as $p | .repos[] | objects | ["\($p)/\(.path)", .url])
        else empty end |
        select(all(type == "string")) |
        select((.[0] | test("^[/~]") or (split("/") | any(. == ".."))) | not) | @tsv' 2>/dev/null)
}

# host/owner/name in lowercase, so the ssh and https spellings of one repo,
# with or without .git, compare equal.
norm_url() {
    local u="$1"
    u="${u%/}"; u="${u%.git}"
    case "$u" in
        *://*) u="${u#*://}" ;;
        *) case "${u%%/*}" in *:*) u="${u%%:*}/${u#*:}" ;; esac ;;
    esac
    case "${u%%/*}" in *@*) u="${u#*@}" ;; esac
    printf '%s' "$u" | tr '[:upper:]' '[:lower:]'
}

# A clone of URL at DIR. Both origin forms are compared: `remote get-url`
# applies insteadOf (ssh.sh rewrites GitHub https to ssh) and the config value
# doesn't.
same_repo() {
    local want
    [ -e "$1/.git" ] || return 1
    want="$(norm_url "$2")"
    [ "$(norm_url "$(git -C "$1" remote get-url origin 2>/dev/null)")" = "$want" ] ||
        [ "$(norm_url "$(git -C "$1" config --get remote.origin.url 2>/dev/null)")" = "$want" ]
}

repo_dir_name() {
    local b="${1%/}"
    b="${b##*/}"; b="${b##*:}"
    printf '%s' "${b%.git}"
}

# Where REPO's checkout is. Sets CHECKOUT, FROM (projects | gylab), STATE
# (ready | clone | blocked), WHY for blocked, and LISTED, the projects path for
# the repo when the list names it but it is not cloned there.
resolve() {
    local repo="$1" want dir url
    want="$(norm_url "$repo")"
    CHECKOUT=""; FROM=""; STATE=""; WHY=""; LISTED=""
    while IFS=$'\t' read -r dir url; do
        [ -n "$dir" ] || continue
        [ "$(norm_url "$url")" = "$want" ] || continue
        if same_repo "$dir" "$repo"; then
            CHECKOUT="$dir"; FROM=projects; STATE=ready
            return 0
        fi
        [ -n "$LISTED" ] || LISTED="$dir"
    done <<EOF
$PROJ_CLONES
EOF
    dir="$GYLAB/$(repo_dir_name "$repo")"
    CHECKOUT="$dir"; FROM=gylab
    if same_repo "$dir" "$repo"; then
        STATE=ready
    elif [ -e "$dir/.git" ]; then
        STATE=blocked
        WHY="$(tilde "$dir") is a clone of $(git -C "$dir" remote get-url origin 2>/dev/null || echo "another repo")"
    elif [ -e "$dir" ] && ! only_tool_data "$dir"; then
        STATE=blocked
        WHY="$(tilde "$dir") is not a clone"
    else
        STATE=clone
    fi
}

# only_holds DIR NAME...: DIR is a folder with nothing in it but NAMEs.
only_holds() {
    local d="$1" f n ok
    shift
    [ -d "$d" ] || return 1
    for f in "$d"/* "$d"/.[!.]*; do
        [ -e "$f" ] || continue
        ok=""
        for n in "$@"; do [ "${f##*/}" = "$n" ] && ok=1; done
        [ -n "$ok" ] || return 1
    done
    return 0
}

# A ~/.gylab/<repo> folder may hold only the tool's config.json and state/,
# left by a setup run against a projects checkout that is gone; the clone can
# go in beside them since the repos gitignore both. Finder drops .DS_Store
# into any folder it opens.
only_tool_data() { only_holds "$1" config.json state .DS_Store; }

# A clone-mode skill's clone is ~/.claude/skills/<name> itself. Sets the same
# globals as resolve; a link there is never followed, so a link-mode leftover
# pointing at a clone of the repo still counts as in the way.
resolve_clone() {
    local dir="$SKILLS_DIR/$1"
    CHECKOUT="$dir"; FROM=skills; STATE=""; WHY=""; LISTED=""
    if [ -L "$dir" ]; then
        STATE=blocked
        WHY="$(tilde "$dir") is a link to $(tilde "$(readlink "$dir")")"
    elif same_repo "$dir" "$2"; then
        STATE=ready
    elif [ -e "$dir/.git" ]; then
        STATE=blocked
        WHY="$(tilde "$dir") is a clone of $(git -C "$dir" remote get-url origin 2>/dev/null || echo "another repo")"
    elif [ -e "$dir" ] && ! only_holds "$dir" .DS_Store; then
        STATE=blocked
        WHY="$(tilde "$dir") is not a clone"
    else
        STATE=clone
    fi
}

locate() {
    if [ "$3" = clone ]; then resolve_clone "$1" "$2"; else resolve "$2"; fi
}

# git clone refuses a non-empty folder, so an existing one is filled in place.
clone_into() {
    local url="$1" dir="$2" branch
    [ -e "$dir" ] || { git clone -q "$url" "$dir" < /dev/null; return; }
    git -C "$dir" init -q &&
        git -C "$dir" remote add origin "$url" &&
        git -C "$dir" fetch -q origin < /dev/null &&
        branch="$(git -C "$dir" ls-remote --symref origin HEAD < /dev/null | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p')" &&
        [ -n "$branch" ] &&
        git -C "$dir" checkout -q -b "$branch" --track "origin/$branch"
}

folder_in_way() { [ -e "$SKILLS_DIR/$1" ] && [ ! -L "$SKILLS_DIR/$1" ]; }

# Sets LINK (correct | other | folder | none) and LINK_TO for NAME and TARGET.
link_state() {
    local l="$SKILLS_DIR/$1"
    LINK_TO=""
    if [ -L "$l" ]; then
        LINK_TO="$(readlink "$l")"
        LINK=other
        if [ -d "$2" ]; then
            if [ "$LINK_TO" = "$2" ] ||
                [ "$(cd "$l" 2>/dev/null && pwd -P)" = "$(cd "$2" && pwd -P)" ]; then
                LINK=correct
            fi
        fi
    elif [ -e "$l" ]; then
        LINK=folder
    else
        LINK=none
    fi
}

N_LINKED=0; N_PRESENT=0; N_LEFT=0; N_WAIT=0

# Sets LINKED=yes when the link points at TARGET afterwards.
link_skill() {
    local name="$1" target="$2" l="$SKILLS_DIR/$1"
    LINKED=""
    if [ ! -d "$target" ]; then
        log_warn "$name: $(tilde "$target") is not in the checkout; not linked"
        N_LEFT=$((N_LEFT + 1))
        return 0
    fi
    link_state "$name" "$target"
    case "$LINK" in
        correct)
            N_PRESENT=$((N_PRESENT + 1))
            ;;
        other)
            rm -f "$l"
            ln -s "$target" "$l"
            log_ok "$name: relinked to $(tilde "$target") (it pointed to $(tilde "$LINK_TO"))"
            N_LINKED=$((N_LINKED + 1))
            ;;
        folder)
            log_warn "$name: $(tilde "$l") exists and is not a link, left alone (move it away to let skills.sh manage it)"
            N_LEFT=$((N_LEFT + 1))
            return 0
            ;;
        none)
            ln -s "$target" "$l"
            log_ok "$name: linked to $(tilde "$target")"
            N_LINKED=$((N_LINKED + 1))
            ;;
    esac
    LINKED=yes
}

# The repo's own setup writes this file, so its absence means the setup never
# finished. Detected, never recorded here.
setup_marker() { printf '%s' "$GYLAB/$(repo_dir_name "$1")/config.json"; }

# run_setup NAME COMMAND CHECKOUT
run_setup() {
    local name="$1" cmd="$2" rc=0
    # A script in the checkout root runs as written in the list: no ./ and no
    # executable bit needed.
    [ -f "$3/${cmd%% *}" ] && cmd="bash ./$cmd"
    log_info "$name: running $cmd in $(tilde "$3")"
    (cd "$3" && bash -c "$cmd") || rc=$?
    if [ "$rc" -eq 0 ]; then
        log_ok "$name: setup done"
    else
        log_error "$name: setup exited with status $rc"
        note "- Skills: the setup of $name failed (exit $rc); fix it and run $(tilde "$SKILLS_HOME")/skills.sh again"
    fi
}

# link_and_setup NAME PATH SETUP REPO
link_and_setup() {
    local name="$1" target
    target="$(join_path "$CHECKOUT" "$2")"
    link_skill "$name" "$target"
    [ "$LINKED" = yes ] && [ -n "$3" ] || return 0
    [ "$LINK" = correct ] && [ -f "$(setup_marker "$4")" ] && return 0
    run_setup "$name" "$3" "$CHECKOUT"
}

# Reads the globals the last locate set.
describe() {
    local name="$1" path="$2" install="$3" target out
    if [ "$install" = clone ]; then
        case "$STATE" in
            ready) out="$(tilde "$CHECKOUT") (clone)" ;;
            clone) out="$(tilde "$CHECKOUT") (will clone)" ;;
            blocked) out="$WHY; left alone" ;;
        esac
        printf '%s' "$out"
        return 0
    fi
    target="$(join_path "$CHECKOUT" "$path")"
    case "$STATE" in
        ready)
            out="$(tilde "$target")"
            [ "$FROM" = projects ] && out="$out (projects checkout)"
            ;;
        clone)
            if [ -n "$LISTED" ] && [ -n "$SKILLS_CHAINED" ] && [ "${PROJECTS_SETUP:-}" = yes ]; then
                out="$(tilde "$(join_path "$LISTED" "$path")") (once projects.sh clones it)"
            else
                out="$(tilde "$target") (will clone)"
            fi
            ;;
        blocked) out="$WHY; skipped" ;;
    esac
    folder_in_way "$name" && out="$out; $(tilde "$SKILLS_DIR/$name") is a folder, left alone"
    printf '%s' "$out"
}

show_list() {
    local name repo install path setup
    echo "Skills in $(tilde "$SKILLS_FILE"), put in $(tilde "$SKILLS_DIR"):"
    while IFS=$'\t' read -r name repo install path setup <&3; do
        locate "$name" "$repo" "$install"
        printf '  %-20s %s\n' "$name" "$(describe "$name" "$path" "$install")"
    done 3< <(list_skills)
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

# Sets PENDING, "dir <TAB> repo" per clone to make: into ~/.gylab for a
# link-mode skill, ~/.claude/skills for a clone-mode one. A link-mode skill
# whose link path is a real folder can't be linked, so its repo isn't cloned.
collect_pending() {
    local name repo install path setup
    PENDING=""
    while IFS=$'\t' read -r name repo install path setup <&3; do
        [ "$install" != clone ] && folder_in_way "$name" && continue
        locate "$name" "$repo" "$install"
        [ "$STATE" = clone ] || continue
        case $'\n'"$PENDING" in *$'\n'"$CHECKOUT"$'\t'*) continue ;; esac
        PENDING="$PENDING$CHECKOUT"$'\t'"$repo"$'\n'
    done 3< <(list_skills)
}

# Prints one row per pending repo. Sets ACCESS_TOTAL, ACCESS_FAILED and
# FAILED_URLS (one per line).
check_access() {
    local dir url errf rc reason label
    ACCESS_TOTAL=0; ACCESS_FAILED=0; FAILED_URLS=""
    errf="$(mktemp)"
    while IFS=$'\t' read -r dir url <&3; do
        label="${dir##*/}"
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
    done 3< <(printf '%s' "$PENDING")
    rm -f "$errf"
}

# Sets CLONED, one dir per line, for the setup of a clone-mode skill.
clone_pending() {
    local dir url cloned=0 failed=0 skipped=0
    CLONED=""
    while IFS=$'\t' read -r dir url <&3; do
        if printf '%s' "$FAILED_URLS" | grep -qxF "$url"; then
            skipped=$((skipped + 1))
            continue
        fi
        log_info "${dir##*/}: cloning into $(tilde "$dir")"
        mkdir -p "${dir%/*}"
        if clone_into "$url" "$dir"; then
            log_ok "${dir##*/} cloned"
            cloned=$((cloned + 1))
            CLONED="$CLONED$dir"$'\n'
        else
            log_error "${dir##*/}: git clone $url failed"
            failed=$((failed + 1))
        fi
    done 3< <(printf '%s' "$PENDING")
    log_ok "Skill repos: $cloned cloned, $failed failed, $skipped skipped (no access)"
    [ "$failed" -eq 0 ] || note "- Skills: $failed repo(s) failed to clone; see the log above, then run $(tilde "$SKILLS_HOME")/skills.sh again"
    [ "$skipped" -eq 0 ] || note "- Skills: $skipped repo(s) skipped for no access; fix it, then run $(tilde "$SKILLS_HOME")/skills.sh again"
}

# A missing list is a skip, not a failure: skills.json is gitignored, so a
# fresh clone has none until it is copied from skills.example.json.
enabled() { [ "${SKILLS_SETUP:-yes}" != no ] && [ -f "$SKILLS_FILE" ]; }

# status_clone NAME REPO SETUP: reads the globals resolve_clone set.
status_clone() {
    case "$STATE" in
        ready)
            if [ -n "$3" ] && [ ! -f "$(setup_marker "$2")" ]; then
                status_row "$1" partial "clone, setup pending (no $(tilde "$(setup_marker "$2")")); will run $3"
            else
                status_row "$1" present "clone at $(tilde "$CHECKOUT")"
            fi
            ;;
        clone) status_row "$1" missing "will clone $2 to $(tilde "$CHECKOUT")" ;;
        blocked) status_row "$1" partial "$WHY; left alone" ;;
    esac
}

module_status() {
    if [ ! -f "$SKILLS_FILE" ]; then
        status_row skills-list missing "no $(tilde "$SKILLS_FILE"); copy skills.example.json there"
        return 0
    fi
    if ! load_list; then
        status_row skills-list partial "$LIST_ERR"
        return 0
    fi
    load_projects
    local name repo install path setup target next
    while IFS=$'\t' read -r name repo install path setup <&3; do
        if [ "$install" = clone ]; then
            resolve_clone "$name" "$repo"
            status_clone "$name" "$repo" "$setup"
            continue
        fi
        resolve "$repo"
        target="$(join_path "$CHECKOUT" "$path")"
        case "$STATE" in
            ready) next="will link from $(tilde "$target")" ;;
            clone) next="will clone to $(tilde "$CHECKOUT")" ;;
            blocked) next="$WHY" ;;
        esac
        if [ "$STATE" = ready ] && [ ! -d "$target" ]; then
            status_row "$name" partial "$(tilde "$target") is not in the checkout"
            continue
        fi
        link_state "$name" "$target"
        case "$LINK" in
            correct)
                if [ -n "$setup" ] && [ ! -f "$(setup_marker "$repo")" ]; then
                    status_row "$name" partial "linked, setup pending (no $(tilde "$(setup_marker "$repo")")); will run $setup"
                else
                    status_row "$name" present "→ $(tilde "$target")"
                fi
                ;;
            folder)  status_row "$name" partial "$(tilde "$SKILLS_DIR/$name") is a folder, not a link; left alone" ;;
            other)
                [ "$STATE" = ready ] && next="will relink to $(tilde "$target")"
                status_row "$name" partial "links to $(tilde "$LINK_TO"); $next"
                ;;
            none)    status_row "$name" missing "$next" ;;
        esac
    done 3< <(list_skills)
}

module_plan() {
    require_user
    if [ -n "$SKILLS_CHAINED" ]; then
        ask_yn SKILLS_SETUP "Set up the agent skills (library, gen-image, ...)?" y
    fi
    if [ "${SKILLS_SETUP:-yes}" != no ] && [ ! -f "$SKILLS_FILE" ]; then
        log_warn "No skills list at $(tilde "$SKILLS_FILE"); copy skills.example.json there and run skills.sh again. Skills skipped"
    fi
    enabled || return 0
    log_step "Agent skills"
    if have jq; then
        load_list || die "$LIST_ERR"
        load_projects
        show_list
    else
        log_info "jq is not installed yet; the skills list is checked after the dependencies"
    fi
}

module_deps() {
    enabled || return 0
    if [ "$(uname -s)" = Darwin ]; then
        have jq || brew install jq
    else
        have jq || die "jq is needed: sudo apt-get install jq"
    fi
    load_list || die "$LIST_ERR"
}

module_auto() {
    enabled || return 0
    load_list || die "$LIST_ERR"
    load_projects
    log_step "Agent skills: links"
    mkdir -p "$SKILLS_DIR"
    local name repo install path setup
    while IFS=$'\t' read -r name repo install path setup <&3; do
        if [ "$install" = clone ]; then
            resolve_clone "$name" "$repo"
            case "$STATE" in
                clone) N_WAIT=$((N_WAIT + 1)) ;;
                blocked) log_warn "$name: $WHY, left alone"; N_LEFT=$((N_LEFT + 1)) ;;
                ready)
                    N_PRESENT=$((N_PRESENT + 1))
                    [ -n "$setup" ] && [ ! -f "$(setup_marker "$repo")" ] &&
                        run_setup "$name" "$setup" "$CHECKOUT"
                    ;;
            esac
            continue
        fi
        if folder_in_way "$name"; then
            log_warn "$name: $(tilde "$SKILLS_DIR/$name") exists and is not a link, left alone (move it away to let skills.sh manage it)"
            N_LEFT=$((N_LEFT + 1))
            continue
        fi
        resolve "$repo"
        case "$STATE" in
            clone) N_WAIT=$((N_WAIT + 1)); continue ;;
            blocked) log_warn "$name: $WHY, left alone"; N_LEFT=$((N_LEFT + 1)); continue ;;
        esac
        link_and_setup "$name" "$path" "$setup" "$repo"
    done 3< <(list_skills)
    log_ok "Skills: $N_LINKED linked, $N_PRESENT already in place, $N_LEFT left alone, $N_WAIT waiting for a clone"
}

module_interactive() {
    enabled || return 0
    load_list || die "$LIST_ERR"
    load_projects
    collect_pending
    CLONED=""
    if [ -n "$PENDING" ]; then
        log_step "Agent skills: repo access"
        while :; do
            check_access
            [ "$ACCESS_FAILED" -eq 0 ] && break
            if [ -n "${ASSUME_YES:-}" ] || ! _have_tty; then
                log_warn "$ACCESS_FAILED of $ACCESS_TOTAL skill repos are not reachable; continuing without them"
                break
            fi
            printf '%s of %s skill repos are not reachable. Fix access, or remove them from %s, then press Enter to retry. Type skip to continue without them. ' \
                "$ACCESS_FAILED" "$ACCESS_TOTAL" "$(tilde "$SKILLS_FILE")" > /dev/tty
            _read_tty || break
            case "$REPLY" in [Ss][Kk][Ii][Pp]) break ;; esac
            while ! load_list; do
                log_error "$LIST_ERR"
                printf 'Fix the list, then press Enter. ' > /dev/tty
                _read_tty || break 2
            done
            collect_pending
            [ -n "$PENDING" ] || break
        done
        if [ -n "$PENDING" ]; then
            log_step "Agent skills: clones"
            clone_pending
        fi
    fi

    # Also catches a repo projects.sh cloned after this module's auto phase.
    # A clone-mode skill's existing clone had its setup in the auto phase, so
    # only one cloned just now runs it here.
    local name repo install path setup header=""
    while IFS=$'\t' read -r name repo install path setup <&3; do
        if [ "$install" = clone ]; then
            [ -n "$setup" ] || continue
            case $'\n'"$CLONED" in *$'\n'"$SKILLS_DIR/$name"$'\n'*) ;; *) continue ;; esac
            resolve_clone "$name" "$repo"
            [ "$STATE" = ready ] || continue
            [ -n "$header" ] || { log_step "Agent skills: links and setup"; header=1; }
            run_setup "$name" "$setup" "$CHECKOUT"
            continue
        fi
        folder_in_way "$name" && continue
        resolve "$repo"
        [ "$STATE" = ready ] && [ -d "$(join_path "$CHECKOUT" "$path")" ] || continue
        link_state "$name" "$(join_path "$CHECKOUT" "$path")"
        [ "$LINK" = correct ] && continue
        [ -n "$header" ] || { log_step "Agent skills: links and setup"; header=1; }
        link_and_setup "$name" "$path" "$setup" "$repo"
    done 3< <(list_skills)
}

module_summary() {
    enabled || return 0
    note "- Skills: edit $(tilde "$SKILLS_FILE") and run $(tilde "$SKILLS_HOME")/skills.sh again to add one. For a linked skill, a repo projects.sh clones later becomes the link's target on the next run."
}

SKILLS_CHAINED=""
for arg in "$@"; do
    [ "$arg" = --phase ] && SKILLS_CHAINED=1
done

module_main "$@"
