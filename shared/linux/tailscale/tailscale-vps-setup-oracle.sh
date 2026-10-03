#!/bin/bash

# Oracle Cloud VM Tailscale SSH Setup Script
# For Ubuntu 24.04 on Oracle Cloud (ARM64)

set -e # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Tailscale SSH Setup for Oracle Cloud${NC}"
echo -e "${BLUE}================================${NC}\n"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Please do not run this script as root (no sudo)${NC}"
    echo "The script will prompt for sudo when needed."
    exit 1
fi

# Detect current user
CURRENT_USER=$(whoami)
echo -e "${BLUE}Running as user: ${YELLOW}$CURRENT_USER${NC}\n"

# IMPORTANT: Ask about server management services
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Important: Server Management Service Check${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Will this server be MANAGED BY (not hosting) any deployment/management services?${NC}"
echo ""
echo "Examples of management services:"
echo "  • Coolify (deployment platform)"
echo "  • Portainer (container management)"
echo "  • Ansible/Terraform (infrastructure automation)"
echo "  • CI/CD services (Jenkins, GitLab CI, GitHub Actions runners)"
echo "  • Deployment platforms that need SSH access"
echo ""
echo -e "${RED}IMPORTANT:${NC} If you answer YES, Tailscale SSH will NOT be enabled."
echo "This is because Tailscale SSH restricts SSH access to only your Tailscale network,"
echo "which would block these management services from connecting to your server."
echo ""
read -p "Is this server MANAGED BY such services? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    SKIP_TAILSCALE_SSH=true
    echo -e "${YELLOW}✓ Noted: Tailscale SSH will be SKIPPED to allow management service access${NC}"
    echo -e "${BLUE}  SSH will remain accessible via normal methods${NC}"
else
    SKIP_TAILSCALE_SSH=false
    echo -e "${GREEN}✓ Noted: Tailscale SSH will be enabled for secure keyless authentication${NC}"
fi
echo ""
read -p "Press Enter to continue..."

# Step 1: System update
echo -e "\n${GREEN}[Step 1/8] Updating system packages...${NC}"
read -p "Would you like to update system packages first? (recommended) [Y/n]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Updating packages..."
    sudo apt update
    echo -e "${GREEN}✓ System packages updated${NC}"
else
    echo -e "${YELLOW}Skipped system update${NC}"
fi

# Step 2: Install Tailscale
echo -e "\n${GREEN}[Step 2/8] Installing Tailscale...${NC}"
if command -v tailscale &> /dev/null; then
    echo -e "${YELLOW}Tailscale is already installed.${NC}"
    TAILSCALE_VERSION=$(tailscale version | head -n1)
    echo -e "Version: ${BLUE}$TAILSCALE_VERSION${NC}"
else
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo -e "${GREEN}✓ Tailscale installed${NC}"
fi

# Step 3: Start Tailscale
echo -e "\n${GREEN}[Step 3/8] Starting Tailscale...${NC}"
if sudo tailscale status &> /dev/null; then
    echo -e "${YELLOW}Tailscale is already running.${NC}"
    TAILSCALE_IP=$(tailscale ip -4)
    echo -e "Current Tailscale IP: ${GREEN}$TAILSCALE_IP${NC}"
else
    echo "Starting Tailscale..."
    echo -e "${YELLOW}You will need to authenticate in your browser.${NC}"
    sudo tailscale up
    sleep 2
    TAILSCALE_IP=$(tailscale ip -4)
    echo -e "${GREEN}✓ Tailscale started with IP: $TAILSCALE_IP${NC}"
fi

# Step 4: Install and configure UFW
echo -e "\n${GREEN}[Step 4/8] Configuring UFW Firewall...${NC}"

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    echo "Installing UFW..."
    sudo apt install -y ufw
fi

# Check if UFW is already enabled
UFW_STATUS=$(sudo ufw status | grep -i "Status:" | awk '{print $2}')

if [ "$UFW_STATUS" = "active" ]; then
    echo -e "${YELLOW}UFW is already active. Current rules:${NC}"
    sudo ufw status numbered
    echo ""
    read -p "Do you want to reconfigure UFW rules? This will reset firewall rules. [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Resetting UFW..."
        sudo ufw --force reset
        CONFIGURE_UFW=true
    else
        echo -e "${YELLOW}Skipping UFW configuration. Existing rules preserved.${NC}"
        CONFIGURE_UFW=false
    fi
else
    CONFIGURE_UFW=true
fi

if [ "$CONFIGURE_UFW" = true ]; then
    echo "Configuring firewall rules..."
    
    # Set default policies
    sudo ufw --force default deny incoming
    sudo ufw --force default allow outgoing
    
    if [ "$SKIP_TAILSCALE_SSH" = true ]; then
        # Allow SSH from anywhere since management services need access
        echo -e "${YELLOW}Allowing SSH from all sources (for management service access)${NC}"
        sudo ufw allow 22/tcp comment 'SSH (for management services)'
    else
        # Allow SSH only from Tailscale network
        sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH from Tailscale'
    fi
    
    # Ask about additional ports
    echo ""
    echo -e "${BLUE}Common additional ports you might want to allow:${NC}"
    echo " - 80 (HTTP)"
    echo " - 443 (HTTPS)"
    echo " - 3000 (Development servers)"
    echo " - Custom application ports"
    echo ""
    read -p "Do you want to allow HTTP (port 80) and HTTPS (port 443)? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo ufw allow 80/tcp comment 'HTTP'
        sudo ufw allow 443/tcp comment 'HTTPS'
        echo -e "${GREEN}✓ HTTP and HTTPS allowed${NC}"
    fi
    
    echo ""
    read -p "Do you want to add any other custom ports? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter port number (or 'done' to finish): " CUSTOM_PORT
            if [ "$CUSTOM_PORT" = "done" ]; then
                break
            fi
            if [[ "$CUSTOM_PORT" =~ ^[0-9]+$ ]] && [ "$CUSTOM_PORT" -ge 1 ] && [ "$CUSTOM_PORT" -le 65535 ]; then
                read -p "Protocol? [tcp/udp/both] (default: tcp): " PROTOCOL
                PROTOCOL=${PROTOCOL:-tcp}
                
                if [ "$PROTOCOL" = "both" ]; then
                    sudo ufw allow $CUSTOM_PORT comment "Custom port $CUSTOM_PORT"
                else
                    sudo ufw allow $CUSTOM_PORT/$PROTOCOL comment "Custom port $CUSTOM_PORT/$PROTOCOL"
                fi
                echo -e "${GREEN}✓ Port $CUSTOM_PORT/$PROTOCOL allowed${NC}"
            else
                echo -e "${RED}Invalid port number. Please enter a number between 1-65535.${NC}"
            fi
        done
    fi
    
    # Enable UFW
    echo ""
    echo "Enabling UFW..."
    sudo ufw --force enable
    
    echo -e "${GREEN}✓ UFW configured and enabled${NC}"
else
    if [ "$SKIP_TAILSCALE_SSH" = true ]; then
        echo -e "${YELLOW}Ensuring SSH is accessible from all sources...${NC}"
        # Make sure SSH rule exists and is not restricted to Tailscale only
        if ! sudo ufw status | grep -q "22/tcp"; then
            sudo ufw allow 22/tcp comment 'SSH (for management services)'
            echo -e "${GREEN}✓ SSH rule added${NC}"
        else
            echo -e "${YELLOW}SSH rule already exists${NC}"
        fi
    else
        echo -e "${YELLOW}Adding Tailscale SSH rule to existing configuration...${NC}"
        # Check if rule already exists
        if ! sudo ufw status | grep -q "100.64.0.0/10.*22/tcp"; then
            sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH from Tailscale'
            echo -e "${GREEN}✓ Tailscale SSH rule added${NC}"
        else
            echo -e "${YELLOW}Tailscale SSH rule already exists${NC}"
        fi
    fi
fi

echo ""
echo -e "${BLUE}Current UFW Status:${NC}"
sudo ufw status verbose

# Step 5: Oracle Cloud Security List configuration
echo -e "\n${YELLOW}[Step 5/8] Oracle Cloud Security List Configuration${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}IMPORTANT: You need to configure Oracle Cloud Security List!${NC}"
echo ""
echo "Steps to follow:"
echo "1. Go to Oracle Cloud Console: https://cloud.oracle.com"
echo "2. Navigate to: Networking → Virtual Cloud Networks"
echo "3. Select your VCN → Select your Subnet"
echo "4. Click on the Security List"
echo "5. Review your Ingress Rules:"
echo ""

if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo -e "${BLUE}For SSH (port 22):${NC}"
    echo " - KEEP the rule allowing 0.0.0.0/0 (management services need access)"
    echo " - OR restrict it to specific IPs of your management services"
else
    echo -e "${BLUE}For SSH (port 22):${NC}"
    echo " - You can DELETE the rule allowing 0.0.0.0/0 (Tailscale provides access)"
    echo " - Or restrict it to your specific IP for backup access"
fi
echo ""

# Check what ports user configured
if sudo ufw status | grep -q "80/tcp"; then
    echo -e "${BLUE}For HTTP (port 80):${NC}"
    echo " - ADD ingress rule: Source 0.0.0.0/0, Protocol TCP, Port 80"
fi

if sudo ufw status | grep -q "443/tcp"; then
    echo -e "${BLUE}For HTTPS (port 443):${NC}"
    echo " - ADD ingress rule: Source 0.0.0.0/0, Protocol TCP, Port 443"
fi

echo ""
echo -e "${YELLOW}Note: UFW (on the VM) and OCI Security List (network level) work together.${NC}"
echo -e "${YELLOW} Both must allow traffic for it to reach your VM.${NC}"
echo ""
read -p "Press Enter once you've completed this step (or press Ctrl+C to exit and do it later)..."

# Step 6: Enable Tailscale SSH (conditionally)
echo -e "\n${GREEN}[Step 6/8] Tailscale SSH Configuration...${NC}"
if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}SKIPPED: Tailscale SSH NOT enabled${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}Reason: Server is managed by external services${NC}"
    echo "SSH remains accessible via standard methods to allow management service connections."
    echo ""
    echo -e "${YELLOW}Note: You can still use Tailscale for secure networking,${NC}"
    echo -e "${YELLOW}but SSH won't be restricted to Tailscale-only access.${NC}"
else
    echo "Enabling Tailscale SSH feature..."
    sudo tailscale up --ssh
    echo -e "${GREEN}✓ Tailscale SSH enabled${NC}"
    echo ""
    echo -e "${BLUE}Keyless SSH authentication is now active!${NC}"
    echo "You can connect from any device in your Tailscale network without SSH keys."
fi

# Step 7: Check PasswordAuthentication setting
echo -e "\n${GREEN}[Step 7/8] Checking SSH PasswordAuthentication...${NC}"
PASSWORD_AUTH=$(sudo sshd -T | grep "^passwordauthentication" | awk '{print $2}')

if [ "$PASSWORD_AUTH" = "no" ]; then
    echo -e "${GREEN}✓ PasswordAuthentication is disabled (secure)${NC}"
else
    echo -e "${YELLOW}⚠ PasswordAuthentication is currently: $PASSWORD_AUTH${NC}"
    echo ""
    
    if [ "$SKIP_TAILSCALE_SSH" = true ]; then
        echo -e "${BLUE}Password authentication status for managed servers:${NC}"
        echo "• Disabling it prevents brute-force attacks"
        echo "• Your management services likely use SSH keys anyway"
        echo "• Consider disabling it after confirming key-based access works"
        echo ""
        read -p "Would you like to disable password authentication? [y/N]: " -n 1 -r
    else
        echo -e "${BLUE}Disabling password authentication improves security by:${NC}"
        echo " • Preventing brute-force password attacks"
        echo " • Forcing key-based or Tailscale authentication only"
        echo ""
        read -p "Would you like to disable it? (recommended) [Y/n]: " -n 1 -r
    fi
    
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || { [ "$SKIP_TAILSCALE_SSH" = false ] && [[ ! $REPLY =~ ^[Nn]$ ]]; }; then
        echo "Disabling PasswordAuthentication..."
        
        # Backup original config
        sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%F-%H%M%S)
        
        # Disable password authentication
        sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        
        # Add the line if it doesn't exist
        if ! grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
            echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config > /dev/null
        fi
        
        sudo systemctl restart ssh
        echo -e "${GREEN}✓ PasswordAuthentication disabled${NC}"
        echo -e "${YELLOW} Backup saved to: /etc/ssh/sshd_config.backup.*${NC}"
    else
        echo -e "${YELLOW}Skipped. You can disable it later by editing /etc/ssh/sshd_config${NC}"
    fi
fi

# Step 8: Set password for Serial Console
echo -e "\n${GREEN}[Step 8/8] Setting password for Serial Console access...${NC}"
echo -e "${YELLOW}Oracle Cloud Serial Console requires a password for emergency access.${NC}"
echo "This password is ONLY for Oracle Cloud Serial Console."
echo "It will NOT be used for SSH (SSH uses keys/Tailscale)."
echo ""
echo -e "${BLUE}To set up Serial Console access:${NC}"
echo "1. Go to: Compute → Instances → Your VM"
echo "2. Resources → Console Connections"
echo "3. Create Console Connection (upload your SSH public key)"
echo ""

# Check if user has a password set
if sudo passwd -S $CURRENT_USER | grep -q "NP\|L"; then
    echo -e "${YELLOW}⚠ User $CURRENT_USER does not have a password set.${NC}"
    read -p "Would you like to set a password now? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo passwd $CURRENT_USER
        echo -e "${GREEN}✓ Password set for $CURRENT_USER${NC}"
    else
        echo -e "${YELLOW}Skipped. Remember to set it later with: sudo passwd $CURRENT_USER${NC}"
    fi
else
    echo -e "${GREEN}✓ User $CURRENT_USER already has a password set${NC}"
    read -p "Would you like to change it? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo passwd $CURRENT_USER
        echo -e "${GREEN}✓ Password updated for $CURRENT_USER${NC}"
    fi
fi

# Final verification and summary
echo -e "\n${BLUE}================================${NC}"
echo -e "${BLUE}Setup Complete! Summary:${NC}"
echo -e "${BLUE}================================${NC}\n"

echo -e "${GREEN}✓ Tailscale installed and running${NC}"
echo -e " Tailscale IP: ${YELLOW}$TAILSCALE_IP${NC}"
echo -e " Hostname: ${YELLOW}$(hostname)${NC}"
echo ""

echo -e "${GREEN}✓ UFW Firewall configured${NC}"
if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo " SSH allowed from all sources (for management services)"
else
    echo " SSH allowed only from Tailscale network (100.64.0.0/10)"
fi

if sudo ufw status | grep -q "80/tcp"; then
    echo " HTTP (port 80) allowed"
fi
if sudo ufw status | grep -q "443/tcp"; then
    echo " HTTPS (port 443) allowed"
fi
echo ""

if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo -e "${YELLOW}⚠ Tailscale SSH: NOT enabled (skipped for management services)${NC}"
    echo " SSH remains accessible via standard methods"
else
    echo -e "${GREEN}✓ Tailscale SSH enabled${NC}"
    echo " You can now SSH without keys from your Tailscale devices"
fi
echo ""

PASSWORD_AUTH_FINAL=$(sudo sshd -T | grep "^passwordauthentication" | awk '{print $2}')
if [ "$PASSWORD_AUTH_FINAL" = "no" ]; then
    echo -e "${GREEN}✓ SSH PasswordAuthentication: disabled${NC}"
else
    echo -e "${YELLOW}⚠ SSH PasswordAuthentication: $PASSWORD_AUTH_FINAL${NC}"
fi
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}How to Connect:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo -e "${BLUE}Standard SSH connection:${NC}"
    echo ""
    echo -e " ${YELLOW}ssh $CURRENT_USER@<server-ip>${NC}"
    echo ""
    echo -e "${BLUE}Or via Tailscale IP (optional):${NC}"
    echo ""
    echo -e " ${YELLOW}ssh $CURRENT_USER@$TAILSCALE_IP${NC}"
    echo ""
    echo -e "${YELLOW}Note: Your management services should use the public IP/hostname${NC}"
else
    echo -e "From any device in your Tailscale network:"
    echo ""
    echo -e " ${YELLOW}ssh $CURRENT_USER@$TAILSCALE_IP${NC}"
    echo ""
    echo " or"
    echo ""
    echo -e " ${YELLOW}ssh $CURRENT_USER@$(hostname)${NC}"
fi
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Oracle Cloud Next Steps:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "1. ${RED}Configure OCI Security List${NC} (if not done already)"

if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo " - Ensure SSH (port 22) is accessible from required sources"
else
    echo " - Remove/restrict SSH (port 22) from 0.0.0.0/0"
fi

if sudo ufw status | grep -q "80/tcp\|443/tcp"; then
    echo " - Add ingress rules for HTTP/HTTPS if configured above"
fi
echo ""
echo "2. ${YELLOW}Set up Serial Console${NC} (emergency backup)"
echo " - Compute → Instances → Console Connections"
echo " - Create Console Connection"
echo " - Upload your SSH public key"
echo " - Test login with your password"
echo ""
echo "3. ${GREEN}Test SSH Access${NC}"
if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo " - Verify your management services can connect"
    echo " - From another device: ssh $CURRENT_USER@<server-ip>"
else
    echo " - From another device: ssh $CURRENT_USER@$TAILSCALE_IP"
fi
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Security Checklist:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo "✓ Tailscale VPN enabled (secure networking)"
    echo "⚠ Tailscale SSH NOT enabled (allows management service access)"
    echo "✓ UFW firewall configured (SSH accessible for management)"
else
    echo "✓ Tailscale SSH enabled (keyless authentication)"
    echo "✓ UFW firewall configured (SSH only from Tailscale)"
fi

if [ "$PASSWORD_AUTH_FINAL" = "no" ]; then
    echo "✓ Password authentication disabled (key-based only)"
else
    echo "⚠ Password authentication still enabled"
fi
echo "⚠ OCI Security List - requires manual configuration"
echo "⚠ Serial Console - recommended to set up for emergencies"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Tailscale Admin:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Manage your Tailscale network at:"
echo -e "${BLUE}https://login.tailscale.com/admin${NC}"
echo ""

if [ "$SKIP_TAILSCALE_SSH" = false ]; then
    echo "Configure SSH ACLs (access controls) at:"
    echo -e "${BLUE}https://login.tailscale.com/admin/acls${NC}"
    echo ""
fi

# Show Tailscale status
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Current Tailscale Status:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
tailscale status

echo ""
if [ "$SKIP_TAILSCALE_SSH" = true ]; then
    echo -e "${GREEN}🎉 Your Oracle Cloud VM is now connected to Tailscale!${NC}"
    echo -e "${BLUE}   SSH remains accessible for management services.${NC}"
else
    echo -e "${GREEN}🎉 Your Oracle Cloud VM is now secured with Tailscale SSH!${NC}"
fi
echo ""