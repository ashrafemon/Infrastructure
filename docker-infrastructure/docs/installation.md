# Installation Guide

## Prerequisites

- **Docker Engine** 24.0+ (with Compose v2.20+ for `include` support)
- **Git** (optional, for version control)
- **Minimum 4 GB RAM** (8 GB+ recommended for full stack)
- **20 GB free disk space** (SSD preferred for databases)

### Install Docker

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Verify
docker --version
docker compose version
```

---

## Step 1: Clone or Copy

```bash
# If using git
git clone <your-repo-url> docker-infrastructure
cd docker-infrastructure

# Or copy the directory to your server
```

## Step 2: Environment Configuration

```bash
cp .env.example .env
```

Edit `.env` with strong passwords:

```bash
nano .env
```

**Important:** Change ALL default passwords. Use a password generator:

```bash
openssl rand -base64 32
```

## Step 3: Create Required Directories

```bash
# Config directories are already present in the repo
# Create backup directory
mkdir -p backups
```

## Step 4: Start the Infrastructure

### Start Everything

```bash
docker compose up -d
```

### Start Specific Stack

```bash
docker compose up -d databases
docker compose up -d monitoring
docker compose up -d proxy
```

### Check Status

```bash
docker compose ps
./scripts/health-check/health-check.sh
```

---

## Initial Access

| Service          | URL                        | Default Credentials                          |
|------------------|----------------------------|----------------------------------------------|
| NPM Admin        | http://YOUR_IP:81          | admin@example.com / changeme                 |
| phpMyAdmin       | http://YOUR_IP:8081        | Use MySQL credentials from .env              |
| pgAdmin          | http://YOUR_IP:5050        | Set in PGADMIN_DEFAULT_EMAIL/PASSWORD        |
| RedisInsight     | http://YOUR_IP:5540        | Use Redis password from .env                 |
| RabbitMQ UI      | http://YOUR_IP:15672       | Set in RABBITMQ_USER/RABBITMQ_PASSWORD       |
| MinIO Console    | http://YOUR_IP:9001        | Set in MINIO_ROOT_USER/MINIO_ROOT_PASSWORD   |
| Mailpit UI       | http://YOUR_IP:8025        | No auth required                             |
| Prometheus       | http://YOUR_IP:9090        | No auth (firewalled)                         |
| Grafana          | http://YOUR_IP:3000        | Set in GF_SECURITY_ADMIN_USER/PASSWORD       |
| Netdata          | http://YOUR_IP:19999       | No auth (firewalled)                         |
| Uptime Kuma      | http://YOUR_IP:3001        | Create on first login                        |
| Jenkins          | http://YOUR_IP:8080        | Initial password in container logs           |
| Arcane           | http://YOUR_IP:3552        | Create on first login                        |

---

## Verifying Health

```bash
# Quick health check (all services)
./scripts/health-check/health-check.sh

# JSON output for monitoring systems
./scripts/health-check/health-check.sh --json

# Check specific services
./scripts/health-check/health-check.sh mysql redis rabbitmq

# Docker compose ps
docker compose ps
```

---

## Logs

```bash
# All services
docker compose logs --tail=100 -f

# Specific service
docker compose logs --tail=50 -f mysql

# Query logs via Loki (if Grafana is set up)
# Navigate to Grafana > Explore > Loki datasource
```
