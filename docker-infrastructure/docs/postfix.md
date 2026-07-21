# Postfix SMTP Relay Guide

## Overview

Postfix runs as a lightweight SMTP relay/outbound mail server in the infrastructure stack. It can:

- Send application emails (transactional, notifications)
- Relay through external SMTP providers (SendGrid, Mailgun, AWS SES)
- Authenticate with SASL
- Use TLS encryption
- Set per-message size limits

---

## Configuration

### Basic Outbound (Direct Delivery)

```bash
POSTFIX_HOSTNAME=mail.yourdomain.com
POSTFIX_DOMAIN=yourdomain.com
# Leave RELAYHOST empty for direct delivery
POSTFIX_RELAYHOST=
```

### Relay through External Provider

Relay all outbound mail through a transactional email service:

**SendGrid:**
```bash
POSTFIX_RELAYHOST=smtp.sendgrid.net:587
POSTFIX_SMTP_USER=apikey
POSTFIX_SMTP_PASSWORD=SG.your-sendgrid-api-key
POSTFIX_TLS=yes
```

**Mailgun:**
```bash
POSTFIX_RELAYHOST=smtp.mailgun.org:587
POSTFIX_SMTP_USER=postmaster@mg.yourdomain.com
POSTFIX_SMTP_PASSWORD=your-mailgun-smtp-password
POSTFIX_TLS=yes
```

**AWS SES:**
```bash
POSTFIX_RELAYHOST=email-smtp.us-east-1.amazonaws.com:587
POSTFIX_SMTP_USER=AKIA...  # SES SMTP username
POSTFIX_SMTP_PASSWORD=...   # SES SMTP password
POSTFIX_TLS=yes
```

---

## DNS Configuration

For better deliverability, configure these DNS records:

| Type | Name | Content |
|------|------|---------|
| PTR  | (reverse) | mail.yourdomain.com (set by hosting provider) |
| A    | mail | Your server IP |
| MX   | @ | mail.yourdomain.com (priority 10) |
| TXT  | @ | v=spf1 mx include:_spf.yourdomain.com ~all |
| TXT  | mail._domainkey | (DKIM key if using signed email) |

---

## Application Integration

Connect your applications to Postfix:

### Laravel (`config/mail.php`)

```php
MAIL_MAILER=smtp
MAIL_HOST=postfix
MAIL_PORT=587
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@yourdomain.com
MAIL_FROM_NAME="${APP_NAME}"
```

### NestJS

```typescript
transport: {
  host: 'postfix',
  port: 587,
  secure: false,
}
```

### NextJS / React (via API)

```javascript
// Use nodemailer or any SMTP library
{
  host: 'postfix',
  port: 587,
}
```

---

## Testing

```bash
# Send test email
docker exec -i postfix mail -s "Test Subject" user@example.com <<< "Test body"

# Check mail queue
docker exec postfix postqueue -p

# View logs
docker compose logs --tail=50 postfix
```

---

## Common Issues

### Port 25 blocked by ISP

Many cloud providers block port 25. Use port 587 with TLS, or relay through a transactional email service (SendGrid, Mailgun, etc.).

### Emails going to spam

1. Set up SPF, DKIM, and DMARC DNS records
2. Configure reverse DNS (PTR record) with your hosting provider
3. Warm up your sending IP with major providers
4. Monitor your sending reputation

### Relay access denied

If using a relay host, verify credentials and TLS settings match your provider's requirements.

### Message too large

Increase the size limit:
```bash
POSTFIX_MESSAGE_SIZE=104857600  # 100 MB
```
