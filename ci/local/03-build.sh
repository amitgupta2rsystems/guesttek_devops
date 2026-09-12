#!/usr/bin/env bash
# Build Docker images for all edge services (amd64 by default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

build_one() {
  local repo="$1" script="$2"
  local script_path="${WORK_ROOT}/${repo}/${script}"

  [[ -d "${WORK_ROOT}/${repo}" ]] || die "Missing repo: ${WORK_ROOT}/${repo}"
  [[ -f "$script_path" ]] || die "Missing build script: ${script_path}"

  log "Build ${repo} (${script}) PLATFORM=${DOCKER_PLATFORM}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] cd ${WORK_ROOT}/${repo} && PLATFORM=${DOCKER_PLATFORM} bash ./${script}"
    return 0
  fi

  (
    cd "${WORK_ROOT}/${repo}"
    PLATFORM="${DOCKER_PLATFORM}" bash "./${script}"
  )

  pause_for_user
}

list_images() {
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  log "Built images (camsuite:*):"
  docker images 'camsuite:*' --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' 2>/dev/null | head -25 || true
  docker images 'camsuite-emb-provisioning:*' --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' 2>/dev/null | head -5 || true
}

main() {
  log "Docker builds under ${WORK_ROOT}"
  local entry repo script
  for entry in "${SERVICE_BUILDS[@]}"; do
    repo="${entry%%|*}"
    script="${entry#*|}"
    build_one "$repo" "$script"
  done
  list_images
  log "All builds finished"
}

main "$@"
