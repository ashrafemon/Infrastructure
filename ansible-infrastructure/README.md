# Ansible Infrastructure

Ansible-based deployment for the Docker Infrastructure stack. Installs Docker, deploys the compose stack, configures firewall, schedules backups, and runs health checks.

---

## Directory Structure

```
ansible-infrastructure/
├── ansible.cfg                   # Global Ansible configuration
├── inventory/
│   ├── production.yml            # Production server inventory
│   └── development.yml           # Local / dev inventory
├── group_vars/
│   ├── all.yml                   # Global variables
│   ├── production.yml            # Production overrides
│   ├── development.yml           # Development overrides
│   └── vault.yml                 # Encrypted secrets
├── playbooks/
│   ├── deploy.yml                # Full deploy (bootstrap → stack → healthcheck)
│   ├── update.yml                # Backup → pull images → recreate
│   └── backup.yml                # Manual backup run
└── roles/
    ├── docker/                   # Install Docker Engine + Compose
    ├── env/                      # Generate .env from template
    ├── deploy/                   # Sync files + docker compose up
    ├── firewall/                 # UFW rules
    ├── backup/                   # Cron job for backups
    └── healthcheck/              # Run health-check.sh and report
```

---

## Quick Start

### 1. Install Ansible + Collections

```bash
pip install ansible
ansible-galaxy collection install community.docker
```

### 2. Configure Inventory

Edit `inventory/production.yml` with your server IP and SSH user.

### 3. Configure Secrets

```bash
# Edit vault with your passwords
ansible-vault edit group_vars/vault.yml

# Generate strong passwords for each:
#   openssl rand -base64 32
```

### 4. Deploy

```bash
# Development (local)
ansible-playbook -i inventory/development.yml playbooks/deploy.yml

# Production (remote server)
ansible-playbook -i inventory/production.yml playbooks/deploy.yml --ask-vault-pass
```

---

## Playbooks

| Playbook | Description |
|----------|-------------|
| `deploy.yml` | Full setup: install Docker, configure firewall, sync files, deploy stack, schedule backups, verify health |
| `update.yml` | Safe update: backup → pull new images → recreate containers → health check |
| `backup.yml` | Manual backup run + list recent backup files |

### Tag Filtering

Run specific parts of the deploy playbook:

```bash
# Only install Docker
ansible-playbook playbooks/deploy.yml --tags bootstrap

# Only update .env and redeploy
ansible-playbook playbooks/deploy.yml --tags deploy

# Only run health check
ansible-playbook playbooks/deploy.yml --tags healthcheck
```

---

## Secrets Management

Passwords are stored in `group_vars/vault.yml` encrypted with Ansible Vault:

```bash
# Edit secrets
ansible-vault edit group_vars/vault.yml

# Encrypt (first time)
ansible-vault encrypt group_vars/vault.yml

# Decrypt (for backup)
ansible-vault decrypt group_vars/vault.yml
```

All Ansible commands require `--ask-vault-pass` to decrypt. For automation, use a vault password file (add `.vault_pass` to `.gitignore`):

```bash
echo "your-vault-password" > .vault_pass
chmod 0600 .vault_pass
ansible-playbook playbooks/deploy.yml --vault-password-file .vault_pass
```

---

## Environment Overrides

Edit `group_vars/production.yml` or `group_vars/development.yml`:

```yaml
env_overrides:
  PRODUCTION: "true"
  DB_BIND_ADDRESS: 127.0.0.1:
```

These are injected into the `.env` template at `roles/env/templates/.env.j2`.

---

## First Run vs Updates

- **First run:** `deploy.yml` runs all roles (bootstrap + deploy + healthcheck)
- **Subsequent updates:** `update.yml` runs backup → pull → recreate → healthcheck
- **Quick .env change:** `deploy.yml --tags deploy` (skips Docker install and firewall)
- **Sync only (update files without restart):** `ansible-playbook playbooks/deploy.yml --tags sync`

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `infra_dir` | `/opt/docker-infrastructure` | Server path for compose files |
| `infra_domain` | `example.com` | Domain for email and SSL |
| `deploy_profile` | `production` | Compose profile (production/development) |
| `timezone` | `UTC` | Container timezone |
| `backup_retention_days` | `7` | Days to keep backups |
| `docker_compose_version` | `v2.32.4` | Docker Compose plugin version |
