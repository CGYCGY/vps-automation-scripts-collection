#!/bin/bash
# The AI coding-agent toolchain, run as one unattended step.

set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/linux-lib.sh"

AI_DEV="$LINUX_DIR/../shared/ai-dev/ai-dev-setup.sh"

module_status() {
    bash "$AI_DEV" --status | sed -n '/^  [a-z]/p' | grep -vE '^  COMPONENT '
}

module_plan() { require_user; }

# deps, not auto as on macOS: projects.sh and skills.sh need jq in their deps
# phase and only install it themselves with brew; here this apt step brings it.
module_deps() {
    log_step "AI dev toolchain"
    # skills.sh is its own module later in the menu, so it isn't offered here.
    # AI_DEV_FLAGS: --upgrade / --force from workstation/setup.sh.
    # shellcheck disable=SC2086
    bash "$AI_DEV" -y --no-skills ${AI_DEV_FLAGS:-}
}

module_summary() {
    note "- Log the agents in: claude, codex login, agy, pi, prime-agent. Then: exec bash -l"
}

module_main "$@"
