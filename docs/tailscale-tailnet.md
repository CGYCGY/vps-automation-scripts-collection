# Tailnet Setup

Every machine here is reached through Tailscale SSH: you, from your own devices,
and Coolify, from its dashboard. Nobody manages SSH keys. The tailnet policy
decides who can SSH where, so set it up before running the setup scripts.

## Machine Types and Tags

| Machine | Tags | Example |
|---------|------|---------|
| Coolify dashboard | `tag:vps` + `tag:coolify` | gylab-management |
| Server managed by Coolify | `tag:vps` | gylab |
| Workstation, laptop, phone | none | mac-mini, pc |

Tagging a server does two things:

- **It stops belonging to you.** It is no longer one of "your devices", so if a
  server is ever compromised, it can't SSH into your workstations.
- **Its key stops expiring**, so a server never drops off the tailnet because a
  login aged out.

The server setup (`sudo ./server/setup.sh`) asks for the role and requests the
matching tags when it logs in. Workstations stay untagged.

## The Policy

Admin console → **Access controls**. Leave the network rules (`grants` /
`acls`) as they are. Add the tags, and replace the `ssh` section:

```jsonc
"tagOwners": {
  "tag:vps":     ["autogroup:admin"],
  "tag:coolify": ["autogroup:admin"],
},

"ssh": [
  // You, from your devices, to your other untagged devices
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["autogroup:nonroot"],
  },
  // You, from your devices, to servers
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["tag:vps"],
    "users":  ["autogroup:nonroot", "root"],
  },
  // The Coolify dashboard to the servers it manages
  {
    "action": "accept",
    "src":    ["tag:coolify"],
    "dst":    ["tag:vps"],
    "users":  ["coolify"],
  },
],
```

In the visual editor, the same three rules go in the **Tailscale SSH** tab, and
the tags in the **Tags** tab.

Notes on the rules:

- **`accept`, not `check`.** `check` asks you to log in through the browser again
  every 12 hours. With servers tagged, a server can't reach your devices
  anyway, so `check` adds little beyond the prompts.
- **`autogroup:self` gets its own rule.** Tailscale doesn't allow it in the same
  `dst` as tags.
- **Coolify logs in as `coolify`, not root.** The Coolify setup on a managed
  server creates that user with passwordless sudo.
- **Servers are never a source** except the dashboard's `tag:coolify` rule.

## Order Matters

1. Save the policy: tags first, then the SSH rules.
2. Only then tag machines, or run the server setup, which tags them itself.

Tagging the dashboard before the `tag:coolify` rule exists cuts Coolify off
from every server. It shows up in Coolify as *"Server is not reachable … SSH
command failed with exit code: 255"*.

## Tagging an Existing Machine

Admin console → **Machines** → `…` on the machine → **Edit ACL tags**. A
machine that is already logged in can't be retagged from the command line.

## Checking Who Got In

Tailscale SSH logs every connection on the target server:

```bash
journalctl -u tailscaled --since "10 min ago" | grep -E "ssh-conn|ssh-session"
```

- `access granted to tagged-devices as ssh-user "coolify"` means Coolify is in.
- `tailnet policy does not permit you to SSH to this node` means no rule matches.
  Check the source machine's tags and the rule's users.

## macOS

Only the open-source `tailscaled`, installed with `brew install tailscale`, can
accept Tailscale SSH on a Mac. The App Store and standalone apps can't. Run it
as a system service, so it starts before anyone logs in:

```bash
brew install tailscale
sudo brew services start tailscale
sudo tailscale up --ssh
```

Remote Login (Apple's own SSH server) can then stay off. Tailscale SSH doesn't
use it.
