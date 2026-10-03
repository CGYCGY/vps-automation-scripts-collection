# Coolify Setup

Sets up [Coolify](https://coolify.io) on a Linux server, in one of two roles:

- **dashboard**: installs Coolify itself.
- **managed**: prepares a server that a Coolify dashboard deploys to.

Coolify reaches managed servers through Tailscale SSH as the user `coolify`,
so no SSH key is ever copied around. Run the Tailscale setup and the
[tailnet policy](../../docs/tailscale-tailnet.md) first.

## Quick Start

```bash
sudo ./coolify-setup.sh
```

It is also run by `sudo ./server/setup.sh --coolify` and `--full`.

## What It Does

| Phase | dashboard | managed |
|-------|-----------|---------|
| plan | Asks the role, and whether to set up ghcr.io and a Cloudflare certificate (with its domain) | same |
| deps | Installs curl, wget, git, jq, openssl | same, plus Docker from get.docker.com |
| auto | Runs Coolify's official installer, which brings its own Docker; skipped if already installed unless you ask to rerun it | Creates user `coolify` in the `docker` and `sudo` groups, with passwordless sudo |
| interactive | Asks for the GitHub token, and takes the pasted Cloudflare certificate and key | same |
| summary | Dashboard URL over the tailnet, tagging reminder | Checks the `coolify` user and Docker, then shows what to enter in Coolify |

Coolify needs passwordless sudo, because it runs `docker` and `apt` through
sudo and can't answer a password prompt.

The firewall is left to the Tailscale setup.

## Adding a Managed Server to Coolify

1. Coolify → **Servers → Add Server**
2. IP/domain: the server's Tailscale name or IP (the script prints it). User:
   `coolify`. Port: `22`.
3. Coolify still makes you pick a private key. Any key works, because Tailscale
   SSH ignores it.
4. **Validate Server**.

If validation fails with exit code 255, the tailnet policy is missing the
`tag:coolify → tag:vps` rule for user `coolify`, or the dashboard isn't tagged
`tag:coolify`. See [Checking Who Got In](../../docs/tailscale-tailnet.md#checking-who-got-in).

## Optional Extras

### GitHub Container Registry

Logs Docker in to `ghcr.io`, so Coolify can pull private images. Create a token
at GitHub → Settings → Developer settings → Personal access tokens (classic),
with scope `read:packages`. Root's credentials are also copied to the
`coolify` user, which is the user Coolify pulls as on a managed server.

### Cloudflare Origin Certificate

Installs a Cloudflare origin certificate into Coolify's proxy for HTTPS.

1. Cloudflare → your domain → SSL/TLS → Origin Server → **Create Certificate**:
   RSA (2048), hostnames `*.example.com` and `example.com`, 15 years.
2. Paste the certificate and the key when the script asks, or pass them as
   files with `CF_CERT_FILE` and `CF_KEY_FILE`.
3. The script saves them to `/data/coolify/proxy/certs/`, checks them with
   openssl, and writes `/data/coolify/proxy/dynamic/cloudflare-origin-cert.yaml`
   for Traefik.
4. In Cloudflare, set SSL/TLS to **Full (strict)** and turn on **Always Use
   HTTPS**. Then restart the proxy in Coolify and redeploy.

## Unattended Runs

Every question can be answered up front, and `-y` takes the defaults for the rest:

```bash
sudo MACHINE_ROLE=managed ./coolify-setup.sh -y
```

| Variable | Values |
|----------|--------|
| `MACHINE_ROLE` | `dashboard`, `managed` |
| `COOLIFY_REINSTALL` | `yes` / `no`: rerun Coolify's installer (upgrades it) |
| `COOLIFY_GHCR` | `yes` / `no`: log Docker in to ghcr.io |
| `GHCR_USER`, `GHCR_TOKEN` | GitHub username and token; the token is asked for if unset |
| `COOLIFY_CF_CERT` | `yes` / `no`: install a Cloudflare origin certificate |
| `CF_DOMAIN` | domain the certificate covers |
| `CF_TRAEFIK_CONFIG` | `yes` / `no`: write the Traefik config that loads it |
| `CF_CERT_FILE`, `CF_KEY_FILE` | certificate and key files; pasted if unset |

Options: `-y` (defaults, no questions), `--phase plan|deps|auto|interactive|summary`
(used by the server menu), `--help`.

## Troubleshooting

```bash
# Is Coolify running? (dashboard)
docker ps | grep coolify
docker logs coolify --tail 100

# Can the coolify user use Docker and sudo? (managed)
sudo -u coolify docker ps
sudo -u coolify sudo -n true && echo ok

# Did the dashboard's SSH get in? (managed)
journalctl -u tailscaled --since "10 min ago" | grep -E "ssh-conn|ssh-session"

# Is the Cloudflare certificate loaded?
docker exec coolify-proxy ls -la /traefik/certs/
docker logs coolify-proxy --tail 100
```

## File Locations

| Path | Contents |
|------|----------|
| `/data/coolify/` | Coolify data |
| `/data/coolify/source/.env` | Coolify's secrets; back it up somewhere safe |
| `/data/coolify/proxy/certs/` | TLS certificates |
| `/data/coolify/proxy/dynamic/` | Traefik dynamic configs |
| `/etc/sudoers.d/coolify` | Passwordless sudo for `coolify` |
| `~/.docker/config.json` | Docker registry credentials |

## Resources

- [Coolify Documentation](https://coolify.io/docs)
- [Cloudflare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
