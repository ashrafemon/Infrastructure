# Backup & Restore Guide

## Overview

The backup system provides automated, timestamped, compressed backups for all critical services:

- **MySQL** - Full database dump (all databases, routines, triggers, events)
- **PostgreSQL** - Global dump (all databases and roles)
- **MongoDB** - BSON dump via mongodump
- **Redis** - RDB snapshot
- **MinIO** - Volume-level tar archive
- **Jenkins** - Volume-level tar archive (`JENKINS_HOME`)
- **Grafana** - Volume-level tar archive

---

## Backup Script

### Usage

```bash
./scripts/backup/backup.sh                    # Backup all services
./scripts/backup/backup.sh mysql              # Backup only MySQL
./scripts/backup/backup.sh mysql postgres     # Backup specific services
./scripts/backup/backup.sh --dry-run          # Preview without backing up
```

### Configuration

`.env` variables:

```bash
BACKUP_DIR=./backups              # Backup destination
BACKUP_RETENTION_DAYS=7           # Days before automatic cleanup
```

### Output

Backups are stored in `BACKUP_DIR` with timestamp naming:

```
backups/
├── mysql_20261201_040000.sql.gz
├── postgres_20261201_040000.sql.gz
├── mongo_20261201_040000.tar.gz
├── redis_20261201_040000.rdb.gz
├── minio_20261201_040000.tar.gz
├── jenkins_20261201_040000.tar.gz
├── grafana_20261201_040000.tar.gz
└── backup_20261201_040000.log
```

### Automate with Cron

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/docker-infrastructure/scripts/backup/backup.sh >> /var/log/infra-backup.log 2>&1

# Backup only databases every 6 hours
0 */6 * * * /path/to/docker-infrastructure/scripts/backup/backup.sh mysql postgres mongo redis
```

### Retention Cleanup

Old backups are automatically removed based on `BACKUP_RETENTION_DAYS`. To manually clean:

```bash
# Remove backups older than 30 days
find ./backups -name "*.gz" -mtime +30 -delete
find ./backups -name "*.rdb.gz" -mtime +30 -delete
```

---

## Restore Script

### Usage

```bash
./scripts/restore/restore.sh                        # List available backups
./scripts/restore/restore.sh mysql ./backups/mysql_20261201_040000.sql.gz
./scripts/restore/restore.sh minio ./backups/minio_20261201_040000.tar.gz
```

### Restoration Notes

| Service    | Method                          | Notes                                    |
|------------|---------------------------------|------------------------------------------|
| MySQL      | mysql CLI pipe                  | Restores all databases                   |
| PostgreSQL | psql CLI pipe                   | Restores all databases and roles         |
| MongoDB    | mongorestore from BSON dump     | Restores all databases                   |
| Redis      | RDB file replacement + restart  | Container restarts after restore         |
| MinIO      | Volume mount + tar extract      | Overwrites entire /data                  |
| Jenkins    | Volume mount + tar extract      | Overwrites entire JENKINS_HOME           |
| Grafana    | Volume mount + tar extract      | Overwrites entire /var/lib/grafana       |

---

## Manual Volume Backups

For services not covered by the script, use `docker run` with `--volumes-from`:

```bash
# Backup RabbitMQ data
docker run --rm \
  --volumes-from rabbitmq \
  -v $(pwd)/backups:/backup \
  alpine:3.21 \
  tar -czf /backup/rabbitmq_$(date +%Y%m%d_%H%M%S).tar.gz /var/lib/rabbitmq

# Restore RabbitMQ data
docker run --rm \
  --volumes-from rabbitmq \
  -v $(pwd)/backups/rabbitmq_file.tar.gz:/backup/restore.tar.gz \
  alpine:3.21 \
  sh -c "rm -rf /var/lib/rabbitmq/* && tar -xzf /backup/restore.tar.gz -C /var/lib/rabbitmq --strip-components=1"
```

---

## Off-site Backup Strategy

### Option 1: rsync to remote server

```bash
rsync -avz --delete ./backups/ user@remote-server:/backups/infrastructure/
```

### Option 2: S3 (using MinIO client or awscli)

```bash
# Install mc
docker run --rm -it --entrypoint sh minio/mc

# Sync to S3
mc alias set s3backup https://s3.amazonaws.com ACCESS_KEY SECRET_KEY
mc mirror ./backups s3backup/bucket-name
```

### Option 3: Rclone

```bash
# Configure rclone
rclone config

# Sync
rclone sync ./backups remote:backup-bucket/infrastructure/
```

---

## Disaster Recovery

In case of complete data loss:

1. Re-create volumes: `docker compose down -v && docker compose up -d`
2. Restore MySQL: `./scripts/restore/restore.sh mysql ./backups/mysql_latest.sql.gz`
3. Restore PostgreSQL: `./scripts/restore/restore.sh postgres ./backups/postgres_latest.sql.gz`
4. Restore MongoDB: `./scripts/restore/restore.sh mongo ./backups/mongo_latest.tar.gz`
5. Restore Redis: `./scripts/restore/restore.sh redis ./backups/redis_latest.rdb.gz`
6. Restore volumes: `./scripts/restore/restore.sh minio ./backups/minio_latest.tar.gz`
7. Restore Jenkins: `./scripts/restore/restore.sh jenkins ./backups/jenkins_latest.tar.gz`
8. Restore Grafana: `./scripts/restore/restore.sh grafana ./backups/grafana_latest.tar.gz`
