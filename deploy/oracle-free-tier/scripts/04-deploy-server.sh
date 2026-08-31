#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

need_config_file
prepare_keys
require_var ORACLE_APP_HOST
require_var ORACLE_DB_PRIVATE_IP
require_var POSTGRES_PASSWORD
require_var REDIS_PASSWORD
require_var ADMIN_PASSWORD
require_var JWT_SECRET
require_var TOTP_ENCRYPTION_KEY
require_file "${IMAGE_ARCHIVE_ABS}"
validate_secret_value POSTGRES_PASSWORD
validate_secret_value REDIS_PASSWORD
validate_secret_value ADMIN_PASSWORD
validate_secret_value JWT_SECRET
validate_secret_value TOTP_ENCRYPTION_KEY

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${ORACLE_DIR}/docker-compose.server.yml" "${tmp_dir}/docker-compose.server.yml"
write_env_file "${tmp_dir}/.env" \
  SUB2API_IMAGE SERVER_PORT SERVER_BIND_HOST SERVER_MODE RUN_MODE TZ APP_GOMEMLIMIT APP_GOGC \
  ORACLE_DB_PRIVATE_IP \
  POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB DATABASE_MAX_OPEN_CONNS DATABASE_MAX_IDLE_CONNS \
  REDIS_PASSWORD REDIS_DB REDIS_POOL_SIZE REDIS_MIN_IDLE_CONNS \
  ADMIN_EMAIL ADMIN_PASSWORD JWT_SECRET TOTP_ENCRYPTION_KEY

ssh_app "mkdir -p '${ORACLE_REMOTE_DIR}/app'"
scp -i "${APP_KEY_ABS}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  "${tmp_dir}/docker-compose.server.yml" "${tmp_dir}/.env" "${IMAGE_ARCHIVE_ABS}" \
  "${ORACLE_APP_SSH_USER}@${ORACLE_APP_HOST}:${ORACLE_REMOTE_DIR}/app/"

archive_name="$(basename "${IMAGE_ARCHIVE_ABS}")"
ssh_app "cd '${ORACLE_REMOTE_DIR}/app' && gzip -dc '${archive_name}' | docker load && mkdir -p data && docker compose --env-file .env -f docker-compose.server.yml up -d"

printf 'App service deployed. Status:\n'
ssh_app "cd '${ORACLE_REMOTE_DIR}/app' && docker compose --env-file .env -f docker-compose.server.yml ps"
