#!/bin/bash

#===============================================================================
# VPS Automation Scripts - Main Setup Script
# A unified entry point to run all automation scripts
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# Helper Functions
#===============================================================================

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║          VPS Automation Scripts Collection                       ║"
    echo "║          Professional VPS/Server Management Tools                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_menu() {
    echo -e "${BLUE}Available Scripts:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Tailscale SSH Setup (Generic VPS)"
    echo -e "     ${YELLOW}Secure your VPS with Tailscale SSH - no more SSH keys!${NC}"
    echo ""
    echo -e "  ${GREEN}2)${NC} Tailscale SSH Setup (Oracle Cloud)"
    echo -e "     ${YELLOW}Oracle Cloud specific setup with OCI Security List guidance${NC}"
    echo ""
    echo -e "  ${GREEN}3)${NC} Coolify Setup"
    echo -e "     ${YELLOW}Install Coolify - self-hostable Heroku/Netlify alternative${NC}"
    echo ""
    echo -e "  ${GREEN}4)${NC} MinIO Migration Tool"
    echo -e "     ${YELLOW}Migrate MinIO data between servers with zero downtime${NC}"
    echo ""
    echo -e "  ${GREEN}5)${NC} Swap Configuration"
    echo -e "     ${YELLOW}Configure RAM-based optimized swap settings${NC}"
    echo ""
    echo -e "  ${GREEN}6)${NC} Full Server Setup (Tailscale + Swap + Coolify)"
    echo -e "     ${YELLOW}Complete new server setup with all essentials${NC}"
    echo ""
    echo -e "  ${GREEN}q)${NC} Quit"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script requires root privileges.${NC}"
        echo -e "${YELLOW}Please run with: sudo $0${NC}"
        exit 1
    fi
}

run_script() {
    local script_path="$1"
    local script_name="$2"

    if [[ -f "$script_path" ]]; then
        echo -e "${GREEN}Running $script_name...${NC}"
        echo ""
        chmod +x "$script_path"
        bash "$script_path"
        echo ""
        echo -e "${GREEN}$script_name completed!${NC}"
    else
        echo -e "${RED}Error: Script not found: $script_path${NC}"
        return 1
    fi
}

confirm_action() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

#===============================================================================
# Script Runners
#===============================================================================

run_tailscale_generic() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Tailscale SSH Setup (Generic VPS)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}This script will:${NC}"
    echo "  - Install Tailscale VPN"
    echo "  - Configure UFW firewall"
    echo "  - Enable Tailscale SSH (keyless auth)"
    echo "  - Secure your SSH access"
    echo ""

    if confirm_action "This will modify your SSH and firewall settings."; then
        run_script "$SCRIPT_DIR/tailscale/tailscale-vps-setup.sh" "Tailscale Setup (Generic)"
    else
        echo -e "${YELLOW}Skipped.${NC}"
    fi
}

run_tailscale_oracle() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Tailscale SSH Setup (Oracle Cloud)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}This script will:${NC}"
    echo "  - Install Tailscale VPN"
    echo "  - Configure iptables firewall"
    echo "  - Enable Tailscale SSH (keyless auth)"
    echo "  - Guide you through OCI Security List setup"
    echo ""

    if confirm_action "This will modify your SSH and firewall settings."; then
        run_script "$SCRIPT_DIR/tailscale/tailscale-vps-setup-oracle.sh" "Tailscale Setup (Oracle)"
    else
        echo -e "${YELLOW}Skipped.${NC}"
    fi
}

run_coolify() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Coolify Setup${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}This script will:${NC}"
    echo "  - Create coolify user with proper permissions"
    echo "  - Install Docker (if needed)"
    echo "  - Install Coolify"
    echo "  - Optionally configure GitHub registry & Cloudflare SSL"
    echo ""

    if confirm_action "This will install Coolify on your server."; then
        run_script "$SCRIPT_DIR/coolify/coolify-setup.sh" "Coolify Setup"
    else
        echo -e "${YELLOW}Skipped.${NC}"
    fi
}

run_minio_migration() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  MinIO Migration Tool${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}This script will:${NC}"
    echo "  - Install MinIO Client (mc) if needed"
    echo "  - Configure source and destination MinIO"
    echo "  - Migrate data with progress monitoring"
    echo "  - Verify migration success"
    echo ""

    run_script "$SCRIPT_DIR/minio/minio_migration.sh" "MinIO Migration"
}

run_swap_config() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Swap Configuration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}This script will:${NC}"
    echo "  - Detect RAM and existing swap"
    echo "  - Create 4GB swap file (if needed)"
    echo "  - Optimize swappiness based on RAM"
    echo "  - Configure persistent swap settings"
    echo ""

    if confirm_action "This will modify your swap configuration."; then
        run_script "$SCRIPT_DIR/swap/swap-configuration-module.sh" "Swap Configuration"
    else
        echo -e "${YELLOW}Skipped.${NC}"
    fi
}

run_full_setup() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Full Server Setup${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}This will run the following in order:${NC}"
    echo "  1. Swap Configuration"
    echo "  2. Tailscale SSH Setup"
    echo "  3. Coolify Installation"
    echo ""

    if ! confirm_action "This is a complete server setup. Make sure you have backups."; then
        echo -e "${YELLOW}Aborted.${NC}"
        return
    fi

    # Detect if Oracle Cloud
    local is_oracle=false
    if [[ -f /etc/oracle-cloud-agent/agent.yml ]] || \
       grep -q "oracle" /sys/class/dmi/id/board_vendor 2>/dev/null || \
       grep -q "OracleCloud" /etc/os-release 2>/dev/null; then
        is_oracle=true
        echo -e "${YELLOW}Detected Oracle Cloud instance.${NC}"
    fi

    echo ""
    echo -e "${GREEN}Step 1/3: Configuring Swap...${NC}"
    echo ""
    run_script "$SCRIPT_DIR/swap/swap-configuration-module.sh" "Swap Configuration"

    echo ""
    echo -e "${GREEN}Step 2/3: Setting up Tailscale SSH...${NC}"
    echo ""
    if [[ "$is_oracle" == true ]]; then
        run_script "$SCRIPT_DIR/tailscale/tailscale-vps-setup-oracle.sh" "Tailscale Setup (Oracle)"
    else
        run_script "$SCRIPT_DIR/tailscale/tailscale-vps-setup.sh" "Tailscale Setup (Generic)"
    fi

    echo ""
    echo -e "${GREEN}Step 3/3: Installing Coolify...${NC}"
    echo ""
    run_script "$SCRIPT_DIR/coolify/coolify-setup.sh" "Coolify Setup"

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Full Server Setup Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Access Coolify at: http://YOUR_SERVER_IP:8000"
    echo "  2. Configure your applications in Coolify"
    echo "  3. Test Tailscale SSH: ssh user@100.x.x.x"
    echo ""
}

show_help() {
    echo -e "${CYAN}VPS Automation Scripts - Help${NC}"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  --tailscale         Run Tailscale SSH setup (auto-detects Oracle Cloud)"
    echo "  --tailscale-generic Run Tailscale SSH setup for generic VPS"
    echo "  --tailscale-oracle  Run Tailscale SSH setup for Oracle Cloud"
    echo "  --coolify           Run Coolify setup"
    echo "  --minio             Run MinIO migration tool"
    echo "  --swap              Run swap configuration"
    echo "  --full              Run full server setup (swap + tailscale + coolify)"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Without arguments, an interactive menu will be displayed."
    echo ""
    echo "Examples:"
    echo "  sudo $0              # Interactive menu"
    echo "  sudo $0 --full       # Full server setup"
    echo "  sudo $0 --coolify    # Coolify only"
    echo ""
}

#===============================================================================
# Main
#===============================================================================

main() {
    # Handle command line arguments
    case "${1:-}" in
        --tailscale)
            check_root
            # Auto-detect Oracle Cloud
            if [[ -f /etc/oracle-cloud-agent/agent.yml ]] || \
               grep -q "oracle" /sys/class/dmi/id/board_vendor 2>/dev/null; then
                run_tailscale_oracle
            else
                run_tailscale_generic
            fi
            exit 0
            ;;
        --tailscale-generic)
            check_root
            run_tailscale_generic
            exit 0
            ;;
        --tailscale-oracle)
            check_root
            run_tailscale_oracle
            exit 0
            ;;
        --coolify)
            check_root
            run_coolify
            exit 0
            ;;
        --minio)
            run_minio_migration
            exit 0
            ;;
        --swap)
            check_root
            run_swap_config
            exit 0
            ;;
        --full)
            check_root
            run_full_setup
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac

    # Interactive menu
    print_header

    while true; do
        print_menu
        read -p "Select an option [1-6, q]: " choice
        echo ""

        case $choice in
            1)
                check_root
                run_tailscale_generic
                ;;
            2)
                check_root
                run_tailscale_oracle
                ;;
            3)
                check_root
                run_coolify
                ;;
            4)
                run_minio_migration
                ;;
            5)
                check_root
                run_swap_config
                ;;
            6)
                check_root
                run_full_setup
                ;;
            q|Q)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac

        echo ""
        read -p "Press Enter to return to menu..."
        echo ""
    done
}

main "$@"
