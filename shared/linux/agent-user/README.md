# Agent User Setup (Linux)

Creates a local account for an automation agent that logs in over Tailscale
SSH: a regular user named `agent`, password locked, with passwordless sudo from
a single drop-in file. Tailscale decides who may log in, so the account needs
no password and no SSH key.

## Quick Start

```bash
sudo ./agent-user-setup.sh                 # creates the user "agent"
sudo ./agent-user-setup.sh --user bot      # another name
./agent-user-setup.sh --status             # what is in place; the password and sudoers checks need sudo
```

From the repository root, the same module runs as `sudo ./setup.sh agent-user
[--status|-y|--user NAME]`, or on a server as `sudo ./server/setup.sh
--agent-user [--user NAME]`. It is not part of `--full`.

Linux only: Debian, Ubuntu and Mint, WSL included. On a Mac, `--status` reports
it as not supported and exits 0; a setup run stops with an error.

## What It Does

| Phase | Steps |
|-------|-------|
| plan | Refuses `root`, your own account and system accounts; asks to lock the password if an existing `agent` has one |
| deps | Installs `sudo` (which brings `visudo`) when it is missing |
| auto | Creates the user, locks its password, writes the sudoers drop-in |
| summary | How to log in, and how to narrow sudo later |

Each step is skipped when already done, so a run that stopped halfway is
finished by running it again.

- **User**: `useradd -m -d /home/agent -s /bin/bash agent`. An existing `agent`
  is kept; only its shell is set to `/bin/bash` if it is something else.
- **Password**: locked (`passwd -S` shows `L`). A new user starts locked. An
  empty password is always locked; a real one only after you say yes.
- **Sudo**: `/etc/sudoers.d/agent`, mode 0440, owned by root, containing:

  ```
  agent ALL=(ALL) NOPASSWD: ALL
  ```

  The file is checked with `visudo -cf` before it is moved into place, since one
  broken file in `/etc/sudoers.d` stops sudo for everyone. A file that passes
  `visudo -cf` with mode 0440 and owner root is left alone, whatever it says,
  so an allowlist you narrowed it to survives a re-run. Anything else is
  replaced.

### `--status`

```
  agent-user         present   agent (uid 1001), home /home/agent, shell /bin/bash
  agent-password     present   locked
  agent-sudo         present   passwordless, /etc/sudoers.d/agent, valid
```

On a machine without the user, each row says `missing` and what the setup will
do. A sudoers file you narrowed shows as `present` and `customized`. Without
sudo, `agent-password` and an existing `agent-sudo` say `unknown`.

## Narrowing Sudo Later

Everything the agent may run as root is in that one file. Replace the line with
an allowlist, for example:

```bash
sudo visudo -f /etc/sudoers.d/agent
```

```
agent ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp, /usr/bin/apt-get update
```

A re-run keeps the narrowed file and `--status` reports it as `customized`.
To go back to full sudo, delete the file and re-run.

## Tailnet Policy

No change needed. The `autogroup:nonroot` users in the
[tailnet policy](../../../docs/tailscale-tailnet.md#the-policy) include every
account except root, so `ssh agent@host` works from your own devices to your
servers and to your other untagged machines.

## Unattended Runs

```bash
sudo AGENT_USER=agent AGENT_LOCK_PASSWORD=yes ./agent-user-setup.sh -y
```

| Variable | Values |
|----------|--------|
| `AGENT_USER` | the account name, same as `--user` (default `agent`) |
| `AGENT_LOCK_PASSWORD` | `yes` / `no`: lock the password of an existing account that has one (`-y` says yes) |

## Removing It

```bash
sudo rm /etc/sudoers.d/agent
sudo userdel -r agent
```
