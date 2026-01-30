#!/bin/bash

################################################################################
# Coolify Remote Server Setup Script
#
# This script prepares a server to be connected to an existing Coolify dashboard
# as a managed/remote server.
#
# Usage:
#   ./coolify-remote-setup.sh              # Interactive menu
#   ./coolify-remote-setup.sh --all        # Full setup (all steps)
#   ./coolify-remote-setup.sh --user       # Create coolify user only
#   ./coolify-remote-setup.sh --docker     # Install Docker only
#   ./coolify-remote-setup.sh --ssh        # Setup SSH key only
#   ./coolify-remote-setup.sh --github     # Setup GitHub Container Registry only
#   ./coolify-remote-setup.sh --cloudflare # Setup Cloudflare Origin Certificate only
#   ./coolify-remote-setup.sh --firewall   # Check firewall only
#   ./coolify-remote-setup.sh --verify     # Verify setup only
#   ./coolify-remote-setup.sh --help       # Show help
#
# Requirements:
#   - Ubuntu/Debian-based system
#   - Run as root or with sudo
#   - Internet connection
#
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
show_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║        Coolify Remote Server Setup Script                     ║"
    echo "║                                                                ║"
    echo "║  Prepare this server to be managed by Coolify dashboard       ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Helper functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm() {
    local prompt="$1"
    local response
    while true; do
        read -rp "$(echo -e "${YELLOW}${prompt} (y/n):${NC} ")" response
        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Step 1: Create coolify user
setup_coolify_user() {
    print_info "Setting up coolify user..."

    # Check if user already exists
    if id "coolify" &>/dev/null; then
        print_warning "User 'coolify' already exists"
        if ! confirm "Do you want to reconfigure this user?"; then
            return 0
        fi
    else
        # Create user with home directory
        print_info "Creating user 'coolify' with home directory..."
        useradd -m -s /bin/bash coolify
        print_success "User 'coolify' created"
    fi

    # Create docker group if it doesn't exist
    if ! getent group docker >/dev/null; then
        print_info "Creating docker group..."
        groupadd docker
    fi

    # Add user to docker and sudo groups
    print_info "Adding coolify to docker and sudo groups..."
    usermod -aG docker coolify
    usermod -aG sudo coolify

    # Configure passwordless sudo (required by Coolify)
    print_info "Configuring passwordless sudo for coolify user..."
    echo "coolify ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coolify
    chmod 440 /etc/sudoers.d/coolify

    print_success "Coolify user setup completed"
    print_info "User 'coolify' can now run docker and sudo commands without password"
}

# Step 2: Install Docker
install_docker() {
    print_info "Installing Docker..."

    # Check if Docker is already installed
    if command -v docker &>/dev/null; then
        print_warning "Docker is already installed"
        docker --version
        if ! confirm "Do you want to reinstall Docker?"; then
            # Just ensure Docker service is running
            systemctl start docker || true
            systemctl enable docker || true
            return 0
        fi
    fi

    # Install Docker using official script
    print_info "Downloading and running Docker installation script..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh

    # Start and enable Docker service
    print_info "Starting Docker service..."
    systemctl start docker
    systemctl enable docker

    print_success "Docker installed successfully"
    docker --version

    # Verify coolify user can run docker commands
    if id "coolify" &>/dev/null; then
        print_info "Verifying docker access for coolify user..."
        if su - coolify -c "docker ps" &>/dev/null; then
            print_success "Coolify user can run docker commands"
        else
            print_warning "Coolify user may need to log out and back in for docker group to take effect"
        fi
    fi
}

# Step 3: Setup SSH key for Coolify access
setup_ssh_key() {
    print_info "Setting up SSH access for Coolify..."

    # Create .ssh directory if it doesn't exist
    local ssh_dir="/home/coolify/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        print_info "Creating .ssh directory..."
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi

    # Prompt for SSH public key
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Instructions to get the SSH public key from Coolify:${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}1.${NC} Go to your Coolify dashboard"
    echo -e "${YELLOW}2.${NC} Navigate to: Servers → Add Server"
    echo -e "${YELLOW}3.${NC} Copy the SSH public key shown in the UI"
    echo -e "${YELLOW}4.${NC} Paste it below when prompted"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    local ssh_key
    read -rp "$(echo -e "${GREEN}Paste the SSH public key from Coolify:${NC} ")" ssh_key

    # Validate SSH key format (basic check)
    if [[ ! "$ssh_key" =~ ^ssh- ]]; then
        print_error "Invalid SSH key format. Key should start with 'ssh-'"
        return 1
    fi

    # Add key to authorized_keys
    local auth_keys="$ssh_dir/authorized_keys"
    print_info "Adding key to authorized_keys..."
    echo "$ssh_key" >> "$auth_keys"
    chmod 600 "$auth_keys"

    # Set ownership to coolify user
    chown -R coolify:coolify "$ssh_dir"

    print_success "SSH key added successfully"
    print_info "Coolify can now connect to this server via SSH"
}

# Step 4: Setup GitHub Container Registry
setup_github_registry() {
    print_info "Setting up GitHub Container Registry..."

    print_info "This will configure Docker to authenticate with GitHub Container Registry (ghcr.io)"
    print_info "You'll need a GitHub Personal Access Token (PAT) with 'read:packages' scope"
    echo ""

    print_warning "To create a PAT:"
    print_info "1. Go to GitHub → Settings → Developer settings"
    print_info "2. Personal access tokens → Tokens (classic)"
    print_info "3. Generate new token with 'read:packages' scope"
    echo ""

    if ! confirm "Do you have your GitHub PAT ready?"; then
        print_warning "Please create a PAT first, then run this option again"
        return 0
    fi

    # Get GitHub credentials
    echo ""
    read -rp "Enter your GitHub username: " GITHUB_USERNAME
    if [[ -z "$GITHUB_USERNAME" ]]; then
        print_error "Username cannot be empty"
        return 1
    fi

    echo ""
    read -rs -p "Enter your GitHub PAT (hidden): " GITHUB_PAT
    echo ""

    if [[ -z "$GITHUB_PAT" ]]; then
        print_error "PAT cannot be empty"
        return 1
    fi

    print_info "Logging into GitHub Container Registry..."

    # Login to ghcr.io
    if echo "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin; then
        print_success "Successfully logged into ghcr.io!"

        # Show config location
        DOCKER_CONFIG="$HOME/.docker/config.json"
        if [[ -f "$DOCKER_CONFIG" ]]; then
            print_info "Credentials saved to: $DOCKER_CONFIG"
        fi

        # Setup for coolify user as well
        if id "coolify" &>/dev/null; then
            print_info "Setting up registry for 'coolify' user as well..."

            COOLIFY_DOCKER_DIR="/home/coolify/.docker"
            mkdir -p "$COOLIFY_DOCKER_DIR"

            # Copy docker config
            if [[ -f "$HOME/.docker/config.json" ]]; then
                cp "$HOME/.docker/config.json" "$COOLIFY_DOCKER_DIR/config.json"
                chown -R coolify:coolify "$COOLIFY_DOCKER_DIR"
                chmod 600 "$COOLIFY_DOCKER_DIR/config.json"
                print_success "Registry configured for 'coolify' user"
            fi
        fi

        echo ""
        print_success "GitHub Container Registry setup complete!"
        print_info "Docker can now pull private images from ghcr.io"
    else
        print_error "Failed to login to ghcr.io"
        print_info "Please check your username and PAT"
        return 1
    fi
}

# Step 5: Setup Cloudflare Origin Certificate
setup_cloudflare_cert() {
    print_info "Setting up Cloudflare Origin Certificate..."

    # Check if Docker is installed (needed for Traefik/proxy)
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed. Please install Docker first (Option 3)"
        return 1
    fi

    # Create proxy directories if they don't exist
    PROXY_DIR="/data/coolify/proxy"
    if [[ ! -d "$PROXY_DIR" ]]; then
        print_info "Creating Coolify proxy directory structure..."
        mkdir -p "$PROXY_DIR/certs"
        mkdir -p "$PROXY_DIR/dynamic"
    fi

    print_info "This will configure Cloudflare Origin Certificates for SSL/TLS"
    echo ""

    # Get domain
    read -rp "Enter your domain (e.g., example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain cannot be empty"
        return 1
    fi

    # Create certificates directory
    CERTS_DIR="$PROXY_DIR/certs"
    print_info "Creating certificates directory: $CERTS_DIR"
    mkdir -p "$CERTS_DIR"

    CERT_FILE="$CERTS_DIR/$DOMAIN.cert"
    KEY_FILE="$CERTS_DIR/$DOMAIN.key"

    echo ""
    print_warning "Before continuing, create an Origin Certificate in Cloudflare:"
    print_info "1. Go to Cloudflare Dashboard → Your Domain"
    print_info "2. Navigate to: SSL/TLS → Origin Server"
    print_info "3. Click 'Create Certificate'"
    print_info "4. Configure:"
    print_info "   • Private key type: RSA (2048)"
    print_info "   • Hostnames: *.$DOMAIN, $DOMAIN"
    print_info "   • Validity: 15 years"
    print_info "5. Click 'Create' and keep the page open"
    echo ""

    if ! confirm "Have you created the certificate in Cloudflare?"; then
        print_warning "Please create the certificate first, then run this option again"
        return 0
    fi

    # Get certificate
    echo ""
    print_info "Paste the Origin Certificate (including BEGIN/END lines)"
    print_info "Press Ctrl+D when done:"
    echo ""

    CERT_CONTENT=$(cat)

    if [[ -z "$CERT_CONTENT" ]]; then
        print_error "Certificate cannot be empty"
        return 1
    fi

    echo "$CERT_CONTENT" > "$CERT_FILE"
    print_success "Certificate saved to: $CERT_FILE"

    # Get private key
    echo ""
    print_info "Paste the Private Key (including BEGIN/END lines)"
    print_info "Press Ctrl+D when done:"
    echo ""

    KEY_CONTENT=$(cat)

    if [[ -z "$KEY_CONTENT" ]]; then
        print_error "Private key cannot be empty"
        return 1
    fi

    echo "$KEY_CONTENT" > "$KEY_FILE"
    print_success "Private key saved to: $KEY_FILE"

    # Set permissions
    print_info "Setting file permissions..."
    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"
    print_success "Permissions set!"

    # Verify files
    print_info "Verifying certificate..."
    if openssl x509 -in "$CERT_FILE" -text -noout > /dev/null 2>&1; then
        print_success "Certificate is valid!"
        echo ""
        openssl x509 -in "$CERT_FILE" -noout -subject -dates | sed 's/^/    /'
    else
        print_error "Certificate appears to be invalid"
        return 1
    fi

    echo ""
    print_info "Verifying private key..."
    if openssl rsa -in "$KEY_FILE" -check -noout > /dev/null 2>&1; then
        print_success "Private key is valid!"
    else
        print_error "Private key appears to be invalid"
        return 1
    fi

    # Create Traefik dynamic configuration
    echo ""
    if confirm "Create Traefik dynamic configuration automatically?"; then
        TRAEFIK_CONFIG="$PROXY_DIR/dynamic/cloudflare-origin-cert.yaml"
        mkdir -p "$PROXY_DIR/dynamic"

        cat > "$TRAEFIK_CONFIG" << EOF
tls:
  certificates:
    - certFile: /traefik/certs/$DOMAIN.cert
      keyFile: /traefik/certs/$DOMAIN.key
EOF

        print_success "Traefik configuration created at: $TRAEFIK_CONFIG"
    else
        echo ""
        print_warning "Add this configuration manually in Coolify UI:"
        print_info "Servers → Your Server → Proxy → Dynamic Configuration → Add"
        echo ""
        echo -e "${GREEN}tls:"
        echo "  certificates:"
        echo "    - certFile: /traefik/certs/$DOMAIN.cert"
        echo -e "      keyFile: /traefik/certs/$DOMAIN.key${NC}"
        echo ""
    fi

    # Final instructions
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Cloudflare Settings Required${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

    print_info "Configure these settings in Cloudflare Dashboard:"
    print_info "1. SSL/TLS → Overview → Set to: Full (strict)"
    print_info "2. SSL/TLS → Edge Certificates → Enable: Always Use HTTPS"

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Next Steps${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

    print_info "1. Add this server to Coolify dashboard first"
    print_info "2. Restart Traefik proxy in Coolify UI:"
    print_info "   Servers → This Server → Proxy → Restart Proxy"
    print_info "3. Redeploy your applications"
    print_info "4. Test with: curl -I https://your-app.$DOMAIN"

    echo ""
    print_success "Cloudflare Origin Certificate setup complete!"
}

# Step 6: Check and configure firewall
check_firewall() {
    print_info "Checking firewall configuration..."

    # Check if UFW is installed
    if ! command -v ufw &>/dev/null; then
        print_info "UFW is not installed. Skipping firewall configuration."
        return 0
    fi

    # Check if UFW is active
    if ! ufw status | grep -q "Status: active"; then
        print_info "UFW is installed but not active. Skipping firewall configuration."
        return 0
    fi

    print_info "UFW is active"

    # Check if SSH is already allowed
    if ufw status | grep -q "22.*ALLOW"; then
        print_success "SSH (port 22) is already allowed in firewall"
        return 0
    fi

    # SSH not allowed, prompt user
    print_warning "SSH (port 22) is NOT allowed in UFW firewall"
    echo -e "${YELLOW}This may prevent Coolify from connecting to this server${NC}"

    if confirm "Do you want to allow SSH (port 22) in UFW?"; then
        ufw allow 22/tcp
        print_success "SSH access allowed in firewall"
    else
        print_warning "Firewall not configured. You may need to manually allow SSH access."
    fi
}

# Step 7: Verify setup
verify_setup() {
    print_info "Verifying setup..."
    echo ""

    local all_good=true

    # Check coolify user
    if id "coolify" &>/dev/null; then
        print_success "✓ User 'coolify' exists"

        # Check groups
        if groups coolify | grep -q docker; then
            print_success "✓ User 'coolify' is in docker group"
        else
            print_error "✗ User 'coolify' is NOT in docker group"
            all_good=false
        fi

        if groups coolify | grep -q sudo; then
            print_success "✓ User 'coolify' is in sudo group"
        else
            print_error "✗ User 'coolify' is NOT in sudo group"
            all_good=false
        fi

        # Check passwordless sudo
        if [[ -f /etc/sudoers.d/coolify ]]; then
            print_success "✓ Passwordless sudo configured"
        else
            print_error "✗ Passwordless sudo NOT configured"
            all_good=false
        fi
    else
        print_error "✗ User 'coolify' does NOT exist"
        all_good=false
    fi

    # Check Docker
    if command -v docker &>/dev/null; then
        print_success "✓ Docker is installed"

        if systemctl is-active --quiet docker; then
            print_success "✓ Docker service is running"
        else
            print_error "✗ Docker service is NOT running"
            all_good=false
        fi

        # Test docker access for coolify user
        if id "coolify" &>/dev/null; then
            if su - coolify -c "docker ps" &>/dev/null; then
                print_success "✓ Coolify user can run docker commands"
            else
                print_warning "⚠ Coolify user cannot run docker commands yet (may need re-login)"
            fi
        fi
    else
        print_error "✗ Docker is NOT installed"
        all_good=false
    fi

    # Check SSH key
    if [[ -f /home/coolify/.ssh/authorized_keys ]]; then
        print_success "✓ SSH authorized_keys file exists"
    else
        print_warning "⚠ SSH authorized_keys file NOT found"
    fi

    # Check GitHub Container Registry
    if [[ -f /home/coolify/.docker/config.json ]] && grep -q "ghcr.io" /home/coolify/.docker/config.json 2>/dev/null; then
        print_success "✓ GitHub Container Registry configured for coolify user"
    else
        print_warning "⚠ GitHub Container Registry NOT configured (optional)"
    fi

    # Check Cloudflare certificates
    if [[ -d /data/coolify/proxy/certs ]] && ls /data/coolify/proxy/certs/*.cert &>/dev/null; then
        print_success "✓ Cloudflare Origin Certificate found"
    else
        print_warning "⚠ Cloudflare Origin Certificate NOT found (optional)"
    fi

    echo ""
    if $all_good; then
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  Setup completed successfully!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    else
        echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  Setup completed with warnings. Please review above.${NC}"
        echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    fi

    # Show next steps
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "${YELLOW}1.${NC} Go to your Coolify dashboard"
    echo -e "${YELLOW}2.${NC} Navigate to: Servers → Add Server"
    echo -e "${YELLOW}3.${NC} Enter the following details:"
    echo -e "   ${CYAN}Server IP:${NC} $(hostname -I | awk '{print $1}')"
    echo -e "   ${CYAN}Username:${NC} coolify"
    echo -e "   ${CYAN}Port:${NC} 22"
    echo -e "${YELLOW}4.${NC} Click 'Validate Server' to test the connection"
    echo -e "${YELLOW}5.${NC} If successful, click 'Add Server' to complete"
    echo ""
}

# Show interactive menu
show_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}  Coolify Remote Server Setup Menu${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}1.${NC} Full Setup (All Steps)"
        echo -e "${YELLOW}2.${NC} Create Coolify User"
        echo -e "${YELLOW}3.${NC} Install Docker"
        echo -e "${YELLOW}4.${NC} Setup SSH Key"
        echo -e "${YELLOW}5.${NC} Setup GitHub Container Registry"
        echo -e "${YELLOW}6.${NC} Setup Cloudflare Origin Certificate"
        echo -e "${YELLOW}7.${NC} Check Firewall"
        echo -e "${YELLOW}8.${NC} Verify Setup"
        echo -e "${YELLOW}9.${NC} Exit"
        echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

        read -rp "$(echo -e "${GREEN}Select an option [1-9]:${NC} ")" choice

        case $choice in
            1)
                setup_coolify_user
                install_docker
                setup_ssh_key
                setup_github_registry
                setup_cloudflare_cert
                check_firewall
                verify_setup
                ;;
            2)
                setup_coolify_user
                ;;
            3)
                install_docker
                ;;
            4)
                setup_ssh_key
                ;;
            5)
                setup_github_registry
                ;;
            6)
                setup_cloudflare_cert
                ;;
            7)
                check_firewall
                ;;
            8)
                verify_setup
                ;;
            9)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-9."
                ;;
        esac
    done
}

# Show help
show_help() {
    echo "Coolify Remote Server Setup Script"
    echo ""
    echo "Usage:"
    echo "  $0                    # Interactive menu"
    echo "  $0 --all              # Full setup (all steps)"
    echo "  $0 --user             # Create coolify user only"
    echo "  $0 --docker           # Install Docker only"
    echo "  $0 --ssh              # Setup SSH key only"
    echo "  $0 --github           # Setup GitHub Container Registry only"
    echo "  $0 --cloudflare       # Setup Cloudflare Origin Certificate only"
    echo "  $0 --firewall         # Check firewall only"
    echo "  $0 --verify           # Verify setup only"
    echo "  $0 --help             # Show this help"
    echo ""
    echo "Description:"
    echo "  This script prepares a server to be connected to an existing Coolify"
    echo "  dashboard as a managed/remote server."
    echo ""
    echo "Requirements:"
    echo "  - Ubuntu/Debian-based system"
    echo "  - Run as root or with sudo"
    echo "  - Internet connection"
    echo ""
}

# Main function
main() {
    show_banner
    check_root

    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        # No arguments, show interactive menu
        show_menu
    else
        case "$1" in
            --all)
                setup_coolify_user
                install_docker
                setup_ssh_key
                setup_github_registry
                setup_cloudflare_cert
                check_firewall
                verify_setup
                ;;
            --user)
                setup_coolify_user
                ;;
            --docker)
                install_docker
                ;;
            --ssh)
                setup_ssh_key
                ;;
            --github)
                setup_github_registry
                ;;
            --cloudflare)
                setup_cloudflare_cert
                ;;
            --firewall)
                check_firewall
                ;;
            --verify)
                verify_setup
                ;;
            --help|-h)
                show_help
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"
