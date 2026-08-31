#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

need_config_file
prepare_keys

target="${1:-server}"
case "${target}" in
  server|app)
    require_var ORACLE_APP_HOST
    ssh_app "cd '${ORACLE_REMOTE_DIR}/app' && docker compose --env-file .env -f docker-compose.server.yml logs -f --tail=200"
    ;;
  db)
    require_var ORACLE_DB_HOST
    ssh_db "cd '${ORACLE_REMOTE_DIR}/db' && docker compose --env-file .env -f docker-compose.db.yml logs -f --tail=200"
    ;;
  caddy|proxy)
    require_var ORACLE_APP_HOST
    ssh_app "cd '${ORACLE_REMOTE_DIR}/caddy' && docker compose --env-file .env -f docker-compose.caddy.yml logs -f --tail=200"
    ;;
  *)
    die "usage: $0 [server|db|caddy]"
    ;;
esac
