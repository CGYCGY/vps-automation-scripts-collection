# VPS Automation Scripts Collection

Setup and management scripts for two kinds of machines:

- **Server**: a Linux VPS hosting [Coolify](https://coolify.io), either the dashboard or a server it manages.
- **Workstation**: a machine used for work, Linux or macOS, set up as an AI coding-agent box.

Everything is reached through Tailscale SSH. Set up your tailnet policy first:
see the [tailnet guide](docs/tailscale-tailnet.md).

## Quick Start

```bash
git clone https://github.com/CGYCGY/vps-automation-scripts-collection.git
cd vps-automation-scripts-collection

sudo ./setup.sh server       # Linux VPS hosting Coolify
./setup.sh workstation       # machine used for work (no sudo)
./setup.sh                   # ask which one
```

Options after the type are passed through, so `sudo ./setup.sh server --full` is
the same as `sudo ./server/setup.sh --full`.

### Server Options

```bash
sudo ./server/setup.sh --full            # Swap + Tailscale SSH + Coolify in one run
sudo ./server/setup.sh --tailscale       # Tailscale SSH and firewall only
sudo ./server/setup.sh --coolify         # Coolify only (asks: dashboard or managed server)
sudo ./server/setup.sh --coolify-remote  # Coolify as a managed server
sudo ./server/setup.sh --swap            # Swap only
./server/setup.sh --status               # Survey swap, Tailscale and Coolify without changing anything
./server/setup.sh --minio                # MinIO migration tool
./server/setup.sh --minio-users          # MinIO user & bucket manager
./server/setup.sh --postgres             # PostgreSQL manager
sudo ./server/setup.sh --help            # Show all options
```

Every setup runs in the same order: sudo first, then all of its questions, then
installs and changes that need no input, and last the steps that need you, such
as the Tailscale login. `-y` takes the default answer for every question.
Every step checks the machine first and skips what is already done, so a run
that stopped halfway is finished by running it again. `--status` shows the same
checks; run it with sudo for the firewall, sshd and Docker ones.

### Workstation Options

```bash
./workstation/setup.sh              # Detects Linux or macOS and runs the matching setup
./workstation/setup.sh --status     # Survey the machine without changing anything
./workstation/setup.sh -y           # Take the default for every question
```

On a Mac this runs the [macOS workstation setup](workstation/macos/README.md).
On Linux it runs the [AI dev setup](workstation/shared/ai-dev/README.md#options),
and every flag is passed through to it.

## Available Scripts

| Type | Script | Description | Documentation |
|------|--------|-------------|---------------|
| Server | **Coolify Setup** | Self-hostable Heroku/Netlify alternative | [server/coolify/README.md](server/coolify/README.md) |
| Server | **MinIO Migration** | Migrate MinIO data between servers | [server/minio/README.md](server/minio/README.md) |
| Server | **MinIO User Manager** | Create users with bucket-specific access | [server/minio/README.md](server/minio/README.md) |
| Server | **PostgreSQL Manager** | Manage databases, users, and permissions | [server/postgres/README.md](server/postgres/README.md) |
| Shared (Linux) | **Tailscale SSH** | Secure the machine with Tailscale SSH - no more SSH keys | [shared/linux/tailscale/README.md](shared/linux/tailscale/README.md) |
| Shared (Linux) | **Swap Config** | RAM-based optimized swap settings | [shared/linux/swap/README.md](shared/linux/swap/README.md) |
| Workstation | **Mac Setup** | Homebrew apps, Tailscale SSH, power, Finder, Zed settings, git and GitHub key, plus the AI dev toolchain | [workstation/macos/README.md](workstation/macos/README.md) |
| Workstation | **Projects** | Clone your repos into the same folder layout on every machine and register each with `cdp`; optional, from a JSONC list | [workstation/shared/projects/README.md](workstation/shared/projects/README.md) |
| Workstation | **Agent Skills** | Link the agent skills into `~/.claude/skills` from your projects checkout or a clone in `~/.gylab/repos`; optional | [workstation/shared/skills/README.md](workstation/shared/skills/README.md) |
| Workstation | **AI Dev Setup** | Bootstrap the author's AI coding-agent toolchain (single-file installer available; [macOS version](workstation/shared/ai-dev/macos/README.md)) | [workstation/shared/ai-dev/README.md](workstation/shared/ai-dev/README.md) |

## Supported Systems

- **Server OS**: Ubuntu 22.04, 24.04 LTS / Debian 11, 12, 13
- **Workstation OS**: the same Linux releases, or macOS
- **Architectures**: ARM64 (aarch64), x86_64 (amd64)
- **Providers**: Oracle Cloud, DigitalOcean, Linode, Vultr, Hetzner, Contabo, OVH, and most VPS providers

## Common Workflows

### New Server Setup
```bash
sudo ./server/setup.sh --full
```
Asks whether this is the Coolify dashboard or a managed server, then sets up swap, Tailscale SSH with the matching tags, and Coolify.

### Secure Existing Server
```bash
sudo ./server/setup.sh --tailscale
```
Restricts SSH access to Tailscale network only.

### Migrate MinIO Data
```bash
./server/setup.sh --minio
```
Interactive tool for migrating MinIO between servers.

### Manage PostgreSQL
```bash
./server/setup.sh --postgres
```
Interactive tool for managing PostgreSQL databases, users, and permissions.

### Linux Workstation
```bash
sudo MACHINE_ROLE=workstation ./shared/linux/tailscale/tailscale-setup.sh
./workstation/setup.sh
```
Secures remote access with Tailscale, then installs the AI development toolchain for the normal user.

### Mac Workstation
```bash
./workstation/setup.sh
```
Asks for sudo once and asks every question first. Then it installs Homebrew, the
apps, Tailscale SSH and the AI development toolchain. It finishes with the steps
that need you: the Tailscale login and the GitHub key.

## Directory Structure

```
.
├── setup.sh                    # Entry point: picks server or workstation
├── server/                     # Linux VPS hosting Coolify
│   ├── setup.sh                # Server menu
│   ├── coolify/
│   │   ├── coolify-setup.sh         # Dashboard install or managed-server prep, by role
│   │   └── README.md
│   ├── minio/
│   │   ├── minio_migration.sh          # MinIO migration tool
│   │   ├── minio_user_bucket_manager.sh # MinIO user & bucket manager
│   │   └── README.md
│   └── postgres/
│       ├── postgres_manager.sh          # PostgreSQL manager
│       └── README.md
├── workstation/                # Machines used for work
│   ├── setup.sh                # Detects Linux or macOS
│   ├── macos/                  # Mac modules: homebrew, apps, tailscale, power, ssh, ...
│   │   ├── macos-lib.sh        # macOS helpers on top of setup-lib.sh
│   │   └── README.md
│   └── shared/                 # Used by both Linux and macOS workstations
│       ├── projects/
│       │   ├── projects.sh           # Clones your projects list, registers cdp names
│       │   ├── projects.example.json # Copy to projects.json (gitignored)
│       │   └── README.md
│       ├── skills/
│       │   ├── skills.sh             # Links the agent skills into ~/.claude/skills
│       │   ├── skills.json           # The skills, their repos and setup commands
│       │   └── README.md
│       └── ai-dev/
│           ├── ai-dev-setup.sh       # Linux AI development toolchain setup
│           ├── ai-dev-standalone.sh  # Generated single-file installer
│           ├── build-standalone.sh   # Regenerates the single-file installers
│           ├── agent-instructions/   # CLAUDE.md, AGENTS.md, GEMINI.md
│           ├── claude/               # Claude Code status line
│           ├── macos/                # macOS (Homebrew + zsh) version
│           └── README.md
├── docs/
│   └── tailscale-tailnet.md    # Tailnet tags and SSH policy
└── shared/
    ├── lib/
    │   ├── setup-lib.sh        # Phase runner every setup script uses
    │   └── project-navigator-lib.sh # cdp install shared by ai-dev and projects
    └── linux/                  # Used by both servers and Linux workstations
        ├── swap/
        │   ├── swap-setup.sh           # RAM-based swap file and tuning
        │   └── README.md
        └── tailscale/
            ├── tailscale-setup.sh  # Tailscale SSH + firewall (detects Oracle Cloud)
            └── README.md
```

## Features at a Glance

| Feature | Tailscale | Coolify | MinIO | Swap |
|---------|-----------|---------|-------|------|
| Interactive prompts | Yes | Yes | Yes | Yes |
| Auto-install dependencies | Yes | Yes | Yes | N/A |
| Config preservation | No | Yes | Yes | Yes |
| Verification built-in | Yes | Yes | Yes | Yes |
| Resumable | N/A | N/A | Yes | N/A |

## Security Considerations

- Server scripts require root/sudo; workstation setup must run as the normal user
- Credentials stored with restricted permissions (mode 600)
- Tailscale restricts SSH to private network
- Scripts are idempotent (safe to run multiple times)

## License

MIT License - See [LICENSE](LICENSE) for details.

## Resources

- [Tailscale Docs](https://tailscale.com/kb/)
- [Coolify Documentation](https://coolify.io/docs)
- [MinIO Docs](https://min.io/docs/minio/linux/index.html)

## Contributing

Found a bug or have a suggestion? Feel free to open an issue or submit a pull request.
