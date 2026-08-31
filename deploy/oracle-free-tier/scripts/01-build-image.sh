#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

mkdir -p "$(dirname "${IMAGE_ARCHIVE_ABS}")"

# .dockerignore 排除了 .git，容器内 resolve-version.sh 拿不到 tag 会回落到
# backend/cmd/server/VERSION（发 tag 时常滞后一版）。在宿主机上解析真实版本
# 并通过 build arg 传入，Dockerfile 里 VERSION 优先级最高。
SUB2API_VERSION="${SUB2API_VERSION:-$(git -C "${REPO_ROOT}" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)}"

printf 'Building %s for %s...\n' "${SUB2API_IMAGE}" "${SUB2API_PLATFORM}"
docker buildx build \
  --platform "${SUB2API_PLATFORM}" \
  --load \
  -t "${SUB2API_IMAGE}" \
  --build-arg "VERSION=${SUB2API_VERSION}" \
  --build-arg "GOPROXY=${GOPROXY:-https://goproxy.cn,direct}" \
  --build-arg "GOSUMDB=${GOSUMDB:-sum.golang.google.cn}" \
  -f "${REPO_ROOT}/Dockerfile" \
  "${REPO_ROOT}"

printf 'Saving image archive: %s\n' "${IMAGE_ARCHIVE_ABS}"
docker save "${SUB2API_IMAGE}" | gzip -9 > "${IMAGE_ARCHIVE_ABS}"

ls -lh "${IMAGE_ARCHIVE_ABS}"
