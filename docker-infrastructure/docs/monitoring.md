# Monitoring Guide

## Stack Overview

```
┌──────────────┐     ┌──────────────┐
│   Netdata    │     │  Promtail    │
│  (Real-time  │     │ (Log agent)  │
│   metrics)   │     │              │
└──────┬───────┘     └──────┬───────┘
       │                    │
       ▼                    ▼
┌──────────────┐     ┌──────────────┐
│  Prometheus  │     │    Loki      │
│  (Metrics    │     │  (Log store) │
│   storage)   │     │              │
└──────┬───────┘     └──────┬───────┘
       │                    │
       └────────┬───────────┘
                ▼
       ┌────────────────┐
       │    Grafana     │
       │ (Visualization)│
       └────────────────┘
```

---

## Grafana

### Access

```
URL: http://YOUR_IP:3000
User: GF_SECURITY_ADMIN_USER (from .env)
Pass: GF_SECURITY_ADMIN_PASSWORD (from .env)
```

### Pre-configured Datasources

- **Prometheus** - Metrics from all monitored services
- **Loki** - Logs from all Docker containers

### Dashboards

Dashboards are auto-provisioned from `configs/grafana/dashboards/`. To add custom dashboards:

1. Export a dashboard as JSON from Grafana UI
2. Save it to `configs/grafana/dashboards/`
3. Wait for provisioning refresh (60s interval) or restart Grafana

### Alerting

To configure alerts:

1. Navigate to **Alerting > Contact points** in Grafana
2. Add notification channels (Email, Slack, PagerDuty, etc.)
3. Create alert rules for your metrics
4. Optionally configure SMTP in `docker-compose.yml` (see `.env.example`)

---

## Prometheus

### Access

```
URL: http://YOUR_IP:9090
```

### Metrics Endpoints

Prometheus scrapes targets defined in `configs/prometheus/prometheus.yml`:

| Target              | Endpoint                          | Requires                     |
|---------------------|-----------------------------------|------------------------------|
| Prometheus self     | localhost:9090                    | Built-in                     |
| Docker daemon       | host.docker.internal:9323         | Docker daemon metrics on    |
| Node exporter       | host.docker.internal:9100         | node_exporter on host        |
| cAdvisor            | host.docker.internal:8080         | cAdvisor container           |
| MySQL exporter      | mysql_exporter:9104               | Separate deploy              |
| PostgreSQL exporter | postgres_exporter:9187            | Separate deploy              |
| Redis exporter      | redis_exporter:9121               | Separate deploy              |
| RabbitMQ exporter   | rabbitmq_exporter:9419            | Separate deploy              |
| MinIO               | minio:9000                        | Built-in                     |

### Adding Exporters

Example: Deploy node_exporter on the host:

```bash
docker run -d \
  --name node_exporter \
  --restart unless-stopped \
  --net="host" \
  --pid="host" \
  prom/node-exporter:v1.8.2
```

### Data Retention

Prometheus retains metrics for **30 days** by default. Change in `compose/monitoring.yml`:

```yaml
command:
  - "--storage.tsdb.retention.time=60d"
```

---

## Loki & Promtail

### Architecture

- **Promtail** runs as a sidecar, reads Docker container logs via Docker socket
- **Loki** stores logs with 30-day retention (configurable in `configs/loki/loki.yml`)
- **Grafana** queries Loki for log visualization

### Log Labels

Promtail attaches these labels to every log entry:

| Label             | Description                    |
|-------------------|--------------------------------|
| `container`       | Container name                 |
| `container_id`    | Container short ID             |
| `image`           | Docker image name              |
| `stream`          | stdout or stderr               |
| `compose_service` | Docker Compose service name    |
| `compose_project` | Docker Compose project name    |

### Viewing Logs in Grafana

1. Open Grafana → **Explore**
2. Select **Loki** datasource
3. Query example: `{container="mysql"} |= "error"`
4. Use label filters for precise searching

---

## Netdata

### Access

```
URL: http://YOUR_IP:19999
```

Netdata provides real-time, per-second metrics for:

- CPU, memory, disk, network
- Docker container resource usage
- 100+ pre-built charts
- Health alarms with notifications

### Claim to Netdata Cloud (Optional)

Set these in `.env`:

```bash
NETDATA_CLAIM_TOKEN=your-token
NETDATA_CLAIM_URL=https://app.netdata.cloud
```

Then restart Netdata:

```bash
docker compose up -d netdata
```

---

## Uptime Kuma

### Access

```
URL: http://YOUR_IP:3001
```

Monitor:
- HTTP/HTTPS endpoints
- TCP ports
- Docker containers via API
- Ping/ICMP
- DNS records
- Certificate expiry

---

## Performance Tuning

| Service    | Setting                        | Default | Recommendation               |
|------------|--------------------------------|---------|------------------------------|
| Prometheus | retention.time                 | 30d     | Depends on disk budget       |
| Loki       | retention_period              | 720h    | 720h (30 days) is standard   |
| Loki       | ingestion_rate_mb             | 10 MB/s | Increase for high-volume     |
| Grafana    | Instance memory               | 256 MB  | 512 MB+ for large dashboards |
| Netdata    | Cache                         | Auto    | 256 MB+ on busy servers      |

---

## Alerting Best Practices

1. **Start small** - Monitor CPU, disk, memory, and critical service health
2. **Use Grafana alerts** for Prometheus metrics
3. **Use Netdata alarms** for real-time system health
4. **Configure notification channels** (Slack, email, webhook)
5. **Set up Uptime Kuma** for external endpoint monitoring
6. **Test your alerts** - Trigger them intentionally to verify delivery
