# Subdomain Binding & SSL with Nginx Proxy Manager

## Architecture

Two tiers of domains:

| Tier | Domain | SSL Cert | Purpose |
|------|--------|----------|---------|
| **Infrastructure** | `*.leafwrap.online` | Wildcard `*.leafwrap.online` | Management UIs (Grafana, Jenkins, etc.) |
| **Client projects** | `leafwrap.top`, `devsloom.ca`, etc. | Per-domain | Customer applications |

```
                          ┌──────────────┐
                          │  Cloudflare  │
                          │  (DNS + SSL) │
                          └──────┬───────┘
                                 │
                          ┌──────┴───────┐
             ┌────────────┤   NPM :80/443 ├────────────┐
             │            └──────────────┘            │
             ▼                                        ▼
  ┌─────────────────────┐                  ┌─────────────────────┐
  │  Infrastructure     │                  │  Client Projects    │
  │  *.leafwrap.online  │                  │  leafwrap.top etc.  │
  │                     │                  │                     │
  │  grafana.leafwrap   │                  │  leafwrap.top       │
  │  jenkins.leafwrap   │                  │  devsloom.ca        │
  │  db.leafwrap        │                  │  cpanel.devsloom.ca │
  │  minio.leafwrap     │                  │                     │
  └─────────────────────┘                  └─────────────────────┘
```

---

## Step 1: Cloudflare API Token

One token with `Zone → DNS → Edit` permission. This single token can issue certs for all domains you manage in Cloudflare.

1. Cloudflare Dashboard → **My Profile** → **API Tokens** → **Create Token**
2. Select **Edit zone DNS** template
3. Set permissions: `Zone → DNS → Edit`
4. Scope to all zones you manage (or create per-zone tokens for stricter access)
5. Copy the token

---

## Step 2: Infrastructure Wildcard Certificate

**In NPM web UI (http://YOUR_IP:81):**

1. **SSL Certificates** → **Add SSL Certificate** → **Let's Encrypt**
2. Fill in:
   - **Domain**: `*.leafwrap.online`
   - **DNS Challenge**: **Cloudflare**
   - **API Token**: Your Cloudflare token
   - **Email**: admin@leafwrap.online
3. **Save**

This single wildcard cert covers all infrastructure subdomains.

---

## Step 3: Infrastructure Proxy Hosts

DNS: `A *.leafwrap.online → YOUR_SERVER_IP` (one wildcard record catches all)

| Subdomain | Forward To | Port | Websocket |
|-----------|------------|------|-----------|
| `grafana.leafwrap.online` | `grafana` | `3000` | On |
| `jenkins.leafwrap.online` | `jenkins` | `8080` | Off |
| `db.leafwrap.online` | `phpmyadmin` | `80` | Off |
| `pgadmin.leafwrap.online` | `pgadmin` | `80` | Off |
| `redis.leafwrap.online` | `redisinsight` | `5540` | Off |
| `mq.leafwrap.online` | `rabbitmq` | `15672` | On |
| `minio.leafwrap.online` | `minio` | `9001` | On |
| `s3.leafwrap.online` | `minio` | `9000` | Off |
| `status.leafwrap.online` | `uptime-kuma` | `3001` | On |
| `docker.leafwrap.online` | `arcane` | `3552` | On |
| `mailpit.leafwrap.online` | `mailpit` | `8025` | On |

For each proxy host in NPM:
- **Scheme**: `http`
- **SSL Certificate**: Select `*.leafwrap.online`
- **Force SSL**: On
- **HTTP/2**: On
- **Block Common Exploits**: On

---

## Step 4: Client Project Certificates

Each client domain needs its own SSL cert. NPM can auto-issue them via **HTTP-01 challenge** (no API token needed) because NPM owns ports 80/443.

**In NPM: SSL Certificates → Add SSL Certificate → Let's Encrypt**

| Field | Value |
|-------|-------|
| **Domain** | e.g. `leafwrap.top` (or add multiple: `leafwrap.top, www.leafwrap.top`) |
| **DNS Challenge** | (leave empty — HTTP challenge is automatic) |
| **Email** | admin@leafwrap.online |

**OR** use Cloudflare DNS challenge if the domain is behind Cloudflare:

| Field | Value |
|-------|-------|
| **Domain** | `leafwrap.top` |
| **DNS Challenge** | **Cloudflare** |
| **API Token** | Same Cloudflare token |

### Per-Domain Proxy Hosts

| Client Domain | Forward To | Port | SSL Cert |
|---|---|---|---|
| `leafwrap.top` | `project-alpha` | 8081 | `leafwrap.top` |
| `www.leafwrap.top` | `project-alpha` | 8081 | `leafwrap.top` |
| `devsloom.ca` | `project-beta` | 8082 | `devsloom.ca` |
| `cpanel.devsloom.ca` | `project-beta` | 8000 | `cpanel.devsloom.ca` |

Each proxy host selects its own certificate from the dropdown.

---

## DNS Records Summary

```
; Infrastructure (leafwrap.online)
A  *.leafwrap.online  YOUR_SERVER_IP

; Client projects - each needs its own A record
A  leafwrap.top        YOUR_SERVER_IP
A  devsloom.ca         YOUR_SERVER_IP
A  cpanel.devsloom.ca  YOUR_SERVER_IP
```

All client A records point to the same server IP. NPM routes by domain name.

---

## SSL/TLS Settings in Cloudflare

For all domains, set:

1. **SSL/TLS → Overview**: **Full (strict)**
2. **Always Use HTTPS**: On
3. **Automatic HTTPS Rewrites**: On
4. **Security → HSTS**: On (max-age 6 months, include subdomains)

> **Important:** Client domains using NPM's HTTP-01 challenge must temporarily set SSL to **Off** or **Flexible** during certificate issuance, then switch back to **Full (strict)** after. Cloudflare API (DNS-01) challenge avoids this — certs issue without touching the proxy toggle.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| 502 Bad Gateway | Container unreachable | Check `docker compose ps`, verify container name matches NPM config |
| SSL not issuing | DNS not propagated | Wait 5 min or use Cloudflare DNS challenge |
| Mixed content warnings | Force SSL off | Enable **Force SSL** + **HSTS** in NPM |
| Client domain shows wrong site | NPM host ordering | Move the correct proxy host above others in NPM list |
| HTTP-01 challenge fails | Port 80 blocked | Use Cloudflare DNS challenge instead |
