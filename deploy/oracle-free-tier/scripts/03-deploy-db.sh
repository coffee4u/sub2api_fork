#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

need_config_file
prepare_keys
require_var ORACLE_DB_HOST
require_var ORACLE_DB_PRIVATE_IP
require_var ORACLE_APP_PRIVATE_IP
require_var POSTGRES_PASSWORD
require_var REDIS_PASSWORD
validate_secret_value POSTGRES_PASSWORD
validate_secret_value REDIS_PASSWORD

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${ORACLE_DIR}/docker-compose.db.yml" "${tmp_dir}/docker-compose.db.yml"
write_env_file "${tmp_dir}/.env" \
  ORACLE_DB_PRIVATE_IP \
  POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB \
  POSTGRES_MAX_CONNECTIONS POSTGRES_SHARED_BUFFERS POSTGRES_EFFECTIVE_CACHE_SIZE \
  POSTGRES_MAINTENANCE_WORK_MEM POSTGRES_WORK_MEM \
  REDIS_PASSWORD REDIS_MAXMEMORY REDIS_MAXCLIENTS TZ

ssh_db "mkdir -p '${ORACLE_REMOTE_DIR}/db'"
scp -i "${DB_KEY_ABS}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  "${tmp_dir}/docker-compose.db.yml" "${tmp_dir}/.env" \
  "${ORACLE_DB_SSH_USER}@${ORACLE_DB_HOST}:${ORACLE_REMOTE_DIR}/db/"

ssh_db "cd '${ORACLE_REMOTE_DIR}/db' && mkdir -p postgres_data redis_data && docker compose --env-file .env -f docker-compose.db.yml up -d"

printf 'DB services deployed. Status:\n'
ssh_db "cd '${ORACLE_REMOTE_DIR}/db' && docker compose --env-file .env -f docker-compose.db.yml ps"
