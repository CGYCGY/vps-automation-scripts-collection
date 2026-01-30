# PostgreSQL Manager

Interactive PostgreSQL management tool for databases, users, and permissions. Works with both Docker containers and remote PostgreSQL servers.

## Features

- **Connection Management**: Support for Docker containers and remote servers
- **Database Operations**: Create, list, and delete databases
- **User Management**: Create users with secure password generation
- **Permissions**: Grant/revoke read-only, read-write, or full access
- **Backup & Restore**: Single or all databases, multiple formats
- **Quick Create**: One-command setup with `.env` output

## Quick Start

### Via Main Setup Script

```bash
./setup.sh --postgres
```

### Direct Execution

```bash
cd postgres
./postgres_manager.sh
```

### Quick Create Mode

```bash
./postgres_manager.sh --quick
# or
./postgres_manager.sh -q
```

## Usage Examples

### 1. Quick Create (Recommended for New Projects)

Creates a database, user, and grants full permissions in one step:

```bash
./postgres_manager.sh --quick
```

**Prompts:**
- Database name (e.g., `myapp`)
- Username (default: same as database name)

**Output:**
```env
# PostgreSQL Configuration
POSTGRES_HOST=172.17.0.2
POSTGRES_PORT=5432
POSTGRES_USER=myapp
POSTGRES_PASSWORD=Abc123_def456...
POSTGRES_DB=myapp
POSTGRES_SSLMODE=disable

# Connection URL:
DATABASE_URL=postgresql://myapp:Abc123_def456...@172.17.0.2:5432/myapp
```

### 2. Connect to Docker Container

**Menu:** Connection Management → Create Docker connection

The script will auto-detect running PostgreSQL containers:

```
Found PostgreSQL containers:
  1) postgres_prod
  2) my_postgres_db
```

### 3. Connect to Remote Server

**Menu:** Connection Management → Create remote connection

**Required Information:**
- Host (e.g., `db.example.com`)
- Port (default: `5432`)
- Admin user (default: `postgres`)
- SSL mode (disable/require/verify-ca/verify-full)

### 4. Manage Users

**Create User:**
```
Menu: User Management → Create user
- Choose: Generate random password (recommended)
- Password is SQL-safe (alphanumeric + _-.)
```

**Test Credentials:**
```
Menu: User Management → Test user credentials
- Verify login works before sharing credentials
```

### 5. Grant Permissions

**Menu:** Permissions → Grant permissions

**Permission Levels:**

| Level | Permissions | Use Case |
|-------|-------------|----------|
| **Read-only** | SELECT | Analytics, reporting |
| **Read-write** | SELECT, INSERT, UPDATE, DELETE | Application access |
| **Full** | ALL PRIVILEGES | Database owner |

**Example:**
1. Select user: `app_user`
2. Select database: `myapp`
3. Choose: Read-write access
4. ✓ Permissions granted

### 6. Backup & Restore

**Backup Single Database:**
```
Menu: Backup / Restore → Backup database
- Choose format: SQL (readable) or Custom (compressed)
- Saved to: ~/pg_backups/
```

**Backup All Databases:**
```
Menu: Backup / Restore → Backup all databases
- Uses pg_dumpall
- Includes users and roles
```

**Restore:**
```
Menu: Backup / Restore → Restore from file
- Option 1: Restore to existing (drops and recreates)
- Option 2: Restore to new database
```

## Menu Structure

```
Main Menu
├── 0) Quick Create (user + db + permissions + .env)
├── 1) Connection Management
│   ├── Select connection
│   ├── Create Docker connection
│   ├── Create remote connection
│   ├── Update connection
│   ├── Remove connection
│   └── Test connection
├── 2) Database Management
│   ├── List databases (with sizes)
│   ├── Create database
│   └── Delete database (with active connection handling)
├── 3) User Management
│   ├── List users (roles)
│   ├── Create user
│   ├── Delete user
│   └── Test user credentials
├── 4) Permissions
│   ├── Grant permissions (read-only/read-write/full)
│   ├── Revoke permissions
│   └── View user permissions
├── 5) Backup / Restore
│   ├── Backup database (.sql or .dump)
│   ├── Backup all databases
│   ├── Restore from file
│   └── List backups
└── q) Exit
```

## Configuration Files

### Connection Storage
```
~/.pg_connections/          # Connection configs
├── local.conf              # Docker connection
├── production.conf         # Remote connection
└── staging.conf            # Another remote
```

**Config Format (Docker):**
```bash
TYPE=docker
CONTAINER_NAME=postgres_prod
ADMIN_USER=postgres
```

**Config Format (Remote):**
```bash
TYPE=remote
HOST=db.example.com
PORT=5432
ADMIN_USER=postgres
SSL_MODE=require
```

### Backups
```
~/pg_backups/               # Backup directory
├── myapp_20260130_143022.sql      # Plain SQL backup
├── myapp_20260130_143500.dump     # Compressed backup
└── all_databases_20260130_150000.sql  # Full backup
```

## Docker Setup Example

### Create PostgreSQL Container

```bash
docker run -d \
  --name postgres_prod \
  -e POSTGRES_PASSWORD=admin_password \
  -v postgres_data:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:16
```

### Connect with Manager

```bash
./postgres_manager.sh

# Menu: Connection Management → Create Docker connection
# Select container: postgres_prod
# Admin user: postgres
```

## Remote Setup Example

### Allow Remote Connections

**Edit `postgresql.conf`:**
```conf
listen_addresses = '*'
```

**Edit `pg_hba.conf`:**
```conf
# Allow connections from specific IP
host    all    all    192.168.1.0/24    scram-sha-256

# Or require SSL from anywhere
hostssl all    all    0.0.0.0/0         scram-sha-256
```

**Restart PostgreSQL:**
```bash
sudo systemctl restart postgresql
```

### Connect with Manager

```bash
./postgres_manager.sh

# Menu: Connection Management → Create remote connection
# Host: db.example.com
# Port: 5432
# Admin user: postgres
# SSL mode: require
```

## Security Best Practices

### 1. Password Generation
- Always use "Generate random password" option
- Passwords are 32 characters: `[A-Za-z0-9_-.]`
- SQL-safe (no special characters that need escaping)

### 2. Principle of Least Privilege
- Grant only required permissions
- Use read-only for analytics/reporting
- Use read-write for applications
- Reserve full access for admins only

### 3. Connection Security
- Use SSL for remote connections (`require` or higher)
- Store connection configs with restricted permissions
- Never share admin credentials

### 4. Regular Backups
```bash
# Automated backup (add to cron)
0 2 * * * /path/to/postgres_manager.sh --quick-backup
```

## Permission Levels Explained

### Read-only
```sql
GRANT CONNECT ON DATABASE mydb TO user;
GRANT USAGE ON SCHEMA public TO user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO user;
```

**Use cases:** Analytics, reporting, read replicas

### Read-write
```sql
GRANT SELECT, INSERT, UPDATE, DELETE
  ON ALL TABLES IN SCHEMA public TO user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO user;
```

**Use cases:** Application database access, CRUD operations

### Full
```sql
GRANT ALL PRIVILEGES ON DATABASE mydb TO user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO user;
```

**Use cases:** Database owners, migrations, schema changes

## Troubleshooting

### Connection Issues

**Docker: "Cannot reach container"**
```bash
# Check container is running
docker ps | grep postgres

# Verify container name
docker ps --format "{{.Names}}"

# Check PostgreSQL is ready
docker exec postgres_prod pg_isready
```

**Remote: "Authentication failed"**
```bash
# Test connection manually
psql -h db.example.com -p 5432 -U postgres -d postgres

# Check pg_hba.conf allows your IP
# Check password is correct
```

### Delete Database with Active Connections

The script automatically:
1. Shows number of active connections
2. Offers to terminate connections
3. Drops the database

**Manual method:**
```sql
-- Terminate connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'mydb' AND pid <> pg_backend_pid();

-- Drop database
DROP DATABASE mydb;
```

### Restore Fails

**"Database already exists"**
- Choose "Restore to existing database" (drops and recreates)
- Or create with different name

**"Permission denied"**
- Ensure admin user has sufficient privileges
- For `pg_dumpall` restores, must be superuser

### Password Issues

**Forgot admin password?**

For Docker:
```bash
# Reset postgres password
docker exec -it postgres_prod bash
psql -U postgres -c "ALTER USER postgres PASSWORD 'new_password';"
```

For remote: Contact database administrator

## Integration Examples

### Node.js (pg)
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.POSTGRES_HOST,
  port: process.env.POSTGRES_PORT,
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  database: process.env.POSTGRES_DB,
  ssl: process.env.POSTGRES_SSLMODE === 'require'
    ? { rejectUnauthorized: false }
    : false
});
```

### Python (psycopg2)
```python
import psycopg2
import os

conn = psycopg2.connect(
    host=os.getenv('POSTGRES_HOST'),
    port=os.getenv('POSTGRES_PORT'),
    user=os.getenv('POSTGRES_USER'),
    password=os.getenv('POSTGRES_PASSWORD'),
    database=os.getenv('POSTGRES_DB'),
    sslmode=os.getenv('POSTGRES_SSLMODE')
)
```

### Django
```python
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('POSTGRES_DB'),
        'USER': os.getenv('POSTGRES_USER'),
        'PASSWORD': os.getenv('POSTGRES_PASSWORD'),
        'HOST': os.getenv('POSTGRES_HOST'),
        'PORT': os.getenv('POSTGRES_PORT'),
        'OPTIONS': {
            'sslmode': os.getenv('POSTGRES_SSLMODE', 'disable'),
        }
    }
}
```

### Ruby on Rails
```yaml
# config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  database: <%= ENV['POSTGRES_DB'] %>
  username: <%= ENV['POSTGRES_USER'] %>
  password: <%= ENV['POSTGRES_PASSWORD'] %>
  host: <%= ENV['POSTGRES_HOST'] %>
  port: <%= ENV['POSTGRES_PORT'] %>
```

## Advanced Usage

### Automated Quick Create
```bash
# For CI/CD pipelines
echo -e "myapp\nmyapp\n" | ./postgres_manager.sh --quick
```

### Batch User Creation
```bash
# Create multiple users
for user in app1 app2 app3; do
  echo "$user" | ./postgres_manager.sh # then navigate menus
done
```

### Scheduled Backups
```bash
# Add to crontab -e
# Daily backup at 2 AM
0 2 * * * cd /path/to/postgres && ./postgres_manager.sh --backup-all

# Cleanup old backups (keep 7 days)
0 3 * * * find ~/pg_backups -name "*.sql" -mtime +7 -delete
```

## Requirements

- **PostgreSQL**: 10+ (tested with 12, 13, 14, 15, 16)
- **Tools**: `psql`, `pg_dump`, `pg_restore` (for remote connections)
- **Docker**: Optional, only for Docker connections
- **Bash**: 4.0+ (for arrays and other features)

## Command Reference

```bash
./postgres_manager.sh           # Interactive menu
./postgres_manager.sh --quick   # Quick create mode
./postgres_manager.sh -q        # Quick create (short)
./postgres_manager.sh --help    # Show help
./postgres_manager.sh -h        # Show help (short)
```

## FAQ

**Q: Can I manage multiple PostgreSQL servers?**
A: Yes, create multiple connections and switch between them.

**Q: Is this safe for production?**
A: Yes, but test first. The script asks for confirmation before destructive operations.

**Q: Does it work with PostgreSQL 16?**
A: Yes, tested with PostgreSQL 10-16.

**Q: Can I automate this for CI/CD?**
A: Yes, use `--quick` mode and pipe inputs, or call psql directly with generated credentials.

**Q: What about connection pooling (pgBouncer)?**
A: The script connects to PostgreSQL directly. Configure your application to use pgBouncer.

**Q: Does it support other schemas besides `public`?**
A: Currently focused on `public` schema. For custom schemas, use psql directly or modify the script.

## Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [pg_dump Reference](https://www.postgresql.org/docs/current/app-pgdump.html)
- [Grant Documentation](https://www.postgresql.org/docs/current/sql-grant.html)
- [pg_hba.conf Guide](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)

## License

MIT License - See [LICENSE](../LICENSE) for details.
