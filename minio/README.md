# MinIO Migration Tool

Interactive tool for migrating MinIO object storage data between servers with zero downtime.

## Quick Start

```bash
# Run from this directory
chmod +x minio_migration.sh
./minio_migration.sh
```

## Features

- Auto-installs MinIO Client (mc) if not present
- Saves configuration for repeated use (`~/.minio_migration_config`)
- Color-coded interactive interface
- Auto-detects Docker MinIO containers
- Multiple migration modes (all buckets, single bucket, multi-select)
- Built-in verification tools
- Progress monitoring and logging
- Advanced options: bandwidth limiting, sync mode, resume capability

## What This Script Does

1. **Install/Verify MinIO Client** (mc command-line tool)
2. **Configure Source MinIO** - supports direct IP/port and Tailscale network
3. **Configure Destination MinIO** - auto-detects Docker containers
4. **Create Buckets** on destination with auto-discovery
5. **Migrate Data** with retry logic and progress logging
6. **Verify Migration** - file count and size comparison
7. **Advanced Options** - bandwidth control, sync mode, resume

## Use Cases

- Migrating MinIO from Portainer to Coolify deployments
- Moving data between VPS providers
- Consolidating multiple MinIO instances
- Creating MinIO backups/replicas
- Zero-downtime migrations (keeps source online)

## Requirements

- Source MinIO instance (accessible via network)
- Destination MinIO instance (can be empty)
- Network connectivity between servers
- Access credentials for both MinIO instances
- Sufficient storage space on destination
- Linux server with bash

## Migration Strategies

### Strategy 1: Direct Migration (Fastest)
```
Server A (Source) ────> Server B (Destination)
   MinIO                    MinIO
```

### Strategy 2: Via Tailscale (Most Secure)
```
Server A ─── Tailscale Network ─── Server B
   MinIO                              MinIO
```

### Strategy 3: Staged Migration (For Large Data)
```
Migrate buckets one at a time:
  1. High priority buckets first
  2. Test applications
  3. Continue with remaining
```

## Configuration Examples

### Portainer MinIO to Coolify MinIO
```
Source: http://portainer-server:9000
Destination: Auto-detect Docker (http://172.17.0.3:9000)
```

### Via Tailscale Network
```
Source: http://100.x.x.1:9000
Destination: http://100.x.x.2:9000
```

### Public Domain Access
```
Source: https://minio-old.yourdomain.com
Destination: https://s3.yourdomain.com
```

## Security Features

- Saves credentials securely (`~/.minio_migration_config`, mode 600)
- Never logs credentials to migration logs
- Tests connections before migration
- Preserves original data (non-destructive)
- Detailed audit logs per bucket

## Troubleshooting

### Can't connect to source/destination
```bash
# Check if MinIO is running
docker ps | grep minio

# Test direct connection
curl http://IP:9000

# Check firewall
sudo ufw status

# Verify credentials
mc alias set test http://IP:9000 ACCESS_KEY SECRET_KEY
mc ls test
```

### Migration stuck halfway
```bash
# Check network activity
sudo iftop

# Resume migration
mc mirror source-minio dest-minio --preserve

# Or use "Resume incomplete migration" option
```

### Destination not accessible (Coolify/Traefik)
```bash
# Find MinIO container
docker ps | grep minio

# Get internal Docker IP
docker inspect <container> | grep IPAddress

# Use internal IP: http://172.17.0.x:9000
```

### Access Denied errors
```bash
# Verify credentials and permissions
mc admin user info dest-minio ACCESS_KEY
```

## File Locations

| Path | Description |
|------|-------------|
| `~/.minio_migration_config` | Saved credentials (mode 600) |
| `migration-<bucket>-<timestamp>.log` | Per-bucket migration logs |

## Resources

- [MinIO Docs](https://min.io/docs/minio/linux/index.html)
- [MinIO Client Guide](https://min.io/docs/minio/linux/reference/minio-mc.html)
- [MinIO Administration](https://min.io/docs/minio/linux/administration/minio-console.html)
