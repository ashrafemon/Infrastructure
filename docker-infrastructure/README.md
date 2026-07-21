# Docker Infrastructure

Production-ready Docker Compose infrastructure for Laravel, NestJS, NextJS, React, mobile APIs, SaaS multi-tenant platforms, and enterprise applications.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          frontend_network                                 │
│                                                                          │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │    NPM     │  │  phpMyAdmin  │  │   pgAdmin    │  │  RedisInsight │ │
│  │  80/81/443 │  │    8081      │  │    5050      │  │    5540       │ │
│  └─────┬──────┘  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘ │
│        │                │                  │                  │         │
│  ┌─────┴──────┐  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐ │
│  │   Jenkins  │  │  Uptime Kuma │  │    Arcane    │  │  MinIO       │ │
│  │    8080    │  │    3001      │  │    3552      │  │  9000/9001   │ │
│  └────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                                          │
│                            backend_network (internal)                    │
│                                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │  MySQL   │  │PostgreSQL│  │ MongoDB  │  │  Redis   │  │ RabbitMQ │ │
│  │  8.0     │  │  18      │  │  8.0     │  │  7.4     │  │  4.1     │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘ │
│                                                                          │
│  ┌──────────┐  ┌──────────┐                                              │
│  │  MinIO   │  │ CrowdSec │                                              │
│  │ S3 Store │  │ IPS/IDS  │                                              │
│  └──────────┘  └──────────┘  └──────────┘                               │
│                                                                          │
│                          monitoring_network                              │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                   │
│  │  Prometheus  │  │   Grafana    │  │    Loki      │                   │
│  │    9090      │  │    3000      │  │    3100      │                   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                   │
│         │                 │                  │                           │
│  ┌──────┴───────┐  ┌──────┴───────┐                                    │
│  │  Promtail    │  │   Netdata    │                                    │
│  │  (log agent) │  │   19999      │                                    │
│  └──────────────┘  └──────────────┘                                    │
│                                                                          │
│                            mail_network                                  │
│                                                                          │
│  ┌────────────────────────────────────┐                                 │
│  │            Postfix                 │                                 │
│  │     SMTP Relay / Outbound Mail     │                                 │
│  │      25 (SMTP)  587 (Submission)   │                                 │
│  │      465 (SMTPS)                   │                                 │
│  └────────────────────────────────────┘                                 │
└──────────────────────────────────────────────────────────────────────────┘

> **Profile note:** Monitoring, security, CI/CD, management stack and Postfix require `--profile production`.
> Mailpit (dev email capture) requires `--profile development`.
> Core services (databases, proxy, storage, messaging) start without any profile.

## Quick Start

### 1. Clone & Configure

```bash
git clone <repo-url> docker-infrastructure
cd docker-infrastructure
cp .env.example .env
```

### 2. Configure .env

```bash
# Generate all passwords
./scripts/generate-env.sh

# For production, also set these in .env:
#   PRODUCTION=true
#   DB_BIND_ADDRESS=127.0.0.1:
```

Regenerate a single password later (if compromised):
```bash
./scripts/generate-env.sh mysql          # MySQL only
./scripts/generate-env.sh redis grafana  # Multiple specific ones
```

### 3. Choose Your Mode

**Development** — core services + Mailpit (SMTP capture):
```bash
docker compose --profile development up -d
```

**Production** — full stack with monitoring, security, CI/CD, Postfix:
```bash
# In .env: set PRODUCTION=true, DB_BIND_ADDRESS=127.0.0.1:
docker compose --profile production up -d
```



### 4. Start Only What You Need

```bash
# Database server (master + replicas + management UIs)
docker compose up -d mysql mysql-replica postgres postgres-replica \
  mongo redis phpmyadmin pgadmin redisinsight

# Monitoring server
docker compose --profile production up -d prometheus grafana loki promtail netdata

# Security server
docker compose --profile production up -d crowdsec uptime-kuma

# CI/CD server
docker compose --profile production up -d jenkins

# App backend (if apps need queue + storage + email)
docker compose up -d mysql redis rabbitmq minio \
  && docker compose --profile production up -d postfix

# Full web server (proxy + all management UIs)
docker compose up -d nginx-proxy-manager phpmyadmin pgadmin redisinsight

# Minimal production (databases + proxy + queue)
docker compose up -d mysql postgres mongo redis nginx-proxy-manager rabbitmq minio
```

### 5. Verify Health

```bash
./scripts/health-check/health-check.sh
```

### 5. What's Next

| Step | Action | Doc |
|------|--------|-----|
| Access NPM | `http://YOUR_IP:81` (admin@example.com / changeme) | [cloudflare-ssl.md](docs/cloudflare-ssl.md) |
| Bind subdomains | Create proxy hosts in NPM for each service | [cloudflare-ssl.md](docs/cloudflare-ssl.md) |
| Create databases | Use phpMyAdmin (`:8081`) or pgAdmin (`:5050`) | — |
| Configure email | Set Postfix relay or use Mailpit UI (`:8025`) | [postfix.md](docs/postfix.md) |
| Connect backend apps | Read credentials from `.env` or Docker network | — |
| Schedule backups | Add cron job for `./scripts/backup/backup.sh` | [backup.md](docs/backup.md) |
| Hardening | Firewall, CrowdSec bouncers, Grafana alerts | [security.md](docs/security.md) |

## Service Overview

### Databases (`compose/databases.yml`)
| Service          | Version     | Port  | Description                                |
|------------------|-------------|-------|--------------------------------------------|
| MySQL            | 8.0.41      | 3306  | Primary relational database                 |
| MySQL Replica    | 8.0.41      | 3307  | Read replica (auto-setup)                  |
| PostgreSQL       | 18.4        | 5432  | Advanced relational database               |
| PostgreSQL Replica | 18.4      | 5433  | Hot standby (auto-setup)                   |
| MongoDB          | 8.0.15      | 27017 | NoSQL document database                    |
| Redis            | 7.4.5-alpine| 6379  | In-memory cache, session store, queue      |

### Database Management (`compose/databases-ui.yml`)
| Service      | Version  | Port  | Description                  |
|--------------|----------|-------|------------------------------|
| phpMyAdmin   | 5.2.2    | 8081  | MySQL web UI                 |
| pgAdmin      | 9.6      | 5050  | PostgreSQL web UI            |
| RedisInsight | 2.70     | 5540  | Redis web UI                 |

### Messaging (`compose/messaging.yml`)
| Service  | Version | Ports         | Description                    |
|----------|---------|---------------|--------------------------------|
| RabbitMQ | 4.1     | 5672 / 15672  | Message broker + management UI |

### Object Storage (`compose/storage.yml`)
| Service | Version                         | Ports        | Description              |
|---------|---------------------------------|--------------|--------------------------|
| MinIO   | 2025-06-13T11-33-47Z            | 9000 / 9001  | S3-compatible storage    |

### Email (`compose/mail.yml`)
| Service       | Profile       | Version | Ports          | Description                           |
|---------------|---------------|---------|----------------|---------------------------------------|
| Postfix       | production    | v3.7.0  | 25 / 587 / 465 | Production SMTP relay                 |
| Mailpit       | development   | v1.21   | 1025 / 8025    | Development SMTP capture + web UI     |

### Monitoring (`compose/monitoring.yml`) — profile: production
| Service   | Version | Ports  | Description                          |
|-----------|---------|--------|--------------------------------------|
| Prometheus| v3.5.0  | 9090   | Metrics collection and alerting      |
| Grafana   | 12.0.2  | 3000   | Metrics visualization & dashboards   |
| Loki      | 3.5.0   | 3100   | Log aggregation                      |
| Promtail  | 3.5.0   | -      | Docker log collector → Loki          |
| Netdata   | v2.4.0  | 19999  | Real-time performance monitoring     |

### Reverse Proxy (`compose/proxy.yml`)
| Service             | Version | Ports       | Description                         |
|---------------------|---------|-------------|-------------------------------------|
| Nginx Proxy Manager | 2.12.3  | 80 / 81 / 443 | SSL termination + reverse proxy   |

### Security (`compose/security.yml`) — profile: production
| Service    | Version | Ports | Description                             |
|------------|---------|-------|-----------------------------------------|
| CrowdSec   | v1.6.8  | -     | IPS/IDS with collaborative IP reputation|
| Uptime Kuma| 1.23.16 | 3001  | Uptime monitoring                       |

### CI/CD (`compose/cicd.yml`) — profile: production
| Service | Version           | Ports       | Description                |
|---------|-------------------|-------------|----------------------------|
| Jenkins | 2.504.1-lts-jdk21 | 8080 / 50000| Automation server          |

### Management (`compose/management.yml`) — profile: production
| Service    | Version | Ports | Description                    |
|------------|---------|-------|--------------------------------|
| Arcane     | 1.10.0  | 3552  | Docker management dashboard    |
| Watchtower | 1.7.1   | -     | Automated container updates    |

## Profiles

Services are organized into profiles — start only what you need:

| Profile | Services | Command |
|---------|----------|---------|
| _(none)_ | mysql, postgres, mongo, redis, phpmyadmin, pgadmin, redisinsight, rabbitmq, minio, nginx-proxy-manager | `docker compose up -d` |
| **development** | _(above)_ + mailpit | `docker compose --profile development up -d` |
| **production** | _(above)_ + postfix, prometheus, grafana, loki, promtail, netdata, crowdsec, uptime-kuma, jenkins, arcane, watchtower | `docker compose --profile production up -d` |

Services without a profile always start. Multiple profiles can be combined:
```bash
docker compose --profile production --profile development up -d
```

## Environment Modes

The `PRODUCTION` and `DB_BIND_ADDRESS` variables in `.env` control security boundaries:

| Variable | Dev default | Production setting | Effect |
|----------|-------------|--------------------|--------|
| `PRODUCTION=false` | ← default | Change to `true` | `backend_network.internal` disabled in dev, enabled in prod |
| `DB_BIND_ADDRESS=` | ← default | `127.0.0.1:` | Empty = ports on `0.0.0.0`, set = restrict to localhost |

In development, databases bind to `0.0.0.0` so applications running on the host can connect directly. In production, they bind to `127.0.0.1` and the backend network is isolated.

## Networks

| Network            | Driver | Internal (dev/prod) | Purpose                                    |
|--------------------|--------|---------------------|--------------------------------------------|
| frontend_network   | bridge | No / No             | Public-facing services, proxy              |
| backend_network    | bridge | No / **Yes**        | Databases, message broker, internal services|
| monitoring_network | bridge | No / No             | Prometheus, Grafana, Loki, Netdata         |
| mail_network       | bridge | No / No             | Email services                             |

`backend_network.internal` is toggled by `PRODUCTION` — open in dev, isolated in prod.

## Persistent Volumes

All data is persisted in Docker volumes (named, not host bind mounts):

| Volume            | Used By                           |
|-------------------|-----------------------------------|
| mysql_data        | MySQL                             |
| postgres_data     | PostgreSQL                        |
| mongo_data        | MongoDB                           |
| redis_data        | Redis                             |
| pgadmin_data      | pgAdmin                           |
| redisinsight_data | RedisInsight                      |
| rabbitmq_data     | RabbitMQ                          |
| minio_data        | MinIO                             |
| nginx_proxy_data  | Nginx Proxy Manager (config)      |
| nginx_proxy_ssl   | Nginx Proxy Manager (SSL certs)   |
| prometheus_data   | Prometheus                        |
| grafana_data      | Grafana                           |
| loki_data         | Loki                              |
| netdata_data         | Netdata                        |
| crowdsec_config_data | CrowdSec (config)               |
| crowdsec_log_data    | CrowdSec (logs)                 |
| uptime_kuma_data     | Uptime Kuma                    |
| jenkins_home         | Jenkins                        |
| arcane_data          | Arcane                         |
| postfix_spool_data   | Postfix (spool)                |
| postfix_config_data  | Postfix (config)               |
| mailpit_data         | Mailpit (dev only)             |
| mysql_replica_data   | MySQL Replica                  |
| postgres_replica_data | PostgreSQL Replica            |

## Usage

### Start Services

```bash
# Start core services (databases, proxy, dev tools)
docker compose --profile development up -d

# Start production stack (includes monitoring, security, CI/CD, SMTP)
docker compose --profile production up -d

# Start specific stacks (profile-agnostic)
docker compose --profile production up -d databases

# Start specific service
docker compose up -d mysql
```

Services without a profile start regardless of `--profile` flag.

### Stop Services

```bash
# Stop everything
docker compose down

# Stop everything and remove volumes (WARNING: destroys data)
docker compose down -v

# Stop specific service
docker compose stop mysql
```

### View Logs

```bash
# All services
docker compose logs --tail=100 -f

# Specific service
docker compose logs --tail=50 -f nginx-proxy-manager
```

### Execute Commands

```bash
# MySQL
docker exec -it mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}"

# PostgreSQL
docker exec -it postgres psql -U ${POSTGRES_USER:-app_user}

# MongoDB
docker exec -it mongo mongosh -u root -p"${MONGO_INITDB_ROOT_PASSWORD}"

# Redis
docker exec -it redis redis-cli -a "${REDIS_PASSWORD}"

# RabbitMQ
docker exec -it rabbitmq rabbitmqadmin list queues
```

## Backup & Restore

### Automated Backups

```bash
# Backup all services
./scripts/backup/backup.sh

# Backup specific services
./scripts/backup/backup.sh mysql postgres

# Dry run (preview)
./scripts/backup/backup.sh --dry-run
```

### Restore

```bash
# List available backups
./scripts/restore/restore.sh

# Restore specific service
./scripts/restore/restore.sh mysql ./backups/mysql_20261201_040000.sql.gz
```

See [docs/backup.md](docs/backup.md) for detailed backup and restore instructions.

## Database Replication

Both MySQL and PostgreSQL have automatic read replicas:

| Service | Type | Port | Replicates from |
|---------|------|------|----------------|
| `mysql-replica` | MySQL read replica | 3307 | `mysql` (master) |
| `postgres-replica` | PostgreSQL hot standby | 5433 | `postgres` (primary) |

### Automatic Setup

On first start:
1. **Master/Primary** creates replication user and slot via init scripts
2. **Replica/Standby** waits for master to be healthy (`depends_on`)
3. **MySQL replica** — init script runs `CHANGE REPLICATION SOURCE TO` + `START REPLICA`
4. **PostgreSQL standby** — init script runs `pg_basebackup` to clone data, creates `standby.signal`

### Verification

```bash
# MySQL — check replica status
docker exec mysql-replica mysql -u root -p"${MYSQL_ROOT_PASSWORD}" \
  -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running|Replica_SQL_Running"

# PostgreSQL — check if standby is receiving
docker exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### Connection Strings

| Role | Host | Port | User | Password from |
|------|------|------|------|---------------|
| MySQL master | `mysql` | 3306 | `root` | `MYSQL_ROOT_PASSWORD` |
| MySQL replica | `mysql-replica` | 3307 | `root` | `MYSQL_ROOT_PASSWORD` |
| PostgreSQL primary | `postgres` | 5432 | `postgres` | `POSTGRES_PASSWORD` |
| PostgreSQL standby | `postgres-replica` | 5433 | `postgres` | `POSTGRES_PASSWORD` |

## Subdomain Binding

All web services are exposed via Nginx Proxy Manager at `https://subdomain.yourdomain.com`.

| Subdomain | Service | Port |
|-----------|---------|------|
| `grafana.yourdomain.com` | Grafana | 3000 |
| `jenkins.yourdomain.com` | Jenkins | 8080 |
| `db.yourdomain.com` | phpMyAdmin | 80 |
| `pgadmin.yourdomain.com` | pgAdmin | 80 |
| `mq.yourdomain.com` | RabbitMQ | 15672 |
| `minio.yourdomain.com` | MinIO Console | 9001 |
| `s3.yourdomain.com` | MinIO S3 API | 9000 |
| `status.yourdomain.com` | Uptime Kuma | 3001 |
| `docker.yourdomain.com` | Arcane | 3552 |

Full setup guide: [docs/cloudflare-ssl.md](docs/cloudflare-ssl.md).

## Health Checks

```bash
# Check all services
./scripts/health-check/health-check.sh

# JSON output for automation
./scripts/health-check/health-check.sh --json

# Check specific services
./scripts/health-check/health-check.sh mysql redis rabbitmq
```

## Security

See [docs/security.md](docs/security.md) for the full security checklist.

### Quick Security Wins

1. Change all default passwords in `.env`
2. Bind management UIs to `127.0.0.1` only
3. Enable UFW/iptables firewall
4. Deploy CrowdSec for IPS/IDS
5. Use Nginx Proxy Manager for SSL termination
6. Restrict Watchtower to label-based updates only

## Updating Versions

See [docs/upgrade.md](docs/upgrade.md) for detailed upgrade procedures.

```bash
# Safe upgrade pattern for any service
./scripts/backup/backup.sh <service>
docker compose pull <service>
docker compose up -d <service> --force-recreate
./scripts/health-check/health-check.sh <service>
```

## Updating Watchtower-Managed Images

Watchtower only updates containers with the label:
```yaml
com.centurylinklabs.watchtower.enable: "true"
```

**Stateful services (databases, storage, mail) are excluded** from automatic updates.

## Email

Two options, selected by profile:

### Production: Postfix (`--profile production`)

Lightweight SMTP relay/outbound mail server. Send directly or relay through SendGrid, Mailgun, AWS SES.

```bash
POSTFIX_HOSTNAME=mail.yourdomain.com
POSTFIX_RELAYHOST=smtp.sendgrid.net:587
POSTFIX_SMTP_USER=apikey
POSTFIX_SMTP_PASSWORD=<your-key>
```

See [docs/postfix.md](docs/postfix.md).

### Development: Mailpit (`--profile development`)

SMTP capture server — intercepts all outgoing email and displays them in a web UI at `http://localhost:8025`. No real emails are sent.

| Setting | Value |
|---------|-------|
| SMTP host | `mailpit` |
| SMTP port | `1025` |
| Web UI | `http://localhost:8025` |

## Credentials

All passwords are in `.env`. This single file is used in both development and production:

```bash
cp .env.example .env
./scripts/generate-env.sh
```

Your backend projects connect to infrastructure services using the Docker network:
- **Host:** The service name (e.g., `mysql`, `redis`, `rabbitmq`)
- **Port:** The container port (e.g., `3306`, `6379`, `5672`)
- **User/Password:** From `.env`

The `.env` file is gitignored — never committed to the repository. On production servers, set file permissions to `chmod 0600 .env`.

## Production Checklist

Before going live, verify each:

- [ ] **Passwords** — ran `./scripts/generate-env.sh`
- [ ] **.env** — `PRODUCTION=true`, `DB_BIND_ADDRESS=127.0.0.1:`
- [ ] **Firewall** — UFW/iptables configured (see [docs/security.md](docs/security.md))
- [ ] **SSH** — key-only authentication, password auth disabled
- [ ] **SSL** — wildcard cert issued in NPM via Cloudflare DNS challenge
- [ ] **Subdomains** — proxy hosts created in NPM for all services
- [ ] **CrowdSec** — running with nginx bouncer configured
- [ ] **Backups** — cron job set for `./scripts/backup/backup.sh`
- [ ] **Off-site backups** — rsync/rclone to remote storage
- [ ] **Grafana alerts** — configured for CPU, disk, service health
- [ ] **Postfix DNS** — SPF, DKIM, reverse PTR records set
- [ ] **Health checks** — `./scripts/health-check/health-check.sh` shows all green
- [ ] **Log shipping** — Grafana → Explore → Loki shows container logs
- [ ] **Docker metrics** — daemon flag `--metrics-addr 0.0.0.0:9323` enabled
- [ ] **Node exporter** — running on host for Prometheus host metrics
- [ ] **Image scanning** — `docker scout` or Trivy scan scheduled

## Project Structure

```
docker-infrastructure/
├── docker-compose.yml          # Main compose file (includes all stacks)
├── .env.example                # Environment template
├── compose/                    # Service stack definitions
│   ├── databases.yml
│   ├── databases-ui.yml
│   ├── messaging.yml
│   ├── storage.yml
│   ├── mail.yml
│   ├── monitoring.yml
│   ├── proxy.yml
│   ├── security.yml
│   ├── cicd.yml
│   └── management.yml
├── configs/                    # Service configuration files
│   ├── prometheus/prometheus.yml
│   ├── grafana/provisioning/datasources/
│   ├── grafana/provisioning/dashboards/
│   ├── loki/loki.yml
│   ├── promtail/promtail.yml
│   ├── crowdsec/acquis.yaml
│   └── nginx/security-headers.conf
├── scripts/                    # Operational scripts
│   ├── backup/backup.sh
│   ├── backup/backup.sh
│   ├── restore/restore.sh
│   ├── health-check/health-check.sh
│   └── generate-env.sh
└── docs/                       # Documentation
    ├── installation.md
    ├── backup.md
    ├── monitoring.md
    ├── security.md
    ├── upgrade.md
    ├── cloudflare-ssl.md
    ├── postfix.md
    └── mailcow.md
```

## License

This infrastructure is provided as-is. Use at your own risk. Always test upgrades in a staging environment before applying to production.
