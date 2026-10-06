#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/deploy"
touch "$test_root/deploy/.env.prod" "$test_root/deploy/compose.prod.yaml"

cat > "$test_root/bin/git" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1 $2" == "rev-parse HEAD" ]]; then
  printf "%s\n" "$FAKE_CURRENT_REVISION"
fi
SCRIPT

cat > "$test_root/bin/docker" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

chmod +x "$test_root/bin/git" "$test_root/bin/docker"

PATH="$test_root/bin:$PATH" \
  FAKE_CURRENT_REVISION=abc \
  DEPLOY_PATH="$test_root/deploy" \
  DEPLOY_REVISION=abc \
  "$repo_root/scripts/deploy-production.sh"

if PATH="$test_root/bin:$PATH" \
  FAKE_CURRENT_REVISION=def \
  DEPLOY_PATH="$test_root/deploy" \
  DEPLOY_REVISION=abc \
  "$repo_root/scripts/deploy-production.sh" >/dev/null 2>&1; then
  echo "Revision guard unexpectedly accepted a different commit" >&2
  exit 1
fi

echo "Deploy script tests passed"
