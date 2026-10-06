#!/usr/bin/env bash

set -Eeuo pipefail

deploy_path="${DEPLOY_PATH:-/opt/connect}"
backup_dir="${BACKUP_DIR:-$deploy_path/backups}"
retention_days="${BACKUP_RETENTION_DAYS:-7}"
azure_backup_container_url="${AZURE_BACKUP_CONTAINER_URL:-}"

if [[ ! "$retention_days" =~ ^[0-9]+$ ]]; then
  echo "BACKUP_RETENTION_DAYS must be a non-negative integer" >&2
  exit 1
fi

cd "$deploy_path"

if [[ ! -f .env.prod ]]; then
  echo "Missing $deploy_path/.env.prod" >&2
  exit 1
fi

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
umask 077

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$backup_dir/connectspace-$timestamp.sql.gz"
temp="$backup.tmp"

cleanup() {
  rm -f "$temp"
}
trap cleanup EXIT

compose=(
  docker compose
  --env-file .env.prod
  -f compose.prod.yaml
)

"${compose[@]}" exec -T mysql sh -lc 'MYSQL_PWD="$MYSQL_PASSWORD" exec mysqldump --single-transaction --no-tablespaces --routines --triggers --set-gtid-purged=OFF -u"$MYSQL_USER" "$MYSQL_DATABASE"' \
  | gzip -9 > "$temp"
gzip -t "$temp"
zgrep -q '^-- Dump completed on' "$temp"
mv "$temp" "$backup"

if [[ -n "$azure_backup_container_url" ]]; then
  if ! command -v azcopy >/dev/null 2>&1; then
    echo "azcopy is required when AZURE_BACKUP_CONTAINER_URL is set" >&2
    exit 1
  fi

  destination="${azure_backup_container_url%/}/$(basename "$backup")"
  AZCOPY_AUTO_LOGIN_TYPE=MSI azcopy copy \
    "$backup" \
    "$destination" \
    --overwrite=false \
    --check-length=true
fi

find "$backup_dir" \
  -type f \
  -name 'connectspace-*.sql.gz' \
  -mtime "+$retention_days" \
  -print \
  -delete

if [[ -n "$azure_backup_container_url" ]]; then
  echo "Backup verified and uploaded: $backup"
else
  echo "Backup verified: $backup"
fi
