# AI Development Toolchain Setup

Bootstraps a VPS or local box with the author's AI coding-agent toolchain so it can be used for remote AI-assisted development.

**On a Mac?** Use [`macos/ai-dev-setup-macos.sh`](macos/README.md) instead. It installs the same toolchain through Homebrew and zsh.

## Quick Start

On a new server or device, download the standalone file and run it. It carries
everything — the setup script, the agent instructions and settings, the Claude
status line and the `cdp` fallback — so nothing else has to be fetched:

```bash
curl -fsSLO https://raw.githubusercontent.com/CGYCGY/vps-automation-scripts-collection/master/workstation/shared/ai-dev/ai-dev-standalone.sh
chmod +x ai-dev-standalone.sh
./ai-dev-standalone.sh
```

Or without touching disk, which works because the prompt reads the terminal
rather than standard input:

```bash
curl -fsSL https://raw.githubusercontent.com/CGYCGY/vps-automation-scripts-collection/master/workstation/shared/ai-dev/ai-dev-standalone.sh | bash
```

Run the setup as your normal user, not with `sudo`. It installs into `$HOME` and
invokes `sudo` itself only when apt packages are needed. Every flag documented
below is forwarded, so `./ai-dev-standalone.sh --status` surveys the machine.

The standalone unpacks into a temporary directory, runs from there and removes
it afterwards. It installs the same files as a checkout and is regenerated from
the same sources, so the two are interchangeable.

### From a Checkout

Working on the scripts themselves, or already have the repository on the box:

```bash
git clone https://github.com/CGYCGY/vps-automation-scripts-collection.git
cd vps-automation-scripts-collection
./workstation/setup.sh
```

That runs this setup as one module of the
[Linux workstation setup](../../linux/README.md), after its questions and
alongside git and the GitHub key, your projects and the agent skills.
`workstation/shared/ai-dev/ai-dev-setup.sh` can be run directly too. It is tracked as executable,
so a clone needs no `chmod` — unlike a raw download, which carries no file mode.

## What It Does

The script installs nvm and Node.js, Bun, Claude Code, Codex, Pi, Prime Agent, Herdr, Antigravity (`agy`), agent-browser, the author's shell aliases, and the `cdp` project navigator from [CGYCGY/shell-utils](https://github.com/CGYCGY/shell-utils). It also configures the user shell paths required by those tools and deploys the tracked agent instructions to:

- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- `~/.gemini/GEMINI.md`

agent-browser also downloads Chrome for Testing into `~/.agent-browser` and
installs the system libraries headless Chrome needs, so the agents can drive a
browser on a server with no desktop.

It also installs the Claude Code status line from `claude/statusline-command.sh`
to `~/.claude/statusline-command.sh` (model, effort, context use, token counts
and cost) and points `statusLine` in `~/.claude/settings.json` at it. The rest of
`settings.json` is kept, and a `statusLine` the machine already has is never
replaced.

It merges the author's agent settings from `agent-settings/` into
`~/.claude/settings.json`, `~/.codex/config.toml` and `~/.pi/agent/settings.json`:
permission mode, theme, plugins, the Codex status line, pi's compaction and
telemetry, and similar. The tracked keys win; every other
key the machine has is kept, including Codex's own `[projects."…"]` tables.
Model, effort and pi's provider are deliberately left out, because they change too often.

Before agent-browser installs, `agent-browser` is added to npm's
`allow-scripts` list in `~/.npmrc`. npm 11 skips the install scripts of global
packages that aren't on that list.

The source files live under `agent-instructions/`. Existing destination files are backed up with a timestamp before they are replaced, and reruns skip files that already match.

This is the author's toolchain. Edit the `APT_PACKAGES` and `ALIAS_DEFS` arrays near the top of `ai-dev-setup.sh` to customize the packages and aliases.

The three instruction files intentionally remain separate so each tool can use its own model identifiers and tool-specific guidance. Update the tracked copies before running the setup on another machine.

## Regenerating the Standalone File

`ai-dev-standalone.sh` and `macos/ai-dev-setup-macos-standalone.sh` are
generated. The sources stay the truth: `ai-dev-setup.sh`, `project-navigator.sh`,
`macos/ai-dev-setup-macos.sh`, `macos/project-navigator.zsh`,
`claude/statusline-command.sh`, the three files under `agent-instructions/`, the
three under `agent-settings/`, and the repository's
`shared/lib/project-navigator-lib.sh`. A bundle unpacks them in the repository's
layout.
After editing any of them, rebuild both:

```bash
./build-standalone.sh          # regenerate
./build-standalone.sh --check  # fail if the committed copy is stale
```

Commit the regenerated files with the change that caused them, or the published
one-liners keep installing the previous version of the instructions.

The build is deterministic — identical sources produce a byte-identical file,
and nothing timestamped goes into it — so rebuilding without a source change
leaves no diff, and `--check` is a reliable staleness test.

## Project Navigator

`project-navigator.sh` is fetched from shell-utils at install time so a new machine gets the current version; the copy tracked here is the offline fallback. It lands at `~/.project-navigator.sh` with an empty registry — the upstream entries are example paths — and `~/.bashrc` is made to source it. Register projects on the new machine with `cdp add <name>`, or all at once with the [projects module](../projects/README.md). The install code is shared with that module in `shared/lib/project-navigator-lib.sh`. An existing `~/.project-navigator.sh` is never overwritten, since it holds that machine's own registry.

Refresh the bundled fallback when upstream changes:

```bash
curl -fsSL https://raw.githubusercontent.com/CGYCGY/shell-utils/master/bash/profile-scripts/project-navigator.sh -o workstation/shared/ai-dev/project-navigator.sh
```

## Options

| Flag | Behavior |
|------|----------|
| `-y`, `--yes` | Install without the confirmation prompt |
| `--upgrade` | Also run a full apt dist-upgrade |
| `--status` | Survey the machine without changing anything |
| `--force` | Reinstall everything, ignoring detection |
| `--reset` | Discard saved progress from an interrupted run |
| `--no-skills` | Don't offer the agent skills at the end |

After a successful run, the script asks "Set up the agent skills too?" and, on
yes, runs [`../skills/skills.sh`](../skills/README.md); with `-y` it says yes
and passes `-y` on. The standalone file has no `skills.sh`, so it prints where
the skills come from instead. The workstation setups run it with `--no-skills`,
since the skills are their own module there.

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
