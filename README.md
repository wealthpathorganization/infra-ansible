# WealthPath Infrastructure - Ansible

Ansible playbooks and deployment configuration for WealthPath.

## Structure

```
├── playbook.yml          # Main deployment playbook
├── inventory.yml         # Server inventory
├── tasks/                # Ansible tasks
│   ├── system.yml        # System setup
│   ├── docker.yml        # Docker installation
│   ├── postgresql.yml    # PostgreSQL setup
│   ├── app.yml           # Application setup
│   ├── config.yml        # Configuration
│   ├── deploy.yml        # Docker Compose deployment
│   ├── health.yml        # Health checks
│   └── backup.yml        # Backup configuration
├── templates/            # Jinja2 templates
├── handlers/             # Ansible handlers
├── scripts/              # Utility scripts
│   ├── backup-db.sh      # Database backup
│   └── restore-db.sh     # Database restore
├── docker-compose.deploy.yaml  # Production compose file
└── Caddyfile             # Caddy web server config
```

## Prerequisites

- Ansible 2.15+
- SSH access to target server
- GitHub Secrets configured

## Usage

### Manual Deployment

```bash
# Set environment variables
export SERVER_IP=your-server-ip
export DOMAIN=your-domain.com
export ADMIN_PASSWORD=your-password

# Run playbook
ansible-playbook playbook.yml
```

### GitHub Actions

Deployment triggers automatically on push to `main`, or manually via:
- Actions → Deploy → Run workflow

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `SERVER_IP` | Target server IP |
| `SSH_PRIVATE_KEY` | SSH key for server access |
| `DOMAIN` | Domain name |
| `ADMIN_PASSWORD` | Admin panel password |
| `GOOGLE_CLIENT_ID` | OAuth - Google |
| `GOOGLE_CLIENT_SECRET` | OAuth - Google |
| `FACEBOOK_APP_ID` | OAuth - Facebook |
| `FACEBOOK_APP_SECRET` | OAuth - Facebook |
| `OPENAI_API_KEY` | AI features |
| `DO_SPACES_KEY` | Backup storage |
| `DO_SPACES_SECRET` | Backup storage |
| `DO_SPACES_BUCKET` | Backup bucket name |
| `DO_SPACES_REGION` | Backup region |

## Backup & Restore

See [docs/BACKUP_RESTORE.md](docs/BACKUP_RESTORE.md) for backup and restore procedures.

### Manual Backup

```bash
ssh root@your-server
/opt/wealthpath/scripts/backup-db.sh daily
```

### Scheduled Backups

Backups run automatically via GitHub Actions:
- Hourly: Every hour, 24h retention
- Daily: 2 AM UTC, 7 day retention
- Weekly: Sunday 3 AM UTC, 30 day retention

## Docker Images

This repo deploys images from:
- `ghcr.io/wealthpathorganization/backend:latest`
- `ghcr.io/wealthpathorganization/frontend:latest`
- `ghcr.io/wealthpathorganization/migrations:latest`
