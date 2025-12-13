# MinIO Tools

Tools for managing MinIO object storage - user management, bucket access control, and data migration.

## Available Scripts

| Script | Description |
|--------|-------------|
| `minio_user_bucket_manager.sh` | Manage users with bucket-specific access |
| `minio_migration.sh` | Migrate data between MinIO servers |

---

# MinIO User & Bucket Manager

Interactive tool for managing MinIO users with bucket-specific access permissions. Perfect for creating restricted users who can only access selected buckets.

## Quick Start

```bash
chmod +x minio_user_bucket_manager.sh
./minio_user_bucket_manager.sh
```

## Features

- **Auto-installs MinIO Client (mc)** with architecture detection (amd64/arm64)
- **Alias Management**: List, create, switch, and remove MinIO connections
- **User Management**: Create, delete, enable/disable users
- **Bucket Access Control**: Assign read-only, read-write, or full access to specific buckets
- **Policy Management**: Automatically creates custom policies per user
- **Test User Access**: Verify user credentials and permissions
- **Interactive Interface**: Color-coded menus with clear prompts

## What This Script Does

1. **Alias Management**
   - List existing MinIO aliases
   - Create new alias (remote URL, localhost, or auto-detect Docker)
   - Switch between different MinIO servers
   - Remove aliases

2. **User Management**
   - View all users and their status
   - Create new users with secure passwords
   - Enable/disable users
   - Delete users (with cleanup of associated policies)

3. **Bucket Access Control**
   - Select specific buckets to grant access
   - Choose access level:
     - **Read-only**: GetObject, ListBucket
     - **Read-write**: GetObject, PutObject, ListBucket
     - **Full access**: All S3 operations
   - Automatically creates IAM-style policies

4. **Quick Setup Wizard**
   - Create a user and assign bucket access in one flow

## Use Cases

- **Multi-tenant setup**: Give each customer access to their own bucket
- **Application credentials**: Create service accounts with minimal permissions
- **Team access**: Different access levels for different teams
- **Backup access**: Read-only users for backup systems
- **Third-party integrations**: Limited access for external services

## Requirements

- Linux server with bash
- MinIO server with admin access (access key & secret key)
- Network connectivity to MinIO server

## Example Workflow

### Create a user with access to a specific bucket

1. Run `./minio_user_bucket_manager.sh`
2. Select or create an alias pointing to your MinIO server
3. Choose **Quick Setup** or navigate to User Management
4. Create user (e.g., `app-backend`)
5. Select bucket(s) to grant access (e.g., `uploads`)
6. Choose access level (e.g., read-write)
7. Done! The user can now access only the `uploads` bucket

### Test user credentials

1. Navigate to User Management > Test User Access
2. Select the user
3. Enter their password
4. Script shows what buckets they can access

## Policy Details

The script creates IAM-compatible policies like:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
            "Resource": [
                "arn:aws:s3:::bucket-name",
                "arn:aws:s3:::bucket-name/*"
            ]
        }
    ]
}
```

Policies are named `user-<username>-policy` and automatically attached to users.

## Troubleshooting

### "Admin access test failed"
- Ensure you're using admin credentials (not a restricted user)
- Check if the MinIO server allows admin API access

### User created but can't access bucket
- Verify the policy was attached: `mc admin policy entities ALIAS --user USERNAME`
- Check bucket name spelling in policy

### Connection timeout
- Verify MinIO URL is accessible
- Check firewall rules
- For Docker, try internal IP instead of localhost

---

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
