# 🚀 Coolify Complete Setup Script

A comprehensive setup script for [Coolify](https://coolify.io) - the self-hostable Heroku/Netlify alternative.

## ✨ Features

| Feature | Description |
|---------|-------------|
| 👤 **User Setup** | Creates a dedicated `coolify` user with proper permissions |
| 📦 **Coolify Install** | Automated Coolify installation |
| 🐙 **GitHub Registry** | Configure authentication for GitHub Container Registry (ghcr.io) |
| 🔒 **Cloudflare SSL** | Setup Cloudflare Origin Certificates for SSL/TLS |

## 📋 Prerequisites

- Ubuntu 20.04/22.04/24.04 LTS (or Debian-based distro)
- Root access or sudo privileges
- A domain configured with Cloudflare (for SSL setup)
- GitHub account with Personal Access Token (for private registry)

## 🚀 Quick Start

### One-liner Installation

```bash
curl -fsSL https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/coolify-setup.sh | sudo bash
```

### Manual Installation

```bash
# Download the script
wget https://gist.githubusercontent.com/CGYCGY/15732ea13901718df6ab97033694aa63/raw/coolify-setup.sh

# Make it executable
chmod +x coolify-setup.sh

# Run with sudo
sudo ./coolify-setup.sh
```

## 📖 Usage

### Interactive Mode (Recommended)

```bash
sudo ./coolify-setup.sh
```

This displays a menu where you can select which components to set up.

### Command Line Options

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

## 📚 Detailed Setup Guide

### 1️⃣ Create Coolify User

Creates a dedicated `coolify` user with:
- Home directory at `/home/coolify`
- Added to `docker` and `sudo` groups
- Passwordless sudo access

### 2️⃣ Install Coolify

Runs the official Coolify installation script which:
- Installs Docker (if not present)
- Sets up Coolify containers
- Configures Traefik proxy
- Creates data directories at `/data/coolify`

After installation, access Coolify at: `http://YOUR_SERVER_IP:8000`

### 3️⃣ Setup GitHub Container Registry

Configures Docker to authenticate with `ghcr.io` for pulling private images.

**Before running, create a GitHub PAT:**
1. Go to GitHub → Settings → Developer settings
2. Personal access tokens → Tokens (classic)
3. Generate new token with `read:packages` scope (add `write:packages` if pushing)

**How it works:**
- Credentials are stored in `~/.docker/config.json`
- Coolify automatically detects and uses these credentials
- Works for both public and private container images

### 4️⃣ Setup Cloudflare Origin Certificate

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