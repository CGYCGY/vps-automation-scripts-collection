#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                     Coolify Complete Setup Script                         ║
# ║                                                                           ║
# ║  Features:                                                                ║
# ║  • Create dedicated coolify user                                          ║
# ║  • Install Coolify                                                        ║
# ║  • Setup GitHub Container Registry authentication                         ║
# ║  • Setup Cloudflare Origin Certificate                                    ║
# ║                                                                           ║
# ║  Author: CGYCGY                                                           ║
# ║  Repository: https://gist.github.com/CGYCGY/15732ea13901718df6ab97033694aa63
# ╚═══════════════════════════════════════════════════════════════════════════╝

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

COOLIFY_USER="coolify"
COOLIFY_HOME="/home/$COOLIFY_USER"

# ─────────────────────────────────────────────────────────────────────────────
# Colors and Formatting
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
   ____            _ _  __         ____       _               
  / ___|___   ___ | (_)/ _|_   _  / ___|  ___| |_ _   _ _ __  
 | |   / _ \ / _ \| | | |_| | | | \___ \ / _ \ __| | | | '_ \ 
 | |__| (_) | (_) | | |  _| |_| |  ___) |  __/ |_| |_| | |_) |
  \____\___/ \___/|_|_|_|  \__, | |____/ \___|\__|\__,_| .__/ 
                          |___/                       |_|    
EOF
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

print_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC}  $1"
}

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${BOLD}${BLUE}[$1/$TOTAL_STEPS]${NC} ${BOLD}$2${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
}

confirm() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        print_info "Please run: sudo $0"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Menu
# ─────────────────────────────────────────────────────────────────────────────

show_menu() {
    clear
    print_banner
    
    echo -e "${BOLD}Select setup options:${NC}\n"
    echo -e "  ${GREEN}1)${NC} Full Setup (All options below)"
    echo -e "  ${GREEN}2)${NC} Create Coolify User"
    echo -e "  ${GREEN}3)${NC} Install Coolify"
    echo -e "  ${GREEN}4)${NC} Setup GitHub Container Registry"
    echo -e "  ${GREEN}5)${NC} Setup Cloudflare Origin Certificate"
    echo -e "  ${GREEN}6)${NC} Exit"
    echo ""
    read -p "Enter your choice [1-6]: " choice
    
    case $choice in
        1) TOTAL_STEPS=4; setup_all ;;
        2) TOTAL_STEPS=1; setup_user ;;
        3) TOTAL_STEPS=1; setup_coolify ;;
        4) TOTAL_STEPS=1; setup_github_registry ;;
        5) TOTAL_STEPS=1; setup_cloudflare_cert ;;
        6) echo "Goodbye!"; exit 0 ;;
        *) print_error "Invalid option"; sleep 2; show_menu ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Create Coolify User
# ─────────────────────────────────────────────────────────────────────────────

setup_user() {
    print_step "1" "Creating Coolify User"
    
    if id "$COOLIFY_USER" &>/dev/null; then
        print_warning "User '$COOLIFY_USER' already exists"
        if confirm "Do you want to skip user creation?"; then
            print_info "Skipping user creation..."
            return 0
        fi
    fi
    
    print_info "Creating user: $COOLIFY_USER"
    
    # Create user with home directory
    useradd -m -s /bin/bash "$COOLIFY_USER" 2>/dev/null || true
    
    # Add to docker group (will be created later if doesn't exist)
    usermod -aG docker "$COOLIFY_USER" 2>/dev/null || true
    
    # Add to sudo group
    usermod -aG sudo "$COOLIFY_USER" 2>/dev/null || true
    
    # Setup passwordless sudo for coolify user
    echo "$COOLIFY_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$COOLIFY_USER
    chmod 440 /etc/sudoers.d/$COOLIFY_USER
    
    print_success "User '$COOLIFY_USER' created successfully"
    
    # Ask if user wants to set a password
    if confirm "Do you want to set a password for '$COOLIFY_USER'?"; then
        passwd "$COOLIFY_USER"
    fi
    
    print_success "User setup complete!"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Install Coolify
# ─────────────────────────────────────────────────────────────────────────────

setup_coolify() {
    print_step "2" "Installing Coolify"
    
    # Check if Coolify is already installed
    if [ -d "/data/coolify" ]; then
        print_warning "Coolify appears to be already installed at /data/coolify"
        if ! confirm "Do you want to reinstall?"; then
            print_info "Skipping Coolify installation..."
            return 0
        fi
    fi
    
    print_info "Installing required packages..."
    apt-get update -qq
    apt-get install -y -qq curl wget git jq openssl
    
    print_info "Running Coolify installation script..."
    echo ""
    
    # Run the official Coolify installation script
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
    
    echo ""
    print_success "Coolify installed successfully!"
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    print_info "Access Coolify at: ${BOLD}http://$SERVER_IP:8000${NC}"
    print_warning "Create your admin account immediately after installation!"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Setup GitHub Container Registry
# ─────────────────────────────────────────────────────────────────────────────

setup_github_registry() {
    print_step "3" "Setting Up GitHub Container Registry"
    
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
    read -p "Enter your GitHub username: " GITHUB_USERNAME
    if [ -z "$GITHUB_USERNAME" ]; then
        print_error "Username cannot be empty"
        return 1
    fi
    
    echo ""
    read -s -p "Enter your GitHub PAT (hidden): " GITHUB_PAT
    echo ""
    
    if [ -z "$GITHUB_PAT" ]; then
        print_error "PAT cannot be empty"
        return 1
    fi
    
    print_info "Logging into GitHub Container Registry..."
    
    # Login to ghcr.io
    echo "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
    
    if [ $? -eq 0 ]; then
        print_success "Successfully logged into ghcr.io!"
        
        # Show config location
        DOCKER_CONFIG="$HOME/.docker/config.json"
        if [ -f "$DOCKER_CONFIG" ]; then
            print_info "Credentials saved to: $DOCKER_CONFIG"
        fi
        
        # If coolify user exists, also setup for that user
        if id "$COOLIFY_USER" &>/dev/null; then
            print_info "Setting up registry for '$COOLIFY_USER' user as well..."
            
            COOLIFY_DOCKER_DIR="$COOLIFY_HOME/.docker"
            mkdir -p "$COOLIFY_DOCKER_DIR"
            
            # Copy docker config
            if [ -f "$HOME/.docker/config.json" ]; then
                cp "$HOME/.docker/config.json" "$COOLIFY_DOCKER_DIR/config.json"
                chown -R "$COOLIFY_USER:$COOLIFY_USER" "$COOLIFY_DOCKER_DIR"
                chmod 600 "$COOLIFY_DOCKER_DIR/config.json"
                print_success "Registry configured for '$COOLIFY_USER' user"
            fi
        fi
        
        echo ""
        print_success "GitHub Container Registry setup complete!"
        print_info "Coolify will now automatically use these credentials for pulling images"
    else
        print_error "Failed to login to ghcr.io"
        print_info "Please check your username and PAT"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Setup Cloudflare Origin Certificate
# ─────────────────────────────────────────────────────────────────────────────

setup_cloudflare_cert() {
    print_step "4" "Setting Up Cloudflare Origin Certificate"
    
    # Check if Coolify proxy directory exists
    if [ ! -d "/data/coolify/proxy" ]; then
        print_error "Coolify proxy directory not found at /data/coolify/proxy"
        print_info "Please install Coolify first (Option 3)"
        return 1
    fi
    
    print_info "This will configure Cloudflare Origin Certificates for SSL/TLS"
    echo ""
    
    # Get domain
    read -p "Enter your domain (e.g., example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "Domain cannot be empty"
        return 1
    fi
    
    # Create certificates directory
    CERTS_DIR="/data/coolify/proxy/certs"
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
    
    if [ -z "$CERT_CONTENT" ]; then
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
    
    if [ -z "$KEY_CONTENT" ]; then
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
        TRAEFIK_CONFIG="/data/coolify/proxy/dynamic/cloudflare-origin-cert.yaml"
        mkdir -p /data/coolify/proxy/dynamic
        
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
    print_header "Cloudflare Settings Required"
    
    print_info "Configure these settings in Cloudflare Dashboard:"
    print_info "1. SSL/TLS → Overview → Set to: ${BOLD}Full (strict)${NC}"
    print_info "2. SSL/TLS → Edge Certificates → Enable: ${BOLD}Always Use HTTPS${NC}"
    
    echo ""
    print_header "Next Steps"
    
    print_info "1. Restart Traefik proxy in Coolify UI:"
    print_info "   Servers → Your Server → Proxy → Restart Proxy"
    echo ""
    print_info "2. Redeploy your applications"
    echo ""
    print_info "3. Test with: curl -I https://your-app.$DOMAIN"
    
    echo ""
    print_success "Cloudflare Origin Certificate setup complete!"
}

# ─────────────────────────────────────────────────────────────────────────────
# Full Setup (All Steps)
# ─────────────────────────────────────────────────────────────────────────────

setup_all() {
    print_header "Full Coolify Setup"
    
    print_info "This will run all setup steps:"
    print_info "  1. Create Coolify user"
    print_info "  2. Install Coolify"
    print_info "  3. Setup GitHub Container Registry"
    print_info "  4. Setup Cloudflare Origin Certificate"
    echo ""
    
    if ! confirm "Continue with full setup?"; then
        show_menu
        return
    fi
    
    setup_user
    setup_coolify
    
    # Wait for Docker to be ready
    print_info "Waiting for Docker to be ready..."
    sleep 5
    
    setup_github_registry
    setup_cloudflare_cert
    
    print_header "Setup Complete!"
    
    print_success "All setup steps completed successfully!"
    echo ""
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    print_info "Summary:"
    echo "  • Coolify User: $COOLIFY_USER"
    echo "  • Coolify URL: http://$SERVER_IP:8000"
    echo "  • GitHub Registry: Configured"
    echo "  • Cloudflare Cert: Configured"
    echo ""
    print_warning "Don't forget to:"
    print_info "  1. Create your Coolify admin account"
    print_info "  2. Set Cloudflare SSL mode to 'Full (strict)'"
    print_info "  3. Restart Traefik proxy after setup"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────────────────────

main() {
    check_root
    
    # Check for command line arguments
    case "${1:-}" in
        --user)
            TOTAL_STEPS=1
            setup_user
            ;;
        --install)
            TOTAL_STEPS=1
            setup_coolify
            ;;
        --github)
            TOTAL_STEPS=1
            setup_github_registry
            ;;
        --cloudflare)
            TOTAL_STEPS=1
            setup_cloudflare_cert
            ;;
        --all)
            TOTAL_STEPS=4
            setup_all
            ;;
        --help|-h)
            print_banner
            echo "Usage: $0 [OPTION]"
            echo ""
            echo "Options:"
            echo "  --user        Create coolify user only"
            echo "  --install     Install Coolify only"
            echo "  --github      Setup GitHub Container Registry only"
            echo "  --cloudflare  Setup Cloudflare Origin Certificate only"
            echo "  --all         Run full setup (all options)"
            echo "  --help        Show this help message"
            echo ""
            echo "Without options, an interactive menu will be displayed."
            ;;
        "")
            show_menu
            ;;
        *)
            print_error "Unknown option: $1"
            print_info "Use --help for usage information"
            exit 1
            ;;
    esac
}

main "$@"