# Tailscale SSH Setup (Linux)

Puts a Linux server or workstation on your tailnet with Tailscale SSH, then
locks SSH to the tailnet. Nobody manages SSH keys: Tailscale decides who gets
in, using your tailnet policy.

Set up the tailnet policy first. Follow the [tailnet guide](../../../docs/tailscale-tailnet.md),
because tagging a server before the policy covers it cuts off Coolify.

## Quick Start

```bash
sudo ./tailscale-setup.sh
```

It is also run by `sudo ./server/setup.sh --tailscale` and `--full`.

## What It Does

| Phase | Steps |
|-------|-------|
| plan | Asks the machine's role, which ports to open, and whether to set a console password |
| deps | Installs curl, ufw, jq and Tailscale |
| auto | Writes the UFW rules, without turning UFW on yet |
| interactive | Logs in with Tailscale SSH and the role's tags, sets the console password, then turns UFW on and SSH password login off |

The lockdown only happens once Tailscale is connected, so a failed login can't
lock you out.

### Roles

| Role | Tailscale tags | Ports opened by default |
|------|----------------|-------------------------|
| `dashboard` | `tag:vps`, `tag:coolify` | 22, 8000, 6001, 6002 from the tailnet |
| `managed` | `tag:vps` | 22 from the tailnet; 80 and 443 from anywhere |
| `workstation` | none | 22 from the tailnet |

If Tailscale refuses the tags because the policy doesn't define them yet, the
script logs in without tags and tells you to tag the machine in the admin
console. A machine that is already logged in can't be retagged from the command
line (`tailscale set` has no tag option), so the script tells you to tag it there too.

### SSH Password Login

The script writes `/etc/ssh/sshd_config.d/00-tailscale-ssh.conf`. Many cloud
images ship `50-cloud-init.conf` with `PasswordAuthentication yes`. sshd uses
the first value it reads, so a file sorting before it is the one that works;
editing `sshd_config` itself has no effect.

## Unattended Runs

Every question can be answered up front, and `-y` takes the defaults for the rest:

```bash
sudo MACHINE_ROLE=managed TS_TAILNET_PORTS="5432" ./tailscale-setup.sh -y
```

| Variable | Values |
|----------|--------|
| `MACHINE_ROLE` | `dashboard`, `managed`, `workstation` |
| `TS_PUBLIC_WEB` | `yes` / `no`: open 80 and 443 to the internet |
| `TS_PUBLIC_PORTS` | e.g. `"3000 5000/udp"`: more ports open to the internet |
| `TS_TAILNET_PORTS` | e.g. `"5432"`: ports open to the tailnet only |
| `TS_UFW_RESET` | `yes` / `no`: drop existing UFW rules first |
| `TS_SET_PASSWORD` | `yes` / `no`: set a password for the provider's console |
| `TS_AUTHKEY` | log in with an auth key instead of the browser |

## Docker Bypasses UFW

Docker publishes container ports through its own iptables rules, before UFW
sees the traffic. Coolify's 80, 443, 8000, 6001 and 6002 are therefore open to
the internet whatever UFW says. Close the ones that shouldn't be public in your
provider's firewall. On Oracle Cloud, that is the subnet's Security List.

## Supported Systems

- Ubuntu 22.04, 24.04 / Debian 11, 12, 13
- ARM64 (aarch64) and x86_64 (amd64)
- Oracle Cloud is detected automatically; the summary then gives Security List
  steps, and the console password defaults to yes

## Lost Access?

- Use the provider's web console (Oracle Cloud: Serial Console). This is why
  the script offers a console password.
- `sudo tailscale status` shows whether the machine is connected.
- `sudo ufw status verbose` shows the firewall rules.

## Resources

- [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh)
- [Tailnet policy file](https://tailscale.com/kb/1018/acls)
