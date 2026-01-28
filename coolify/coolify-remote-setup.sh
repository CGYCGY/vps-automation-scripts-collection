#!/bin/bash

################################################################################
# Coolify Remote Server Setup Script
#
# This script prepares a server to be connected to an existing Coolify dashboard
# as a managed/remote server.
#
# Usage:
#   ./coolify-remote-setup.sh           # Interactive menu
#   ./coolify-remote-setup.sh --all     # Full setup (all steps)
#   ./coolify-remote-setup.sh --user    # Create coolify user only
#   ./coolify-remote-setup.sh --docker  # Install Docker only
#   ./coolify-remote-setup.sh --ssh     # Setup SSH key only
#   ./coolify-remote-setup.sh --help    # Show help
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

# Step 4: Check and configure firewall
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

# Step 5: Verify setup
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
        echo -e "${YELLOW}5.${NC} Check Firewall"
        echo -e "${YELLOW}6.${NC} Verify Setup"
        echo -e "${YELLOW}7.${NC} Exit"
        echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

        read -rp "$(echo -e "${GREEN}Select an option [1-7]:${NC} ")" choice

        case $choice in
            1)
                setup_coolify_user
                install_docker
                setup_ssh_key
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
                check_firewall
                ;;
            6)
                verify_setup
                ;;
            7)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-7."
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
