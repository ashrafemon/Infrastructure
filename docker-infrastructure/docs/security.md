# Security Guide

## Firewall Configuration

### UFW (Ubuntu/Debian)

```bash
# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow ssh

# Reverse proxy (public)
ufw allow 80/tcp
ufw allow 443/tcp

# NPM admin (restrict to VPN or office IP)
ufw allow from 192.168.1.0/24 to any port 81

# Management UIs (allow only from trusted networks)
ufw allow from 10.0.0.0/8 to any port 8081  # phpMyAdmin
ufw allow from 10.0.0.0/8 to any port 5050  # pgAdmin
ufw allow from 10.0.0.0/8 to any port 5540  # RedisInsight
ufw allow from 10.0.0.0/8 to any port 3000  # Grafana
ufw allow from 10.0.0.0/8 to any port 8080  # Jenkins

# Enable
ufw enable
ufw status verbose
```

### iptables Alternative

```bash
# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH, HTTP, HTTPS
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Drop everything else
iptables -P INPUT DROP
iptables -P FORWARD DROP
```

---

## Password Policy

### Required Changes Before Production

| Variable                      | Minimum Requirements                          |
|-------------------------------|-----------------------------------------------|
| MYSQL_ROOT_PASSWORD           | 24+ chars, mixed case, numbers, symbols       |
| MYSQL_PASSWORD                | 16+ chars                                     |
| POSTGRES_PASSWORD             | 16+ chars                                     |
| MONGO_INITDB_ROOT_PASSWORD    | 24+ chars, mixed case, numbers, symbols       |
| REDIS_PASSWORD                | 24+ chars, mixed case, numbers, symbols       |
| RABBITMQ_PASSWORD             | 24+ chars                                     |
| MINIO_ROOT_PASSWORD           | 32+ chars, mixed case, numbers                |
| GF_SECURITY_ADMIN_PASSWORD    | 16+ chars, mixed case, numbers, symbols       |
| PGADMIN_DEFAULT_PASSWORD      | 16+ chars, mixed case, numbers                |

### Generate Strong Passwords

```bash
# Generate a 32-character password
openssl rand -base64 32

# Generate a password with symbols
openssl rand -base64 32 | tr -d '\n' | head -c 32; echo

# Generate multiple passwords at once
for i in {1..8}; do openssl rand -base64 24; done
```

---

## Network Security

### Network Isolation

The infrastructure uses Docker networks to segment traffic:

| Network            | Services                                      | Exposure           |
|--------------------|-----------------------------------------------|--------------------|
| frontend_network   | NPM, phpMyAdmin, pgAdmin, RedisInsight, Uptime Kuma, Arcane | Limited ports |
| backend_network    | MySQL, PostgreSQL, MongoDB, Redis, RabbitMQ, MinIO | Internal only     |
| monitoring_network | Prometheus, Grafana, Loki, Promtail  | Limited ports     |
| mail_network       | Mailpit                                       | Internal only     |

### Internal Network

`backend_network` is marked `internal: true`, meaning it has **no external access**. Only other Docker containers connected to it can reach these services.

---

## SSL/TLS Configuration

### Nginx Proxy Manager (NPM)

NPM handles SSL termination automatically:

1. Access NPM on port 81
2. Add your domain
3. Request Let's Encrypt SSL certificate
4. Set up SSL with Cloudflare DNS challenge (for wildcard certs)

### DNS Challenge for Wildcard Certificates

In NPM, use these DNS providers:

| Provider     | Credentials Needed                     |
|--------------|----------------------------------------|
| Cloudflare   | Global API Key or API Token            |
| AWS Route53  | AWS Access Key + Secret Key            |
| DigitalOcean | Personal Access Token                  |
| GoDaddy      | API Key + Secret                       |

---

## CrowdSec IPS/IDS

### Overview

CrowdSec analyzes logs and blocks malicious IPs using community-curated threat intelligence.

### Default Collections

- `crowdsecurity/nginx` - Nginx attacks
- `crowdsecurity/linux` - SSH, brute force
- `crowdsecurity/http-cve` - Known CVE exploitation attempts

### Adding Bouncers

After CrowdSec starts:

```bash
# Create a bouncer API key
docker exec crowdsec cscli bouncers add nginx-bouncer

# Use this key in your Nginx config or firewall bouncer
```

### Monitoring

```bash
# View blocked IPs
docker exec crowdsec cscli decision list

# View alerts
docker exec crowdsec cscli alerts list

# View metrics
docker exec crowdsec cscli metrics
```

---

## Docker Security

### Container Capabilities

The infrastructure applies minimal capabilities:

- Most containers run with **no extra capabilities**
- Jenkins needs no special capabilities

- Watchtower needs Docker socket access

### Read-only Root Filesystem

For production hardening, add to any service:

```yaml
read_only: true
tmpfs:
  - /tmp
  - /run
```

### Security Scanning

```bash
# Scan images with Docker Scout
docker scout quickstart
docker scout recommendations

# Scan with Trivy (recommended)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.58 image --severity HIGH,CRITICAL mysql:9.3.0
```

---

## Security Checklist

### Pre-Production

- [ ] All default passwords changed
- [ ] Management UIs bound to localhost (`127.0.0.1`) or behind VPN
- [ ] UFW/iptables firewall enabled
- [ ] SSH key-based authentication only (no passwords)
- [ ] Automatic security updates enabled: `unattended-upgrades`
- [ ] Docker daemon configured with `userns-remap`
- [ ] Auditd installed and configured
- [ ] Fail2ban installed for SSH

### Production Hardening

- [ ] Internal services behind Nginx Proxy Manager
- [ ] CrowdSec deployed and active
- [ ] Failed login monitoring enabled
- [ ] Docker content trust enabled: `export DOCKER_CONTENT_TRUST=1`
- [ ] Secrets stored in Docker secrets (not plain env vars)
- [ ] Regular image scanning integrated into CI/CD
- [ ] WAF rules active in Nginx Proxy Manager
- [ ] Rate limiting configured at proxy level
- [ ] Backups encrypted before off-site transfer

### Monitoring & Response

- [ ] Grafana alerting configured for critical events
- [ ] CrowdSec alerts forwarded to notification channel
- [ ] Log aggregation working (Promtail → Loki)
- [ ] Incident response runbook documented
- [ ] Regular security audits scheduled

---

## Mailcow Security

When deploying Mailcow (see `mailcow.md`):

- Generate strong DKIM keys
- Configure SPF record: `v=spf1 mx include:spf.yourdomain.com ~all`
- Configure DMARC record: `v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com`
- Enable TLS 1.3 only
- Set up Cloudflare DNS for DDoS protection
- Monitor mail logs with Fail2ban
- Keep Mailcow updated via the built-in updater
