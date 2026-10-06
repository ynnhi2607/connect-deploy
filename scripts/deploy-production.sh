#!/usr/bin/env bash

set -Eeuo pipefail

deploy_path="${DEPLOY_PATH:-/opt/connect}"
deploy_revision="${DEPLOY_REVISION:?DEPLOY_REVISION is required}"
cd "$deploy_path"

if [[ ! -f .env.prod ]]; then
  echo "Missing $deploy_path/.env.prod" >&2
  exit 1
fi

git fetch origin main
git checkout main
git pull --ff-only origin main

current_revision="$(git rev-parse HEAD)"
if [[ "$current_revision" != "$deploy_revision" ]]; then
  echo "Expected main at $deploy_revision but found $current_revision" >&2
  exit 1
fi

compose=(
  docker compose
  --env-file .env.prod
  -f compose.prod.yaml
)

"${compose[@]}" config --quiet
"${compose[@]}" pull backend frontend

"${compose[@]}" up -d --no-deps --force-recreate \
  --wait --wait-timeout 240 backend

"${compose[@]}" up -d --no-deps --force-recreate \
  --wait --wait-timeout 120 frontend

"${compose[@]}" ps
