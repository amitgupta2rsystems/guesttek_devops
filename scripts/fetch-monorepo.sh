#!/usr/bin/env bash
# Fetch/clone GuestTek service repos from GitHub/Bitbucket using scripts/service-repos.list.
# No release-manifest.yaml required on the host.
#
# Usage:
#   ./scripts/fetch-monorepo.sh
#   ./scripts/fetch-monorepo.sh --root /path/to/workspace
#   ./scripts/fetch-monorepo.sh --service-branches --clone-missing

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_LIST="${ROOT}/scripts/service-repos.list"
CLONE_MISSING=1
SERVICE_BRANCHES=0
DRY_RUN=0

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

log() { echo "==> $*"; }
warn() { echo "  WARN $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; REPO_LIST="${ROOT}/scripts/service-repos.list"; shift 2 ;;
    --repos-file) REPO_LIST="$2"; shift 2 ;;
    --clone-missing) CLONE_MISSING=1; shift ;;
    --no-clone-missing) CLONE_MISSING=0; shift ;;
    --service-branches) SERVICE_BRANCHES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -f "$REPO_LIST" ]] || { echo "Error: missing ${REPO_LIST}" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "Error: git required" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

is_remote_host() {
  local url="$1"
  [[ "$url" == git@github.com:* || "$url" == https://github.com/* ]] && return 0
  [[ "$url" == git@bitbucket.org:* || "$url" == https://bitbucket.org/* ]] && return 0
  return 1
}

fetch_repo() {
  local name="$1" path="$2" remote="$3" branch="$4"
  local dir="${ROOT}/${path}"

  [[ -n "$remote" ]] || { warn "${name}: empty remote"; return 0; }
  is_remote_host "$remote" || { log "SKIP ${name}: not GitHub/Bitbucket (${remote})"; return 0; }

  if [[ ! -d "$dir/.git" ]]; then
    if [[ "$CLONE_MISSING" -eq 0 ]]; then
      warn "${name}: missing ${dir} (use --clone-missing)"
      return 0
    fi
    log "${name}: clone ${remote} → ${dir}"
    run git clone "$remote" "$dir"
  fi

  log "${name}: fetch ${remote}"
  run git -C "$dir" fetch --all --tags --prune

  if [[ -n "$branch" && "$branch" != "-" ]]; then
    if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
      log "${name}: checkout origin/${branch}"
      run git -C "$dir" checkout -B "$branch" "origin/${branch}"
    else
      warn "${name}: branch origin/${branch} not found after fetch"
    fi
  fi

  echo "  OK   ${name} @ $(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
}

while IFS='|' read -r name path remote branch _rest; do
  [[ -z "$name" || "$name" =~ ^# ]] && continue
  fetch_repo "$name" "$path" "$remote" "${branch:--}"
done < "$REPO_LIST"

if [[ "$SERVICE_BRANCHES" -eq 1 ]]; then
  log "Checkout Bitbucket dev branches"
  run "${ROOT}/scripts/checkout-service-branches.sh"
fi

log "Fetch complete under ${ROOT}"
