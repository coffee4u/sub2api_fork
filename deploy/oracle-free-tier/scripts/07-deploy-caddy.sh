#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

need_config_file
prepare_keys
require_var ORACLE_APP_HOST

CADDY_EMAIL="${CADDY_EMAIL:-${ADMIN_EMAIL:-}}"
CADDY_UPSTREAM="${CADDY_UPSTREAM:-127.0.0.1:8080}"

require_var CADDY_DOMAIN
require_var CADDY_EMAIL
require_var CADDY_UPSTREAM
validate_secret_value CADDY_DOMAIN
validate_secret_value CADDY_EMAIL
validate_secret_value CADDY_UPSTREAM

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${ORACLE_DIR}/docker-compose.caddy.yml" "${tmp_dir}/docker-compose.caddy.yml"
cp "${ORACLE_DIR}/Caddyfile" "${tmp_dir}/Caddyfile"
write_env_file "${tmp_dir}/.env" CADDY_DOMAIN CADDY_EMAIL CADDY_UPSTREAM TZ

ssh_app "mkdir -p '${ORACLE_REMOTE_DIR}/caddy'"
scp -i "${APP_KEY_ABS}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  "${tmp_dir}/docker-compose.caddy.yml" "${tmp_dir}/Caddyfile" "${tmp_dir}/.env" \
  "${ORACLE_APP_SSH_USER}@${ORACLE_APP_HOST}:${ORACLE_REMOTE_DIR}/caddy/"

ssh_app "cd '${ORACLE_REMOTE_DIR}/caddy' && mkdir -p caddy_data caddy_config && docker compose --env-file .env -f docker-compose.caddy.yml up -d"

printf 'Caddy deployed. Status:\n'
ssh_app "cd '${ORACLE_REMOTE_DIR}/caddy' && docker compose --env-file .env -f docker-compose.caddy.yml ps"

printf '\nLocal origin checks:\n'
ssh_app "curl -fsSI -H 'Host: ${CADDY_DOMAIN}' http://127.0.0.1 || true"
ssh_app "curl -fsSkI --resolve '${CADDY_DOMAIN}:443:127.0.0.1' 'https://${CADDY_DOMAIN}' || true"
