#!/usr/bin/env bash
# Local amd64 pipeline — clone → patch → build (interactive pause between builds).
#
# Usage:
#   ./ci/local/run.sh
#   ./ci/local/run.sh --work-root /tmp/guesttek-amd64-build
#   ./ci/local/run.sh --skip-clone --skip-patches
#   ./ci/local/run.sh --fresh-clone
#   ./ci/local/run.sh --dry-run
#
# No release-manifest.yaml. Patches apply only to the work copy (never pushed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

export DRY_RUN=0
export SKIP_CLONE=0
export SKIP_PATCHES=0
export FRESH_CLONE=0
export NO_PAUSE=0

usage() {
  cat <<EOF
GuestTek local amd64 pipeline

  ./ci/local/run.sh [options]

Options:
  --work-root DIR     Clone and build here (default: ${WORK_ROOT})
  --fresh-clone       Remove existing repos before cloning
  --skip-clone        Repos already present under work-root
  --skip-patches      Build upstream sources without patches
  --no-pause          Do not wait for Enter between Docker builds
  --dry-run           Print steps only
  -h, --help

Steps: 01-clone.sh → 02-patch.sh → 03-build.sh

EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-root)   WORK_ROOT="$2"; export WORK_ROOT; shift 2 ;;
    --fresh-clone) FRESH_CLONE=1; export FRESH_CLONE; shift ;;
    --skip-clone)  SKIP_CLONE=1; export SKIP_CLONE; shift ;;
    --skip-patches) SKIP_PATCHES=1; export SKIP_PATCHES; shift ;;
    --no-pause)    NO_PAUSE=1; export NO_PAUSE; shift ;;
    --dry-run)     DRY_RUN=1; export DRY_RUN; shift ;;
    -h|--help)     usage 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

main() {
  echo "=== GuestTek local amd64 pipeline ==="
  echo "Orchestration: ${ORCHESTRATION_ROOT}"
  echo "Work root:     ${WORK_ROOT}"
  echo "Platform:      ${DOCKER_PLATFORM}"
  echo "Patches:       $([[ "$SKIP_PATCHES" -eq 1 ]] && echo skipped || echo yes)"
  echo "Pause:         $([[ "$NO_PAUSE" -eq 1 ]] && echo no || echo after each build)"
  echo ""

  preflight_host

  "${SCRIPT_DIR}/01-clone.sh"
  "${SCRIPT_DIR}/02-patch.sh"
  "${SCRIPT_DIR}/03-build.sh"

  echo ""
  echo "=== Pipeline complete ==="
  echo "Repos:  ${WORK_ROOT}"
  echo "Images: docker images 'camsuite:*'"
}

main "$@"
