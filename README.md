# SHC DMARC Processor

A self-contained Docker Compose stack for automatically processing DMARC aggregate and forensic reports received by email, storing the data in Elasticsearch, and visualizing it in Kibana — secured behind an nginx reverse proxy with automatic Let's Encrypt TLS.

## Stack

| Service | Image | Role |
|---|---|---|
| **parsedmarc** | `python:3.13-slim` + parsedmarc | Polls IMAP inbox in watch mode, parses and indexes reports |
| **Elasticsearch** | `8.17.0` | Stores parsed report data with 1-year retention |
| **Kibana** | `8.17.0` | DMARC dashboards (login required) |
| **nginx** | `nginx:alpine` + certbot | Reverse proxy with automatic Let's Encrypt TLS |
| **setup** | `alpine` | One-shot init: sets passwords, ILM policy, imports dashboards |

## How It Works

1. **parsedmarc** connects to a dedicated IMAP mailbox over SSL (port 993) and uses IMAP IDLE to process reports as they arrive — no cron job required.
2. Parsed reports are indexed into **Elasticsearch** immediately. Index lifecycle management automatically deletes data older than one year.
3. **Kibana** provides pre-built dashboards for DMARC aggregate and forensic reports, imported automatically on first run.
4. **nginx** terminates TLS using a Let's Encrypt certificate, redirects HTTP to HTTPS, and proxies all traffic to Kibana. The certificate is renewed automatically twice daily.

## Prerequisites

- Docker and Docker Compose (v2) installed on the host
- A DNS **A record** for your Kibana hostname pointing to this server's public IP — required before first start so Let's Encrypt can validate domain ownership
- Ports **80** and **443** open and reachable from the internet (for Let's Encrypt and Kibana access)
- A dedicated email mailbox for DMARC reports (configure your domain's `rua=` and `ruf=` DNS records to deliver to it)
- Minimum **8 GB RAM** on the host (Elasticsearch uses 2 GB heap)

## Deployment

### 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and fill in all values:

```env
# Elasticsearch
ELASTIC_PASSWORD=          # strong password for the elastic superuser
KIBANA_SYSTEM_PASSWORD=    # strong password for the kibana_system account

# IMAP
IMAP_HOST=                 # e.g. mail.example.com
IMAP_USER=                 # e.g. dmarc@example.com
IMAP_PASSWORD=             # IMAP account password

# nginx / Let's Encrypt
KIBANA_HOSTNAME=           # e.g. dmarc.example.com (must resolve to this server)
CERTBOT_EMAIL=             # email for Let's Encrypt registration and expiry notices
```

### 2. Start the stack

```bash
docker compose up -d
```

**First-run sequence:**

1. Elasticsearch starts and becomes healthy (~60s)
2. `setup` runs: sets `kibana_system` password, creates the 1-year ILM policy and index templates, waits for Kibana, then imports the pre-built DMARC dashboards
3. Kibana starts after Elasticsearch is ready
4. `parsedmarc` starts after `setup` completes successfully
5. `nginx` starts after Kibana is healthy, acquires a Let's Encrypt certificate on first run, then begins proxying traffic

Kibana will be available at `https://<KIBANA_HOSTNAME>` once nginx is up. Log in with username `elastic` and your `ELASTIC_PASSWORD`.

### Deploying via Portainer

Use **Stacks → Add stack → Repository** and point Portainer at this git repository. Set all environment variables in the Portainer **Environment variables** UI instead of a `.env` file.

## DMARC DNS Configuration

To start receiving reports, add `rua` (aggregate) and `ruf` (forensic) tags to your domain's DMARC DNS record:

```
_dmarc.example.com TXT "v=DMARC1; p=none; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com"
```

Replace `dmarc@example.com` with the address configured in `IMAP_USER`.

## Data Retention

Reports are retained for **365 days**. Elasticsearch index lifecycle management applies automatically to all `dmarc_aggregate-*`, `dmarc_forensic-*`, and `smtp_tls-*` indices via the `dmarc-retention-1year` ILM policy created during setup.

## TLS Certificate Renewal

The nginx container runs `certbot renew` via cron every 12 hours. Certbot only renews when the certificate is within 30 days of expiry and automatically reloads nginx on success — no manual intervention required.

## Useful Commands

```bash
# View logs for all services
docker compose logs -f

# View parsedmarc logs only
docker compose logs -f parsedmarc

# Reload nginx (e.g. after manual config change)
docker exec dmarc-nginx nginx -s reload

# Force certificate renewal
docker exec dmarc-nginx certbot renew --force-renewal

# Stop the stack
docker compose down

# Stop and remove all data (destructive)
docker compose down -v
```
