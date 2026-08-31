#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

need_config_file
prepare_keys
require_var ORACLE_APP_HOST
require_var ORACLE_DB_HOST

printf '\n== app host ==\n'
ssh_app "cd '${ORACLE_REMOTE_DIR}/app' 2>/dev/null && docker compose --env-file .env -f docker-compose.server.yml ps || true; curl -fsS 'http://127.0.0.1:8080/health' || true"

printf '\n== caddy ==\n'
ssh_app "cd '${ORACLE_REMOTE_DIR}/caddy' 2>/dev/null && docker compose --env-file .env -f docker-compose.caddy.yml ps || true"

printf '\n== db host ==\n'
ssh_db "cd '${ORACLE_REMOTE_DIR}/db' 2>/dev/null && docker compose --env-file .env -f docker-compose.db.yml ps || true"
