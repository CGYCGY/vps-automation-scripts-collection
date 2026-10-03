# Tailscale SSH Setup Scripts

Automated setup scripts for securing your VPS/server with Tailscale SSH. No more managing SSH keys!

## Scripts

| Script | Use Case |
|--------|----------|
| `tailscale-vps-setup.sh` | Generic VPS (DigitalOcean, Linode, Vultr, Hetzner, etc.) |
| `tailscale-vps-setup-oracle.sh` | Oracle Cloud Infrastructure with OCI-specific handling |

## Quick Start

### Generic VPS
```bash
chmod +x tailscale-vps-setup.sh
sudo ./tailscale-vps-setup.sh
```

### Oracle Cloud
```bash
chmod +x tailscale-vps-setup-oracle.sh
sudo ./tailscale-vps-setup-oracle.sh
```

## What These Scripts Do

1. **Update system packages** (optional)
2. **Install Tailscale VPN**
3. **Start Tailscale** and authenticate via browser
4. **Configure firewall**
   - SSH restricted to Tailscale network only
   - Optional HTTP/HTTPS ports
   - Custom port configuration
5. **Enable Tailscale SSH** (keyless authentication)
6. **Disable SSH password authentication** (recommended)
7. **Set up emergency console access**
8. **Provide verification summary**

## Supported Systems

- **Ubuntu**: 22.04, 24.04 (LTS)
- **Debian**: 11, 12
- **Architectures**: ARM64 (aarch64) and x86_64 (amd64)

## Providers

| Provider | Script |
|----------|--------|
| DigitalOcean | Generic |
| Linode | Generic |
| Vultr | Generic |
| Hetzner | Generic |
| Contabo | Generic |
| OVH | Generic |
| Oracle Cloud | Oracle-specific |

## Oracle Cloud Notes

The Oracle version includes special handling for:
- OCI Serial Console emergency access
- Security List configuration guidance
- iptables-based firewall (instead of UFW)

**After running the Oracle script:**
1. Navigate to: Networking > Virtual Cloud Networks > Security Lists
2. Remove/restrict SSH (port 22) from 0.0.0.0/0
3. Add HTTP/HTTPS rules if needed
4. Set up Serial Console for emergency access

## Security Features

- Restricts SSH to Tailscale network only (100.x.x.x/8)
- Disables password authentication
- Enables Tailscale SSH for keyless auth
- Preserves emergency console access
- Color-coded output for clarity
- Step-by-step verification

## Tips & Best Practices

### Use Tailscale ACLs for Team Access
```json
{
  "ssh": [{
    "action": "accept",
    "src": ["user1@github", "user2@google"],
    "dst": ["tag:production-servers"],
    "users": ["deploy", "admin"]
  }]
}
```

### Tag Your Servers
```bash
sudo tailscale up --ssh --advertise-tags=tag:webserver
```

### Enable MagicDNS
Access servers by name instead of IP:
```bash
ssh username@server-name
```

## Troubleshooting

### Can't connect via Tailscale SSH?
```bash
# Check Tailscale status
tailscale status

# Verify both devices are in the same Tailnet
tailscale status | grep "logged in"

# Ensure Tailscale SSH is enabled
sudo tailscale up --ssh
```

### Lost SSH access completely?

**Oracle Cloud:**
- Use Serial Console in OCI dashboard

**Other VPS:**
- Use provider's VNC/console access
- Check provider's control panel

### Verify firewall configuration
```bash
# UFW (Generic VPS)
sudo ufw status verbose

# iptables (Oracle)
sudo iptables -L -n
```

## Important Notes

- Review the script before running (good security practice)
- Backup important data before making system changes
- Set a strong password for emergency console access
- Test Tailscale SSH before removing other access methods
- Keep Tailscale updated for latest security patches

## Resources

- [Tailscale Docs](https://tailscale.com/kb/)
- [Tailscale SSH Guide](https://tailscale.com/kb/1193/tailscale-ssh/)
- [Tailscale ACLs](https://tailscale.com/kb/1018/acls/)
- [UFW Documentation](https://help.ubuntu.com/community/UFW)
