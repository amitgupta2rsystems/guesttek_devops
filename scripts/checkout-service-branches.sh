#!/usr/bin/env bash
# Check out development branches for Bitbucket service repos whose master is empty.
# Run after clone/checkout-from-manifest and before build-package.sh.
#
# Usage:
#   ./scripts/checkout-service-branches.sh
#   ./scripts/checkout-service-branches.sh --dry-run

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# repo|branch
BRANCHES=(
  "camsuite-emb-ip-camera|feature/ip-camera-service-approach-b"
  "camsuite-emb-video-capture|feature/Packaging"
  "camsuite-emb-video-upload-manager|dev"
)

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

log() { echo "==> $*"; }

for entry in "${BRANCHES[@]}"; do
  repo="${entry%%|*}"
  branch="${entry#*|}"
  dir="${ROOT}/${repo}"

  [[ -d "$dir/.git" ]] || { echo "  SKIP ${repo}: not a git repo"; continue; }

  if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
    log "${repo}: checkout origin/${branch}"
    run git -C "$dir" checkout -B "$branch" "origin/${branch}"
  elif git -C "$dir" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
    log "${repo}: checkout ${branch}"
    run git -C "$dir" checkout "$branch"
  else
    echo "  WARN ${repo}: branch ${branch} not found" >&2
  fi
done

log "Service branch checkout complete."
