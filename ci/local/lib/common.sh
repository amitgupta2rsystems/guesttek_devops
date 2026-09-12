#!/usr/bin/env bash
# Shared helpers for ci/local pipeline scripts.

log()  { echo "==> $*"; }
warn() { echo "!!  $*" >&2; }
die()  { echo "Error: $*" >&2; exit 1; }

run_or_echo() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

pause_for_user() {
  [[ "${DRY_RUN:-0}" -eq 1 || "${NO_PAUSE:-0}" -eq 1 ]] && return 0
  echo ""
  read -r -p "Press Enter to continue (Ctrl+C to stop)... "
  echo ""
}

preflight_host() {
  require_cmd git docker patch
  [[ -f "$REPO_LIST" ]] || die "Missing repo list: ${REPO_LIST}"
  [[ -d "$PATCH_DIR" ]] || die "Missing patches dir: ${PATCH_DIR}"
  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    docker info >/dev/null 2>&1 || die "Docker daemon is not running"
  fi
  run_or_echo mkdir -p "$WORK_ROOT"
}
