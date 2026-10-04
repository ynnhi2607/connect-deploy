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
from GHCR and publishes only the frontend Nginx port.

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

For a local production-like test, use `HTTP_PORT=3002`. On a server, use port
`80` until TLS is configured.

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

## Remaining Production Hardening

- Add Flyway migrations, then change Hibernate `ddl-auto` from `update` to
  `validate`.
- Configure HTTPS with Nginx and Certbot.
- Store server secrets outside Git and rotate them regularly.
- Configure MySQL backups and verify restore procedures.
- Add container resource limits, monitoring, and log rotation.
- Document versioned deployment and rollback procedures.
