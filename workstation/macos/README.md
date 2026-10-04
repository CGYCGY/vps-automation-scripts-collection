# Mac Workstation Setup

Sets up a Mac as a work machine: Homebrew and everyday apps, Tailscale SSH,
the AI coding-agent toolchain, and the settings an always-on Mac needs.

```bash
./workstation/setup.sh            # run it; asks for sudo once
./workstation/setup.sh --status   # survey this Mac, change nothing
./workstation/setup.sh -y         # take the default for every question
```

Run it as your normal user, not with `sudo`. It runs on the bash 3.2 that
macOS ships, so nothing has to be installed first.

## Order

1. **sudo:** asked once. It stays valid for the whole run, so no step stops
   halfway to ask again.
2. **Questions:** desktop apps or not, always on or not, git identity, GitHub
   key, your projects, the agent skills. Then one "Start the setup?".
3. **Dependencies:** Homebrew, apps, Tailscale. Then Full Disk Access is
   checked, once the apps it applies to exist.
4. **No input needed:** Tailscale as a system service, the AI dev toolchain,
   power, Finder, Zed settings, git settings, project folders and `cdp` names,
   links for the agent skills whose repos are already there.
5. **Needs you:** the Tailscale login, then creating the GitHub key and adding
   it to your account, then Remote Login off. Your projects are cloned once the
   key is on the account, then the repos of any skills still missing.

## Modules

| Module | What it does |
|--------|--------------|
| `homebrew.sh` | Homebrew, with `brew shellenv` in `~/.zprofile` |
| `apps.sh` | btop, just, OrbStack. Warp, Zed and RustDesk too, unless the Mac is headless. Apps already in /Applications count as installed |
| `tailscale.sh` | The brew `tailscaled` as a system service, so it starts before anyone logs in; logs in with Tailscale SSH on. The machine stays untagged |
| `full-disk-access.sh` | Checks that the terminal has Full Disk Access; if not, opens the System Settings list |
| `ai-dev.sh` | Runs [the AI dev toolchain setup](../shared/ai-dev/macos/README.md) unattended |
| `power.sh` | On power: no sleep, and restart after a power cut. Defaults to no on a laptop |
| `finder.sh` | Finder shows hidden files |
| `zed.sh` | Merges `zed-settings.json` into Zed's settings when Zed is installed: panel docks, Ayu themes, telemetry off. Only values that differ from Zed's defaults are tracked. The rewrite drops the file's comments, so the original is kept as a `.backup.*` copy |
| `ssh.sh` | Git identity, GitHub https URLs through SSH, a GitHub key in the Keychain, and Remote Login off |
| [`projects.sh`](../shared/projects/README.md) | Optional, one question. Clones the repos in your projects list and registers each name with `cdp` |
| [`skills.sh`](../shared/skills/README.md) | Optional, one question. Links each agent skill into `~/.claude/skills` from your projects checkout, or from a clone in `~/.gylab/<repo>` |

Each module also runs alone, e.g. `./workstation/macos/power.sh --status` or
`./workstation/shared/projects/projects.sh`.

## Remote Access

Remote access is through Tailscale SSH only (see the
[tailnet guide](../../docs/tailscale-tailnet.md)). Apple's Remote Login is
turned off, but only when it's safe to:

- **Tailscale is connected.** Otherwise turning it off could lock you out.
- **The terminal has Full Disk Access.** macOS refuses to turn it off from a
  script without it.

If either is missing, the summary says so and a re-run finishes it.

## Full Disk Access

Only a person can grant it, in System Settings → Privacy & Security → Full Disk
Access, and an app only picks it up after it restarts. On a first run the
script opens that list and carries on. Turn on Terminal and Warp, reopen them,
and run the setup again for the steps that need it.

## Answers Up Front

| Variable | Values |
|----------|--------|
| `MAC_HEADED` | `yes` / `no`: install Warp, Zed and RustDesk |
| `MAC_ALWAYS_ON` | `yes` / `no`: no sleep on power, restart after a power cut |
| `GIT_NAME`, `GIT_EMAIL` | git identity |
| `GH_SSH_KEY` | `yes` / `no`: create a GitHub key when none exists |
| `PROJECTS_SETUP` | `yes` / `no`: clone your projects |
| `PROJECTS_SOURCE` | URL, file path or JSON of your projects list, when there is none yet |
| `PROJECTS_ROOT` | where your projects live, when the list has no root |
| `SKILLS_SETUP` | `yes` / `no`: link the agent skills |
