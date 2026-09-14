# AI Development Toolchain Setup

Bootstraps a VPS or local box with the author's AI coding-agent toolchain so it can be used for remote AI-assisted development.

## Quick Start

Run this setup as your normal user, not with `sudo`. The script installs into `$HOME` and invokes `sudo` itself only when apt packages are needed.

```bash
chmod +x ai-dev-setup.sh
./ai-dev-setup.sh
```

From the repository root:

```bash
./setup.sh --ai-dev
```

## What It Does

The script installs nvm and Node.js, Bun, Claude Code, Codex, Pi, Prime Agent, Herdr, Antigravity (`agy`), the author's shell aliases, and the `cdp` project navigator from [CGYCGY/shell-utils](https://github.com/CGYCGY/shell-utils). It also configures the user shell paths required by those tools and deploys the tracked agent instructions to:

- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- `~/.gemini/GEMINI.md`

The source files live under `agent-instructions/`. Existing destination files are backed up with a timestamp before they are replaced, and reruns skip files that already match.

This is the author's toolchain. Edit the `APT_PACKAGES` and `ALIAS_DEFS` arrays near the top of `ai-dev-setup.sh` to customize the packages and aliases.

The three instruction files intentionally remain separate so each tool can use its own model identifiers and tool-specific guidance. Update the tracked copies before running the setup on another machine.

## Project Navigator

`project-navigator.sh` is fetched from shell-utils at install time so a new machine gets the current version; the copy tracked here is the offline fallback. It lands at `~/.project-navigator.sh` with an empty registry — the upstream entries are example paths — and `~/.bashrc` is made to source it. Register projects on the new machine with `cdp add <name>`. An existing `~/.project-navigator.sh` is never overwritten, since it holds that machine's own registry.

Refresh the bundled fallback when upstream changes:

```bash
curl -fsSL https://raw.githubusercontent.com/CGYCGY/shell-utils/master/bash/profile-scripts/project-navigator.sh -o ai-dev/project-navigator.sh
```

## Options

| Flag | Behavior |
|------|----------|
| `-y`, `--yes` | Install without the confirmation prompt |
| `--upgrade` | Also run a full apt dist-upgrade |
| `--status` | Survey the machine without changing anything |
| `--force` | Reinstall everything, ignoring detection |
| `--reset` | Discard saved progress from an interrupted run |

## Environment Overrides

Versions float to the latest releases by default. Override them for one run:

```bash
NODE_VERSION=25.2.1 NVM_VERSION=v0.40.7 ./ai-dev-setup.sh
```

- `NODE_VERSION` accepts values supported by nvm, such as `24`, `25.2.1`, or `--lts`; its default is `node`.
- `NVM_VERSION` accepts an nvm tag such as `v0.40.7`; when unset, the latest release tag is detected.

## Detection and Resume Behavior

Before installing, the script surveys every component and shows what is present or missing. Re-running it skips detected components. If a run fails, completed steps are recorded under `${XDG_STATE_HOME:-$HOME/.local/state}/new-device-setup`; fix the cause and rerun to resume. The progress record is removed after a successful run.

Existing `new-device-setup` shell markers remain recognized for compatibility with machines bootstrapped under the script's former name.

## Post-install Authentication

Each coding agent authenticates separately. After installation:

```bash
claude          # browser OAuth
codex login     # browser OAuth
agy             # browser OAuth with Google
pi              # configure an API key
prime-agent     # configure an API key
herdr --help    # follow the tool's authentication guidance
exec bash -l    # reload shell configuration
upd             # verify the installed tools update successfully
cdp add <name>  # register this machine's projects
```
