# DMARC Processor on Docker

A self-contained Docker Compose stack for automatically processing DMARC aggregate and forensic reports received by email, storing the data in Elasticsearch, and visualizing it in Kibana — secured behind an nginx reverse proxy with automatic Let's Encrypt TLS, or optionally in HTTP-only mode when running behind an existing reverse proxy.

## Stack

| Service | Image | Role |
|---|---|---|
| **parsedmarc** | `python:3.13-slim` + parsedmarc | Polls IMAP inbox in watch mode, parses and indexes reports |
| **Elasticsearch** | `8.17.0` | Stores parsed report data with 1-year retention |
| **Kibana** | `8.17.0` | DMARC dashboards (login required) |
| **nginx** | `nginx:alpine` + certbot | Reverse proxy with automatic Let's Encrypt TLS (or HTTP-only when `NGINX_LOCALHOST_ONLY=true`) |
| **geoipupdate** | `ghcr.io/maxmind/geoipupdate` | Downloads and weekly-refreshes MaxMind GeoLite2-Country database |
| **setup** | `alpine` | One-shot init: sets passwords, ILM policy, imports dashboards |

## How It Works

1. **parsedmarc** connects to a dedicated IMAP mailbox over SSL (port 993) and uses IMAP IDLE to process reports as they arrive — no cron job required.
2. Parsed reports are indexed into **Elasticsearch** immediately. Index lifecycle management automatically deletes data older than one year.
3. **Kibana** provides pre-built dashboards for DMARC aggregate and forensic reports, imported automatically on first run.
4. **geoipupdate** downloads the MaxMind GeoLite2-Country database on startup and refreshes it weekly. parsedmarc uses it to resolve sender IPs to countries in the dashboard.
5. **nginx** terminates TLS using a Let's Encrypt certificate, redirects HTTP to HTTPS, and proxies all traffic to Kibana. The certificate is renewed automatically twice daily. In `NGINX_LOCALHOST_ONLY=true` mode, nginx runs HTTP-only on port 80 with no certificate — suitable for deployments behind an existing TLS-terminating reverse proxy.

## Prerequisites

- Docker and Docker Compose (v2) installed on the host
- A DNS **A record** for your Kibana hostname pointing to this server's public IP — required before first start so Let's Encrypt can validate domain ownership (not required when `NGINX_LOCALHOST_ONLY=true`)
- Ports **80** and **443** open and reachable from the internet (for Let's Encrypt and Kibana access; not required when `NGINX_LOCALHOST_ONLY=true`)
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

# MaxMind GeoIP (free account at https://www.maxmind.com)
MAXMIND_ACCOUNT_ID=        # MaxMind account ID
MAXMIND_LICENSE_KEY=       # MaxMind license key

# nginx / Let's Encrypt
KIBANA_HOSTNAME=           # e.g. dmarc.example.com (must resolve to this server)
CERTBOT_EMAIL=             # email for Let's Encrypt registration and expiry notices

# Optional: localhost / behind-proxy mode
NGINX_LOCALHOST_ONLY=      # set to 'true' to skip Let's Encrypt and run HTTP-only
NGINX_BIND_ADDR=           # set to '127.0.0.1' to restrict Docker port binding to host loopback
NGINX_HTTP_PORT=           # host port for HTTP (default: 80)
NGINX_HTTPS_PORT=          # host port for HTTPS (default: 443; unused when NGINX_LOCALHOST_ONLY=true)
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

> **Note:** Certificate renewal does not apply when `NGINX_LOCALHOST_ONLY=true`. In that mode, certbot and crond are not started.

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

## Deploying via Portainer

### 1. Add the Stack

1. In the Portainer sidebar, go to **Stacks**
2. Click **+ Add stack**
3. Give it a name — e.g. `dmarc-processor`
4. Under **Build method**, select **Repository**

### 2. Configure the Repository

- **Repository URL:** `https://github.com/Snark-Networks/parsedmarc-ek-docker`
- **Repository reference:** `refs/heads/main`
- **Compose path:** `docker-compose.yml`
- If the repo is private, enable **Authentication** and provide a GitHub personal access token

### 3. Set Environment Variables

Scroll down to **Environment variables** and add each of the following:

| Variable | Value |
|---|---|
| `ELASTIC_PASSWORD` | Strong password for the `elastic` superuser |
| `KIBANA_SYSTEM_PASSWORD` | Strong password for `kibana_system` (must differ from above) |
| `IMAP_HOST` | Your IMAP server hostname |
| `IMAP_USER` | The DMARC mailbox address |
| `IMAP_PASSWORD` | The IMAP account password |
| `MAXMIND_ACCOUNT_ID` | MaxMind account ID (free account at maxmind.com) |
| `MAXMIND_LICENSE_KEY` | MaxMind license key |
| `KIBANA_HOSTNAME` | Public hostname for Kibana (e.g. `dmarc.example.com`) |
| `CERTBOT_EMAIL` | Your email for Let's Encrypt registration and expiry notices (not required when `NGINX_LOCALHOST_ONLY=true`) |
| `NGINX_LOCALHOST_ONLY` | Set to `true` to skip Let's Encrypt and run nginx in HTTP-only mode (optional) |
| `NGINX_BIND_ADDR` | Set to `127.0.0.1` to restrict Docker port binding to the host loopback interface (optional, recommended with `NGINX_LOCALHOST_ONLY=true`) |
| `NGINX_HTTP_PORT` | Host port to expose for HTTP — defaults to `80` (optional) |
| `NGINX_HTTPS_PORT` | Host port to expose for HTTPS — defaults to `443`; unused when `NGINX_LOCALHOST_ONLY=true` (optional) |

### 4. Before You Click Deploy

- The DNS A record for `KIBANA_HOSTNAME` must already point to this server's public IP
- Ports **80** and **443** must be open and reachable from the internet
- No other service on the host may be using ports 80 or 443

### 5. Deploy

Click **Deploy the stack**. Portainer will clone the repo and start all services. The startup order is:

```
elasticsearch → (setup + kibana + geoipupdate) → parsedmarc → nginx
```

The `setup` container will exit once initialization is complete — this is expected. The stack is fully up when `dmarc-nginx` shows as running.

### 6. Updating

When changes are pushed to the repo, go to the stack in Portainer and click **Pull and redeploy**.

## Default Credentials

| Service | Username | Password |
|---|---|---|
| Kibana | `elastic` | Value of `ELASTIC_PASSWORD` |
| Elasticsearch API | `elastic` | Value of `ELASTIC_PASSWORD` |

There are no hardcoded default passwords — all credentials are set by you in the environment variables before deployment. The `kibana_system` account is used internally by Kibana to communicate with Elasticsearch and is not used for interactive login.

## Attribution

This project does not contain original software — it is a Docker Compose configuration that bundles the following open source projects:

| Project | Author | License | Link |
|---|---|---|---|
| **parsedmarc** | Domainaware | Apache 2.0 | [github.com/domainaware/parsedmarc](https://github.com/domainaware/parsedmarc) |
| **Elasticsearch** | Elastic | ELv2 / SSPL | [elastic.co/elasticsearch](https://www.elastic.co/elasticsearch) |
| **Kibana** | Elastic | ELv2 / SSPL | [elastic.co/kibana](https://www.elastic.co/kibana) |
| **nginx** | nginx, Inc. | BSD 2-Clause | [nginx.org](https://nginx.org) |
| **Certbot** | EFF | Apache 2.0 | [certbot.eff.org](https://certbot.eff.org) |
| **Let's Encrypt** | ISRG | — | [letsencrypt.org](https://letsencrypt.org) |
| **GeoLite2** | MaxMind | CC BY-SA 4.0 | [maxmind.com](https://dev.maxmind.com/geoip/geolite2-free-geolocation-data) |
| **geoipupdate** | MaxMind | MIT | [github.com/maxmind/geoipupdate](https://github.com/maxmind/geoipupdate) |

All trademarks and registered trademarks are the property of their respective owners.
