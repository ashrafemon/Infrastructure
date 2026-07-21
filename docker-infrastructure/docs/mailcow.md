# Mailcow Deployment Guide

## Overview

Mailcow is integrated into the main Docker Compose stack via `compose/mail.yml`. It provides a full mail server suite (SMTP, IMAP, POP3, Webmail, anti-spam, antivirus) running in the infrastructure alongside your applications.

---

## Architecture

```
              mail_network
  ┌──────────────────────────────────────────┐
  │  mariadb-mailcow    redis-mailcow        │
  │  postfix-mailcow    dovecot-mailcow      │
  │  rspamd-mailcow     clamd-mailcow        │
  │  unbound-mailcow    olefy-mailcow        │
  │  sogo-mailcow       php-fpm-mailcow      │
  │  nginx-mailcow      watchdog-mailcow     │
  │  acme-mailcow                            │
  └──────────────────────────────────────────┘
          │
          │ (via NPM proxy on port 8989 → 443)
          ▼
      frontend_network → nginx-proxy-manager
```

---

## Prerequisites

- **DNS control** for the mail domain (e.g., `example.com`)
- **Reverse DNS (PTR record)** set by your hosting provider
- **Port 25 unblocked** by your hosting provider
- **Cloudflare API Token** (for SSL via DNS challenge)

---

## Required DNS Records

Create these in Cloudflare DNS (grey cloud / DNS only for MX, TXT, A):

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | mail | Your server IP | DNS |
| A | autodiscover | Your server IP | DNS |
| A | autoconfig | Your server IP | DNS |
| MX | @ | mail.yourdomain.com (priority 10) | DNS |
| TXT | @ | v=spf1 mx include:spf.yourdomain.com ~all | DNS |
| TXT | _dmarc | v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com | DNS |
| CNAME | imap | mail.yourdomain.com | DNS |
| CNAME | smtp | mail.yourdomain.com | DNS |
| CNAME | pop3 | mail.yourdomain.com | DNS |

**Important:** Set all records to **DNS only** (grey cloud). Do NOT proxy mail traffic through Cloudflare.

---

## Initial Setup

### Step 1: Configure Environment

Edit `.env`:

```bash
# Mailcow hostname
MAILCOW_HOSTNAME=mail.yourdomain.com

# Database credentials (auto-generated, but set explicitly for consistency)
MAILCOW_DB_ROOT_PASSWORD=<strong-password>
MAILCOW_DB_NAME=mailcow
MAILCOW_DB_USER=mailcow
MAILCOW_DB_PASSWORD=<strong-password>

# SSL via Let's Encrypt with Cloudflare DNS challenge
CLOUDFLARE_EMAIL=admin@yourdomain.com
CLOUDFLARE_API_TOKEN=<your-cloudflare-api-token>
MAILCOW_ACME_ACCOUNT=admin@yourdomain.com
```

### Step 2: Start Mailcow

```bash
# Start the full stack (including mail)
docker compose up -d

# Start only mail services
docker compose up -d --wait mariadb-mailcow redis-mailcow
docker compose up -d --wait postfix-mailcow dovecot-mailcow
docker compose up -d --wait rspamd-mailcow clamd-mailcow
docker compose up -d unbound-mailcow acme-mailcow php-fpm-mailcow sogo-mailcow nginx-mailcow watchdog-mailcow olefy-mailcow
```

### Step 3: Configure Nginx Proxy Manager

1. Access NPM at `http://YOUR_IP:81`
2. Create a proxy host for `mail.yourdomain.com`:
   - **Scheme**: `https`
   - **Forward IP/Hostname**: `nginx-mailcow`
   - **Port**: `8443`
   - **SSL**: Get a Let's Encrypt certificate (use Cloudflare DNS challenge)
   - **Force SSL**: On
   - **HSTS**: Enabled

### Step 4: Access Web Admin

```
https://mail.yourdomain.com
```

Default admin: `admin` (password set during first login setup)

---

## Post-Installation

### Generate DKIM Keys

```bash
# Generate DKIM key pair inside the rspamd container
docker exec -it rspamd-mailcow rspamadm dkim_keygen \
  -d yourdomain.com -s mail 2>/dev/null

# Copy the public key
docker exec -it rspamd-mailcow cat /etc/rspamd/dkim/mail.txt
```

Add the DKIM TXT record to Cloudflare DNS:

```
TXT | mail._domainkey | v=DKIM1; h=sha256; k=rsa; p=MIGfMA0GCSqGSIb... (the full key)
```

### Test Email Flow

```bash
# Using swaks (install first: apt install swaks)
swaks -t test@example.com -f admin@yourdomain.com \
  -s mail.yourdomain.com -p 587 -tls \
  -au admin@yourdomain.com -ap "your-password"
```

### Configure SPF

```
v=spf1 mx include:spf.yourdomain.com -all
```

### Configure DMARC

```
_dmarc.yourdomain.com TXT
"v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com; ruf=mailto:dmarc-report@yourdomain.com; fo=1; pct=100"
```

---

## Port Reference

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 25 | postfix-mailcow | SMTP | Inbound mail |
| 143 | dovecot-mailcow | IMAP | Unencrypted (STARTTLS) |
| 587 | postfix-mailcow | Submission | Client outbound (STARTTLS) |
| 993 | dovecot-mailcow | IMAPS | Encrypted IMAP |
| 995 | dovecot-mailcow | POP3S | Encrypted POP3 |
| 8989 | nginx-mailcow | HTTPS | Internal web UI (proxied via NPM to 443) |

---

## Backup

### Database & Configuration

```bash
# Backup MariaDB (Mailcow internal DB)
docker exec mariadb-mailcow mysqldump \
  --all-databases \
  -u root -p"${MAILCOW_DB_ROOT_PASSWORD}" | gzip \
  > ./backups/mailcow_db_$(date +%Y%m%d).sql.gz

# Backup mail data (vmail volume)
docker run --rm \
  --volumes-from postfix-mailcow \
  -v $(pwd)/backups:/backup \
  alpine:3.21 \
  tar -czf /backup/mailcow_vmail_$(date +%Y%m%d).tar.gz /var/vmail

# Backup all mailcow volumes
for vol in mariadb_mailcow_data redis_mailcow_data postfix_mailcow_data \
  dovecot_mailcow_data rspamd_mailcow_data clamd_mailcow_data \
  unbound_mailcow_data nginx_mailcow_data php_fpm_mailcow_data \
  sogo_mailcow_data acme_mailcow_data vmail_mailcow_data; do
  docker run --rm -v $vol:/data -v $(pwd)/backups:/backup \
    alpine:3.21 tar -czf /backup/${vol}_$(date +%Y%m%d).tar.gz /data
done
```

### Automated Backup (Cron)

```bash
0 3 * * * /path/to/mailcow-backup.sh >> /var/log/mailcow-backup.log 2>&1
```

---

## Upgrade

```bash
# 1. Backup first
./scripts/backup/backup.sh

# 2. Pull new images
docker compose pull postfix-mailcow dovecot-mailcow rspamd-mailcow

# 3. Recreate services
docker compose up -d --force-recreate postfix-mailcow dovecot-mailcow rspamd-mailcow

# 4. Verify
./scripts/health-check/health-check.sh postfix-mailcow dovecot-mailcow
```

---

## Troubleshooting

### Check Logs

```bash
# Postfix logs
docker compose logs --tail=50 postfix-mailcow

# Dovecot logs
docker compose logs --tail=50 dovecot-mailcow

# Rspamd stats
docker exec -it rspamd-mailcow rspamadm stat

# View mail queue
docker exec -it postfix-mailcow postqueue -p
```

### Restart All Mail Services

```bash
docker compose restart postfix-mailcow dovecot-mailcow rspamd-mailcow
```

### Reset Admin Password

```bash
docker exec -it php-fpm-mailcow /opt/mailcow-cli/admin --reset admin
```
