#!/bin/bash
# The AI coding-agent toolchain, run as one unattended step.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos-lib.sh"

AI_DEV="$MACOS_DIR/../shared/ai-dev/macos/ai-dev-setup-macos.sh"

module_status() {
    bash "$AI_DEV" --status | sed -n '/^  [a-z]/p' | grep -vE '^  (COMPONENT|homebrew) '
}

module_plan() { require_user; }

module_auto() {
    log_step "AI dev toolchain"
    # skills.sh is its own module later in the menu, so it isn't offered here.
    bash "$AI_DEV" -y --no-skills
}

module_summary() {
    note "- Log the agents in: claude, codex login, agy, pi, prime-agent. Then: exec zsh -l"
}

module_main "$@"
