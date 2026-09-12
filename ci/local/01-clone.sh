#!/usr/bin/env bash
# Clone or refresh all service repos listed in scripts/service-repos.list.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SKIP_CLONE="${SKIP_CLONE:-0}"
FRESH_CLONE="${FRESH_CLONE:-0}"

clone_one() {
  local name="$1" path_rel="$2" remote="$3" branch="$4"
  local dest="${WORK_ROOT}/${path_rel}"

  [[ -n "$remote" ]] || { warn "Skip ${name}: empty remote"; return 0; }

  if [[ "$FRESH_CLONE" -eq 1 && -d "$dest" ]]; then
    log "Remove existing ${dest}"
    run_or_echo rm -rf "$dest"
  fi

  if [[ ! -d "${dest}/.git" ]]; then
    log "Clone ${remote} → ${dest}"
    local args=(clone --depth 1)
    if [[ -n "$branch" && "$branch" != "-" ]]; then
      args+=(--branch "$branch")
    fi
    run_or_echo git "${args[@]}" "$remote" "$dest"
  else
    log "Fetch ${name}"
    run_or_echo git -C "$dest" fetch --all --tags --prune
    if [[ -n "$branch" && "$branch" != "-" ]]; then
      if git -C "$dest" show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
        log "Checkout ${name} @ origin/${branch}"
        run_or_echo git -C "$dest" checkout -B "$branch" "origin/${branch}"
      else
        warn "${name}: branch origin/${branch} not found"
      fi
    fi
  fi

  if [[ "${DRY_RUN:-0}" -eq 0 && -d "${dest}/.git" ]]; then
    echo "  OK  ${name} @ $(git -C "$dest" rev-parse --short HEAD)"
  fi
}

main() {
  [[ "$SKIP_CLONE" -eq 1 ]] && { log "Skip clone (SKIP_CLONE=1)"; return 0; }

  log "Clone service repos → ${WORK_ROOT}"
  while IFS='|' read -r name path_rel remote branch _rest; do
    [[ -z "$name" || "$name" =~ ^[[:space:]]*# ]] && continue
    clone_one "$name" "$path_rel" "$remote" "${branch:--}"
  done < "$REPO_LIST"
  log "Clone complete"
}

main "$@"
