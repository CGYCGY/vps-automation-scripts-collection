# VPS Automation Scripts Collection

Professional automation scripts for VPS/server management, security, and data migration.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/CGYCGY/vps-automation-scripts-collection.git
cd vps-automation-scripts-collection

# Run the main setup script
chmod +x setup.sh
sudo ./setup.sh
```

The interactive menu will guide you through available options.

### Command Line Options

```bash
sudo ./setup.sh --full       # Full server setup (swap + tailscale + coolify)
sudo ./setup.sh --tailscale  # Tailscale SSH setup only
sudo ./setup.sh --coolify    # Coolify installation only
sudo ./setup.sh --swap       # Swap configuration only
sudo ./setup.sh --minio      # MinIO migration tool
./setup.sh --minio-users     # MinIO user & bucket manager
sudo ./setup.sh --help       # Show all options
```

## Available Scripts

| Script | Description | Documentation |
|--------|-------------|---------------|
| **Tailscale SSH** | Secure VPS with Tailscale SSH - no more SSH keys | [tailscale/README.md](tailscale/README.md) |
| **Coolify Setup** | Self-hostable Heroku/Netlify alternative | [coolify/README.md](coolify/README.md) |
| **MinIO Migration** | Migrate MinIO data between servers | [minio/README.md](minio/README.md) |
| **MinIO User Manager** | Create users with bucket-specific access | [minio/README.md](minio/README.md) |
| **Swap Config** | RAM-based optimized swap settings | [swap/README.md](swap/README.md) |

## Supported Systems

- **OS**: Ubuntu 22.04, 24.04 LTS / Debian 11, 12
- **Architectures**: ARM64 (aarch64), x86_64 (amd64)
- **Providers**: Oracle Cloud, DigitalOcean, Linode, Vultr, Hetzner, Contabo, OVH, and most VPS providers

## Common Workflows

### New Server Setup
```bash
sudo ./setup.sh --full
```
This runs swap configuration, Tailscale SSH setup, and Coolify installation in sequence.

### Secure Existing Server
```bash
sudo ./setup.sh --tailscale
```
Restricts SSH access to Tailscale network only.

### Migrate MinIO Data
```bash
./setup.sh --minio
```
Interactive tool for migrating MinIO between servers.

## Directory Structure

```
.
├── setup.sh              # Main entry point
├── coolify/
│   ├── coolify-setup.sh  # Coolify installation script
│   └── README.md         # Coolify documentation
├── minio/
│   ├── minio_migration.sh          # MinIO migration tool
│   ├── minio_user_bucket_manager.sh # MinIO user & bucket manager
│   └── README.md                    # MinIO documentation
├── swap/
│   ├── swap-configuration-module.sh # Swap setup script
│   └── README.md                    # Swap documentation
└── tailscale/
    ├── tailscale-vps-setup.sh       # Generic VPS setup
    ├── tailscale-vps-setup-oracle.sh # Oracle Cloud setup
    └── README.md                     # Tailscale documentation
```

## Features at a Glance

| Feature | Tailscale | Coolify | MinIO | Swap |
|---------|-----------|---------|-------|------|
| Interactive prompts | Yes | Yes | Yes | Yes |
| Auto-install dependencies | Yes | Yes | Yes | N/A |
| Config preservation | No | Yes | Yes | Yes |
| Verification built-in | Yes | Yes | Yes | Yes |
| Resumable | N/A | N/A | Yes | N/A |

## Security Considerations

- All scripts require root/sudo for system modifications
- Credentials stored with restricted permissions (mode 600)
- Tailscale restricts SSH to private network
- Scripts are idempotent (safe to run multiple times)

## License

MIT License - See [LICENSE](LICENSE) for details.

## Resources

- [Tailscale Docs](https://tailscale.com/kb/)
- [Coolify Documentation](https://coolify.io/docs)
- [MinIO Docs](https://min.io/docs/minio/linux/index.html)

## Contributing

Found a bug or have a suggestion? Feel free to open an issue or submit a pull request.
