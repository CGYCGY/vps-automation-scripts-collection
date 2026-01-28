# 🚀 Coolify Setup Scripts

Comprehensive setup scripts for [Coolify](https://coolify.io) - the self-hostable Heroku/Netlify alternative.

## 📦 Available Scripts

### 1. coolify-setup.sh - Dashboard Installation
Install Coolify dashboard on your main controller server.

### 2. coolify-remote-setup.sh - Remote Server Setup
Prepare servers to be connected to an existing Coolify dashboard as managed/remote servers.

## ✨ Features

### Dashboard Setup (coolify-setup.sh)

| Feature | Description |
|---------|-------------|
| 👤 **User Setup** | Creates a dedicated `coolify` user with proper permissions |
| 📦 **Coolify Install** | Automated Coolify installation |
| 🐙 **GitHub Registry** | Configure authentication for GitHub Container Registry (ghcr.io) |
| 🔒 **Cloudflare SSL** | Setup Cloudflare Origin Certificates for SSL/TLS |

### Remote Server Setup (coolify-remote-setup.sh)

| Feature | Description |
|---------|-------------|
| 👤 **User Setup** | Creates `coolify` user with passwordless sudo |
| 🐳 **Docker Install** | Installs Docker Engine if not present |
| 🔑 **SSH Setup** | Configures SSH key for Coolify access |
| 🔥 **Firewall Check** | Smart firewall configuration (only if needed) |
| ✅ **Verification** | Tests setup and shows next steps |

## 📋 Prerequisites

### For Dashboard Installation (coolify-setup.sh)
- Ubuntu 20.04/22.04/24.04 LTS (or Debian-based distro)
- Root access or sudo privileges
- A domain configured with Cloudflare (for SSL setup)
- GitHub account with Personal Access Token (for private registry)

### For Remote Server Setup (coolify-remote-setup.sh)
- Ubuntu 20.04/22.04/24.04 LTS (or Debian-based distro)
- Root access or sudo privileges
- Existing Coolify dashboard (on another server)
- SSH public key from Coolify dashboard

## 🚀 Quick Start

### Dashboard Installation (coolify-setup.sh)

#### One-liner Installation

```bash
curl -fsSL https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/coolify-setup.sh | sudo bash
```

#### Manual Installation

```bash
# Download the script
wget https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/coolify-setup.sh

# Make it executable
chmod +x coolify-setup.sh

# Run with sudo
sudo ./coolify-setup.sh
```

### Remote Server Setup (coolify-remote-setup.sh)

```bash
# Clone the repository
git clone https://github.com/CGYCGY/vps-automation-scripts-collection.git
cd vps-automation-scripts-collection/coolify

# Make it executable
chmod +x coolify-remote-setup.sh

# Run with sudo
sudo ./coolify-remote-setup.sh
```

## 📖 Usage

### Dashboard Installation (coolify-setup.sh)

#### Interactive Mode (Recommended)

```bash
sudo ./coolify-setup.sh
```

This displays a menu where you can select which components to set up.

#### Command Line Options

```bash
# Full setup (all options)
sudo ./coolify-setup.sh --all

# Individual components
sudo ./coolify-setup.sh --user        # Create coolify user only
sudo ./coolify-setup.sh --install     # Install Coolify only
sudo ./coolify-setup.sh --github      # Setup GitHub registry only
sudo ./coolify-setup.sh --cloudflare  # Setup Cloudflare cert only

# Help
sudo ./coolify-setup.sh --help
```

### Remote Server Setup (coolify-remote-setup.sh)

#### Interactive Mode (Recommended)

```bash
sudo ./coolify-remote-setup.sh
```

#### Command Line Options

```bash
# Full setup (all steps)
sudo ./coolify-remote-setup.sh --all

# Individual steps
sudo ./coolify-remote-setup.sh --user      # Create coolify user only
sudo ./coolify-remote-setup.sh --docker    # Install Docker only
sudo ./coolify-remote-setup.sh --ssh       # Setup SSH key only
sudo ./coolify-remote-setup.sh --firewall  # Check firewall only
sudo ./coolify-remote-setup.sh --verify    # Verify setup only

# Help
sudo ./coolify-remote-setup.sh --help
```

## 📚 Detailed Setup Guide

### Dashboard Installation

#### 1️⃣ Create Coolify User

Creates a dedicated `coolify` user with:
- Home directory at `/home/coolify`
- Added to `docker` and `sudo` groups
- Passwordless sudo access

#### 2️⃣ Install Coolify

Runs the official Coolify installation script which:
- Installs Docker (if not present)
- Sets up Coolify containers
- Configures Traefik proxy
- Creates data directories at `/data/coolify`

After installation, access Coolify at: `http://YOUR_SERVER_IP:8000`

### Remote Server Setup

#### 1️⃣ Create Coolify User

Creates a dedicated `coolify` user with:
- Home directory at `/home/coolify`
- Added to `docker` and `sudo` groups
- **Passwordless sudo configured** (required by Coolify):
  ```bash
  echo "coolify ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coolify
  ```
  This allows Coolify to run commands like `docker`, `apt`, etc. without password prompts.

#### 2️⃣ Install Docker

Installs Docker Engine using the official script:
- Downloads from `https://get.docker.com`
- Starts and enables Docker service
- Verifies `coolify` user can run docker commands

#### 3️⃣ Setup SSH Key

Configures SSH access for Coolify:
- Creates `/home/coolify/.ssh` directory with proper permissions
- Prompts you to paste SSH public key from Coolify UI
- Where to get the key:
  1. Go to Coolify dashboard
  2. Navigate to: **Servers → Add Server**
  3. Copy the SSH public key shown in the UI
  4. Paste it when prompted by the script

#### 4️⃣ Firewall Check (Smart)

Intelligently checks and configures firewall:
- Checks if UFW is installed and active
- Verifies if SSH (port 22) is already allowed
- Only prompts to configure if SSH is NOT allowed
- Skips firewall config if already accessible

#### 5️⃣ Verification & Next Steps

Tests the setup:
- Verifies `coolify` user exists with proper groups
- Tests docker access: `su - coolify -c "docker ps"`
- Displays server IP for adding to Coolify dashboard
- Shows next steps for connecting in Coolify UI

#### 3️⃣ Setup GitHub Container Registry

Configures Docker to authenticate with `ghcr.io` for pulling private images.

**Before running, create a GitHub PAT:**
1. Go to GitHub → Settings → Developer settings
2. Personal access tokens → Tokens (classic)
3. Generate new token with `read:packages` scope (add `write:packages` if pushing)

**How it works:**
- Credentials are stored in `~/.docker/config.json`
- Coolify automatically detects and uses these credentials
- Works for both public and private container images

#### 4️⃣ Setup Cloudflare Origin Certificate

Configures SSL/TLS using Cloudflare Origin Certificates for secure HTTPS connections.

**Before running, create an Origin Certificate in Cloudflare:**
1. Go to Cloudflare Dashboard → Your Domain
2. SSL/TLS → Origin Server → Create Certificate
3. Configure:
   - Private key type: **RSA (2048)**
   - Hostnames: `*.yourdomain.com`, `yourdomain.com`
   - Validity: **15 years**

**The script will:**
- Create certificate files in `/data/coolify/proxy/certs/`
- Generate Traefik dynamic configuration
- Verify certificate validity

**After running, configure Cloudflare:**
- SSL/TLS → Overview → Set to **Full (strict)**
- SSL/TLS → Edge Certificates → Enable **Always Use HTTPS**

## 🔗 Connecting Remote Servers to Coolify

After running `coolify-remote-setup.sh` on your remote server:

### Step 1: Add Server in Coolify Dashboard

1. Go to your Coolify dashboard
2. Navigate to: **Servers → Add Server**
3. Enter the server details:
   - **Name**: Give your server a friendly name
   - **IP Address**: Use the IP shown by the setup script
   - **Port**: `22` (default SSH port)
   - **User**: `coolify`
   - **Private Key**: The setup script already configured the public key

### Step 2: Validate Server

1. Click **Validate Server** to test the connection
2. Coolify will attempt to SSH into the server
3. If successful, you'll see a green checkmark

### Step 3: Complete Setup

1. Click **Add Server** to complete
2. The server will appear in your servers list
3. You can now deploy applications to this server

### Troubleshooting Connection Issues

If validation fails:

```bash
# On the remote server, check SSH access
sudo -u coolify ssh -v coolify@localhost

# Verify authorized_keys
sudo cat /home/coolify/.ssh/authorized_keys

# Check SSH daemon is running
sudo systemctl status sshd

# Test docker access
sudo -u coolify docker ps
```

## 🔧 Post-Installation

### Restart Traefik Proxy

After setting up certificates, restart the proxy:
1. Go to Coolify UI
2. Servers → Your Server → Proxy
3. Click **Restart Proxy**

### Redeploy Applications

Redeploy your applications to apply the new SSL configuration.

### Verify SSL

```bash
# Test SSL connection
curl -I https://your-app.yourdomain.com

# Detailed SSL check
openssl s_client -connect your-app.yourdomain.com:443 -servername your-app.yourdomain.com
```

## 🐛 Troubleshooting

### GitHub Registry Issues

```bash
# Check if credentials are saved
cat ~/.docker/config.json

# Test pulling an image
docker pull ghcr.io/your-org/your-image:tag

# View Coolify deployment logs in UI for auth errors
```

### Cloudflare Certificate Issues

```bash
# Check Traefik logs
docker logs coolify-proxy --tail 100

# Verify certificate is loaded
docker exec coolify-proxy ls -la /traefik/certs/

# Test SSL connection
openssl s_client -connect your-app.yourdomain.com:443 -servername your-app.yourdomain.com
```

### Coolify Not Accessible

```bash
# Check if containers are running
docker ps | grep coolify

# Check Coolify logs
docker logs coolify --tail 100

# Restart Coolify
cd /data/coolify/source
docker compose down
docker compose up -d
```

## 📁 File Locations

| Path | Description |
|------|-------------|
| `/data/coolify/` | Main Coolify data directory |
| `/data/coolify/proxy/` | Traefik proxy configuration |
| `/data/coolify/proxy/certs/` | SSL certificates |
| `/data/coolify/proxy/dynamic/` | Traefik dynamic configs |
| `~/.docker/config.json` | Docker registry credentials |

## 🔗 Related Resources

- [Coolify Documentation](https://coolify.io/docs)
- [Coolify GitHub](https://github.com/coollabsio/coolify)
- [Cloudflare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

## 📝 License

MIT License - Feel free to use and modify as needed.