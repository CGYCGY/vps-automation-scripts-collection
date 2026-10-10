#!/bin/bash
# Updates every agent CLI that ai-dev-setup-macos.sh installs. The setup copies it
# to ~/.local/bin/upd, and a LaunchAgent runs it daily at 09:00.
#
# launchd starts it with a bare PATH and without ~/.zshrc, so it builds its own
# PATH and loads nvm's default Node rather than a fixed version directory, which a
# Node upgrade would leave behind.

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" --no-use && nvm use default --silent

echo "=== upd $(date '+%Y-%m-%d %H:%M:%S') ==="
fail=0
# Each one runs regardless of the others: a single failing updater must not
# leave the rest stale.
for cmd in "claude update" "codex update" "pi update" "prime-agent update" \
           "herdr update" "agy update" "agent-browser upgrade"; do
    echo "--- $cmd"
    # shellcheck disable=SC2086
    $cmd || { echo "!!! FAILED: $cmd"; fail=1; }
done
exit "$fail"
