#!/bin/bash

# PostgreSQL Manager - Interactive Script
# Version: 1.0.0
# Manages PostgreSQL databases, users, and permissions via Docker or remote connections

#===============================================================================
# Configuration
#===============================================================================

VERSION="1.0.0"
CONFIG_FILE="$HOME/.pg_manager_config"
CONNECTIONS_DIR="$HOME/.pg_connections"
BACKUP_DIR="$HOME/pg_backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Current connection
CURRENT_CONNECTION=""
CONNECTION_TYPE=""
CONTAINER_NAME=""
HOST=""
PORT=""
ADMIN_USER=""
ADMIN_PASS=""
SSL_MODE=""

#===============================================================================
# Helper Functions
#===============================================================================

print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              PostgreSQL Manager v${VERSION}                           ║${NC}"
    echo -e "${CYAN}║         Manage databases, users, and permissions                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ -n "$CURRENT_CONNECTION" ]; then
        echo -e "${MAGENTA}Current Connection: ${GREEN}$CURRENT_CONNECTION${NC}"
        if [ "$CONNECTION_TYPE" = "docker" ]; then
            echo -e "${MAGENTA}Type: ${YELLOW}Docker (${CONTAINER_NAME})${NC}"
        else
            echo -e "${MAGENTA}Type: ${YELLOW}Remote (${HOST}:${PORT})${NC}"
        fi
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

# Detect if docker needs sudo
get_docker_cmd() {
    if docker ps &>/dev/null 2>&1; then
        echo "docker"
    elif sudo docker ps &>/dev/null 2>&1; then
        echo "sudo docker"
    else
        echo ""
    fi
}

# Generate SQL-safe password (alphanumeric + _-.)
generate_password() {
    local length=${1:-32}
    local upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local lower='abcdefghijklmnopqrstuvwxyz'
    local digits='0123456789'
    local special='_-.'
    local all="${upper}${lower}${digits}${special}"
    local password=""

    # Ensure at least 2 of each type
    for ((j=0; j<2; j++)); do
        password+="${upper:$((RANDOM % 26)):1}"
        password+="${lower:$((RANDOM % 26)):1}"
        password+="${digits:$((RANDOM % 10)):1}"
        password+="${special:$((RANDOM % 3)):1}"
    done

    # Fill remaining length with random chars
    for ((i=8; i<length; i++)); do
        password+="${all:$((RANDOM % ${#all})):1}"
    done

    # Shuffle the password
    echo "$password" | fold -w1 | shuf | tr -d '\n'
}

#===============================================================================
# Connection Management Functions
#===============================================================================

ensure_connections_dir() {
    mkdir -p "$CONNECTIONS_DIR"
    mkdir -p "$BACKUP_DIR"
}

save_connection() {
    local alias="$1"
    local type="$2"
    local config_file="$CONNECTIONS_DIR/${alias}.conf"

    ensure_connections_dir

    if [ "$type" = "docker" ]; then
        cat > "$config_file" << EOF
TYPE=docker
CONTAINER_NAME=${CONTAINER_NAME}
ADMIN_USER=${ADMIN_USER}
EOF
    else
        cat > "$config_file" << EOF
TYPE=remote
HOST=${HOST}
PORT=${PORT}
ADMIN_USER=${ADMIN_USER}
SSL_MODE=${SSL_MODE}
EOF
    fi

    # Save current alias to config file
    echo "$alias" > "$CONFIG_FILE"
}

load_connection() {
    local alias="$1"
    local config_file="$CONNECTIONS_DIR/${alias}.conf"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # Reset variables
    CONNECTION_TYPE=""
    CONTAINER_NAME=""
    HOST=""
    PORT=""
    ADMIN_USER=""
    ADMIN_PASS=""
    SSL_MODE=""

    # Source the config file
    source "$config_file"
    CONNECTION_TYPE="$TYPE"
    CURRENT_CONNECTION="$alias"

    return 0
}

list_connections() {
    ensure_connections_dir
    local connections=()
    shopt -s nullglob
    for conf in "$CONNECTIONS_DIR"/*.conf; do
        if [ -f "$conf" ]; then
            local name=$(basename "$conf" .conf)
            connections+=("$name")
        fi
    done
    shopt -u nullglob
    echo "${connections[@]}"
}

detect_postgres_container() {
    local docker_cmd=$(get_docker_cmd)
    if [ -z "$docker_cmd" ]; then
        return 1
    fi

    # Find postgres containers
    local containers=$($docker_cmd ps --format "{{.Names}}" 2>/dev/null | while read name; do
        # Check if it's a postgres container by looking at the image or process
        local image=$($docker_cmd inspect "$name" --format '{{.Config.Image}}' 2>/dev/null)
        if echo "$image" | grep -qi "postgres"; then
            echo "$name"
        fi
    done)

    if [ -n "$containers" ]; then
        echo "$containers"
        return 0
    fi
    return 1
}

create_connection_docker() {
    print_header
    echo -e "${BLUE}=== Create Docker Connection ===${NC}"
    echo ""

    local docker_cmd=$(get_docker_cmd)
    if [ -z "$docker_cmd" ]; then
        print_error "Docker is not accessible (tried with and without sudo)"
        print_info "Please ensure Docker is installed and you have permission to use it"
        press_enter
        return 1
    fi

    # Try to detect postgres containers
    print_info "Searching for PostgreSQL containers..."
    local detected=$(detect_postgres_container)

    if [ -n "$detected" ]; then
        echo ""
        echo "Found PostgreSQL containers:"
        echo ""
        local i=1
        local containers=()
        while IFS= read -r container; do
            containers+=("$container")
            echo "  $i) $container"
            ((i++))
        done <<< "$detected"
        echo "  $i) Enter container name manually"
        echo ""
        read -p "Selection [1-$i]: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            CONTAINER_NAME="${containers[$((choice-1))]}"
        else
            read -p "Enter container name: " CONTAINER_NAME
        fi
    else
        print_warning "No PostgreSQL containers detected"
        read -p "Enter container name: " CONTAINER_NAME
    fi

    if [ -z "$CONTAINER_NAME" ]; then
        print_error "Container name cannot be empty"
        press_enter
        return 1
    fi

    # Verify container exists and is running
    if ! $docker_cmd ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_error "Container '$CONTAINER_NAME' is not running"
        press_enter
        return 1
    fi

    # Get admin user (default: postgres)
    echo ""
    read -p "PostgreSQL admin user [postgres]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-postgres}

    # Get alias name
    echo ""
    read -p "Connection alias name: " alias_name
    if [ -z "$alias_name" ]; then
        print_error "Alias name cannot be empty"
        press_enter
        return 1
    fi

    CONNECTION_TYPE="docker"
    save_connection "$alias_name" "docker"
    CURRENT_CONNECTION="$alias_name"

    print_success "Connection '$alias_name' created successfully!"
    press_enter
}

create_connection_remote() {
    print_header
    echo -e "${BLUE}=== Create Remote Connection ===${NC}"
    echo ""

    read -p "PostgreSQL host: " HOST
    if [ -z "$HOST" ]; then
        print_error "Host cannot be empty"
        press_enter
        return 1
    fi

    read -p "Port [5432]: " PORT
    PORT=${PORT:-5432}

    read -p "Admin user [postgres]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-postgres}

    echo ""
    echo "SSL Mode options:"
    echo "  1) disable - No SSL"
    echo "  2) require - SSL required (recommended for remote)"
    echo "  3) verify-ca - Verify server certificate"
    echo "  4) verify-full - Verify server certificate and hostname"
    echo ""
    read -p "Selection [1-4, default=2]: " ssl_choice
    ssl_choice=${ssl_choice:-2}

    case $ssl_choice in
        1) SSL_MODE="disable" ;;
        2) SSL_MODE="require" ;;
        3) SSL_MODE="verify-ca" ;;
        4) SSL_MODE="verify-full" ;;
        *) SSL_MODE="require" ;;
    esac

    # Get alias name
    echo ""
    read -p "Connection alias name: " alias_name
    if [ -z "$alias_name" ]; then
        print_error "Alias name cannot be empty"
        press_enter
        return 1
    fi

    CONNECTION_TYPE="remote"
    save_connection "$alias_name" "remote"
    CURRENT_CONNECTION="$alias_name"

    print_success "Connection '$alias_name' created successfully!"
    press_enter
}

test_connection() {
    if [ -z "$CURRENT_CONNECTION" ]; then
        print_error "No connection selected"
        return 1
    fi

    print_info "Testing connection to '$CURRENT_CONNECTION'..."

    local result
    if [ "$CONNECTION_TYPE" = "docker" ]; then
        local docker_cmd=$(get_docker_cmd)
        result=$($docker_cmd exec -i "$CONTAINER_NAME" psql -U "$ADMIN_USER" -d postgres -t -c "SELECT 'Connection successful'" 2>&1)
    else
        if [ -n "$ADMIN_PASS" ]; then
            result=$(PGPASSWORD="$ADMIN_PASS" psql -h "$HOST" -p "$PORT" -U "$ADMIN_USER" -d postgres -t -c "SELECT 'Connection successful'" 2>&1)
        else
            read -sp "Enter password for $ADMIN_USER: " ADMIN_PASS
            echo ""
            result=$(PGPASSWORD="$ADMIN_PASS" psql -h "$HOST" -p "$PORT" -U "$ADMIN_USER" -d postgres -t -c "SELECT 'Connection successful'" 2>&1)
        fi
    fi

    if echo "$result" | grep -q "Connection successful"; then
        print_success "Connection test passed!"
        # Show PostgreSQL version
        local version
        if [ "$CONNECTION_TYPE" = "docker" ]; then
            local docker_cmd=$(get_docker_cmd)
            version=$($docker_cmd exec -i "$CONTAINER_NAME" psql -U "$ADMIN_USER" -d postgres -t -c "SELECT version()" 2>/dev/null | head -1)
        else
            version=$(PGPASSWORD="$ADMIN_PASS" psql -h "$HOST" -p "$PORT" -U "$ADMIN_USER" -d postgres -t -c "SELECT version()" 2>/dev/null | head -1)
        fi
        if [ -n "$version" ]; then
            echo ""
            print_info "PostgreSQL version:"
            echo "  $version"
        fi
        return 0
    else
        print_error "Connection test failed!"
        echo "$result"
        return 1
    fi
}

select_connection() {
    print_header
    echo -e "${BLUE}=== Select Connection ===${NC}"
    echo ""

    local connections=($(list_connections))

    if [ ${#connections[@]} -eq 0 ]; then
        print_warning "No connections configured."
        echo ""
        read -p "Would you like to create a new connection? (y/n): " create_new
        if [[ $create_new =~ ^[Yy]$ ]]; then
            echo ""
            echo "Connection type:"
            echo "  1) Docker container"
            echo "  2) Remote server"
            echo ""
            read -p "Selection [1-2]: " type_choice
            case $type_choice in
                1) create_connection_docker ;;
                2) create_connection_remote ;;
                *) print_error "Invalid choice" ;;
            esac
        fi
        return
    fi

    echo "Available connections:"
    echo ""
    local i=1
    for conn in "${connections[@]}"; do
        local config_file="$CONNECTIONS_DIR/${conn}.conf"
        source "$config_file"
        if [ "$TYPE" = "docker" ]; then
            echo -e "  ${GREEN}$i)${NC} $conn"
            echo -e "     ${YELLOW}Docker: $CONTAINER_NAME${NC}"
        else
            echo -e "  ${GREEN}$i)${NC} $conn"
            echo -e "     ${YELLOW}Remote: $HOST:$PORT${NC}"
        fi
        echo ""
        ((i++))
    done

    echo -e "  ${GREEN}n)${NC} Create new connection"
    echo -e "  ${GREEN}b)${NC} Back to main menu"
    echo ""

    read -p "Select connection [1-$((i-1)), n, b]: " choice

    if [[ "$choice" == "n" ]]; then
        echo ""
        echo "Connection type:"
        echo "  1) Docker container"
        echo "  2) Remote server"
        echo ""
        read -p "Selection [1-2]: " type_choice
        case $type_choice in
            1) create_connection_docker ;;
            2) create_connection_remote ;;
            *) print_error "Invalid choice" ;;
        esac
    elif [[ "$choice" == "b" ]]; then
        return
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#connections[@]} ]; then
        local selected="${connections[$((choice-1))]}"
        if load_connection "$selected"; then
            print_success "Loaded connection '$selected'"

            # Test connection
            if ! test_connection; then
                CURRENT_CONNECTION=""
            fi
        else
            print_error "Failed to load connection"
        fi
        press_enter
    else
        print_error "Invalid selection"
        sleep 1
        select_connection
    fi
}

update_connection() {
    print_header
    echo -e "${BLUE}=== Update Connection ===${NC}"
    echo ""

    local connections=($(list_connections))

    if [ ${#connections[@]} -eq 0 ]; then
        print_warning "No connections to update."
        press_enter
        return
    fi

    echo "Select connection to update:"
    echo ""
    local i=1
    for conn in "${connections[@]}"; do
        echo "  $i) $conn"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#connections[@]} ]; then
        local selected="${connections[$((choice-1))]}"
        load_connection "$selected"

        echo ""
        if [ "$CONNECTION_TYPE" = "docker" ]; then
            echo "Current settings:"
            echo "  Container: $CONTAINER_NAME"
            echo "  Admin user: $ADMIN_USER"
            echo ""
            read -p "New container name [$CONTAINER_NAME]: " new_container
            CONTAINER_NAME=${new_container:-$CONTAINER_NAME}
            read -p "New admin user [$ADMIN_USER]: " new_admin
            ADMIN_USER=${new_admin:-$ADMIN_USER}
        else
            echo "Current settings:"
            echo "  Host: $HOST"
            echo "  Port: $PORT"
            echo "  Admin user: $ADMIN_USER"
            echo "  SSL mode: $SSL_MODE"
            echo ""
            read -p "New host [$HOST]: " new_host
            HOST=${new_host:-$HOST}
            read -p "New port [$PORT]: " new_port
            PORT=${new_port:-$PORT}
            read -p "New admin user [$ADMIN_USER]: " new_admin
            ADMIN_USER=${new_admin:-$ADMIN_USER}
            read -p "New SSL mode [$SSL_MODE]: " new_ssl
            SSL_MODE=${new_ssl:-$SSL_MODE}
        fi

        save_connection "$selected" "$CONNECTION_TYPE"
        print_success "Connection '$selected' updated!"
    else
        print_error "Invalid selection"
    fi

    press_enter
}

remove_connection() {
    print_header
    echo -e "${BLUE}=== Remove Connection ===${NC}"
    echo ""

    local connections=($(list_connections))

    if [ ${#connections[@]} -eq 0 ]; then
        print_warning "No connections to remove."
        press_enter
        return
    fi

    echo "Select connection to remove:"
    echo ""
    local i=1
    for conn in "${connections[@]}"; do
        echo "  $i) $conn"
        ((i++))
    done
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#connections[@]} ]; then
        local selected="${connections[$((choice-1))]}"

        read -p "Are you sure you want to remove '$selected'? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            rm -f "$CONNECTIONS_DIR/${selected}.conf"
            print_success "Connection '$selected' removed"

            if [ "$CURRENT_CONNECTION" == "$selected" ]; then
                CURRENT_CONNECTION=""
                CONNECTION_TYPE=""
            fi
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

connection_menu() {
    while true; do
        print_header
        echo -e "${BLUE}=== Connection Management ===${NC}"
        echo ""
        echo "  1) Select connection"
        echo "  2) Create Docker connection"
        echo "  3) Create remote connection"
        echo "  4) Update connection"
        echo "  5) Remove connection"
        echo "  6) Test current connection"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) select_connection ;;
            2) create_connection_docker ;;
            3) create_connection_remote ;;
            4) update_connection ;;
            5) remove_connection ;;
            6)
                if [ -z "$CURRENT_CONNECTION" ]; then
                    print_error "No connection selected"
                    sleep 2
                else
                    test_connection
                    press_enter
                fi
                ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# SQL Execution Helper
#===============================================================================

run_psql() {
    local sql="$1"
    local db="${2:-postgres}"

    if [ "$CONNECTION_TYPE" = "docker" ]; then
        local docker_cmd=$(get_docker_cmd)
        $docker_cmd exec -i "$CONTAINER_NAME" psql -U "$ADMIN_USER" -d "$db" -t -c "$sql" 2>&1
    else
        if [ -z "$ADMIN_PASS" ]; then
            read -sp "Enter password for $ADMIN_USER: " ADMIN_PASS
            echo ""
        fi
        PGPASSWORD="$ADMIN_PASS" PGSSLMODE="$SSL_MODE" psql -h "$HOST" -p "$PORT" -U "$ADMIN_USER" -d "$db" -t -c "$sql" 2>&1
    fi
}

run_psql_file() {
    local file="$1"
    local db="${2:-postgres}"

    if [ "$CONNECTION_TYPE" = "docker" ]; then
        local docker_cmd=$(get_docker_cmd)
        cat "$file" | $docker_cmd exec -i "$CONTAINER_NAME" psql -U "$ADMIN_USER" -d "$db" 2>&1
    else
        if [ -z "$ADMIN_PASS" ]; then
            read -sp "Enter password for $ADMIN_USER: " ADMIN_PASS
            echo ""
        fi
        PGPASSWORD="$ADMIN_PASS" PGSSLMODE="$SSL_MODE" psql -h "$HOST" -p "$PORT" -U "$ADMIN_USER" -d "$db" -f "$file" 2>&1
    fi
}

#===============================================================================
# Database Management Functions
#===============================================================================

list_databases() {
    print_header
    echo -e "${BLUE}=== Databases ===${NC}"
    echo ""

    local result=$(run_psql "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false ORDER BY datname")

    if [ -n "$result" ]; then
        echo -e "${CYAN}Database                          Size${NC}"
        echo "----------------------------------------"
        echo "$result" | while read -r line; do
            if [ -n "$line" ]; then
                echo "  $line"
            fi
        done
    else
        print_warning "No databases found or connection error"
    fi

    press_enter
}

create_database() {
    print_header
    echo -e "${BLUE}=== Create Database ===${NC}"
    echo ""

    read -p "Enter database name: " db_name

    if [ -z "$db_name" ]; then
        print_error "Database name cannot be empty"
        press_enter
        return
    fi

    # Validate database name (alphanumeric + underscore, starts with letter)
    if ! [[ "$db_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        print_error "Invalid database name. Must start with a letter and contain only letters, numbers, and underscores."
        press_enter
        return
    fi

    # Check if database exists
    local exists=$(run_psql "SELECT 1 FROM pg_database WHERE datname = '$db_name'" | tr -d ' ')
    if [ "$exists" = "1" ]; then
        print_error "Database '$db_name' already exists"
        press_enter
        return
    fi

    # Optional: set owner
    echo ""
    read -p "Owner (leave empty for default): " owner

    print_info "Creating database '$db_name'..."

    local sql="CREATE DATABASE \"$db_name\""
    if [ -n "$owner" ]; then
        sql="$sql OWNER \"$owner\""
    fi

    local result=$(run_psql "$sql")

    if echo "$result" | grep -qi "error"; then
        print_error "Failed to create database"
        echo "$result"
    else
        print_success "Database '$db_name' created successfully!"
    fi

    press_enter
}

delete_database() {
    print_header
    echo -e "${BLUE}=== Delete Database ===${NC}"
    echo ""

    # List databases
    local databases=$(run_psql "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres') ORDER BY datname" | tr -d ' ')

    if [ -z "$databases" ]; then
        print_warning "No user databases found"
        press_enter
        return
    fi

    echo "Select database to delete:"
    echo ""
    local i=1
    local db_array=()
    while IFS= read -r db; do
        if [ -n "$db" ]; then
            db_array+=("$db")
            local size=$(run_psql "SELECT pg_size_pretty(pg_database_size('$db'))" | tr -d ' ')
            echo "  $i) $db ($size)"
            ((i++))
        fi
    done <<< "$databases"
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#db_array[@]} ]; then
        local selected_db="${db_array[$((choice-1))]}"

        # Check for active connections
        local active=$(run_psql "SELECT count(*) FROM pg_stat_activity WHERE datname = '$selected_db'" | tr -d ' ')
        if [ "$active" -gt 0 ]; then
            print_warning "Database '$selected_db' has $active active connection(s)!"
            echo ""
            echo "Options:"
            echo "  1) Terminate connections and delete"
            echo "  2) Cancel"
            echo ""
            read -p "Selection [1-2]: " action_choice

            if [ "$action_choice" != "1" ]; then
                print_info "Deletion cancelled"
                press_enter
                return
            fi

            print_info "Terminating connections..."
            run_psql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$selected_db' AND pid <> pg_backend_pid()" > /dev/null
        fi

        echo ""
        print_warning "This will permanently delete database '$selected_db' and ALL its data!"
        read -p "Type the database name to confirm: " confirm

        if [ "$confirm" == "$selected_db" ]; then
            print_info "Dropping database '$selected_db'..."
            local result=$(run_psql "DROP DATABASE \"$selected_db\"")

            if echo "$result" | grep -qi "error"; then
                print_error "Failed to delete database"
                echo "$result"
            else
                print_success "Database '$selected_db' deleted successfully!"
            fi
        else
            print_warning "Deletion cancelled - name did not match"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

database_menu() {
    if [ -z "$CURRENT_CONNECTION" ]; then
        print_error "Please select a connection first"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BLUE}=== Database Management ===${NC}"
        echo ""
        echo "  1) List databases"
        echo "  2) Create database"
        echo "  3) Delete database"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) list_databases ;;
            2) create_database ;;
            3) delete_database ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# User Management Functions
#===============================================================================

list_users() {
    print_header
    echo -e "${BLUE}=== Users (Roles) ===${NC}"
    echo ""

    local result=$(run_psql "SELECT rolname, CASE WHEN rolsuper THEN 'superuser' WHEN rolcreatedb THEN 'createdb' WHEN rolcreaterole THEN 'createrole' ELSE 'user' END as type, CASE WHEN rolcanlogin THEN 'yes' ELSE 'no' END as login FROM pg_roles WHERE rolname NOT LIKE 'pg_%' ORDER BY rolname")

    if [ -n "$result" ]; then
        echo -e "${CYAN}Username                Type          Can Login${NC}"
        echo "------------------------------------------------"
        echo "$result" | while read -r line; do
            if [ -n "$line" ]; then
                echo "  $line"
            fi
        done
    else
        print_warning "No users found or connection error"
    fi

    press_enter
}

create_user() {
    print_header
    echo -e "${BLUE}=== Create User ===${NC}"
    echo ""

    read -p "Enter username: " username

    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        press_enter
        return
    fi

    # Validate username
    if ! [[ "$username" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        print_error "Invalid username. Must start with a letter and contain only letters, numbers, and underscores."
        press_enter
        return
    fi

    # Check if user exists
    local exists=$(run_psql "SELECT 1 FROM pg_roles WHERE rolname = '$username'" | tr -d ' ')
    if [ "$exists" = "1" ]; then
        print_error "User '$username' already exists"
        press_enter
        return
    fi

    # Password option
    echo ""
    echo "Password options:"
    echo "  1) Generate random password (recommended)"
    echo "  2) Enter password manually"
    echo ""
    read -p "Selection [1-2]: " pass_choice

    local password=""
    if [ "$pass_choice" = "2" ]; then
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
    else
        password=$(generate_password 32)
    fi

    print_info "Creating user '$username'..."

    # Escape single quotes in password for SQL
    local escaped_password="${password//\'/\'\'}"
    local result=$(run_psql "CREATE USER \"$username\" WITH PASSWORD '$escaped_password'")

    if echo "$result" | grep -qi "error"; then
        print_error "Failed to create user"
        echo "$result"
    else
        print_success "User '$username' created successfully!"
        echo ""
        echo -e "${YELLOW}Password: $password${NC}"
        echo ""
        print_warning "Save this password - it cannot be retrieved later!"
    fi

    press_enter
}

delete_user() {
    print_header
    echo -e "${BLUE}=== Delete User ===${NC}"
    echo ""

    # List users
    local users=$(run_psql "SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' AND rolname NOT IN ('postgres') AND rolcanlogin = true ORDER BY rolname" | tr -d ' ')

    if [ -z "$users" ]; then
        print_warning "No user accounts found"
        press_enter
        return
    fi

    echo "Select user to delete:"
    echo ""
    local i=1
    local user_array=()
    while IFS= read -r user; do
        if [ -n "$user" ]; then
            user_array+=("$user")
            echo "  $i) $user"
            ((i++))
        fi
    done <<< "$users"
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#user_array[@]} ]; then
        local selected_user="${user_array[$((choice-1))]}"

        echo ""
        print_warning "This will permanently delete user '$selected_user'!"
        read -p "Type the username to confirm: " confirm

        if [ "$confirm" == "$selected_user" ]; then
            # Revoke all privileges first
            print_info "Revoking privileges..."
            run_psql "REASSIGN OWNED BY \"$selected_user\" TO postgres" > /dev/null 2>&1
            run_psql "DROP OWNED BY \"$selected_user\"" > /dev/null 2>&1

            print_info "Dropping user '$selected_user'..."
            local result=$(run_psql "DROP USER \"$selected_user\"")

            if echo "$result" | grep -qi "error"; then
                print_error "Failed to delete user"
                echo "$result"
            else
                print_success "User '$selected_user' deleted successfully!"
            fi
        else
            print_warning "Deletion cancelled - name did not match"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

test_user_credentials() {
    print_header
    echo -e "${BLUE}=== Test User Credentials ===${NC}"
    echo ""

    # List users
    local users=$(run_psql "SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' AND rolcanlogin = true ORDER BY rolname" | tr -d ' ')

    if [ -z "$users" ]; then
        print_warning "No user accounts found"
        press_enter
        return
    fi

    echo "Select user to test:"
    echo ""
    local i=1
    local user_array=()
    while IFS= read -r user; do
        if [ -n "$user" ]; then
            user_array+=("$user")
            echo "  $i) $user"
            ((i++))
        fi
    done <<< "$users"
    echo ""

    read -p "Selection [1-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#user_array[@]} ]; then
        local selected_user="${user_array[$((choice-1))]}"

        echo ""
        read -sp "Enter password for '$selected_user': " test_password
        echo ""
        echo ""

        print_info "Testing credentials..."

        local result
        if [ "$CONNECTION_TYPE" = "docker" ]; then
            local docker_cmd=$(get_docker_cmd)
            result=$($docker_cmd exec -i "$CONTAINER_NAME" bash -c "PGPASSWORD='$test_password' psql -U '$selected_user' -d postgres -t -c \"SELECT 'Login successful'\"" 2>&1)
        else
            result=$(PGPASSWORD="$test_password" PGSSLMODE="$SSL_MODE" psql -h "$HOST" -p "$PORT" -U "$selected_user" -d postgres -t -c "SELECT 'Login successful'" 2>&1)
        fi

        if echo "$result" | grep -q "Login successful"; then
            print_success "Credentials are valid!"
        else
            print_error "Authentication failed!"
            echo "$result"
        fi
    else
        print_error "Invalid selection"
    fi

    press_enter
}

user_menu() {
    if [ -z "$CURRENT_CONNECTION" ]; then
        print_error "Please select a connection first"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BLUE}=== User Management ===${NC}"
        echo ""
        echo "  1) List users"
        echo "  2) Create user"
        echo "  3) Delete user"
        echo "  4) Test user credentials"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) list_users ;;
            2) create_user ;;
            3) delete_user ;;
            4) test_user_credentials ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# Permissions Management Functions
#===============================================================================

grant_permissions() {
    print_header
    echo -e "${BLUE}=== Grant Permissions ===${NC}"
    echo ""

    # Select user
    local users=$(run_psql "SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' AND rolcanlogin = true ORDER BY rolname" | tr -d ' ')

    if [ -z "$users" ]; then
        print_warning "No user accounts found"
        press_enter
        return
    fi

    echo "Select user:"
    echo ""
    local i=1
    local user_array=()
    while IFS= read -r user; do
        if [ -n "$user" ]; then
            user_array+=("$user")
            echo "  $i) $user"
            ((i++))
        fi
    done <<< "$users"
    echo ""

    read -p "Selection [1-$((i-1))]: " user_choice

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || [ "$user_choice" -lt 1 ] || [ "$user_choice" -gt ${#user_array[@]} ]; then
        print_error "Invalid selection"
        press_enter
        return
    fi

    local selected_user="${user_array[$((user_choice-1))]}"

    # Select database
    echo ""
    local databases=$(run_psql "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname" | tr -d ' ')

    echo "Select database:"
    echo ""
    i=1
    local db_array=()
    while IFS= read -r db; do
        if [ -n "$db" ]; then
            db_array+=("$db")
            echo "  $i) $db"
            ((i++))
        fi
    done <<< "$databases"
    echo ""

    read -p "Selection [1-$((i-1))]: " db_choice

    if ! [[ "$db_choice" =~ ^[0-9]+$ ]] || [ "$db_choice" -lt 1 ] || [ "$db_choice" -gt ${#db_array[@]} ]; then
        print_error "Invalid selection"
        press_enter
        return
    fi

    local selected_db="${db_array[$((db_choice-1))]}"

    # Select permission level
    echo ""
    echo "Permission level:"
    echo "  1) Read-only (SELECT)"
    echo "  2) Read-write (SELECT, INSERT, UPDATE, DELETE)"
    echo "  3) Full access (ALL PRIVILEGES)"
    echo ""
    read -p "Selection [1-3]: " perm_choice

    print_info "Granting permissions to '$selected_user' on '$selected_db'..."

    # Grant CONNECT on database
    run_psql "GRANT CONNECT ON DATABASE \"$selected_db\" TO \"$selected_user\"" > /dev/null

    # Grant USAGE on public schema
    run_psql "GRANT USAGE ON SCHEMA public TO \"$selected_user\"" "$selected_db" > /dev/null

    case $perm_choice in
        1)
            # Read-only
            run_psql "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"$selected_user\"" "$selected_db"
            run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \"$selected_user\"" "$selected_db"
            print_success "Read-only permissions granted!"
            ;;
        2)
            # Read-write
            run_psql "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"$selected_user\"" "$selected_db"
            run_psql "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"$selected_user\"" "$selected_db"
            run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"$selected_user\"" "$selected_db"
            run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"$selected_user\"" "$selected_db"
            print_success "Read-write permissions granted!"
            ;;
        3)
            # Full access
            run_psql "GRANT ALL PRIVILEGES ON DATABASE \"$selected_db\" TO \"$selected_user\"" > /dev/null
            run_psql "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"$selected_user\"" "$selected_db"
            run_psql "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"$selected_user\"" "$selected_db"
            run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO \"$selected_user\"" "$selected_db"
            run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO \"$selected_user\"" "$selected_db"
            print_success "Full permissions granted!"
            ;;
        *)
            print_error "Invalid permission level"
            ;;
    esac

    press_enter
}

revoke_permissions() {
    print_header
    echo -e "${BLUE}=== Revoke Permissions ===${NC}"
    echo ""

    # Select user
    local users=$(run_psql "SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' AND rolcanlogin = true AND rolname NOT IN ('postgres') ORDER BY rolname" | tr -d ' ')

    if [ -z "$users" ]; then
        print_warning "No user accounts found"
        press_enter
        return
    fi

    echo "Select user:"
    echo ""
    local i=1
    local user_array=()
    while IFS= read -r user; do
        if [ -n "$user" ]; then
            user_array+=("$user")
            echo "  $i) $user"
            ((i++))
        fi
    done <<< "$users"
    echo ""

    read -p "Selection [1-$((i-1))]: " user_choice

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || [ "$user_choice" -lt 1 ] || [ "$user_choice" -gt ${#user_array[@]} ]; then
        print_error "Invalid selection"
        press_enter
        return
    fi

    local selected_user="${user_array[$((user_choice-1))]}"

    # Select database
    echo ""
    local databases=$(run_psql "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname" | tr -d ' ')

    echo "Select database:"
    echo ""
    i=1
    local db_array=()
    while IFS= read -r db; do
        if [ -n "$db" ]; then
            db_array+=("$db")
            echo "  $i) $db"
            ((i++))
        fi
    done <<< "$databases"
    echo ""

    read -p "Selection [1-$((i-1))]: " db_choice

    if ! [[ "$db_choice" =~ ^[0-9]+$ ]] || [ "$db_choice" -lt 1 ] || [ "$db_choice" -gt ${#db_array[@]} ]; then
        print_error "Invalid selection"
        press_enter
        return
    fi

    local selected_db="${db_array[$((db_choice-1))]}"

    echo ""
    print_warning "This will revoke all permissions for '$selected_user' on '$selected_db'"
    read -p "Continue? (y/n): " confirm

    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        press_enter
        return
    fi

    print_info "Revoking permissions..."

    # Revoke all privileges
    run_psql "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"$selected_user\"" "$selected_db"
    run_psql "REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM \"$selected_user\"" "$selected_db"
    run_psql "REVOKE USAGE ON SCHEMA public FROM \"$selected_user\"" "$selected_db"
    run_psql "REVOKE CONNECT ON DATABASE \"$selected_db\" FROM \"$selected_user\""

    # Remove default privileges
    run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM \"$selected_user\"" "$selected_db"
    run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM \"$selected_user\"" "$selected_db"

    print_success "Permissions revoked!"

    press_enter
}

list_user_permissions() {
    print_header
    echo -e "${BLUE}=== User Permissions ===${NC}"
    echo ""

    # Select user
    local users=$(run_psql "SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' AND rolcanlogin = true ORDER BY rolname" | tr -d ' ')

    if [ -z "$users" ]; then
        print_warning "No user accounts found"
        press_enter
        return
    fi

    echo "Select user:"
    echo ""
    local i=1
    local user_array=()
    while IFS= read -r user; do
        if [ -n "$user" ]; then
            user_array+=("$user")
            echo "  $i) $user"
            ((i++))
        fi
    done <<< "$users"
    echo ""

    read -p "Selection [1-$((i-1))]: " user_choice

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || [ "$user_choice" -lt 1 ] || [ "$user_choice" -gt ${#user_array[@]} ]; then
        print_error "Invalid selection"
        press_enter
        return
    fi

    local selected_user="${user_array[$((user_choice-1))]}"

    print_header
    echo -e "${CYAN}Permissions for user: $selected_user${NC}"
    echo ""

    # Database connect privileges
    echo -e "${BLUE}Database Access:${NC}"
    echo "----------------------------------------"
    local db_access=$(run_psql "SELECT datname FROM pg_database d WHERE datistemplate = false AND has_database_privilege('$selected_user', datname, 'CONNECT') ORDER BY datname")
    if [ -n "$db_access" ]; then
        echo "$db_access" | while read -r db; do
            if [ -n "$db" ]; then
                echo "  • $(echo $db | tr -d ' ')"
            fi
        done
    else
        echo "  (none)"
    fi

    echo ""
    echo -e "${BLUE}Table Privileges:${NC}"
    echo "----------------------------------------"
    local table_privs=$(run_psql "SELECT table_catalog || '.' || table_schema || '.' || table_name || ': ' || string_agg(privilege_type, ', ') FROM information_schema.table_privileges WHERE grantee = '$selected_user' GROUP BY table_catalog, table_schema, table_name ORDER BY table_catalog, table_schema, table_name")
    if [ -n "$table_privs" ]; then
        echo "$table_privs" | while read -r priv; do
            if [ -n "$priv" ]; then
                echo "  $priv"
            fi
        done
    else
        echo "  (none)"
    fi

    press_enter
}

permissions_menu() {
    if [ -z "$CURRENT_CONNECTION" ]; then
        print_error "Please select a connection first"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BLUE}=== Permissions Management ===${NC}"
        echo ""
        echo "  1) Grant permissions"
        echo "  2) Revoke permissions"
        echo "  3) View user permissions"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) grant_permissions ;;
            2) revoke_permissions ;;
            3) list_user_permissions ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# Backup & Restore Functions
#===============================================================================

backup_database() {
    print_header
    echo -e "${BLUE}=== Backup Database ===${NC}"
    echo ""

    ensure_connections_dir

    # Select database
    local databases=$(run_psql "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname" | tr -d ' ')

    if [ -z "$databases" ]; then
        print_warning "No databases found"
        press_enter
        return
    fi

    echo "Select database to backup:"
    echo ""
    local i=1
    local db_array=()
    while IFS= read -r db; do
        if [ -n "$db" ]; then
            db_array+=("$db")
            local size=$(run_psql "SELECT pg_size_pretty(pg_database_size('$db'))" | tr -d ' ')
            echo "  $i) $db ($size)"
            ((i++))
        fi
    done <<< "$databases"
    echo ""

    read -p "Selection [1-$((i-1))]: " db_choice

    if ! [[ "$db_choice" =~ ^[0-9]+$ ]] || [ "$db_choice" -lt 1 ] || [ "$db_choice" -gt ${#db_array[@]} ]; then
        print_error "Invalid selection"
        press_enter
        return
    fi

    local selected_db="${db_array[$((db_choice-1))]}"

    # Select format
    echo ""
    echo "Backup format:"
    echo "  1) SQL (plain text, readable, larger)"
    echo "  2) Custom (compressed, faster restore)"
    echo ""
    read -p "Selection [1-2]: " format_choice

    local ext="sql"
    local format_opt=""
    if [ "$format_choice" = "2" ]; then
        ext="dump"
        format_opt="-Fc"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${selected_db}_${timestamp}.${ext}"

    print_info "Creating backup..."

    local result
    if [ "$CONNECTION_TYPE" = "docker" ]; then
        local docker_cmd=$(get_docker_cmd)
        if [ "$ext" = "sql" ]; then
            $docker_cmd exec "$CONTAINER_NAME" pg_dump -U "$ADMIN_USER" "$selected_db" > "$backup_file" 2>&1
        else
            $docker_cmd exec "$CONTAINER_NAME" pg_dump -U "$ADMIN_USER" $format_opt "$selected_db" > "$backup_file" 2>&1
        fi
        result=$?
    else
        if [ -z "$ADMIN_PASS" ]; then
            read -sp "Enter password for $ADMIN_USER: " ADMIN_PASS
            echo ""
        fi
        if [ "$ext" = "sql" ]; then
            PGPASSWORD="$ADMIN_PASS" PGSSLMODE="$SSL_MODE" pg_dump -h "$HOST" -p "$PORT" -U "$ADMIN_USER" "$selected_db" > "$backup_file" 2>&1
        else
            PGPASSWORD="$ADMIN_PASS" PGSSLMODE="$SSL_MODE" pg_dump -h "$HOST" -p "$PORT" -U "$ADMIN_USER" $format_opt "$selected_db" > "$backup_file" 2>&1
        fi
        result=$?
    fi

    if [ $result -eq 0 ] && [ -s "$backup_file" ]; then
        local size=$(ls -lh "$backup_file" | awk '{print $5}')
        print_success "Backup created successfully!"
        echo ""
        echo "File: $backup_file"
        echo "Size: $size"
    else
        print_error "Backup failed!"
        rm -f "$backup_file"
    fi

    press_enter
}

backup_all() {
    print_header
    echo -e "${BLUE}=== Backup All Databases ===${NC}"
    echo ""

    ensure_connections_dir

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/all_databases_${timestamp}.sql"

    print_info "Creating full backup of all databases..."

    local result
    if [ "$CONNECTION_TYPE" = "docker" ]; then
        local docker_cmd=$(get_docker_cmd)
        $docker_cmd exec "$CONTAINER_NAME" pg_dumpall -U "$ADMIN_USER" > "$backup_file" 2>&1
        result=$?
    else
        if [ -z "$ADMIN_PASS" ]; then
            read -sp "Enter password for $ADMIN_USER: " ADMIN_PASS
            echo ""
        fi
        PGPASSWORD="$ADMIN_PASS" PGSSLMODE="$SSL_MODE" pg_dumpall -h "$HOST" -p "$PORT" -U "$ADMIN_USER" > "$backup_file" 2>&1
        result=$?
    fi

    if [ $result -eq 0 ] && [ -s "$backup_file" ]; then
        local size=$(ls -lh "$backup_file" | awk '{print $5}')
        print_success "Full backup created successfully!"
        echo ""
        echo "File: $backup_file"
        echo "Size: $size"
    else
        print_error "Backup failed!"
        rm -f "$backup_file"
    fi

    press_enter
}

restore_database() {
    print_header
    echo -e "${BLUE}=== Restore Database ===${NC}"
    echo ""

    ensure_connections_dir

    # List available backups
    local backups=$(ls -t "$BACKUP_DIR"/*.{sql,dump} 2>/dev/null)

    if [ -z "$backups" ]; then
        print_warning "No backup files found in $BACKUP_DIR"
        echo ""
        read -p "Enter backup file path manually: " backup_file
        if [ ! -f "$backup_file" ]; then
            print_error "File not found"
            press_enter
            return
        fi
    else
        echo "Available backups:"
        echo ""
        local i=1
        local backup_array=()
        while IFS= read -r backup; do
            if [ -n "$backup" ]; then
                backup_array+=("$backup")
                local size=$(ls -lh "$backup" | awk '{print $5}')
                local name=$(basename "$backup")
                echo "  $i) $name ($size)"
                ((i++))
            fi
        done <<< "$backups"
        echo "  $i) Enter path manually"
        echo ""

        read -p "Selection [1-$i]: " backup_choice

        if [ "$backup_choice" = "$i" ]; then
            read -p "Enter backup file path: " backup_file
            if [ ! -f "$backup_file" ]; then
                print_error "File not found"
                press_enter
                return
            fi
        elif [[ "$backup_choice" =~ ^[0-9]+$ ]] && [ "$backup_choice" -ge 1 ] && [ "$backup_choice" -lt "$i" ]; then
            backup_file="${backup_array[$((backup_choice-1))]}"
        else
            print_error "Invalid selection"
            press_enter
            return
        fi
    fi

    # Determine restore method based on file extension
    local ext="${backup_file##*.}"

    # Target database
    echo ""
    echo "Restore options:"
    echo "  1) Restore to existing database (will drop and recreate)"
    echo "  2) Restore to new database"
    echo ""
    read -p "Selection [1-2]: " restore_option

    local target_db=""
    if [ "$restore_option" = "1" ]; then
        # Select existing database
        local databases=$(run_psql "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres') ORDER BY datname" | tr -d ' ')

        echo ""
        echo "Select target database:"
        local i=1
        local db_array=()
        while IFS= read -r db; do
            if [ -n "$db" ]; then
                db_array+=("$db")
                echo "  $i) $db"
                ((i++))
            fi
        done <<< "$databases"
        echo ""

        read -p "Selection [1-$((i-1))]: " db_choice

        if [[ "$db_choice" =~ ^[0-9]+$ ]] && [ "$db_choice" -ge 1 ] && [ "$db_choice" -le ${#db_array[@]} ]; then
            target_db="${db_array[$((db_choice-1))]}"

            echo ""
            print_warning "This will DROP and recreate database '$target_db'!"
            read -p "Type the database name to confirm: " confirm

            if [ "$confirm" != "$target_db" ]; then
                print_warning "Restore cancelled"
                press_enter
                return
            fi

            # Terminate connections and drop database
            print_info "Terminating connections..."
            run_psql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$target_db' AND pid <> pg_backend_pid()" > /dev/null
            print_info "Dropping database..."
            run_psql "DROP DATABASE \"$target_db\"" > /dev/null
            print_info "Creating database..."
            run_psql "CREATE DATABASE \"$target_db\"" > /dev/null
        else
            print_error "Invalid selection"
            press_enter
            return
        fi
    else
        read -p "Enter new database name: " target_db
        if [ -z "$target_db" ]; then
            print_error "Database name cannot be empty"
            press_enter
            return
        fi

        # Create database
        print_info "Creating database '$target_db'..."
        local result=$(run_psql "CREATE DATABASE \"$target_db\"")
        if echo "$result" | grep -qi "error"; then
            print_error "Failed to create database"
            echo "$result"
            press_enter
            return
        fi
    fi

    print_info "Restoring backup to '$target_db'..."

    local result
    if [ "$CONNECTION_TYPE" = "docker" ]; then
        local docker_cmd=$(get_docker_cmd)
        if [ "$ext" = "dump" ]; then
            cat "$backup_file" | $docker_cmd exec -i "$CONTAINER_NAME" pg_restore -U "$ADMIN_USER" -d "$target_db" 2>&1
        else
            cat "$backup_file" | $docker_cmd exec -i "$CONTAINER_NAME" psql -U "$ADMIN_USER" -d "$target_db" 2>&1
        fi
        result=$?
    else
        if [ -z "$ADMIN_PASS" ]; then
            read -sp "Enter password for $ADMIN_USER: " ADMIN_PASS
            echo ""
        fi
        if [ "$ext" = "dump" ]; then
            PGPASSWORD="$ADMIN_PASS" PGSSLMODE="$SSL_MODE" pg_restore -h "$HOST" -p "$PORT" -U "$ADMIN_USER" -d "$target_db" "$backup_file" 2>&1
        else
            PGPASSWORD="$ADMIN_PASS" PGSSLMODE="$SSL_MODE" psql -h "$HOST" -p "$PORT" -U "$ADMIN_USER" -d "$target_db" -f "$backup_file" 2>&1
        fi
        result=$?
    fi

    if [ $result -eq 0 ]; then
        print_success "Database restored successfully!"
    else
        print_warning "Restore completed with warnings (this is often normal)"
    fi

    press_enter
}

list_backups() {
    print_header
    echo -e "${BLUE}=== Available Backups ===${NC}"
    echo ""

    ensure_connections_dir

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_warning "No backups found in $BACKUP_DIR"
        press_enter
        return
    fi

    echo "Backup directory: $BACKUP_DIR"
    echo ""
    echo -e "${CYAN}Filename                                    Size        Date${NC}"
    echo "----------------------------------------------------------------------"

    ls -lt "$BACKUP_DIR"/*.{sql,dump} 2>/dev/null | while read -r line; do
        local size=$(echo "$line" | awk '{print $5}')
        local date=$(echo "$line" | awk '{print $6, $7, $8}')
        local name=$(basename "$(echo "$line" | awk '{print $NF}')")
        printf "  %-40s %-10s %s\n" "$name" "$size" "$date"
    done

    echo ""

    # Show total size
    local total=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    echo "Total backup size: $total"

    press_enter
}

backup_menu() {
    if [ -z "$CURRENT_CONNECTION" ]; then
        print_error "Please select a connection first"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BLUE}=== Backup / Restore ===${NC}"
        echo ""
        echo "  1) Backup database"
        echo "  2) Backup all databases"
        echo "  3) Restore from file"
        echo "  4) List backups"
        echo ""
        echo "  b) Back to main menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) backup_database ;;
            2) backup_all ;;
            3) restore_database ;;
            4) list_backups ;;
            b|B) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# Quick Create Function
#===============================================================================

quick_create() {
    print_header
    echo -e "${BLUE}=== Quick Create: Database + User + Permissions ===${NC}"
    echo ""

    if [ -z "$CURRENT_CONNECTION" ]; then
        print_warning "No connection selected. Let's set one up first."
        echo ""
        read -p "Press Enter to continue..."
        select_connection

        if [ -z "$CURRENT_CONNECTION" ]; then
            return
        fi
        print_header
        echo -e "${BLUE}=== Quick Create: Database + User + Permissions ===${NC}"
        echo ""
    fi

    echo "This will create a new database, user, and grant full permissions."
    echo "Perfect for setting up a new project/application."
    echo ""

    # Get database name
    read -p "Enter database name: " db_name

    if [ -z "$db_name" ]; then
        print_error "Database name cannot be empty"
        press_enter
        return
    fi

    # Validate database name
    if ! [[ "$db_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        print_error "Invalid database name. Must start with a letter and contain only letters, numbers, and underscores."
        press_enter
        return
    fi

    # Username (default = db_name)
    echo ""
    read -p "Username [$db_name]: " username
    username=${username:-$db_name}

    # Check if database exists
    local db_exists=$(run_psql "SELECT 1 FROM pg_database WHERE datname = '$db_name'" | tr -d ' ')
    if [ "$db_exists" = "1" ]; then
        print_error "Database '$db_name' already exists"
        press_enter
        return
    fi

    # Check if user exists
    local user_exists=$(run_psql "SELECT 1 FROM pg_roles WHERE rolname = '$username'" | tr -d ' ')
    if [ "$user_exists" = "1" ]; then
        print_error "User '$username' already exists"
        press_enter
        return
    fi

    # Generate password
    local password=$(generate_password 32)

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Creating resources...${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Step 1: Create database
    print_info "Creating database '$db_name'..."
    local result=$(run_psql "CREATE DATABASE \"$db_name\"")
    if echo "$result" | grep -qi "error"; then
        print_error "Failed to create database"
        echo "$result"
        press_enter
        return
    fi
    print_success "Database '$db_name' created"

    # Step 2: Create user
    print_info "Creating user '$username'..."
    local escaped_password="${password//\'/\'\'}"
    result=$(run_psql "CREATE USER \"$username\" WITH PASSWORD '$escaped_password'")
    if echo "$result" | grep -qi "error"; then
        print_error "Failed to create user"
        echo "$result"
        press_enter
        return
    fi
    print_success "User '$username' created"

    # Step 3: Grant permissions
    print_info "Granting permissions..."
    run_psql "GRANT ALL PRIVILEGES ON DATABASE \"$db_name\" TO \"$username\"" > /dev/null
    run_psql "GRANT USAGE, CREATE ON SCHEMA public TO \"$username\"" "$db_name" > /dev/null
    run_psql "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"$username\"" "$db_name" > /dev/null
    run_psql "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"$username\"" "$db_name" > /dev/null
    run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO \"$username\"" "$db_name" > /dev/null
    run_psql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO \"$username\"" "$db_name" > /dev/null
    print_success "Full permissions granted"

    # Determine connection details for .env output
    local pg_host=""
    local pg_port=""
    local ssl_mode_env=""

    if [ "$CONNECTION_TYPE" = "docker" ]; then
        local docker_cmd=$(get_docker_cmd)
        # Get container IP
        pg_host=$($docker_cmd inspect "$CONTAINER_NAME" 2>/dev/null | grep -m 1 '"IPAddress"' | awk -F'"' '{print $4}')
        if [ -z "$pg_host" ]; then
            pg_host="localhost"
        fi
        pg_port="5432"
        ssl_mode_env="disable"
    else
        pg_host="$HOST"
        pg_port="$PORT"
        ssl_mode_env="$SSL_MODE"
    fi

    # Output .env format
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ Setup Complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Copy these to your .env file:${NC}"
    echo ""
    echo -e "${YELLOW}# PostgreSQL Configuration${NC}"
    echo "POSTGRES_HOST=$pg_host"
    echo "POSTGRES_PORT=$pg_port"
    echo "POSTGRES_USER=$username"
    echo "POSTGRES_PASSWORD=$password"
    echo "POSTGRES_DB=$db_name"
    echo "POSTGRES_SSLMODE=$ssl_mode_env"
    echo ""
    echo -e "${CYAN}Connection URL:${NC}"
    echo ""
    if [ "$ssl_mode_env" = "disable" ]; then
        echo "DATABASE_URL=postgresql://$username:$password@$pg_host:$pg_port/$db_name"
    else
        echo "DATABASE_URL=postgresql://$username:$password@$pg_host:$pg_port/$db_name?sslmode=$ssl_mode_env"
    fi
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    print_warning "IMPORTANT: Save the password now! It cannot be retrieved later."

    press_enter
}

#===============================================================================
# Main Menu
#===============================================================================

main_menu() {
    while true; do
        print_header
        echo -e "${BLUE}Main Menu${NC}"
        echo ""
        echo -e "  ${GREEN}0) Quick Create (user + db + permissions + .env)${NC}"
        echo ""
        echo "  1) Connection Management"
        echo "  2) Database Management"
        echo "  3) User Management"
        echo "  4) Permissions"
        echo "  5) Backup / Restore"
        echo ""
        echo "  q) Quit"
        echo ""
        read -p "Selection: " choice

        case $choice in
            0) quick_create ;;
            1) connection_menu ;;
            2) database_menu ;;
            3) user_menu ;;
            4) permissions_menu ;;
            5) backup_menu ;;
            q|Q)
                echo ""
                echo -e "${GREEN}Thank you for using PostgreSQL Manager!${NC}"
                echo ""
                exit 0
                ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# CLI Argument Parsing & Entry Point
#===============================================================================

show_help() {
    echo "PostgreSQL Manager v${VERSION}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --quick, -q    Quick create mode (db + user + permissions + .env output)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Without options, the interactive menu will be displayed."
    echo ""
    echo "Configuration:"
    echo "  Connections: $CONNECTIONS_DIR/"
    echo "  Backups:     $BACKUP_DIR/"
    echo ""
}

main() {
    # Ensure directories exist
    ensure_connections_dir

    # Parse command line arguments
    case "${1:-}" in
        --quick|-q)
            # Try to load last used connection
            if [ -f "$CONFIG_FILE" ]; then
                local last_alias=$(cat "$CONFIG_FILE")
                if [ -n "$last_alias" ] && load_connection "$last_alias"; then
                    print_info "Using connection: $last_alias"
                fi
            fi

            # If no connection, try to select
            if [ -z "$CURRENT_CONNECTION" ]; then
                local connections=($(list_connections))
                if [ ${#connections[@]} -eq 1 ]; then
                    load_connection "${connections[0]}"
                    print_info "Using connection: ${connections[0]}"
                elif [ ${#connections[@]} -gt 1 ]; then
                    select_connection
                fi
            fi

            quick_create
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            # No arguments, continue to interactive mode
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    # Try to load last used connection
    if [ -f "$CONFIG_FILE" ]; then
        local last_alias=$(cat "$CONFIG_FILE")
        if [ -n "$last_alias" ]; then
            if load_connection "$last_alias"; then
                print_header
                echo "Found previous connection: $last_alias"
                read -p "Use this connection? (y/n): " use_last
                if [[ $use_last =~ ^[Yy]$ ]]; then
                    if ! test_connection; then
                        CURRENT_CONNECTION=""
                    fi
                else
                    CURRENT_CONNECTION=""
                fi
            fi
        fi
    fi

    # If no connection loaded, check for available connections
    if [ -z "$CURRENT_CONNECTION" ]; then
        local connections=($(list_connections))
        if [ ${#connections[@]} -gt 0 ]; then
            print_header
            echo "Found existing connections."
            read -p "Would you like to select one now? (y/n): " select_now
            if [[ $select_now =~ ^[Yy]$ ]]; then
                select_connection
            fi
        fi
    fi

    # Start main menu
    main_menu
}

# Run the script
main "$@"
