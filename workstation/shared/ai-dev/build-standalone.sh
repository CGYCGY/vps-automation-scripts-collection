#!/usr/bin/env bash
# Regenerates the standalone bundles — the whole setup as one self-extracting
# file, for devices where fetching the repository is not worth the trouble:
#
#   ai-dev-standalone.sh                    Linux, runs ai-dev-setup.sh
#   macos/ai-dev-setup-macos-standalone.sh  macOS, runs macos/ai-dev-setup-macos.sh
#
# Each bundle unpacks its payload in the same layout as this directory, so the
# setup script resolves agent-instructions/, agent-settings/, claude/ and its
# project navigator through its own SCRIPT_DIR exactly as it does in a
# checkout, and stays bundle-unaware.
#
# Output is byte-deterministic — rebuilding without a source change produces no
# diff — so nothing emitted below may carry a timestamp, hostname or path.
#
#   ./build-standalone.sh          regenerate both bundles
#   ./build-standalone.sh --check  exit non-zero if either committed copy is stale

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Everything each setup script reads from its own directory at run time, entry
# script first. README.md is deliberately absent: it documents the repository,
# not the install.
LINUX_PAYLOAD=(
    ai-dev-setup.sh
    project-navigator.sh
    agent-instructions/CLAUDE.md
    agent-instructions/AGENTS.md
    agent-instructions/GEMINI.md
    claude/statusline-command.sh
    agent-settings/claude-settings.json
    agent-settings/codex-config.toml
    agent-settings/pi-settings.json
)
MACOS_PAYLOAD=(
    macos/ai-dev-setup-macos.sh
    macos/project-navigator.zsh
    agent-instructions/CLAUDE.md
    agent-instructions/AGENTS.md
    agent-instructions/GEMINI.md
    claude/statusline-command.sh
    agent-settings/claude-settings.json
    agent-settings/codex-config.toml
    agent-settings/pi-settings.json
)

# A payload line equal to this would close its heredoc early and corrupt the
# bundle, so every source is checked for it rather than assumed clean.
DELIM="AI_DEV_PAYLOAD_EOF"

die() { printf 'build-standalone: %s\n' "$1" >&2; exit 1; }

check_sources() {
    local f path
    for f in "$@"; do
        path="${SCRIPT_DIR}/${f}"
        [ -f "$path" ] || die "missing source: $f"
        if grep -qxF "$DELIM" "$path"; then
            die "$f contains a line equal to $DELIM — change DELIM in this script"
        fi
        # Without a final newline the terminator would fuse to the last line.
        if [ -n "$(tail -c1 "$path")" ]; then
            die "$f does not end in a newline"
        fi
    done
}

# $1 names the platform in the header line; the rest is the payload, entry
# script first. Unpack directories come from the payload paths, in order.
emit() {
    local title="$1"; shift
    local entry="$1" f d dirs=""
    for f in "$@"; do
        d="${f%/*}"
        [ "$d" = "$f" ] && continue
        case " $dirs " in *" $d "*) ;; *) dirs="${dirs:+$dirs }$d" ;; esac
    done

    cat <<'HEADER'
#!/usr/bin/env bash
HEADER
    printf '# %s, bundled as a single self-extracting file.\n' "$title"
    cat <<'HEADER'
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
HEADER
    printf 'mkdir -p'
    for d in $dirs; do printf ' "$AI_DEV_TMP/%s"' "$d"; done
    printf '\n'

    for f in "$@"; do
        printf '\ncat > "$AI_DEV_TMP/%s" <<'\''%s'\''\n' "$f" "$DELIM"
        cat "${SCRIPT_DIR}/${f}"
        printf '%s\n' "$DELIM"
    done

    printf '\nchmod +x "$AI_DEV_TMP/%s"\n' "$entry"
    cat <<'FOOTER'
# Run rather than exec: exec would drop the trap that cleans the unpacked copy.
FOOTER
    printf '"$AI_DEV_TMP/%s" "$@"\n' "$entry"
}

# $1 is the output path relative to this directory; the rest goes to emit.
build() {
    local output="${SCRIPT_DIR}/$1"; shift
    local title="$1"; shift
    check_sources "$@"

    local tmp
    tmp="$(mktemp)"
    emit "$title" "$@" > "$tmp"
    bash -n "$tmp" || { rm -f "$tmp"; die "generated ${output##*/} is not valid bash"; }

    if [ "$mode" = "check" ]; then
        if cmp -s "$tmp" "$output"; then
            rm -f "$tmp"
            echo "${output##*/} is up to date"
        else
            rm -f "$tmp"
            stale=1
            printf 'build-standalone: %s is out of date — run ./build-standalone.sh\n' "${output##*/}" >&2
        fi
    else
        chmod 755 "$tmp"
        mv "$tmp" "$output"
        printf 'wrote %s (%s bytes)\n' "${output##*/}" "$(wc -c < "$output")"
    fi
}

mode="build"
case "${1:-}" in
    "") ;;
    --check) mode="check" ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
esac

stale=0
build ai-dev-standalone.sh "AI development toolchain setup" "${LINUX_PAYLOAD[@]}"
build macos/ai-dev-setup-macos-standalone.sh "AI development toolchain setup for macOS" "${MACOS_PAYLOAD[@]}"
[ "$stale" -eq 0 ] || exit 1
