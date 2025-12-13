#!/bin/bash

# MinIO User & Bucket Manager - Interactive Script
# Version: 1.0.0
# Manages MinIO users with bucket-specific access permissions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Script version
VERSION="1.0.0"

# Current selected alias
CURRENT_ALIAS=""

#===============================================================================
# Helper Functions
#===============================================================================

print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         MinIO User & Bucket Manager v${VERSION}                       ║${NC}"
    echo -e "${CYAN}║         Manage users with bucket-specific access                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ -n "$CURRENT_ALIAS" ]; then
        echo -e "${MAGENTA}Current Alias: ${GREEN}$CURRENT_ALIAS${NC}"
        echo ""
    fi
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

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}

#===============================================================================
# MC Installation Functions
#===============================================================================

check_mc_installed() {
    if command -v mc &> /dev/null; then
        return 0
    else
        return 1
    fi
}

detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        *)
            echo "amd64"
            ;;
    esac
}

install_mc() {
    print_header
    echo -e "${YELLOW}MinIO Client (mc) is not installed.${NC}"
    echo ""
    echo "The MinIO Client is required to manage users and buckets."
    echo ""
    read -p "Do you want to install it now? (y/n): " install_choice

    if [[ $install_choice =~ ^[Yy]$ ]]; then
        echo ""
        local arch=$(detect_architecture)
        print_info "Detected architecture: $arch"
        print_info "Downloading MinIO Client..."

        local download_url="https://dl.min.io/client/mc/release/linux-${arch}/mc"

        if wget -q "$download_url" -O /tmp/mc; then
            chmod +x /tmp/mc

            # Try to install to /usr/local/bin, fall back to ~/bin
            if sudo mv /tmp/mc /usr/local/bin/ 2>/dev/null; then
                print_success "MinIO Client installed to /usr/local/bin/"
            else
                mkdir -p "$HOME/bin"
                mv /tmp/mc "$HOME/bin/"
                export PATH="$HOME/bin:$PATH"
                print_success "MinIO Client installed to ~/bin/"
                print_warning "Add ~/bin to your PATH: export PATH=\"\$HOME/bin:\$PATH\""
            fi

            echo ""
            mc --version
            sleep 2
            return 0
        else
            print_error "Failed to download MinIO Client"
            echo ""
            echo "Manual installation:"
            echo "  wget $download_url"
            echo "  chmod +x mc"
            echo "  sudo mv mc /usr/local/bin/"
            return 1
        fi
    else
        print_error "Cannot proceed without MinIO Client"
        return 1
    fi
}

#===============================================================================
# Alias Management Functions
#===============================================================================

list_aliases() {
    mc alias list 2>/dev/null | grep -E "^[a-zA-Z]" | awk '{print $1}'
}

get_alias_info() {
    local alias_name=$1
    mc alias list "$alias_name" 2>/dev/null
}

select_alias() {
    print_header
    echo -e "${BLUE}=== Select MinIO Alias ===${NC}"
    echo ""

    local aliases=($(list_aliases))

    if [ ${#aliases[@]} -eq 0 ]; then
        print_warning "No aliases configured."
        echo ""
        read -p "Would you like to create a new alias? (y/n): " create_new
        if [[ $create_new =~ ^[Yy]$ ]]; then
            create_alias
        fi
        return
    fi

    echo "Available aliases:"
    echo ""
    local i=1
    for alias in "${aliases[@]}"; do
        local url=$(mc alias list "$alias" 2>/dev/null | grep "URL" | awk '{print $3}')
        echo -e "  ${GREEN}$i)${NC} $alias"
        echo -e "     ${YELLOW}URL: $url${NC}"
        echo ""
        ((i++))
    done

    echo -e "  ${GREEN}n)${NC} Create new alias"
    echo -e "  ${GREEN}b)${NC} Back to main menu"
    echo ""

    read -p "Select alias [1-$((i-1)), n, b]: " choice

    if [[ "$choice" == "n" ]]; then
        create_alias
    elif [[ "$choice" == "b" ]]; then
        return
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#aliases[@]} ]; then
        CURRENT_ALIAS="${aliases[$((choice-1))]}"

        # Test connection
        print_info "Testing connection to $CURRENT_ALIAS..."
        if mc admin info "$CURRENT_ALIAS" &> /dev/null; then
            print_success "Connected successfully!"
            sleep 1
        else
            print_error "Failed to connect. Please check your credentials."
            print_warning "Note: You need admin access for user management."
            CURRENT_ALIAS=""
            press_enter
        fi
    else
        print_error "Invalid selection"
        sleep 1
        select_alias
    fi
}

create_alias() {
    print_header
    echo -e "${BLUE}=== Create New MinIO Alias ===${NC}"
    echo ""

    read -p "Enter alias name (e.g., local, myminio): " alias_name

    if [ -z "$alias_name" ]; then
        print_error "Alias name cannot be empty"
        press_enter
        return 1
    fi

    echo ""
    echo "Connection type:"
    echo "  1) Remote URL (e.g., https://minio.example.com)"
    echo "  2) Local URL (e.g., http://localhost:9000)"
    echo "  3) Docker container (auto-detect IP)"
    echo ""
    read -p "Select type [1-3]: " conn_type

    case $conn_type in
        1)
            read -p "Enter MinIO URL (e.g., https://minio.example.com): " minio_url
            ;;
        2)
            read -p "Enter port (default: 9000): " port
            port=${port:-9000}
            minio_url="http://localhost:$port"
            ;;
        3)
            print_info "Finding MinIO Docker container..."
            local container=$(docker ps --filter name=minio --format "{{.Names}}" 2>/dev/null | head -1)
            if [ -n "$container" ]; then
                local docker_ip=$(docker inspect "$container" 2>/dev/null | grep -m 1 '"IPAddress"' | awk -F'"' '{print $4}')
                if [ -n "$docker_ip" ]; then
                    print_success "Found container: $container"
                    print_success "Docker IP: $docker_ip"
                    minio_url="http://$docker_ip:9000"
                else
                    print_error "Could not get container IP"
                    read -p "Enter MinIO URL manually: " minio_url
                fi
            else
                print_warning "No MinIO container found"
                read -p "Enter MinIO URL manually: " minio_url
            fi
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac

    echo ""
    read -p "Enter access key: " access_key
    read -sp "Enter secret key: " secret_key
    echo ""
    echo ""

    print_info "Setting up alias '$alias_name'..."

    if mc alias set "$alias_name" "$minio_url" "$access_key" "$secret_key" &> /dev/null; then
        # Test connection
        if mc admin info "$alias_name" &> /dev/null; then
            print_success "Alias '$alias_name' created and connected successfully!"
            CURRENT_ALIAS="$alias_name"
        else
            print_warning "Alias created but admin access test failed."
            print_warning "You may not have admin privileges for user management."
        fi
    else
        print_error "Failed to create alias"
    fi

    press_enter
}

remove_alias() {
    print_header
    echo -e "${BLUE}=== Remove MinIO Alias ===${NC}"
    echo ""

    local aliases=($(list_aliases))

    if [ ${#aliases[@]} -eq 0 ]; then
        print_warning "No aliases to remove."
        press_enter
        return
    fi

    echo "Select alias to remove:"
    echo ""
    local i=1
    for alias in "${aliases[@]}"; do
        echo "  $i) $alias"
        ((i++))
    done
    echo ""

    read -p "Select alias [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#aliases[@]} ]; then
        local selected_alias="${aliases[$((choice-1))]}"

        read -p "Are you sure you want to remove '$selected_alias'? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            if mc alias remove "$selected_alias" &> /dev/null; then
                print_success "Alias '$selected_alias' removed"
                if [ "$CURRENT_ALIAS" == "$selected_alias" ]; then
                    CURRENT_ALIAS=""
                fi
            else
                print_error "Failed to remove alias"
            fi
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

#===============================================================================
# Bucket Management Functions
#===============================================================================

list_buckets() {
    local alias=$1
    mc ls "$alias" 2>/dev/null | awk '{print $NF}' | sed 's/\///g'
}

select_buckets_interactive() {
    local alias=$1
    local prompt_msg=${2:-"Select buckets"}

    local buckets=($(list_buckets "$alias"))

    if [ ${#buckets[@]} -eq 0 ]; then
        print_error "No buckets found"
        return 1
    fi

    echo "$prompt_msg (space-separated numbers, or 'all'):"
    echo ""
    local i=1
    for bucket in "${buckets[@]}"; do
        echo "  $i) $bucket"
        ((i++))
    done
    echo ""

    read -p "Selection: " selection

    SELECTED_BUCKETS=()

    if [ "$selection" == "all" ]; then
        SELECTED_BUCKETS=("${buckets[@]}")
    else
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#buckets[@]} ]; then
                SELECTED_BUCKETS+=("${buckets[$((num-1))]}")
            fi
        done
    fi

    if [ ${#SELECTED_BUCKETS[@]} -eq 0 ]; then
        print_error "No valid buckets selected"
        return 1
    fi

    return 0
}

create_bucket() {
    print_header
    echo -e "${BLUE}=== Create New Bucket ===${NC}"
    echo ""

    read -p "Enter bucket name: " bucket_name

    if [ -z "$bucket_name" ]; then
        print_error "Bucket name cannot be empty"
        press_enter
        return
    fi

    # Validate bucket name (lowercase, no special chars except hyphen)
    if ! [[ "$bucket_name" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]]; then
        print_warning "Bucket names should be lowercase and can contain hyphens/periods"
    fi

    print_info "Creating bucket '$bucket_name'..."

    if mc mb "$CURRENT_ALIAS/$bucket_name" 2>/dev/null; then
        print_success "Bucket '$bucket_name' created successfully!"
    else
        print_error "Failed to create bucket (may already exist)"
    fi

    press_enter
}

view_buckets() {
    print_header
    echo -e "${BLUE}=== Buckets on $CURRENT_ALIAS ===${NC}"
    echo ""

    local buckets=$(list_buckets "$CURRENT_ALIAS")

    if [ -z "$buckets" ]; then
        print_warning "No buckets found"
    else
        echo "Buckets:"
        echo ""
        for bucket in $buckets; do
            local size=$(mc du "$CURRENT_ALIAS/$bucket" --json 2>/dev/null | grep -o '"size":[0-9]*' | cut -d: -f2)
            local size_human=$(numfmt --to=iec-i --suffix=B ${size:-0} 2>/dev/null || echo "${size:-0} bytes")
            echo -e "  ${GREEN}•${NC} $bucket ${YELLOW}($size_human)${NC}"
        done
    fi

    press_enter
}

view_bucket_contents() {
    print_header
    echo -e "${BLUE}=== View Bucket Contents ===${NC}"
    echo ""

    local buckets=($(list_buckets "$CURRENT_ALIAS"))

    if [ ${#buckets[@]} -eq 0 ]; then
        print_warning "No buckets found"
        press_enter
        return
    fi

    echo "Select bucket to view:"
    echo ""
    local i=1
    for bucket in "${buckets[@]}"; do
        echo "  $i) $bucket"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#buckets[@]} ]; then
        local selected_bucket="${buckets[$((choice-1))]}"

        print_header
        echo -e "${BLUE}=== Contents of: $selected_bucket ===${NC}"
        echo ""

        # Show bucket info
        local size=$(mc du "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null)
        local file_count=$(mc ls "$CURRENT_ALIAS/$selected_bucket" --recursive 2>/dev/null | wc -l)

        echo -e "${CYAN}Bucket Info:${NC}"
        echo "  Total size: $size"
        echo "  File count: $file_count"
        echo ""

        echo -e "${CYAN}Contents (first 20 items):${NC}"
        echo "----------------------------------------"
        mc ls "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null | head -20

        local total_items=$(mc ls "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null | wc -l)
        if [ "$total_items" -gt 20 ]; then
            echo ""
            print_info "... and $((total_items - 20)) more items"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

delete_bucket() {
    print_header
    echo -e "${BLUE}=== Delete Bucket ===${NC}"
    echo ""

    local buckets=($(list_buckets "$CURRENT_ALIAS"))

    if [ ${#buckets[@]} -eq 0 ]; then
        print_warning "No buckets found"
        press_enter
        return
    fi

    echo "Select bucket to delete:"
    echo ""
    local i=1
    for bucket in "${buckets[@]}"; do
        local size=$(mc du "$CURRENT_ALIAS/$bucket" --json 2>/dev/null | grep -o '"size":[0-9]*' | cut -d: -f2)
        local size_human=$(numfmt --to=iec-i --suffix=B ${size:-0} 2>/dev/null || echo "${size:-0} bytes")
        echo "  $i) $bucket ($size_human)"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#buckets[@]} ]; then
        local selected_bucket="${buckets[$((choice-1))]}"

        # Check if bucket is empty
        local file_count=$(mc ls "$CURRENT_ALIAS/$selected_bucket" --recursive 2>/dev/null | wc -l)

        echo ""
        if [ "$file_count" -gt 0 ]; then
            print_warning "Bucket '$selected_bucket' contains $file_count file(s)!"
            echo ""
            echo "Options:"
            echo "  1) Delete bucket and all contents (DANGEROUS)"
            echo "  2) Cancel"
            echo ""
            read -p "Selection [1-2]: " delete_choice

            case $delete_choice in
                1)
                    print_warning "This will permanently delete ALL data in '$selected_bucket'!"
                    read -p "Type the bucket name to confirm: " confirm

                    if [ "$confirm" == "$selected_bucket" ]; then
                        print_info "Removing all objects..."
                        mc rm "$CURRENT_ALIAS/$selected_bucket" --recursive --force 2>/dev/null

                        print_info "Removing bucket..."
                        if mc rb "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null; then
                            print_success "Bucket '$selected_bucket' deleted successfully!"
                        else
                            print_error "Failed to delete bucket"
                        fi
                    else
                        print_warning "Deletion cancelled - name did not match"
                    fi
                    ;;
                *)
                    print_info "Deletion cancelled"
                    ;;
            esac
        else
            print_warning "Are you sure you want to delete empty bucket '$selected_bucket'?"
            read -p "Type 'yes' to confirm: " confirm

            if [ "$confirm" == "yes" ]; then
                if mc rb "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null; then
                    print_success "Bucket '$selected_bucket' deleted successfully!"
                else
                    print_error "Failed to delete bucket"
                fi
            else
                print_info "Deletion cancelled"
            fi
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

empty_bucket() {
    print_header
    echo -e "${BLUE}=== Empty Bucket (Delete All Objects) ===${NC}"
    echo ""

    local buckets=($(list_buckets "$CURRENT_ALIAS"))

    if [ ${#buckets[@]} -eq 0 ]; then
        print_warning "No buckets found"
        press_enter
        return
    fi

    echo "Select bucket to empty:"
    echo ""
    local i=1
    for bucket in "${buckets[@]}"; do
        local file_count=$(mc ls "$CURRENT_ALIAS/$bucket" --recursive 2>/dev/null | wc -l)
        echo "  $i) $bucket ($file_count files)"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#buckets[@]} ]; then
        local selected_bucket="${buckets[$((choice-1))]}"
        local file_count=$(mc ls "$CURRENT_ALIAS/$selected_bucket" --recursive 2>/dev/null | wc -l)

        if [ "$file_count" -eq 0 ]; then
            print_info "Bucket '$selected_bucket' is already empty"
            press_enter
            return
        fi

        echo ""
        print_warning "This will delete ALL $file_count file(s) in '$selected_bucket'!"
        print_warning "The bucket itself will remain."
        echo ""
        read -p "Type the bucket name to confirm: " confirm

        if [ "$confirm" == "$selected_bucket" ]; then
            print_info "Removing all objects from '$selected_bucket'..."
            if mc rm "$CURRENT_ALIAS/$selected_bucket" --recursive --force 2>/dev/null; then
                print_success "All objects deleted from '$selected_bucket'!"
            else
                print_error "Failed to empty bucket"
            fi
        else
            print_warning "Operation cancelled - name did not match"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

set_bucket_policy() {
    print_header
    echo -e "${BLUE}=== Set Bucket Access Policy ===${NC}"
    echo ""

    local buckets=($(list_buckets "$CURRENT_ALIAS"))

    if [ ${#buckets[@]} -eq 0 ]; then
        print_warning "No buckets found"
        press_enter
        return
    fi

    echo "Select bucket:"
    echo ""
    local i=1
    for bucket in "${buckets[@]}"; do
        # Get current policy
        local current_policy=$(mc anonymous get "$CURRENT_ALIAS/$bucket" 2>/dev/null | grep -oE "(none|download|upload|public)" || echo "none")
        echo "  $i) $bucket [current: $current_policy]"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#buckets[@]} ]; then
        local selected_bucket="${buckets[$((choice-1))]}"

        echo ""
        echo -e "${CYAN}Select access policy for '$selected_bucket':${NC}"
        echo ""
        echo "  1) none     - No anonymous access (private, default)"
        echo "  2) download - Anonymous download allowed (public read)"
        echo "  3) upload   - Anonymous upload allowed"
        echo "  4) public   - Anonymous read/write allowed (DANGEROUS)"
        echo ""
        read -p "Selection [1-4]: " policy_choice

        local policy=""
        case $policy_choice in
            1) policy="none" ;;
            2) policy="download" ;;
            3) policy="upload" ;;
            4) policy="public" ;;
            *)
                print_error "Invalid selection"
                press_enter
                return
                ;;
        esac

        if [ "$policy" == "public" ]; then
            print_warning "Setting public access allows ANYONE to read AND write to this bucket!"
            read -p "Are you sure? (type 'yes' to confirm): " confirm
            if [ "$confirm" != "yes" ]; then
                print_info "Operation cancelled"
                press_enter
                return
            fi
        fi

        print_info "Setting policy '$policy' on '$selected_bucket'..."

        if mc anonymous set "$policy" "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null; then
            print_success "Policy set successfully!"
            echo ""
            echo "Current policy:"
            mc anonymous get "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null
        else
            print_error "Failed to set policy"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

get_bucket_info() {
    print_header
    echo -e "${BLUE}=== Bucket Information ===${NC}"
    echo ""

    local buckets=($(list_buckets "$CURRENT_ALIAS"))

    if [ ${#buckets[@]} -eq 0 ]; then
        print_warning "No buckets found"
        press_enter
        return
    fi

    echo "Select bucket:"
    echo ""
    local i=1
    for bucket in "${buckets[@]}"; do
        echo "  $i) $bucket"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#buckets[@]} ]; then
        local selected_bucket="${buckets[$((choice-1))]}"

        print_header
        echo -e "${CYAN}=== Bucket: $selected_bucket ===${NC}"
        echo ""

        echo -e "${BLUE}Size & Files:${NC}"
        echo "----------------------------------------"
        mc du "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null
        local file_count=$(mc ls "$CURRENT_ALIAS/$selected_bucket" --recursive 2>/dev/null | wc -l)
        echo "Total files: $file_count"
        echo ""

        echo -e "${BLUE}Anonymous Access Policy:${NC}"
        echo "----------------------------------------"
        mc anonymous get "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null || echo "Unable to get policy"
        echo ""

        echo -e "${BLUE}Bucket Versioning:${NC}"
        echo "----------------------------------------"
        mc version info "$CURRENT_ALIAS/$selected_bucket" 2>/dev/null || echo "Versioning not available"
        echo ""

    else
        print_error "Invalid selection"
    fi

    press_enter
}

#===============================================================================
# User Management Functions
#===============================================================================

list_users() {
    mc admin user list "$CURRENT_ALIAS" 2>/dev/null | grep -E "^enabled|^disabled" | awk '{print $2}'
}

get_user_info() {
    local username=$1
    mc admin user info "$CURRENT_ALIAS" "$username" 2>/dev/null
}

view_users() {
    print_header
    echo -e "${BLUE}=== Users on $CURRENT_ALIAS ===${NC}"
    echo ""

    local users_output=$(mc admin user list "$CURRENT_ALIAS" 2>/dev/null)

    if [ -z "$users_output" ]; then
        print_warning "No users found or unable to list users"
    else
        echo "$users_output"
    fi

    press_enter
}

view_user_details() {
    print_header
    echo -e "${BLUE}=== User Details ===${NC}"
    echo ""

    local users=($(list_users))

    if [ ${#users[@]} -eq 0 ]; then
        print_warning "No users found"
        press_enter
        return
    fi

    echo "Select user to view:"
    echo ""
    local i=1
    for user in "${users[@]}"; do
        echo "  $i) $user"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#users[@]} ]; then
        local selected_user="${users[$((choice-1))]}"
        echo ""
        echo -e "${CYAN}User: $selected_user${NC}"
        echo "----------------------------------------"
        mc admin user info "$CURRENT_ALIAS" "$selected_user" 2>/dev/null
        echo ""
        echo -e "${CYAN}Attached Policies:${NC}"
        echo "----------------------------------------"
        mc admin policy entities "$CURRENT_ALIAS" --user "$selected_user" 2>/dev/null || echo "No policies attached"
    else
        print_error "Invalid selection"
    fi

    press_enter
}

create_user() {
    print_header
    echo -e "${BLUE}=== Create New User ===${NC}"
    echo ""

    read -p "Enter username: " username

    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        press_enter
        return
    fi

    # Check if user already exists
    if mc admin user info "$CURRENT_ALIAS" "$username" &> /dev/null; then
        print_error "User '$username' already exists"
        press_enter
        return
    fi

    while true; do
        read -sp "Enter password (min 8 characters): " password
        echo ""

        if [ ${#password} -lt 8 ]; then
            print_error "Password must be at least 8 characters"
            continue
        fi

        read -sp "Confirm password: " password_confirm
        echo ""

        if [ "$password" != "$password_confirm" ]; then
            print_error "Passwords do not match"
            continue
        fi

        break
    done

    echo ""
    print_info "Creating user '$username'..."

    if mc admin user add "$CURRENT_ALIAS" "$username" "$password" 2>/dev/null; then
        print_success "User '$username' created successfully!"
        echo ""

        read -p "Would you like to assign bucket access now? (y/n): " assign_now
        if [[ $assign_now =~ ^[Yy]$ ]]; then
            assign_bucket_access "$username"
            return
        fi
    else
        print_error "Failed to create user"
    fi

    press_enter
}

assign_bucket_access() {
    local username=${1:-}

    print_header
    echo -e "${BLUE}=== Assign Bucket Access ===${NC}"
    echo ""

    # If username not provided, let user select
    if [ -z "$username" ]; then
        local users=($(list_users))

        if [ ${#users[@]} -eq 0 ]; then
            print_warning "No users found"
            press_enter
            return
        fi

        echo "Select user:"
        echo ""
        local i=1
        for user in "${users[@]}"; do
            echo "  $i) $user"
            ((i++))
        done
        echo ""

        read -p "Selection [1-$((i-1))]: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#users[@]} ]; then
            username="${users[$((choice-1))]}"
        else
            print_error "Invalid selection"
            press_enter
            return
        fi
    fi

    echo ""
    echo -e "${CYAN}Assigning bucket access to user: $username${NC}"
    echo ""

    # Select access type
    echo "Select access type:"
    echo "  1) Read-only access"
    echo "  2) Read-write access"
    echo "  3) Full access (read, write, delete)"
    echo ""
    read -p "Selection [1-3]: " access_type

    echo ""

    # Select buckets
    if ! select_buckets_interactive "$CURRENT_ALIAS" "Select buckets to grant access"; then
        press_enter
        return
    fi

    # Create policy based on access type
    local policy_name="user-${username}-policy"
    local actions=""

    case $access_type in
        1)
            # Read-only: get objects, list bucket, check bucket location
            actions='"s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"'
            ;;
        2)
            # Read-write: full CRUD operations + multipart uploads (for large files)
            actions='"s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads", "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"'
            ;;
        3)
            actions='"s3:*"'
            ;;
        *)
            print_error "Invalid access type"
            press_enter
            return
            ;;
    esac

    # Build resource list for selected buckets
    local resources=""
    for bucket in "${SELECTED_BUCKETS[@]}"; do
        if [ -n "$resources" ]; then
            resources="$resources,"
        fi
        resources="$resources
        \"arn:aws:s3:::${bucket}\",
        \"arn:aws:s3:::${bucket}/*\""
    done

    # Create policy JSON
    local policy_json=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [$actions],
            "Resource": [$resources
            ]
        }
    ]
}
EOF
)

    # Save policy to temp file and apply
    local policy_file="/tmp/minio_policy_${username}_$$.json"
    echo "$policy_json" > "$policy_file"

    echo ""
    print_info "Creating policy '$policy_name'..."

    # Remove existing policy if exists
    mc admin policy remove "$CURRENT_ALIAS" "$policy_name" &> /dev/null

    # Create new policy
    if mc admin policy create "$CURRENT_ALIAS" "$policy_name" "$policy_file" 2>/dev/null; then
        print_success "Policy created"

        # Attach policy to user
        print_info "Attaching policy to user..."
        if mc admin policy attach "$CURRENT_ALIAS" "$policy_name" --user "$username" 2>/dev/null; then
            print_success "Policy attached to user '$username'!"
            echo ""
            echo "User '$username' now has access to:"
            for bucket in "${SELECTED_BUCKETS[@]}"; do
                echo "  • $bucket"
            done
        else
            print_error "Failed to attach policy to user"
        fi
    else
        print_error "Failed to create policy"
    fi

    # Cleanup
    rm -f "$policy_file"

    press_enter
}

delete_user() {
    print_header
    echo -e "${BLUE}=== Delete User ===${NC}"
    echo ""

    local users=($(list_users))

    if [ ${#users[@]} -eq 0 ]; then
        print_warning "No users found"
        press_enter
        return
    fi

    echo "Select user to delete:"
    echo ""
    local i=1
    for user in "${users[@]}"; do
        echo "  $i) $user"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#users[@]} ]; then
        local selected_user="${users[$((choice-1))]}"

        echo ""
        print_warning "This will permanently delete user '$selected_user' and their policies!"
        read -p "Type the username to confirm deletion: " confirm

        if [ "$confirm" == "$selected_user" ]; then
            # Remove user's custom policy first
            local policy_name="user-${selected_user}-policy"
            mc admin policy detach "$CURRENT_ALIAS" "$policy_name" --user "$selected_user" &> /dev/null
            mc admin policy remove "$CURRENT_ALIAS" "$policy_name" &> /dev/null

            # Delete user
            if mc admin user remove "$CURRENT_ALIAS" "$selected_user" 2>/dev/null; then
                print_success "User '$selected_user' deleted successfully!"
            else
                print_error "Failed to delete user"
            fi
        else
            print_warning "Deletion cancelled - username did not match"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

disable_user() {
    print_header
    echo -e "${BLUE}=== Enable/Disable User ===${NC}"
    echo ""

    local users=($(list_users))

    if [ ${#users[@]} -eq 0 ]; then
        print_warning "No users found"
        press_enter
        return
    fi

    echo "Select user:"
    echo ""
    local i=1
    for user in "${users[@]}"; do
        local status=$(mc admin user info "$CURRENT_ALIAS" "$user" 2>/dev/null | grep -i "status" | awk '{print $NF}')
        echo "  $i) $user [$status]"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#users[@]} ]; then
        local selected_user="${users[$((choice-1))]}"

        echo ""
        echo "1) Enable user"
        echo "2) Disable user"
        read -p "Action [1-2]: " action

        case $action in
            1)
                if mc admin user enable "$CURRENT_ALIAS" "$selected_user" 2>/dev/null; then
                    print_success "User '$selected_user' enabled"
                else
                    print_error "Failed to enable user"
                fi
                ;;
            2)
                if mc admin user disable "$CURRENT_ALIAS" "$selected_user" 2>/dev/null; then
                    print_success "User '$selected_user' disabled"
                else
                    print_error "Failed to disable user"
                fi
                ;;
            *)
                print_error "Invalid action"
                ;;
        esac
    else
        print_error "Invalid selection"
    fi

    press_enter
}

#===============================================================================
# Policy Management Functions
#===============================================================================

view_policies() {
    print_header
    echo -e "${BLUE}=== Policies on $CURRENT_ALIAS ===${NC}"
    echo ""

    print_info "Built-in policies:"
    echo "----------------------------------------"
    mc admin policy list "$CURRENT_ALIAS" 2>/dev/null | head -20

    press_enter
}

#===============================================================================
# Test User Access Function
#===============================================================================

test_user_access() {
    print_header
    echo -e "${BLUE}=== Test User Access ===${NC}"
    echo ""

    echo "This will create a temporary alias to test user credentials."
    echo ""

    local users=($(list_users))

    if [ ${#users[@]} -eq 0 ]; then
        print_warning "No users found"
        press_enter
        return
    fi

    echo "Select user to test:"
    echo ""
    local i=1
    for user in "${users[@]}"; do
        echo "  $i) $user"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#users[@]} ]; then
        local selected_user="${users[$((choice-1))]}"

        # Get the URL from current alias
        local minio_url=$(mc alias list "$CURRENT_ALIAS" 2>/dev/null | grep "URL" | awk '{print $3}')

        echo ""
        read -sp "Enter password for '$selected_user': " user_password
        echo ""
        echo ""

        local test_alias="test-${selected_user}-$$"

        print_info "Testing connection as '$selected_user'..."

        if mc alias set "$test_alias" "$minio_url" "$selected_user" "$user_password" &> /dev/null; then
            echo ""
            print_success "Authentication successful!"
            echo ""
            echo "Accessible buckets:"
            echo "----------------------------------------"
            mc ls "$test_alias" 2>/dev/null || print_warning "Cannot list buckets (may not have permission)"

            # Cleanup test alias
            mc alias remove "$test_alias" &> /dev/null
        else
            print_error "Authentication failed"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

#===============================================================================
# Menu Functions
#===============================================================================

alias_menu() {
    while true; do
        print_header
        echo -e "${BLUE}=== Alias Management ===${NC}"
        echo ""
        echo "  1) Select/Switch alias"
        echo "  2) Create new alias"
        echo "  3) Remove alias"
        echo "  4) View all aliases"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) select_alias ;;
            2) create_alias ;;
            3) remove_alias ;;
            4)
                print_header
                echo -e "${BLUE}=== All Configured Aliases ===${NC}"
                echo ""
                mc alias list 2>/dev/null
                press_enter
                ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

user_menu() {
    if [ -z "$CURRENT_ALIAS" ]; then
        print_error "Please select an alias first"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BLUE}=== User Management ===${NC}"
        echo ""
        echo "  1) View all users"
        echo "  2) View user details"
        echo "  3) Create new user"
        echo "  4) Assign bucket access to user"
        echo "  5) Enable/Disable user"
        echo "  6) Delete user"
        echo "  7) Test user access"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) view_users ;;
            2) view_user_details ;;
            3) create_user ;;
            4) assign_bucket_access ;;
            5) disable_user ;;
            6) delete_user ;;
            7) test_user_access ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

bucket_menu() {
    if [ -z "$CURRENT_ALIAS" ]; then
        print_error "Please select an alias first"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BLUE}=== Bucket Management ===${NC}"
        echo ""
        echo "  1) View all buckets"
        echo "  2) View bucket contents"
        echo "  3) Bucket info (size, policy, versioning)"
        echo "  4) Create new bucket"
        echo "  5) Delete bucket"
        echo "  6) Empty bucket (delete all objects)"
        echo "  7) Set bucket access policy"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) view_buckets ;;
            2) view_bucket_contents ;;
            3) get_bucket_info ;;
            4) create_bucket ;;
            5) delete_bucket ;;
            6) empty_bucket ;;
            7) set_bucket_policy ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

quick_setup_menu() {
    print_header
    echo -e "${BLUE}=== Quick Setup: Create User with Bucket Access ===${NC}"
    echo ""

    if [ -z "$CURRENT_ALIAS" ]; then
        print_warning "No alias selected. Let's set one up first."
        echo ""
        read -p "Press Enter to continue..."
        select_alias

        if [ -z "$CURRENT_ALIAS" ]; then
            return
        fi
    fi

    echo "This wizard will:"
    echo "  1. Create a new user"
    echo "  2. Let you select bucket(s)"
    echo "  3. Configure the access permissions"
    echo ""
    read -p "Continue? (y/n): " proceed

    if [[ ! $proceed =~ ^[Yy]$ ]]; then
        return
    fi

    # Create user (the function will offer to assign bucket access)
    create_user
}

main_menu() {
    while true; do
        print_header
        echo -e "${BLUE}Main Menu${NC}"
        echo ""
        echo "  1) Alias Management (select/create MinIO connection)"
        echo "  2) User Management"
        echo "  3) Bucket Management"
        echo "  4) View Policies"
        echo ""
        echo "  5) Quick Setup: Create User with Bucket Access"
        echo ""
        echo "  q) Quit"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) alias_menu ;;
            2) user_menu ;;
            3) bucket_menu ;;
            4)
                if [ -z "$CURRENT_ALIAS" ]; then
                    print_error "Please select an alias first"
                    sleep 2
                else
                    view_policies
                fi
                ;;
            5) quick_setup_menu ;;
            q|Q)
                echo ""
                echo -e "${GREEN}Thank you for using MinIO User & Bucket Manager!${NC}"
                echo ""
                exit 0
                ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Check if mc is installed
    if ! check_mc_installed; then
        if ! install_mc; then
            exit 1
        fi
    fi

    # Check for existing aliases and offer to select one
    local aliases=($(list_aliases))
    if [ ${#aliases[@]} -gt 0 ]; then
        print_header
        echo "Found existing MinIO aliases."
        read -p "Would you like to select one now? (y/n): " select_now
        if [[ $select_now =~ ^[Yy]$ ]]; then
            select_alias
        fi
    fi

    # Start main menu
    main_menu
}

# Run the script
main "$@"
