# Linux Workstation Setup

Sets up a Linux machine (Debian or Ubuntu) as a work machine: git and a GitHub
key, the AI coding-agent toolchain, your projects and the agent skills.

```bash
./workstation/setup.sh            # run it
./workstation/setup.sh --status   # survey this machine, change nothing
./workstation/setup.sh -y         # take the default for every question
```

Run it as your normal user, not with `sudo`. Nothing asks for sudo up front:
`sudo` is called only to install missing apt packages. Tailscale SSH is set up
separately, as root, by
[`shared/linux/tailscale/tailscale-setup.sh`](../../shared/linux/tailscale/README.md);
run that first (see the root README's Linux Workstation workflow).

## Order

1. **Questions:** git identity, GitHub key, your projects, the agent skills.
   Then one "Start the setup?".
2. **Dependencies:** git and the ssh client, git-crypt, qrencode, stow, then
   the whole AI dev toolchain, because it brings the `jq` the projects and
   skills modules need.
3. **No input needed:** git settings, project folders and `cdp` names, links
   for the agent skills whose repos are already there.
4. **Needs you:** creating the GitHub key and adding it to your account. Your
   projects are cloned once the key is on the account, then the repos of any
   skills still missing.

## Modules

| Module | What it does |
|--------|--------------|
| `ssh.sh` | Git identity, GitHub https URLs through SSH, and a GitHub key at `~/.ssh/id_ed25519`. The key has no passphrase: there is no Keychain to remember one. With no terminal, it prints the key and leaves the "add it to GitHub" step for the summary |
| `apps.sh` | git-crypt, qrencode, stow |
| `ai-dev.sh` | Runs [the AI dev toolchain setup](../shared/ai-dev/README.md) unattended. `--upgrade` and `--force` given to `workstation/setup.sh` are passed on to it |
| [`projects.sh`](../shared/projects/README.md) | Optional, one question. Clones the repos in your projects list and registers each name with `cdp` |
| [`skills.sh`](../shared/skills/README.md) | Optional, one question. Links each agent skill into `~/.claude/skills` from your projects checkout, or from a clone in `~/.gylab/<repo>`; the library catalog is cloned straight to `~/.claude/skills/library` |

Each module also runs alone, e.g. `./workstation/linux/ssh.sh --status` or
`./workstation/shared/projects/projects.sh`.

## Answers Up Front

| Variable | Values |
|----------|--------|
| `GIT_NAME`, `GIT_EMAIL` | git identity |
| `GH_SSH_KEY` | `yes` / `no`: create a GitHub key when none exists |
| `PROJECTS_SETUP` | `yes` / `no`: clone your projects |
| `PROJECTS_SOURCE` | URL, file path or JSON of your projects list, when there is none yet |
| `PROJECTS_ROOT` | where your projects live, when the list has no root |
| `SKILLS_SETUP` | `yes` / `no`: link the agent skills |
