# Upgrade Guide

## Safe Version Upgrade Procedure

### Step 1: Backup Everything

```bash
./scripts/backup/backup.sh
```

### Step 2: Review Release Notes

Before upgrading any service:

1. Check the upstream image changelog/release notes
2. Note any breaking changes or migration steps
3. Verify compatibility with dependent services

### Step 3: Pull the New Image

```bash
# Pull a specific version
docker compose pull mysql

# Test run without replacing the container
docker compose create mysql
```

### Step 4: Recreate the Service

```bash
# Graceful replacement
docker compose up -d mysql --force-recreate

# Check logs immediately
docker compose logs --tail=50 mysql
```

### Step 5: Verify Health

```bash
# Check health status
./scripts/health-check/health-check.sh mysql

# Check service logs for errors
docker compose logs --tail=100 mysql | grep -i error

# Run application integration tests
```

---

## Database Version Upgrades

### Major MySQL Version Upgrade

```bash
# 1. Backup
./scripts/backup/backup.sh mysql

# 2. Stop MySQL
docker compose stop mysql

# 3. Create a data dump for safety
docker run --rm --volumes-from mysql -v $(pwd):/backup \
  alpine tar -czf /backup/mysql-data-pre-upgrade.tar.gz /var/lib/mysql

# 4. Update image version in compose file
# Edit docker-infrastructure/compose/databases.yml

# 5. Start with new version
docker compose up -d mysql

# 6. Run mysql_upgrade if needed
docker exec mysql mysql_upgrade -u root -p"${MYSQL_ROOT_PASSWORD}"

# 7. Verify
docker compose logs mysql
./scripts/health-check/health-check.sh mysql
```

### Major PostgreSQL Version Upgrade

```bash
# Use pg_upgrade or dump/restore:
# 1. Backup
./scripts/backup/backup.sh postgres

# 2. Dump all data
docker exec postgres pg_dumpall -U app_user > /tmp/postgres_dump.sql

# 3. Stop and remove old container
docker compose down postgres

# 4. Update version in compose file

# 5. Start fresh container
docker compose up -d postgres

# 6. Restore data
cat /tmp/postgres_dump.sql | docker exec -i postgres psql -U app_user
```

---

## Updating Image Versions

### Step-by-Step for Any Service

```bash
# 1. Identify current version
docker inspect mysql | jq '.[].Config.Image'

# 2. Update the version tag in the compose file
# Edit: compose/databases.yml → change image: mysql:X.Y.Z

# 3. Pull the new image
docker compose pull mysql

# 4. Recreate the container
docker compose up -d mysql --force-recreate

# 5. Verify
docker compose ps
./scripts/health-check/health-check.sh mysql
```

### Batch Updates (with Caution)

```bash
# Update all non-database service images
docker compose pull

# Recreate all services
docker compose up -d --force-recreate
```

---

## Watchtower

### Safely Using Watchtower

Watchtower is configured with `WATCHTOWER_LABEL_ENABLE: "true"`, meaning it **only updates containers with the label**:

```yaml
com.centurylinklabs.watchtower.enable=true
```

### Add Watchtower label to a service

```yaml
services:
  my-app:
    image: my-app:1.2.3
    labels:
      com.centurylinklabs.watchtower.enable: "true"
```

**Database services (MySQL, PostgreSQL, MongoDB, Redis) do NOT have this label.** Stateful services must be upgraded manually after backup.

---

## Version Tracking

### Document Current Versions

Keep a record of deployed versions:

```bash
# Save current versions
docker ps --format "table {{.Names}}\t{{.Image}}" > versions-$(date +%Y%m%d).txt

# Compare with previous
diff versions-20261201.txt versions-20261215.txt
```

### Rollback Plan

Always have a rollback plan:

1. **Before upgrade:** Run backup
2. **If upgrade fails:** `docker compose down <service>`
3. Revert the image tag in the compose file
4. `docker compose up -d <service>`
5. If data migration was required, restore from backup

---

## Service-Specific Upgrade Notes

### RabbitMQ

```bash
# Check for version compatibility first
# RabbitMQ requires careful version upgrades (skip incompatible versions)

# Backup definitions
docker exec rabbitmq rabbitmqadmin export /tmp/definitions.json
docker cp rabbitmq:/tmp/definitions.json ./backups/

# Upgrade
docker compose pull rabbitmq
docker compose up -d rabbitmq --force-recreate
```

### MinIO

```bash
# MinIO upgrades are generally safe
# Backup data first
./scripts/backup/backup.sh minio

# Upgrade
docker compose pull minio
docker compose up -d minio --force-recreate
```

### Jenkins

```bash
# Backup JENKINS_HOME first
./scripts/backup/backup.sh jenkins

# Jenkins plugin compatibility is the main concern
# Check https://plugins.jenkins.io/ for each plugin's supported Jenkins version

# Upgrade
docker compose pull jenkins
docker compose up -d jenkins --force-recreate
```

---

## Maintenance Window Checklist

- [ ] Notify stakeholders of maintenance window
- [ ] Run full backup (`./scripts/backup/backup.sh`)
- [ ] Verify backups are valid (check file sizes, test restore on staging)
- [ ] Pull new images (`docker compose pull`)
- [ ] Perform upgrade (`docker compose up -d --force-recreate`)
- [ ] Run health checks (`./scripts/health-check/health-check.sh`)
- [ ] Verify application functionality
- [ ] Monitor logs for 15 minutes post-upgrade
- [ ] Update version documentation
