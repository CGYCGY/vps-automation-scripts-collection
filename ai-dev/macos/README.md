# AI Development Toolchain Setup — macOS

The macOS counterpart of [`../ai-dev-setup.sh`](../README.md). It installs the
same coding agents but sets up the Mac the Mac way: Homebrew in place of apt and
zsh (`~/.zshrc`) in place of bash. It runs on the bash 3.2 that macOS ships,
so nothing has to be installed first.

## Quick Start

```bash
curl -fsSLO https://raw.githubusercontent.com/CGYCGY/vps-automation-scripts-collection/master/ai-dev/macos/ai-dev-setup-macos.sh
chmod +x ai-dev-setup-macos.sh
./ai-dev-setup-macos.sh
```

Or from a checkout:

```bash
git clone https://github.com/CGYCGY/vps-automation-scripts-collection.git
cd vps-automation-scripts-collection
./ai-dev/macos/ai-dev-setup-macos.sh
```

Run it as your normal user, not with `sudo`. If Homebrew is missing, the script
asks for your password once so Homebrew can install.

## What It Does

| Step | macOS install |
|------|---------------|
| `homebrew` | Official Homebrew installer, which also installs the Xcode Command Line Tools; `brew shellenv` goes in `~/.zprofile` |
| `nvm` | nvm's `install.sh`, with `PROFILE=/dev/null` so it leaves `~/.zshrc` alone |
| `node` | `nvm install node`, which becomes nvm's default |
| `bun` | `brew install bun` |
| `shell-path` | A marked block in `~/.zshrc` covering `~/.local/bin`, the nvm loader and `~/.bun/bin` |
| `claude` | `claude.ai/install.sh` |
| `codex` | `npm i -g @openai/codex` |
| `pi` | `bun add -g @earendil-works/pi-coding-agent` |
| `prime-agent` | Prime Intellect's installer, with every prompt answered yes (see below) |
| `herdr` | `herdr.dev/install.sh` |
| `agy` | Antigravity CLI installer |
| `agent-browser` | `npm i -g agent-browser` followed by `agent-browser install` (Chrome for Testing) |
| `aliases` | `cc`, `aa`, `pa`, `upd`, `dc`, `jj`, added to `~/.zshrc` |
| `project-navigator` | The zsh `cdp` from [CGYCGY/shell-utils](https://github.com/CGYCGY/shell-utils), installed to `~/.zsh/project-navigator.zsh` |

Every vendor installer is downloaded to a file before it runs. macOS `curl`
(LibreSSL) sometimes drops the connection, and a `curl | bash` pipe would then
run a truncated script.

### Prime Agent, Unattended

The Prime Agent installer asks *Install?* and *Prepare Python runtime?*. It
reads the answers straight from `/dev/tty`, so neither a pipe nor `yes |` can
answer them. Both prompts default to yes, and when no terminal can be opened
each one proceeds as if you had pressed yes. The script therefore runs the
installer detached from the terminal. The same job is done by `setsid` on Linux;
macOS has no `setsid`, so the script uses Perl's `POSIX::setsid`. The result is
the same as pressing yes at every prompt. Node must already be installed, which
the `node` step guarantees.

## Differences from the Linux Script

- Homebrew replaces `apt`, and `--upgrade` runs `brew update && brew upgrade`.
- Everything goes in `~/.zshrc`; there is no `~/.bash_aliases`.
- `agy install` is not run. The installer already puts `agy` in `~/.local/bin`,
  and `agy install` would add a duplicate PATH line to `~/.zprofile`.
- `agent-browser install` runs without `--with-deps`, since macOS needs no extra
  system libraries.
- Agent instructions (`../agent-instructions`) and the Claude status line
  (`../claude/statusline-command.sh`) are **not** deployed unless you pass
  `--with-instructions`. `jq`, which the status line needs, is installed with
  brew when the Mac lacks it.
- `cdp` registers its tab completion with `compdef`, so `compinit` is added
  only when `~/.zshrc` and oh-my-zsh do not already load it.

## Options

| Flag | Behavior |
|------|----------|
| `-y`, `--yes` | Install without the confirmation prompt |
| `--upgrade` | Also run `brew update && brew upgrade` |
| `--status` | Survey the machine without changing anything |
| `--force` | Reinstall everything, ignoring detection |
| `--with-instructions` | Also deploy `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` and the Claude status line (needs a checkout) |
| `--reset` | Discard saved progress from an interrupted run |

`NODE_VERSION` and `NVM_VERSION` work the same way as in the Linux script.

Detection, resume and backups also match the Linux script. Re-runs skip
anything already present, even when it was configured by hand. A failed run
can be resumed. Before the script changes a file, it saves a timestamped
`.backup.*` copy.

## Project Navigator Fallback

`project-navigator.zsh` here is the offline fallback copy. Refresh it when
upstream changes:

```bash
curl -fsSL https://raw.githubusercontent.com/CGYCGY/shell-utils/master/zsh/profile-scripts/project-navigator.zsh -o ai-dev/macos/project-navigator.zsh
```

## After Installing

```bash
claude          # browser OAuth
codex login     # browser OAuth
agy             # browser OAuth with Google
pi              # configure an API key
prime-agent     # configure an API key
herdr --help    # follow the tool's authentication guidance
exec zsh -l     # reload the shell
upd             # verify every tool updates
cdp add <name>  # register this Mac's projects
```

The `jj` and `dc` aliases need `brew install just` and Docker Desktop
(`brew install --cask docker`), which this script does not install.
