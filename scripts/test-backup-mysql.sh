#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/deploy/backups"
touch "$test_root/deploy/.env.prod" "$test_root/deploy/compose.prod.yaml"

cat > "$test_root/bin/docker" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${FAKE_DOCKER_FAIL:-0}" == "1" ]]; then
  exit 1
fi
cat <<'DUMP'
-- MySQL dump
CREATE TABLE `users` (`id` bigint NOT NULL);
-- Dump completed on 2026-10-06 15:45:00
DUMP
SCRIPT
chmod +x "$test_root/bin/docker"

printf 'old backup' | gzip > "$test_root/deploy/backups/connectspace-old.sql.gz"
touch -d '10 days ago' "$test_root/deploy/backups/connectspace-old.sql.gz"

PATH="$test_root/bin:$PATH" \
  DEPLOY_PATH="$test_root/deploy" \
  BACKUP_RETENTION_DAYS=7 \
  "$repo_root/scripts/backup-mysql.sh"

mapfile -t backups < <(find "$test_root/deploy/backups" -name 'connectspace-*.sql.gz')
test "${#backups[@]}" -eq 1
gzip -t "${backups[0]}"
zgrep -q '^-- Dump completed on' "${backups[0]}"
test ! -e "$test_root/deploy/backups/connectspace-old.sql.gz"

if PATH="$test_root/bin:$PATH" \
  FAKE_DOCKER_FAIL=1 \
  DEPLOY_PATH="$test_root/deploy" \
  "$repo_root/scripts/backup-mysql.sh" >/dev/null 2>&1; then
  echo "Backup script unexpectedly accepted a failed dump" >&2
  exit 1
fi

if find "$test_root/deploy/backups" -name '*.tmp' -print -quit | grep -q .; then
  echo "Backup script left a temporary file after failure" >&2
  exit 1
fi

echo "MySQL backup script tests passed"
