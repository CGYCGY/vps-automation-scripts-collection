#!/bin/bash

# MinIO Migration Tool - Interactive Script
# Version: 1.0.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script version
VERSION="1.0.0"

# Configuration file
CONFIG_FILE="$HOME/.minio_migration_config"

# Functions
print_header() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   MinIO Migration Tool v${VERSION}${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if mc is installed
check_mc_installed() {
    if command -v mc &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Install MinIO Client
install_mc() {
    print_header
    echo "MinIO Client (mc) is not installed."
    echo ""
    read -p "Do you want to install it now? (y/n): " install_choice
    
    if [[ $install_choice =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Installing MinIO Client..."
        
        # Download mc
        wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /tmp/mc
        
        if [ $? -eq 0 ]; then
            chmod +x /tmp/mc
            sudo mv /tmp/mc /usr/local/bin/
            print_success "MinIO Client installed successfully!"
            mc --version
            sleep 2
            return 0
        else
            print_error "Failed to download MinIO Client"
            return 1
        fi
    else
        print_error "Cannot proceed without MinIO Client"
        return 1
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << CONFIGEOF
SOURCE_ALIAS=$SOURCE_ALIAS
SOURCE_URL=$SOURCE_URL
SOURCE_ACCESS_KEY=$SOURCE_ACCESS_KEY
DEST_ALIAS=$DEST_ALIAS
DEST_URL=$DEST_URL
DEST_ACCESS_KEY=$DEST_ACCESS_KEY
CONFIGEOF
    chmod 600 "$CONFIG_FILE"
}

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# Configure source MinIO
configure_source() {
    print_header
    echo "=== Configure SOURCE MinIO ==="
    echo ""
    
    read -p "Enter source alias name (default: source-minio): " SOURCE_ALIAS
    SOURCE_ALIAS=${SOURCE_ALIAS:-source-minio}
    
    read -p "Enter source URL (e.g., http://100.x.x.1:9000): " SOURCE_URL
    read -p "Enter source access key: " SOURCE_ACCESS_KEY
    read -sp "Enter source secret key: " SOURCE_SECRET_KEY
    echo ""
    
    # Test connection
    print_info "Testing source connection..."
    mc alias set "$SOURCE_ALIAS" "$SOURCE_URL" "$SOURCE_ACCESS_KEY" "$SOURCE_SECRET_KEY" &> /dev/null
    
    if mc ls "$SOURCE_ALIAS" &> /dev/null; then
        print_success "Source MinIO connected successfully!"
        save_config
        sleep 2
        return 0
    else
        print_error "Failed to connect to source MinIO"
        read -p "Press Enter to retry..."
        return 1
    fi
}

# Configure destination MinIO
configure_destination() {
    print_header
    echo "=== Configure DESTINATION MinIO ==="
    echo ""
    
    echo "Choose destination type:"
    echo "1) Remote URL (http://IP:PORT)"
    echo "2) Local Docker IP (auto-detect)"
    echo "3) Localhost (http://localhost:9000)"
    echo ""
    read -p "Enter choice (1-3): " dest_type
    
    read -p "Enter destination alias name (default: dest-minio): " DEST_ALIAS
    DEST_ALIAS=${DEST_ALIAS:-dest-minio}
    
    case $dest_type in
        1)
            read -p "Enter destination URL (e.g., http://100.x.x.2:9000): " DEST_URL
            ;;
        2)
            echo ""
            print_info "Finding Docker MinIO container..."
            CONTAINER=$(docker ps --filter name=minio --format "{{.Names}}" | head -1)
            if [ -n "$CONTAINER" ]; then
                DOCKER_IP=$(docker inspect "$CONTAINER" | grep -m 1 '"IPAddress"' | awk -F'"' '{print $4}')
                print_success "Found container: $CONTAINER"
                print_success "Docker IP: $DOCKER_IP"
                DEST_URL="http://$DOCKER_IP:9000"
                echo "Using: $DEST_URL"
            else
                print_error "No MinIO container found"
                read -p "Enter destination URL manually: " DEST_URL
            fi
            ;;
        3)
            DEST_URL="http://localhost:9000"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    read -p "Enter destination access key: " DEST_ACCESS_KEY
    read -sp "Enter destination secret key: " DEST_SECRET_KEY
    echo ""
    
    # Test connection
    print_info "Testing destination connection..."
    mc alias set "$DEST_ALIAS" "$DEST_URL" "$DEST_ACCESS_KEY" "$DEST_SECRET_KEY" &> /dev/null
    
    if mc ls "$DEST_ALIAS" &> /dev/null; then
        print_success "Destination MinIO connected successfully!"
        save_config
        sleep 2
        return 0
    else
        print_error "Failed to connect to destination MinIO"
        read -p "Press Enter to retry..."
        return 1
    fi
}

# List buckets
list_buckets() {
    local alias=$1
    mc ls "$alias" 2>/dev/null | awk '{print $NF}' | sed 's/\///g'
}

# Show bucket info
show_bucket_info() {
    local alias=$1
    local bucket=$2
    
    local size=$(mc du $alias/$bucket 2>/dev/null)
    local files=$(mc ls $alias/$bucket --recursive 2>/dev/null | wc -l)
    
    echo "    Size: $size"
    echo "    Files: $files"
}

# Create buckets on destination
create_buckets() {
    print_header
    echo "=== Create Buckets on Destination ==="
    echo ""
    
    BUCKETS=$(list_buckets "$SOURCE_ALIAS")
    
    if [ -z "$BUCKETS" ]; then
        print_error "No buckets found on source"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo "Buckets found on source:"
    for bucket in $BUCKETS; do
        echo "  - $bucket"
        show_bucket_info "$SOURCE_ALIAS" "$bucket"
    done
    echo ""
    
    read -p "Create all buckets on destination? (y/n): " create_all
    
    if [[ $create_all =~ ^[Yy]$ ]]; then
        for bucket in $BUCKETS; do
            print_info "Creating bucket: $bucket"
            mc mb "$DEST_ALIAS/$bucket" 2>/dev/null && print_success "Created: $bucket" || print_warning "Already exists: $bucket"
        done
    else
        echo ""
        echo "Select buckets to create (space-separated numbers, or 'all'):"
        local i=1
        declare -A bucket_array
        for bucket in $BUCKETS; do
            echo "$i) $bucket"
            bucket_array[$i]=$bucket
            ((i++))
        done
        echo ""
        read -p "Enter selection: " selection
        
        if [ "$selection" = "all" ]; then
            for bucket in $BUCKETS; do
                mc mb "$DEST_ALIAS/$bucket" 2>/dev/null && print_success "Created: $bucket" || print_warning "Already exists: $bucket"
            done
        else
            for num in $selection; do
                if [ -n "${bucket_array[$num]}" ]; then
                    bucket="${bucket_array[$num]}"
                    mc mb "$DEST_ALIAS/$bucket" 2>/dev/null && print_success "Created: $bucket" || print_warning "Already exists: $bucket"
                fi
            done
        fi
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Migrate data
migrate_data() {
    print_header
    echo "=== Migration Options ==="
    echo ""
    echo "1) Migrate all buckets"
    echo "2) Migrate specific bucket"
    echo "3) Migrate multiple buckets (select)"
    echo "4) Back to main menu"
    echo ""
    read -p "Enter choice (1-4): " migration_choice
    
    case $migration_choice in
        1)
            migrate_all_buckets
            ;;
        2)
            migrate_single_bucket
            ;;
        3)
            migrate_multiple_buckets
            ;;
        4)
            return
            ;;
        *)
            print_error "Invalid choice"
            sleep 1
            migrate_data
            ;;
    esac
}

# Migrate all buckets
migrate_all_buckets() {
    print_header
    echo "=== Migrate All Buckets ==="
    echo ""
    
    BUCKETS=$(list_buckets "$SOURCE_ALIAS")
    
    echo "Buckets to migrate:"
    for bucket in $BUCKETS; do
        echo "  - $bucket"
        show_bucket_info "$SOURCE_ALIAS" "$bucket"
    done
    echo ""
    
    read -p "Start migration? (y/n): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Starting migration of all buckets..."
        echo ""
        
        for bucket in $BUCKETS; do
            echo "----------------------------------------"
            print_info "Migrating bucket: $bucket"
            echo "Started at: $(date)"
            echo ""
            
            mc mirror "$SOURCE_ALIAS/$bucket" "$DEST_ALIAS/$bucket" \
                --preserve \
                --retry 3 \
                2>&1 | tee "migration-$bucket-$(date +%Y%m%d-%H%M%S).log"
            
            if [ $? -eq 0 ]; then
                print_success "✓ $bucket completed"
            else
                print_error "✗ $bucket failed"
            fi
            echo ""
        done
        
        print_success "All buckets migration completed!"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# Migrate single bucket
migrate_single_bucket() {
    print_header
    echo "=== Migrate Single Bucket ==="
    echo ""
    
    BUCKETS=$(list_buckets "$SOURCE_ALIAS")
    
    echo "Available buckets:"
    local i=1
    declare -A bucket_array
    for bucket in $BUCKETS; do
        echo "$i) $bucket"
        show_bucket_info "$SOURCE_ALIAS" "$bucket"
        bucket_array[$i]=$bucket
        ((i++))
        echo ""
    done
    
    read -p "Select bucket number: " bucket_num
    
    if [ -n "${bucket_array[$bucket_num]}" ]; then
        SELECTED_BUCKET="${bucket_array[$bucket_num]}"
        
        print_header
        echo "=== Migrating: $SELECTED_BUCKET ==="
        echo ""
        
        print_info "Source info:"
        show_bucket_info "$SOURCE_ALIAS" "$SELECTED_BUCKET"
        echo ""
        
        read -p "Start migration? (y/n): " confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo ""
            print_info "Starting migration..."
            echo ""
            
            mc mirror "$SOURCE_ALIAS/$SELECTED_BUCKET" "$DEST_ALIAS/$SELECTED_BUCKET" \
                --preserve \
                --retry 3
            
            if [ $? -eq 0 ]; then
                print_success "Migration completed!"
            else
                print_error "Migration failed!"
            fi
            echo ""
            read -p "Press Enter to continue..."
        fi
    else
        print_error "Invalid selection"
        sleep 1
        migrate_single_bucket
    fi
}

# Migrate multiple buckets
migrate_multiple_buckets() {
    print_header
    echo "=== Migrate Multiple Buckets ==="
    echo ""
    
    BUCKETS=$(list_buckets "$SOURCE_ALIAS")
    
    echo "Available buckets:"
    local i=1
    declare -A bucket_array
    for bucket in $BUCKETS; do
        echo "$i) $bucket"
        show_bucket_info "$SOURCE_ALIAS" "$bucket"
        bucket_array[$i]=$bucket
        ((i++))
        echo ""
    done
    
    echo "Enter bucket numbers separated by spaces (e.g., 1 3 5):"
    read -p "Selection: " selection
    
    echo ""
    echo "Selected buckets:"
    for num in $selection; do
        if [ -n "${bucket_array[$num]}" ]; then
            echo "  - ${bucket_array[$num]}"
        fi
    done
    echo ""
    
    read -p "Start migration? (y/n): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo ""
        for num in $selection; do
            if [ -n "${bucket_array[$num]}" ]; then
                bucket="${bucket_array[$num]}"
                echo "----------------------------------------"
                print_info "Migrating: $bucket"
                echo ""
                
                mc mirror "$SOURCE_ALIAS/$bucket" "$DEST_ALIAS/$bucket" \
                    --preserve \
                    --retry 3
                
                if [ $? -eq 0 ]; then
                    print_success "✓ $bucket completed"
                else
                    print_error "✗ $bucket failed"
                fi
                echo ""
            fi
        done
        
        print_success "Migration completed!"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# Verify migration
verify_migration() {
    print_header
    echo "=== Verify Migration ==="
    echo ""
    
    print_info "Checking buckets..."
    echo ""
    
    BUCKETS=$(list_buckets "$SOURCE_ALIAS")
    
    printf "%-20s | %15s | %15s | %10s\n" "Bucket" "Source Files" "Dest Files" "Status"
    echo "------------------------------------------------------------------------"
    
    ALL_MATCH=true
    
    for bucket in $BUCKETS; do
        src_count=$(mc ls "$SOURCE_ALIAS/$bucket" --recursive 2>/dev/null | wc -l)
        dst_count=$(mc ls "$DEST_ALIAS/$bucket" --recursive 2>/dev/null | wc -l)
        
        if [ "$src_count" -eq "$dst_count" ]; then
            status="${GREEN}✓ MATCH${NC}"
        else
            status="${RED}✗ DIFF${NC}"
            ALL_MATCH=false
        fi
        
        printf "%-20s | %15s | %15s | " "$bucket" "$src_count" "$dst_count"
        echo -e "$status"
    done
    
    echo ""
    echo "Overall comparison:"
    echo "  Source total:"
    mc du "$SOURCE_ALIAS"
    echo "  Destination total:"
    mc du "$DEST_ALIAS"
    echo ""
    
    print_info "Running detailed diff..."
    DIFF_OUTPUT=$(mc diff "$SOURCE_ALIAS" "$DEST_ALIAS" 2>&1)
    
    if [ -z "$DIFF_OUTPUT" ]; then
        print_success "✓✓✓ Perfect match - No differences found!"
    else
        print_warning "Differences found:"
        echo "$DIFF_OUTPUT"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Show current configuration
show_config() {
    print_header
    echo "=== Current Configuration ==="
    echo ""
    
    if [ -n "$SOURCE_ALIAS" ]; then
        echo "Source MinIO:"
        echo "  Alias: $SOURCE_ALIAS"
        echo "  URL: $SOURCE_URL"
        echo "  Access Key: $SOURCE_ACCESS_KEY"
        echo -n "  Status: "
        if mc ls "$SOURCE_ALIAS" &> /dev/null; then
            echo -e "${GREEN}Connected${NC}"
            echo "  Buckets: $(list_buckets "$SOURCE_ALIAS" | wc -l)"
        else
            echo -e "${RED}Disconnected${NC}"
        fi
    else
        print_warning "Source not configured"
    fi
    
    echo ""
    
    if [ -n "$DEST_ALIAS" ]; then
        echo "Destination MinIO:"
        echo "  Alias: $DEST_ALIAS"
        echo "  URL: $DEST_URL"
        echo "  Access Key: $DEST_ACCESS_KEY"
        echo -n "  Status: "
        if mc ls "$DEST_ALIAS" &> /dev/null; then
            echo -e "${GREEN}Connected${NC}"
            echo "  Buckets: $(list_buckets "$DEST_ALIAS" | wc -l)"
        else
            echo -e "${RED}Disconnected${NC}"
        fi
    else
        print_warning "Destination not configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Advanced options menu
advanced_options() {
    while true; do
        print_header
        echo "=== Advanced Options ==="
        echo ""
        echo "1) Sync with --remove flag (delete extra files)"
        echo "2) Migrate with bandwidth limit"
        echo "3) Resume incomplete migration"
        echo "4) Export migration report"
        echo "5) Show migration logs"
        echo "6) Back to main menu"
        echo ""
        read -p "Enter choice (1-6): " adv_choice
        
        case $adv_choice in
            1)
                print_header
                print_warning "This will delete files in destination that don't exist in source!"
                read -p "Are you sure? (type 'yes' to confirm): " confirm
                if [ "$confirm" = "yes" ]; then
                    mc mirror "$SOURCE_ALIAS" "$DEST_ALIAS" --preserve --remove
                    read -p "Press Enter to continue..."
                fi
                ;;
            2)
                print_header
                read -p "Enter upload limit (e.g., 5M, 10M): " upload_limit
                read -p "Enter download limit (e.g., 5M, 10M): " download_limit
                mc mirror "$SOURCE_ALIAS" "$DEST_ALIAS" \
                    --preserve \
                    --limit-upload "$upload_limit" \
                    --limit-download "$download_limit"
                read -p "Press Enter to continue..."
                ;;
            3)
                print_header
                print_info "Resuming migration (will skip existing files)..."
                mc mirror "$SOURCE_ALIAS" "$DEST_ALIAS" --preserve
                read -p "Press Enter to continue..."
                ;;
            4)
                print_header
                REPORT_FILE="migration_report_$(date +%Y%m%d_%H%M%S).txt"
                {
                    echo "MinIO Migration Report"
                    echo "Generated: $(date)"
                    echo ""
                    echo "Source: $SOURCE_URL"
                    echo "Destination: $DEST_URL"
                    echo ""
                    echo "Bucket Summary:"
                    for bucket in $(list_buckets "$SOURCE_ALIAS"); do
                        echo "  $bucket"
                        echo "    Source: $(mc du $SOURCE_ALIAS/$bucket 2>/dev/null)"
                        echo "    Dest:   $(mc du $DEST_ALIAS/$bucket 2>/dev/null)"
                    done
                } > "$REPORT_FILE"
                print_success "Report saved to: $REPORT_FILE"
                read -p "Press Enter to continue..."
                ;;
            5)
                print_header
                echo "Recent migration logs:"
                echo ""
                ls -lht migration-*.log 2>/dev/null | head -10
                echo ""
                read -p "Enter log filename to view (or press Enter to skip): " logfile
                if [ -n "$logfile" ] && [ -f "$logfile" ]; then
                    less "$logfile"
                fi
                read -p "Press Enter to continue..."
                ;;
            6)
                return
                ;;
            *)
                print_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Main menu
main_menu() {
    while true; do
        print_header
        echo "Main Menu:"
        echo ""
        echo "1) Configure Source MinIO"
        echo "2) Configure Destination MinIO"
        echo "3) Show Current Configuration"
        echo "4) Create Buckets on Destination"
        echo "5) Migrate Data"
        echo "6) Verify Migration"
        echo "7) Advanced Options"
        echo "8) Exit"
        echo ""
        read -p "Enter choice (1-8): " choice
        
        case $choice in
            1)
                configure_source
                ;;
            2)
                configure_destination
                ;;
            3)
                show_config
                ;;
            4)
                if [ -z "$SOURCE_ALIAS" ] || [ -z "$DEST_ALIAS" ]; then
                    print_error "Please configure both source and destination first"
                    sleep 2
                else
                    create_buckets
                fi
                ;;
            5)
                if [ -z "$SOURCE_ALIAS" ] || [ -z "$DEST_ALIAS" ]; then
                    print_error "Please configure both source and destination first"
                    sleep 2
                else
                    migrate_data
                fi
                ;;
            6)
                if [ -z "$SOURCE_ALIAS" ] || [ -z "$DEST_ALIAS" ]; then
                    print_error "Please configure both source and destination first"
                    sleep 2
                else
                    verify_migration
                fi
                ;;
            7)
                if [ -z "$SOURCE_ALIAS" ] || [ -z "$DEST_ALIAS" ]; then
                    print_error "Please configure both source and destination first"
                    sleep 2
                else
                    advanced_options
                fi
                ;;
            8)
                print_header
                echo "Thank you for using MinIO Migration Tool!"
                echo ""
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Main execution
main() {
    # Check if mc is installed
    if ! check_mc_installed; then
        if ! install_mc; then
            exit 1
        fi
    fi
    
    # Load previous configuration if exists
    load_config
    
    # Start main menu
    main_menu
}

# Run the script
main