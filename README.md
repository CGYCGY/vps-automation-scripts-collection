# VPS Automation Scripts Collection

Professional automation scripts for VPS/server management, security, and data migration.

## 📦 Available Scripts

### 1. Tailscale SSH Setup Scripts
Automated setup scripts for securing your VPS/server with Tailscale SSH. No more managing SSH keys!

### 2. MinIO Migration Tool
Interactive tool for migrating MinIO data between servers with zero downtime.

---

## 🔐 Tailscale SSH Setup Scripts

### 🚀 Quick Start

#### Generic VPS (DigitalOcean, Linode, Vultr, Hetzner, etc.)

```bash
curl -fsSL https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/tailscale-vps-setup.sh -o setup.sh
chmod +x setup.sh
./setup.sh
```

#### Oracle Cloud Infrastructure (OCI)

```bash
curl -fsSL https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/tailscale-vps-setup-oracle.sh -o setup.sh
chmod +x setup.sh
./setup.sh
```

### 📋 What These Scripts Do

Both scripts provide a complete, automated setup:

1. ✅ **Update system packages** (optional)
2. ✅ **Install Tailscale VPN**
3. ✅ **Start Tailscale** and authenticate
4. ✅ **Configure UFW firewall**
   * SSH restricted to Tailscale network only
   * Optional HTTP/HTTPS ports
   * Custom port configuration
5. ✅ **Enable Tailscale SSH** (keyless authentication)
6. ✅ **Disable SSH password authentication** (recommended)
7. ✅ **Set up emergency console access**
8. ✅ **Provide comprehensive summary and verification**

---

## 🗄️ MinIO Migration Tool

Interactive script for migrating MinIO object storage data between servers with full control and verification.

### 🚀 Quick Start

```bash
curl -fsSL https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/minio_migration.sh -o minio_migration.sh
chmod +x minio_migration.sh
./minio_migration.sh
```

### ✨ Features

**Complete Migration Workflow:**
- 🔧 **Auto-installs MinIO Client (mc)** if not present
- 💾 **Saves configuration** for repeated use
- 🎨 **Color-coded interface** for easy navigation
- 🐳 **Auto-detects Docker MinIO** containers
- 🔄 **Multiple migration modes:**
  - Migrate all buckets
  - Migrate single bucket
  - Migrate selected buckets (multi-select)
- ✅ **Built-in verification** tools
- 📊 **Progress monitoring** and logging
- 🚀 **Advanced options:**
  - Bandwidth limiting
  - Sync with file removal
  - Resume incomplete migrations
  - Export detailed reports
  - View migration logs

### 📋 What This Script Does

The MinIO Migration Tool provides an interactive, step-by-step process:

1. ✅ **Install/Verify MinIO Client** (mc command-line tool)
2. ✅ **Configure Source MinIO** (your old server)
   - Supports direct IP/port access
   - Supports Tailscale network access
   - Tests connection before proceeding
3. ✅ **Configure Destination MinIO** (your new server)
   - Auto-detects Docker containers
   - Supports multiple access methods
   - Tests connection before proceeding
4. ✅ **Create Buckets** on destination
   - Auto-discovers source buckets
   - Selective or bulk creation
5. ✅ **Migrate Data** with options
   - Full migration with metadata preservation
   - Retry logic for reliability
   - Progress logging per bucket
6. ✅ **Verify Migration** success
   - File count comparison
   - Size comparison
   - Detailed diff reports
7. ✅ **Advanced Options** available
   - Bandwidth control for limited connections
   - Sync mode with cleanup
   - Resume capability

### 🎯 Use Cases

**Perfect for:**
- ✅ Migrating MinIO from Portainer to Coolify deployments
- ✅ Moving data between VPS providers
- ✅ Consolidating multiple MinIO instances
- ✅ Creating MinIO backups/replicas
- ✅ Testing new MinIO configurations
- ✅ Zero-downtime migrations (keeps source online)

**Supports:**
- ✅ MinIO instances on any server/VPS
- ✅ Docker-deployed MinIO (Portainer, Coolify, Docker Compose)
- ✅ Native MinIO installations
- ✅ Tailscale private network connections
- ✅ Public internet connections
- ✅ Local network migrations

### 🔍 Migration Workflow Example

```
1. Run Script
   └─> Installs mc if needed

2. Configure Source
   └─> Enter: http://100.x.x.1:9000
   └─> Test connection ✓

3. Configure Destination  
   └─> Auto-detect Docker IP
   └─> Test connection ✓

4. Create Buckets
   └─> Found: documents, images, backups
   └─> Create all on destination ✓

5. Migrate Data
   └─> Select: Migrate all buckets
   └─> documents: 1.2 GB, 543 files ✓
   └─> images: 3.4 GB, 1,234 files ✓
   └─> backups: 5.6 GB, 89 files ✓

6. Verify Migration
   └─> File count matches ✓
   └─> Size matches ✓
   └─> No differences found ✓
   
7. Migration Complete! 🎉
```

### 📝 Requirements

**For MinIO Migration:**
- ✅ Source MinIO instance (accessible via network)
- ✅ Destination MinIO instance (can be empty)
- ✅ Network connectivity between servers
- ✅ Access credentials for both MinIO instances
- ✅ Sufficient storage space on destination
- ✅ Linux server with bash (Ubuntu, Debian, etc.)

**Optional but recommended:**
- ✅ Tailscale network for secure private connections
- ✅ Screen/tmux for long migrations
- ✅ Adequate bandwidth for large data transfers

### 💡 Migration Strategies

#### Strategy 1: Direct Migration (Fastest)
```
Server A (Source) ─────> Server B (Destination)
   MinIO                    MinIO
```
- Run script on Server B
- Connect to Server A via IP or Tailscale
- Migrate directly

#### Strategy 2: Via Tailscale (Most Secure)
```
Server A ─── Tailscale Network ─── Server B
   MinIO                              MinIO
```
- Both servers on Tailscale
- Private encrypted connection
- No firewall configuration needed
- Run script on either server

#### Strategy 3: Staged Migration (For Large Data)
```
Migrate buckets one at a time:
  1. High priority buckets first
  2. Test applications
  3. Continue with remaining buckets
  4. Verify each step
```
- Minimizes risk
- Allows testing between migrations
- Better for production systems

### 🔒 Security Features

**MinIO Migration Tool:**
- 🔐 Saves credentials securely (`~/.minio_migration_config`, mode 600)
- 🔑 Never logs credentials to migration logs
- 🛡️ Tests connections before migration
- ✅ Preserves original data (non-destructive)
- 📊 Detailed audit logs per bucket

### ⚙️ Configuration Examples

#### Example 1: Portainer MinIO → Coolify MinIO
```
Source: http://portainer-server:9000
Destination: Auto-detect Docker (http://172.17.0.3:9000)
Method: Run script on Coolify server
```

#### Example 2: Via Tailscale Network
```
Source: http://100.x.x.1:9000
Destination: http://100.x.x.2:9000
Method: Run script on either server
```

#### Example 3: Public Domain Access
```
Source: https://minio-old.yourdomain.com
Destination: https://s3.yourdomain.com
Method: Run from any server with network access
```

### 🆘 Troubleshooting MinIO Migration

#### Issue: Can't connect to source/destination
**Solutions:**
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

#### Issue: Migration stuck halfway
**Solutions:**
```bash
# Check if it's actually stuck (look for network activity)
sudo iftop

# Resume migration (mc mirror is smart)
mc mirror source-minio dest-minio --preserve

# Or use the script's "Resume incomplete migration" option
```

#### Issue: Destination not accessible (Coolify/Traefik)
**Solutions:**
```bash
# Find MinIO container
docker ps | grep minio

# Get internal Docker IP
docker inspect <container> | grep IPAddress

# Use internal IP: http://172.17.0.x:9000
```

#### Issue: "Access Denied" errors
**Solutions:**
```bash
# Verify credentials are correct
# Check MinIO user has proper permissions
# Ensure user can create buckets (if auto-creating)
mc admin user info dest-minio ACCESS_KEY
```

---

## 🖥️ Supported Systems

**All Scripts:**
* **Ubuntu**: 22.04, 24.04 (LTS)
* **Debian**: 11, 12
* **Architectures**: ARM64 (aarch64) and x86\_64 (amd64)
* **Providers**: Oracle Cloud, DigitalOcean, Linode, Vultr, Hetzner, Contabo, OVH, and most VPS providers

---

## 🔧 Script Comparison

| Feature | Tailscale Setup | MinIO Migration |
|---------|----------------|-----------------|
| **Purpose** | Secure SSH access | Data migration |
| **Auto-install tools** | ✅ Tailscale | ✅ MinIO Client |
| **Interactive prompts** | ✅ | ✅ |
| **Config preservation** | ❌ | ✅ |
| **Verification built-in** | ✅ | ✅ |
| **Logging** | System logs | Per-bucket logs |
| **Resumable** | N/A | ✅ |
| **Network requirements** | Internet | Server-to-server |
| **Typical runtime** | 5-10 min | Varies (data size) |

---

## 📚 Complete Documentation

### Tailscale SSH Setup

For complete Tailscale SSH setup documentation, including:
- Detailed security features
- Provider-specific instructions
- ACL configuration examples
- Troubleshooting guides

See the [full README sections](#-important-notes) below.

### MinIO Migration

**Full workflow:**
1. Download and run the script
2. Follow interactive prompts
3. Configure source and destination
4. Choose migration options
5. Monitor progress
6. Verify completion
7. Update application configurations

**Configuration saved to:** `~/.minio_migration_config`

**Logs saved to:** `migration-<bucket>-<timestamp>.log`

---

## ⚠️ Important Notes

### For Tailscale Users:

* 📖 **Review the script** before running (good security practice)
* 💾 **Backup important data** before making system changes
* 🔑 **Set a strong password** for emergency console access
* ✅ **Test Tailscale SSH** before removing other access methods
* 🔄 **Keep Tailscale updated** for latest security patches

### Oracle Cloud Specific:

* 🟠 **Must configure OCI Security List** manually after script runs
  + Navigate to: Networking → Virtual Cloud Networks → Security Lists
  + Remove/restrict SSH (port 22) from 0.0.0.0/0
  + Add HTTP/HTTPS rules if you configured those ports
* 🖥️ **Set up Serial Console** for emergency access

### Generic VPS Specific:

* ☁️ **Check cloud firewall settings** if your provider has them
* 🔍 Most providers don't require additional firewall configuration
* 🌐 Tailscale works through most firewalls automatically

### For MinIO Migration Users:

* 💾 **Test migration on small buckets first**
* 🔄 **Keep source MinIO running** during and after migration
* ✅ **Verify all data** before decommissioning source
* 📊 **Check application compatibility** with new MinIO instance
* 🔐 **Update application endpoints** after migration
* ⏱️ **Allow extra time** for large datasets
* 🌐 **Use Tailscale** for secure migrations over internet
* 💻 **Run in screen/tmux** for long migrations

---

## 🎯 Common Workflows

### Workflow 1: New VPS Setup with Tailscale
```bash
# 1. Run Tailscale setup
curl -fsSL https://gist.githubusercontent.com/.../tailscale-vps-setup.sh | bash

# 2. Connect from your machine
ssh user@100.x.x.x

# 3. Enjoy secure, keyless access!
```

### Workflow 2: Migrate MinIO Between VPS
```bash
# 1. Ensure both servers are accessible (Tailscale recommended)
# On Server A and B:
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 2. Run migration tool on either server
curl -fsSL https://gist.githubusercontent.com/.../minio_migration.sh -o migrate.sh
chmod +x migrate.sh
./migrate.sh

# 3. Follow interactive prompts
# 4. Verify migration
# 5. Update app configs to new MinIO endpoint
```

### Workflow 3: Complete VPS Migration
```bash
# Old VPS (Server A) → New VPS (Server B)

# Step 1: Set up Tailscale on both servers
# Step 2: Deploy MinIO on Server B
# Step 3: Run MinIO migration tool
# Step 4: Test applications with new MinIO
# Step 5: Update DNS/configs
# Step 6: Decommission Server A (after verification)
```

---

## 💡 Tips & Best Practices

### Tailscale SSH:

#### 1. Use Tailscale ACLs for Team Access
```json
{
  "ssh": [
    {
      "action": "accept",
      "src": ["user1@github", "user2@google"],
      "dst": ["tag:production-servers"],
      "users": ["deploy", "admin"]
    }
  ]
}
```

#### 2. Tag Your Servers
```bash
sudo tailscale up --ssh --advertise-tags=tag:webserver
```

#### 3. Enable MagicDNS
Access servers by name instead of IP:
```bash
ssh username@server-name
```

### MinIO Migration:

#### 1. Use Bucket-by-Bucket Migration for Production
```bash
# Migrate critical buckets first
# Test applications
# Continue with remaining buckets
```

#### 2. Monitor Disk Space
```bash
# Before migration
df -h

# During migration
watch -n 5 'df -h'
```

#### 3. Use Bandwidth Limiting for Shared Connections
```bash
# In Advanced Options menu:
# Select "Migrate with bandwidth limit"
# Set appropriate limits (e.g., 5M, 10M)
```

#### 4. Keep Migration Logs
```bash
# Logs are automatically saved
ls -lh migration-*.log

# Review logs after completion
less migration-bucket-name-*.log
```

#### 5. Test Before Switching
```bash
# Update one non-critical app to use new MinIO
# Verify functionality for 24-48 hours
# Then switch remaining apps
```

---

## 🆘 Troubleshooting

### Tailscale SSH Issues

#### Can't connect via Tailscale SSH after setup?

**Check Tailscale status:**
```bash
tailscale status
```

**Verify both devices are in the same Tailnet:**
```bash
tailscale status | grep "logged in"
```

**Ensure Tailscale SSH is enabled:**
```bash
sudo tailscale up --ssh
```

#### Lost SSH access completely?

**Oracle Cloud:**
* Use Serial Console

**Other VPS:**
* Use provider's VNC/console access
* Check provider's control panel

### MinIO Migration Issues

See [🆘 Troubleshooting MinIO Migration](#-troubleshooting-minio-migration) section above.

---

## 🔄 Updating the Scripts

To get the latest version of any script:

```bash
# Re-download
curl -fsSL https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/<script-name>.sh -o script.sh
chmod +x script.sh
./script.sh
```

Scripts are designed to be idempotent (safe to run multiple times).

---

## 📜 License

These scripts are provided as-is for educational and practical use. Feel free to modify and distribute.

---

## ⭐ Show Your Support

If these scripts helped you:

* ⭐ Star this gist
* 🔄 Share with others
* 💬 Leave feedback in the comments

---

## 📚 Learn More

### Tailscale Documentation
* [Tailscale Docs](https://tailscale.com/kb/)
* [Tailscale SSH Guide](https://tailscale.com/kb/1193/tailscale-ssh/)
* [Tailscale ACLs](https://tailscale.com/kb/1018/acls/)

### MinIO Documentation
* [MinIO Docs](https://min.io/docs/minio/linux/index.html)
* [MinIO Client Guide](https://min.io/docs/minio/linux/reference/minio-mc.html)
* [MinIO Administration](https://min.io/docs/minio/linux/administration/minio-console.html)

### Infrastructure & Security
* [UFW Documentation](https://help.ubuntu.com/community/UFW)
* [SSH Security Best Practices](https://www.ssh.com/academy/ssh/security)
* [Docker Networking](https://docs.docker.com/network/)

---

## 🤝 Contributing

Found a bug or have a suggestion? Feel free to:

* Comment on this gist
* Suggest improvements
* Report issues

---

**Created:** December 2024  
**Last Updated:** December 2024  
**Compatibility:** Ubuntu 22.04+, Debian 11+, Most VPS Providers  
**Tools:** Tailscale, MinIO Client, UFW

---

## 🎉 Happy Automating!

Your VPS management is now streamlined with professional automation scripts!

For support and updates:

* 🌐 [Tailscale Community](https://tailscale.com/community)
* 💬 [MinIO Slack](https://slack.min.io/)
* 🐦 [@Tailscale on Twitter](https://twitter.com/tailscale)
* 🐦 [@MinIO on Twitter](https://twitter.com/minio)