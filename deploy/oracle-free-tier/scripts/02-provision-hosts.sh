#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

need_config_file
prepare_keys
require_var ORACLE_APP_HOST
require_var ORACLE_DB_HOST
require_var ORACLE_APP_PRIVATE_IP
require_var ORACLE_DB_PRIVATE_IP

remote_setup='
set -euo pipefail

log_step() {
  printf "\n[%s] %s\n" "$(date -u +%H:%M:%S)" "$*"
}

ensure_swap() {
  log_step "checking swap"
  local swap_size_gb="${SWAP_SIZE_GB:-4}"
  local target_size
  target_size=$((swap_size_gb * 1024 * 1024 * 1024))
  local current_size=0
  if [ -f /swapfile ]; then
    current_size="$(stat -c%s /swapfile 2>/dev/null || echo 0)"
  fi
  if swapon --show=NAME | grep -qx "/swapfile" && [ "${current_size}" -ge "${target_size}" ]; then
    log_step "swap already enabled with sufficient size"
    return
  fi
  if swapon --show=NAME | grep -qx "/swapfile"; then
    log_step "disabling existing undersized swap"
    sudo -n swapoff /swapfile
  fi
  if [ ! -f /swapfile ] || [ "${current_size}" -lt "${target_size}" ]; then
    log_step "creating /swapfile (${swap_size_gb}G)"
    sudo -n rm -f /swapfile
    sudo -n fallocate -l "${swap_size_gb}G" /swapfile || sudo -n dd if=/dev/zero of=/swapfile bs=1M count="$((swap_size_gb * 1024))"
    sudo -n chmod 600 /swapfile
    sudo -n mkswap /swapfile
  fi
  log_step "enabling swap"
  sudo -n swapon /swapfile || true
  grep -q "^/swapfile " /etc/fstab || echo "/swapfile none swap sw 0 0" | sudo -n tee -a /etc/fstab >/dev/null
}

install_docker() {
  log_step "checking docker"
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log_step "docker already installed"
    return
  fi
  os_id=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    os_id="${ID:-}"
  fi
  log_step "installing docker for os_id=${os_id:-unknown}"

  case "${os_id}" in
    ol)
      wait_for_package_managers() {
        local i
        for i in $(seq 1 60); do
          if pgrep -x dnf >/dev/null 2>&1 || \
             pgrep -x yum >/dev/null 2>&1 || \
             pgrep -x rpm >/dev/null 2>&1 || \
             pgrep -x packagekitd >/dev/null 2>&1; then
            log_step "waiting for existing package manager process to finish"
            sleep 5
            continue
          fi
          return
        done
        echo "package manager lock did not clear in time" >&2
        exit 1
      }
      dnf_install() {
        wait_for_package_managers
        sudo -n dnf install -y --setopt=install_weak_deps=False --setopt=keepcache=False "$@"
      }
      if command -v dnf >/dev/null 2>&1; then
        log_step "installing dnf prerequisites"
        dnf_install dnf-plugins-core curl ca-certificates
        log_step "adding docker ce repo"
        wait_for_package_managers
        sudo -n dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        log_step "importing docker gpg key"
        wait_for_package_managers
        sudo -n rpm --import https://download.docker.com/linux/centos/gpg
        log_step "cleaning dnf package cache"
        wait_for_package_managers
        sudo -n dnf clean packages || true
        log_step "installing docker ce packages"
        dnf_install --allowerasing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || \
          {
            log_step "docker ce install failed; cleaning cache before fallback"
            wait_for_package_managers
            sudo -n dnf clean packages || true
            dnf_install --nobest --allowerasing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
          }
      elif command -v yum >/dev/null 2>&1; then
        log_step "installing yum prerequisites"
        sudo -n yum install -y yum-utils curl ca-certificates
        log_step "adding docker ce repo"
        sudo -n yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        log_step "importing docker gpg key"
        sudo -n rpm --import https://download.docker.com/linux/centos/gpg
        log_step "installing docker ce packages"
        sudo -n yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      else
        echo "Oracle Linux detected but neither dnf nor yum is available" >&2
        exit 1
      fi
      ;;
    *)
      if ! command -v curl >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          log_step "installing apt prerequisites"
          sudo -n apt-get update
          sudo -n apt-get install -y curl ca-certificates
        elif command -v dnf >/dev/null 2>&1; then
          log_step "installing dnf prerequisites"
          sudo -n dnf install -y curl ca-certificates
        elif command -v yum >/dev/null 2>&1; then
          log_step "installing yum prerequisites"
          sudo -n yum install -y curl ca-certificates
        else
          echo "curl is required to install Docker" >&2
          exit 1
        fi
      fi
      log_step "running docker convenience installer"
      curl -fsSL https://get.docker.com | sudo sh
      ;;
  esac

  log_step "enabling docker service"
  sudo -n usermod -aG docker "$USER" || true
  sudo -n systemctl enable --now docker
}

ensure_dirs() {
  log_step "ensuring remote directory $1"
  sudo -n mkdir -p "$1"
  sudo -n chown -R "$USER:$USER" "$1"
}

ensure_swap
install_docker
ensure_dirs "$REMOTE_DIR"
log_step "printing docker versions"
docker --version
docker compose version
'

printf 'Provisioning app host...\n'
ssh_app "REMOTE_DIR='${ORACLE_REMOTE_DIR}' SWAP_SIZE_GB='${ORACLE_SWAP_SIZE_GB:-4}' bash -s" <<< "${remote_setup}"

printf 'Provisioning db host...\n'
ssh_db "REMOTE_DIR='${ORACLE_REMOTE_DIR}' SWAP_SIZE_GB='${ORACLE_SWAP_SIZE_GB:-4}' bash -s" <<< "${remote_setup}"

printf 'Applying firewalld rules when firewalld is present...\n'
ssh_app "if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then sudo firewall-cmd --permanent --add-port=${SERVER_PORT}/tcp && sudo firewall-cmd --permanent --add-port=80/tcp && sudo firewall-cmd --permanent --add-port=443/tcp && sudo firewall-cmd --reload; fi"
ssh_db "if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then sudo firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" source address=\"${ORACLE_APP_PRIVATE_IP}\" port protocol=\"tcp\" port=\"5432\" accept' && sudo firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" source address=\"${ORACLE_APP_PRIVATE_IP}\" port protocol=\"tcp\" port=\"6379\" accept' && sudo firewall-cmd --reload; fi"

printf 'Provisioning complete. Log out/in later if you want to run docker manually without sudo on the hosts.\n'
