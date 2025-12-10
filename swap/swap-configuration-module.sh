#!/bin/bash
# Swap Configuration Section
# To be inserted as Step 2 in both scripts (after system update, before Tailscale install)

# Step 2: Swap Configuration
echo -e "\n${GREEN}[Step 2/9] Configuring Swap...${NC}"

# Detect current RAM and swap
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
CURRENT_SWAP_MB=$(free -m | awk '/^Swap:/ {print $2}')

echo -e "${BLUE}System Memory:${NC}"
echo "  RAM: ${YELLOW}${TOTAL_RAM_MB}MB${NC}"
echo "  Current Swap: ${YELLOW}${CURRENT_SWAP_MB}MB${NC}"

# Check if sufficient swap already exists
if [ "$CURRENT_SWAP_MB" -ge 2048 ]; then
    echo -e "${GREEN}✓ Sufficient swap already exists (${CURRENT_SWAP_MB}MB)${NC}"
    echo "  Skipping swap creation."
else
    # Check available disk space (in KB)
    AVAILABLE_SPACE_KB=$(df / | awk 'NR==2 {print $4}')
    AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))
    
    echo "  Available disk space: ${YELLOW}${AVAILABLE_SPACE_GB}GB${NC}"
    
    if [ "$AVAILABLE_SPACE_KB" -lt 8388608 ]; then  # Less than 8GB in KB
        echo -e "${YELLOW}⚠ Insufficient disk space (< 8GB free)${NC}"
        echo "  Skipping swap creation for safety."
    else
        echo ""
        echo -e "${CYAN}Recommended: 4GB swap file with RAM-optimized settings${NC}"
        echo "  • Swap size: 4GB (suitable for 1GB-16GB RAM)"
        
        # Show what settings will be applied
        if [ "$TOTAL_RAM_MB" -ge 16384 ]; then
            echo "  • Profile: Optimal performance (16GB+ RAM)"
            echo "  • Swappiness: 10, Cache pressure: 50"
        elif [ "$TOTAL_RAM_MB" -ge 12288 ]; then
            echo "  • Profile: Good performance (12GB+ RAM)"
            echo "  • Swappiness: 10, Cache pressure: 60"
        elif [ "$TOTAL_RAM_MB" -ge 8192 ]; then
            echo "  • Profile: Balanced (8GB+ RAM)"
            echo "  • Swappiness: 20, Cache pressure: 80"
        else
            echo "  • Profile: Survival mode (<8GB RAM)"
            echo "  • Swappiness: 30, Cache pressure: 100"
        fi
        
        echo ""
        read -p "Create optimized swap configuration? [Y/n]: " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "Creating 4GB swap file..."
            
            # Check if /swapfile already exists
            if [ -f /swapfile ]; then
                echo -e "${YELLOW}⚠ /swapfile already exists. Removing old swap file...${NC}"
                sudo swapoff /swapfile 2>/dev/null || true
                sudo rm -f /swapfile
            fi
            
            # Create swap file
            echo "  Allocating 4GB swap file (this may take a moment)..."
            if sudo fallocate -l 4G /swapfile 2>/dev/null; then
                echo -e "${GREEN}  ✓ Swap file allocated${NC}"
            else
                echo -e "${YELLOW}  fallocate failed, using dd instead (slower)...${NC}"
                sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
            fi
            
            # Set permissions
            sudo chmod 600 /swapfile
            echo -e "${GREEN}  ✓ Permissions set${NC}"
            
            # Set up swap
            sudo mkswap /swapfile
            sudo swapon /swapfile
            echo -e "${GREEN}  ✓ Swap activated${NC}"
            
            # Make swap permanent
            if ! grep -q '/swapfile' /etc/fstab; then
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
                echo -e "${GREEN}  ✓ Added to /etc/fstab (persists on reboot)${NC}"
            fi
            
            # Optimize swap settings based on RAM amount
            echo ""
            echo "Optimizing swap settings based on RAM size..."
            
            # Determine optimal settings based on RAM
            # Reference: RAM-based performance tuning
            if [ "$TOTAL_RAM_MB" -ge 16384 ]; then
                # 16GB+ RAM: Optimal performance, minimal swap
                SWAPPINESS=10
                CACHE_PRESSURE=50
                USE_CASE="Optimal performance, minimal swap"
            elif [ "$TOTAL_RAM_MB" -ge 12288 ]; then
                # 12GB+ RAM: Good performance, light swap
                SWAPPINESS=10
                CACHE_PRESSURE=60
                USE_CASE="Good performance, light swap"
            elif [ "$TOTAL_RAM_MB" -ge 8192 ]; then
                # 8GB+ RAM: Balanced, moderate swap
                SWAPPINESS=20
                CACHE_PRESSURE=80
                USE_CASE="Balanced, moderate swap"
            else
                # <8GB RAM: Survival mode, active swap
                SWAPPINESS=30
                CACHE_PRESSURE=100
                USE_CASE="Survival mode, active swap"
            fi
            
            echo "  Profile: ${CYAN}${USE_CASE}${NC}"
            
            # Set swappiness
            sudo sysctl vm.swappiness=$SWAPPINESS > /dev/null
            if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
                echo "vm.swappiness=$SWAPPINESS" | sudo tee -a /etc/sysctl.conf > /dev/null
            else
                sudo sed -i "s/^vm.swappiness=.*/vm.swappiness=$SWAPPINESS/" /etc/sysctl.conf
            fi
            echo -e "${GREEN}  ✓ Swappiness set to $SWAPPINESS${NC}"
            
            # Set cache pressure
            sudo sysctl vm.vfs_cache_pressure=$CACHE_PRESSURE > /dev/null
            if ! grep -q 'vm.vfs_cache_pressure' /etc/sysctl.conf; then
                echo "vm.vfs_cache_pressure=$CACHE_PRESSURE" | sudo tee -a /etc/sysctl.conf > /dev/null
            else
                sudo sed -i "s/^vm.vfs_cache_pressure=.*/vm.vfs_cache_pressure=$CACHE_PRESSURE/" /etc/sysctl.conf
            fi
            echo -e "${GREEN}  ✓ Cache pressure set to $CACHE_PRESSURE${NC}"
            
            # Verify swap is active
            NEW_SWAP_MB=$(free -m | awk '/^Swap:/ {print $2}')
            echo ""
            echo -e "${GREEN}✓ Swap configuration complete!${NC}"
            echo "  Total swap: ${YELLOW}${NEW_SWAP_MB}MB${NC}"
            echo "  Profile: ${CYAN}${USE_CASE}${NC}"
            echo "  Swappiness: ${YELLOW}${SWAPPINESS}${NC}"
            echo "  Cache pressure: ${YELLOW}${CACHE_PRESSURE}${NC}"
        else
            echo -e "${YELLOW}Skipped swap creation${NC}"
        fi
    fi
fi

# Continue with next step...
echo ""
read -p "Press Enter to continue..."