#!/usr/bin/env bash

set -Eeuo pipefail

deploy_path="${DEPLOY_PATH:-/opt/connect}"
backup_dir="${BACKUP_DIR:-$deploy_path/backups}"
retention_days="${BACKUP_RETENTION_DAYS:-7}"

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

find "$backup_dir" \
  -type f \
  -name 'connectspace-*.sql.gz' \
  -mtime "+$retention_days" \
  -print \
  -delete

echo "Backup verified: $backup"
