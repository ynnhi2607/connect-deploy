# Connect Deploy

Docker Compose configuration for running the Connect frontend, backend, and
MySQL database together.

## Architecture

```text
Browser
  |
  v
Frontend / Nginx (127.0.0.1:3000)
  |
  | /api/*
  v
Backend / Spring Boot (backend:8080)
  |
  v
MySQL (mysql:3306)
```

The frontend and backend share the `application` network. The backend and
MySQL share the `database` network. The frontend cannot connect directly to
MySQL.

## Required Directory Layout

The local Compose file builds the sibling frontend and backend repositories,
so the directories must have this layout:

```text
resumeproject/
|-- be/
|-- fe/
`-- deploy/
```

## Requirements

- Docker Engine
- Docker Compose v2
- OpenSSL for generating local secrets

Verify the installation:

```bash
docker version
docker compose version
```

## Environment Setup

Create the local environment file:

```bash
cp .env.example .env
```

Generate separate values for the MySQL user password, MySQL root password,
and JWT signing secret:

```bash
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 48
```

Put those values in `.env`. Never commit `.env`, passwords, or JWT tokens.
Only `.env.example` belongs in Git.

Validate the resolved Compose configuration without printing it:

```bash
docker compose config --quiet
```

## Start The Stack

Build the application images, start all services, and wait for their health
checks:

```bash
docker compose up -d --build --wait --wait-timeout 180
```

Check their status:

```bash
docker compose ps
```

All three services should show `healthy`.

| Service | Local address | Notes |
| --- | --- | --- |
| Frontend | `http://localhost:3000` | Public entry point for local use |
| Backend | `http://localhost:8080` | Exposed only on the local machine |
| MySQL | `mysql:3306` | Available only inside the Docker network |

## Health Checks

Frontend:

```bash
curl http://localhost:3000/health
```

Backend:

```bash
curl http://localhost:8080/actuator/health
```

Expected backend response:

```json
{"groups":["liveness","readiness"],"status":"UP"}
```

## Authentication Smoke Test

Register through Nginx without printing the returned JWT:

```bash
curl -sS \
  -o /dev/null \
  -w "HTTP %{http_code}\n" \
  -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Docker Test","email":"docker@example.com","password":"Docker123!"}'
```

The first registration should return `HTTP 201`. Use another email if that
account already exists.

Log in through Nginx:

```bash
curl -sS \
  -o /dev/null \
  -w "HTTP %{http_code}\n" \
  -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"docker@example.com","password":"Docker123!"}'
```

A successful login returns `HTTP 200`. This verifies:

```text
Nginx -> Spring Boot -> MySQL
```

## Logs

Follow all logs:

```bash
docker compose logs -f
```

Follow one service:

```bash
docker compose logs -f frontend
docker compose logs -f backend
docker compose logs -f mysql
```

Press `Ctrl+C` to stop following logs. This does not stop the containers.

## Rebuild One Service

After changing backend code:

```bash
docker compose up -d --build --wait --wait-timeout 180 backend
```

After changing frontend code or Nginx configuration:

```bash
docker compose up -d --build --wait --wait-timeout 180 frontend
```

## Stop And Remove Containers

Stop services while keeping their containers:

```bash
docker compose stop
```

Remove containers and Compose networks while keeping MySQL data:

```bash
docker compose down
```

Start the same stack again:

```bash
docker compose up -d --wait --wait-timeout 180
```

The named volume `connect_mysql_data` preserves database data across
`docker compose down` and subsequent startups.

## Delete Local Database Data

The following command permanently deletes the local MySQL volume and all data:

```bash
docker compose down -v
```

Use it only when intentionally resetting the local database.

## Troubleshooting

### Port Is Already Allocated

Find the container using a port:

```bash
docker ps --filter publish=3000
docker ps --filter publish=8080
```

Stop only the identified container, or change the host-side port in
`compose.yaml`.

### Container Is Unhealthy

Inspect service logs and health-check output:

```bash
docker compose logs --tail 200 <service>
docker inspect --format '{{json .State.Health}}' <container>
```

### Connection Reset Immediately After Startup

`docker compose up -d` only starts container processes. Spring Boot can still
be initializing. Use `--wait` and check `docker compose ps` before requests.

### Docker Hub TLS Timeout

Retry the image pull separately:

```bash
docker pull mysql:8.4
```

## Production Compose

This `compose.yaml` is intended for local integration because it builds from
`../be` and `../fe`. The standalone `compose.prod.yaml` pulls prebuilt images
from GHCR and publishes the frontend Nginx port on the host interface
configured by `HTTP_PORT`.

Create the production environment file:

```bash
cp .env.prod.example .env.prod
```

Replace every secret placeholder with a unique random value:

```bash
openssl rand -hex 24
openssl rand -hex 24
openssl rand -base64 48
```

For a local production-like test, use `HTTP_PORT=3002`. On the production
server, use `HTTP_PORT=127.0.0.1:3000` so only the host Nginx proxy can
reach the frontend container.

Validate the configuration:

```bash
docker compose \
  --env-file .env.prod \
  -f compose.prod.yaml \
  config --quiet
```

Pull immutable application images:

```bash
docker compose \
  --env-file .env.prod \
  -f compose.prod.yaml \
  pull
```

Start the production stack and wait for health checks:

```bash
docker compose \
  --env-file .env.prod \
  -f compose.prod.yaml \
  up -d --wait --wait-timeout 180
```

Check status:

```bash
docker compose \
  --env-file .env.prod \
  -f compose.prod.yaml \
  ps
```

Stop and remove production containers while preserving database data:

```bash
docker compose \
  --env-file .env.prod \
  -f compose.prod.yaml \
  down
```

The production stack uses a separate `connect-prod_mysql_data` volume. Never
run `down -v` unless the production database must be permanently deleted.

For real releases, set `BACKEND_TAG` and `FRONTEND_TAG` to explicit version
tags such as `v1.0.0`. Do not deploy the moving `develop` tag to production.

The GHCR images are:

```text
ghcr.io/ynnhi2607/connect-be
ghcr.io/ynnhi2607/connect-frontend
```

## HTTPS Edge Proxy

Production uses `connect-nanest.duckdns.org`. The frontend container listens
only on `127.0.0.1:3000`; host Nginx owns public ports 80 and 443.

On a new Ubuntu host, install Nginx and copy the HTTP bootstrap configuration:

```bash
sudo apt update
sudo apt install -y nginx
sudo cp nginx/connect-nanest.conf /etc/nginx/sites-available/connect-nanest
sudo ln -s /etc/nginx/sites-available/connect-nanest \
  /etc/nginx/sites-enabled/connect-nanest
sudo unlink /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

After DNS points to the server and ports 80 and 443 are open, install Certbot
and let it add the certificate paths and HTTP-to-HTTPS redirect:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d connect-nanest.duckdns.org
sudo certbot renew --dry-run
```

The repository file is only the bootstrap configuration. Do not copy it over
an Nginx site that Certbot has already updated, because that would remove the
active TLS directives. Certificates and private keys under `/etc/letsencrypt`
must remain on the server and must never be committed.

Set these production environment values before recreating the services:

```text
HTTP_PORT=127.0.0.1:3000
CORS_ALLOWED_ORIGINS=https://connect-nanest.duckdns.org
```

Verify the edge after deployment:

```bash
curl -I https://connect-nanest.duckdns.org
sudo nginx -t
sudo systemctl status nginx --no-pager
```

## Remaining Production Hardening

- Add Flyway migrations, then change Hibernate `ddl-auto` from `update` to
  `validate`.
- Store server secrets outside Git and rotate them regularly.
- Configure MySQL backups and verify restore procedures.
- Add monitoring and codify Docker log rotation.
- Document versioned deployment and rollback procedures.

## Manual Production CD

Production deployment is intentionally manual. A successful merge to `main`
does not immediately modify the VM. Run the `Production CD` workflow only
after the application image workflows for `main` have completed.

Create a dedicated key on the operator machine. Do not reuse a personal SSH
private key:

```bash
ssh-keygen \
  -t ed25519 \
  -C "github-actions-connect-prod" \
  -f ~/.ssh/connect_prod_actions \
  -N ""

ssh-copy-id \
  -i ~/.ssh/connect_prod_actions.pub \
  azureuser@connect-nanest.duckdns.org
```

Verify the host key before storing it in GitHub. On the VM, display the trusted
ED25519 fingerprint:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

On the operator machine, collect the same host key and compare its fingerprint
with the VM output:

```bash
ssh-keyscan -t ed25519 connect-nanest.duckdns.org \
  > ~/.ssh/connect_prod_known_hosts
ssh-keygen -lf ~/.ssh/connect_prod_known_hosts
```

In the GitHub repository, create an environment named `production`. Restrict
its deployment branch to `main` and configure these environment values:

| Type | Name | Value |
| --- | --- | --- |
| Secret | `PROD_SSH_PRIVATE_KEY` | Contents of `~/.ssh/connect_prod_actions` |
| Secret | `PROD_SSH_KNOWN_HOSTS` | Contents of `~/.ssh/connect_prod_known_hosts` |
| Variable | `PROD_HOST` | `connect-nanest.duckdns.org` |
| Variable | `PROD_SSH_USER` | `azureuser` |
| Variable | `PROD_PATH` | `/opt/connect` |

Never paste either secret into an issue, pull request, terminal screenshot, or
tracked file. Add a required reviewer to the `production` environment when the
repository plan supports deployment protection rules.

To deploy, open **Actions**, choose **Production CD**, select **Run workflow**
on `main`, enter `deploy`, and confirm. The workflow:

1. verifies the selected branch and explicit confirmation;
2. connects using the dedicated key and pinned SSH host key;
3. fast-forwards `/opt/connect` to `origin/main` and verifies it still
   matches the commit selected by the workflow;
4. validates Compose and pulls the `main` application images;
5. recreates backend and frontend in order and waits for health checks; and
6. verifies `https://connect-nanest.duckdns.org/health` from the runner.

MySQL is not recreated by this workflow. The `.env.prod` file and MySQL volume
remain on the VM.

## MySQL Backups

The production VM creates a compressed logical dump each day. Backup files are
written atomically with mode `600` under `/opt/connect/backups`; incomplete dumps
are removed, and local files older than seven days are deleted. After a dump is
verified, AzCopy uploads it to the private `mysql-backups` container in the
`stconnectnanest2607` Azure Storage account.

The VM uses its system-assigned Managed Identity, so no storage account key or
SAS token is stored on disk. Before enabling the timer:

1. install AzCopy on the VM;
2. enable the VM system-assigned Managed Identity;
3. grant that identity `Storage Blob Data Contributor` on the
   `mysql-backups` container; and
4. configure an Azure lifecycle rule to delete base blobs matching
   `mysql-backups/connectspace-` 30 days after their last modification.

Confirm that the identity can list the private container:

```bash
AZCOPY_AUTO_LOGIN_TYPE=MSI azcopy list \
  'https://stconnectnanest2607.blob.core.windows.net/mysql-backups'
```

Install the systemd units after releasing this repository to production:

```bash
cd /opt/connect
git pull --ff-only origin main
sudo install -m 644 systemd/connect-backup.service \
  /etc/systemd/system/connect-backup.service
sudo install -m 644 systemd/connect-backup.timer \
  /etc/systemd/system/connect-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now connect-backup.timer
```

Run and inspect the first automated backup immediately:

```bash
sudo systemctl start connect-backup.service
sudo systemctl status connect-backup.service --no-pager
sudo systemctl list-timers connect-backup.timer --no-pager
journalctl -u connect-backup.service -n 50 --no-pager
ls -lh /opt/connect/backups
AZCOPY_AUTO_LOGIN_TYPE=MSI azcopy list \
  'https://stconnectnanest2607.blob.core.windows.net/mysql-backups'
```

The timer runs around `02:30 UTC` each day with a randomized delay of up to 15
minutes. `Persistent=true` runs a missed backup after the VM starts again.

Periodically verify restoration into a disposable database. Never restore a dump
directly over the production database as a test:

```bash
cd /opt/connect
backup="$(find backups -name 'connectspace-*.sql.gz' -type f | sort | tail -1)"
test -n "$backup"
gzip -t "$backup"

docker compose --env-file .env.prod -f compose.prod.yaml exec -T mysql \
  sh -lc 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "
    DROP DATABASE IF EXISTS connectspace_restore_check;
    CREATE DATABASE connectspace_restore_check;
  "'

gzip -cd "$backup" | docker compose \
  --env-file .env.prod \
  -f compose.prod.yaml \
  exec -T mysql \
  sh -lc 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot connectspace_restore_check'

docker compose --env-file .env.prod -f compose.prod.yaml exec -T mysql \
  sh -lc 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "
    USE connectspace_restore_check;
    SHOW TABLES;
  "'

docker compose --env-file .env.prod -f compose.prod.yaml exec -T mysql \
  sh -lc 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "
    DROP DATABASE connectspace_restore_check;
  "'
```

The local copy supports quick recovery, while the Azure Blob copy remains
available if the VM or its disk is lost. Azure encrypts the private container at
rest, and AzCopy sends the dump over TLS. Periodically test restoration from a
downloaded Blob copy as well as from the local copy.
