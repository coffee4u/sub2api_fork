#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORACLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ORACLE_DIR}/../.." && pwd)"
CONFIG_FILE="${ORACLE_CONFIG:-${ORACLE_DIR}/oracle.env}"

if [ -f "${CONFIG_FILE}" ]; then
  # shellcheck disable=SC1090
  set -a
  source "${CONFIG_FILE}"
  set +a
fi

ORACLE_APP_SSH_USER="${ORACLE_APP_SSH_USER:-opc}"
ORACLE_DB_SSH_USER="${ORACLE_DB_SSH_USER:-${ORACLE_APP_SSH_USER}}"
ORACLE_APP_SSH_KEY="${ORACLE_APP_SSH_KEY:-keys_pub/ssh-key-sub2api-server.key}"
ORACLE_DB_SSH_KEY="${ORACLE_DB_SSH_KEY:-keys_pub/ssh-key-sub2api-db.key}"
ORACLE_REMOTE_DIR="${ORACLE_REMOTE_DIR:-/opt/sub2api}"
SUB2API_IMAGE="${SUB2API_IMAGE:-sub2api:oracle-amd64}"
SUB2API_PLATFORM="${SUB2API_PLATFORM:-linux/amd64}"
SUB2API_IMAGE_ARCHIVE="${SUB2API_IMAGE_ARCHIVE:-deploy/oracle-free-tier/artifacts/sub2api-oracle-amd64.tar.gz}"
SERVER_PORT="${SERVER_PORT:-8080}"

abs_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${REPO_ROOT}/${path}"
  fi
}

APP_KEY_ABS="$(abs_path "${ORACLE_APP_SSH_KEY}")"
DB_KEY_ABS="$(abs_path "${ORACLE_DB_SSH_KEY}")"
IMAGE_ARCHIVE_ABS="$(abs_path "${SUB2API_IMAGE_ARCHIVE}")"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_config_file() {
  [ -f "${CONFIG_FILE}" ] || die "missing ${CONFIG_FILE}; copy oracle.env.example to oracle.env and fill it"
}

require_var() {
  local name="$1"
  local value="${!name:-}"
  [ -n "${value}" ] || die "${name} is required in ${CONFIG_FILE}"
}

require_file() {
  local path="$1"
  [ -f "${path}" ] || die "file not found: ${path}"
}

prepare_keys() {
  require_file "${APP_KEY_ABS}"
  require_file "${DB_KEY_ABS}"
  chmod 600 "${APP_KEY_ABS}" "${DB_KEY_ABS}"
}

ssh_common_opts() {
  local key="$1"
  printf '%s\0' \
    -i "${key}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3
}

ssh_app() {
  ssh -i "${APP_KEY_ABS}" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=60 \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    "${ORACLE_APP_SSH_USER}@${ORACLE_APP_HOST}" "$@"
}

ssh_db() {
  ssh -i "${DB_KEY_ABS}" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=60 \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    "${ORACLE_DB_SSH_USER}@${ORACLE_DB_HOST}" "$@"
}

scp_to_app() {
  scp -i "${APP_KEY_ABS}" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=60 \
    -o StrictHostKeyChecking=accept-new \
    "$@" "${ORACLE_APP_SSH_USER}@${ORACLE_APP_HOST}:"
}

scp_to_db() {
  scp -i "${DB_KEY_ABS}" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=60 \
    -o StrictHostKeyChecking=accept-new \
    "$@" "${ORACLE_DB_SSH_USER}@${ORACLE_DB_HOST}:"
}

write_env_file() {
  local dest="$1"
  shift
  : > "${dest}"
  local name
  for name in "$@"; do
    printf '%s=%s\n' "${name}" "${!name:-}" >> "${dest}"
  done
}

validate_secret_value() {
  local name="$1"
  local value="${!name:-}"
  [[ "${value}" != *$'\n'* ]] || die "${name} must not contain newlines"
  [[ "${value}" != *' '* ]] || die "${name} should not contain spaces; use openssl rand -hex 32"
}
