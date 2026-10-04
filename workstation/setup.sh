#!/bin/bash
# Workstation Setup - entry point for machines used for work (Linux or macOS)
#
# Must stay bash 3.2 compatible: it is the first thing run on a fresh Mac.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../shared/lib/setup-lib.sh
. "$SCRIPT_DIR/../shared/lib/setup-lib.sh"

MAC="$SCRIPT_DIR/macos"
LINUX="$SCRIPT_DIR/linux"
SHARED="$SCRIPT_DIR/shared"
# Order matters within each phase: Full Disk Access comes after the apps it
# applies to are installed, ssh after tailscale, because Remote Login only
# goes off once Tailscale SSH is connected, projects after ssh, because
# cloning needs the GitHub key on the account, and skills after projects, so a
# skill links into the projects checkout when its repo is there.
MACOS_MODULES="$MAC/homebrew.sh $MAC/apps.sh $MAC/tailscale.sh $MAC/full-disk-access.sh
$MAC/ai-dev.sh $MAC/power.sh $MAC/finder.sh $MAC/zed.sh $MAC/ssh.sh
$SHARED/projects/projects.sh $SHARED/skills/skills.sh"
# Same reasons, and ai-dev before projects and skills: its deps phase installs
# the jq theirs need.
LINUX_MODULES="$LINUX/ssh.sh $LINUX/ai-dev.sh $SHARED/projects/projects.sh $SHARED/skills/skills.sh"

show_help() {
    cat <<EOF
Usage: $0 [--status] [-y] [--upgrade] [--force]

  --status    Survey this machine without changing anything
  -y, --yes   Take the default answer for every question
  --upgrade   Linux: also run a full apt dist-upgrade (AI dev setup)
  --force     Linux: reinstall the AI dev toolchain, ignoring detection

Asks every question first, installs, then leaves the steps that need you
(the GitHub key, cloning your projects and the agent skills' repos) for the
end. macOS asks for sudo once up front and adds Homebrew, apps, Tailscale and
the Mac settings. Linux asks for sudo only when apt packages are missing;
Tailscale is its own root script, shared/linux/tailscale/tailscale-setup.sh.
EOF
}

require_user

case "$(uname -s)" in
    Linux)
        MODULES="$LINUX_MODULES"
        # Where ai-dev installs bun and the agents: later modules (a skill's
        # setup needs bun) run in this session, before ~/.bashrc is reread.
        export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
        ;;
    Darwin) MODULES="$MACOS_MODULES" ;;
    *) die "unsupported OS: $(uname -s)" ;;
esac

status=""
AI_DEV_FLAGS=""
for arg in "$@"; do
    case "$arg" in
        --status) status=1 ;;
        -y|--yes) ASSUME_YES=1; export ASSUME_YES ;;
        -h|--help) show_help; exit 0 ;;
        --upgrade|--force)
            [ "$(uname -s)" = Linux ] || { log_error "$arg is Linux only"; show_help; exit 1; }
            AI_DEV_FLAGS="$AI_DEV_FLAGS $arg"
            ;;
        *) log_error "unknown option: $arg"; show_help; exit 1 ;;
    esac
done
export AI_DEV_FLAGS

# shellcheck disable=SC2086
if [ -n "$status" ]; then
    status_modules $MODULES
else
    [ "$(uname -s)" = Darwin ] && sudo_keepalive
    run_modules $MODULES
fi
