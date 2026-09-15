#!/usr/bin/env bash
# Regenerates ai-dev-standalone.sh: the whole setup as one self-extracting file,
# for devices where fetching the repository is not worth the trouble.
#
# The bundle unpacks its payload beside a copy of ai-dev-setup.sh, so that script
# resolves agent-instructions/ and project-navigator.sh through its own
# SCRIPT_DIR exactly as it does in a checkout, and stays bundle-unaware.
#
# Output is byte-deterministic — rebuilding without a source change produces no
# diff — so nothing emitted below may carry a timestamp, hostname or path.
#
#   ./build-standalone.sh          regenerate ai-dev-standalone.sh
#   ./build-standalone.sh --check  exit non-zero if the committed copy is stale

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/ai-dev-standalone.sh"

# Everything ai-dev-setup.sh reads from its own directory at run time. README.md
# is deliberately absent: it documents the repository, not the install.
PAYLOAD=(
    ai-dev-setup.sh
    project-navigator.sh
    agent-instructions/CLAUDE.md
    agent-instructions/AGENTS.md
    agent-instructions/GEMINI.md
)

# A payload line equal to this would close its heredoc early and corrupt the
# bundle, so every source is checked for it rather than assumed clean.
DELIM="AI_DEV_PAYLOAD_EOF"

die() { printf 'build-standalone: %s\n' "$1" >&2; exit 1; }

check_sources() {
    local f path
    for f in "${PAYLOAD[@]}"; do
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

emit() {
    cat <<'HEADER'
#!/usr/bin/env bash
# AI development toolchain setup, bundled as a single self-extracting file.
#
# GENERATED FILE — do not edit. Change the sources in the repository's ai-dev/
# directory, then run ./build-standalone.sh to regenerate this.
#
# Unpacks to a temporary directory and runs the setup from there. Every flag is
# forwarded, so -y, --status, --upgrade, --force and --reset behave as usual.

set -euo pipefail

AI_DEV_TMP="$(mktemp -d)"
trap 'rm -rf "$AI_DEV_TMP"' EXIT
mkdir -p "$AI_DEV_TMP/agent-instructions"
HEADER

    local f
    for f in "${PAYLOAD[@]}"; do
        printf '\ncat > "$AI_DEV_TMP/%s" <<'\''%s'\''\n' "$f" "$DELIM"
        cat "${SCRIPT_DIR}/${f}"
        printf '%s\n' "$DELIM"
    done

    cat <<'FOOTER'

chmod +x "$AI_DEV_TMP/ai-dev-setup.sh"
# Run rather than exec: exec would drop the trap that cleans the unpacked copy.
"$AI_DEV_TMP/ai-dev-setup.sh" "$@"
FOOTER
}

mode="build"
case "${1:-}" in
    "") ;;
    --check) mode="check" ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
esac

check_sources

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
emit > "$tmp"
bash -n "$tmp" || die "generated bundle is not valid bash"

if [ "$mode" = "check" ]; then
    if cmp -s "$tmp" "$OUTPUT"; then
        echo "ai-dev-standalone.sh is up to date"
    else
        die "ai-dev-standalone.sh is out of date — run ./build-standalone.sh"
    fi
else
    chmod 755 "$tmp"
    mv "$tmp" "$OUTPUT"
    trap - EXIT
    printf 'wrote %s (%s bytes)\n' "${OUTPUT##*/}" "$(wc -c < "$OUTPUT")"
fi
