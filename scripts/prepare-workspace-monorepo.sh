#!/usr/bin/env bash
# Prepare Jenkins workspace: orchestration seed + clone service repos from remotes.
#
# Service repos are defined in scripts/service-repos.list (not release-manifest.yaml).
# release-manifest.yaml is generated during the Build stage from cloned repo HEADs.
#
# Usage:
#   ./scripts/prepare-workspace-monorepo.sh \
#     --orchestration-src /home/proximus2/GuestTek \
#     --dest /var/lib/jenkins/workspace/.../guestek-build

set -euo pipefail

ORCHESTRATION_SRC=""
DEST=""
CLONE_REMOTES=1
SERVICE_BRANCHES=0
PIN_MANIFEST=0
DRY_RUN=0

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

log() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --orchestration-src) ORCHESTRATION_SRC="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --pin-manifest) PIN_MANIFEST=1; shift ;;
    --service-branches) SERVICE_BRANCHES=1; shift ;;
    --clone-remotes) CLONE_REMOTES=1; shift ;;
    --no-clone-remotes) CLONE_REMOTES=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$ORCHESTRATION_SRC" && -n "$DEST" ]] || {
  echo "Error: --orchestration-src and --dest are required" >&2
  usage 1
}
[[ -d "$ORCHESTRATION_SRC" ]] || { echo "Error: orchestration source not found: ${ORCHESTRATION_SRC}" >&2; exit 1; }

ORCHESTRATION_SRC="$(cd "$ORCHESTRATION_SRC" && pwd)"
DEST="$(mkdir -p "$DEST" && cd "$DEST" && pwd)"

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

RSYNC_EXCLUDES=(
  --exclude artifacts/
  --exclude '*.deb'
  --exclude '*.buildinfo'
  --exclude '*.changes'
  --exclude 'build.log'
  --exclude 'build-deb.log'
  --exclude 'release-manifest.yaml'
  --exclude 'release-manifest.example.yaml'
  --exclude 'deploy/'
  --exclude 'guesttek-camsuite-edge/'
  --exclude 'camsuite-emb-*/'
  --exclude 'suspicious_objects_inference_service/'
  --exclude 'alert_manager_service/'
  --exclude 'alert_patch_extracted/'
  --exclude 'inference_patch_extracted/'
  --exclude '*.7z'
)

log "Seed orchestration ${ORCHESTRATION_SRC}/ → ${DEST}/"
run rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${ORCHESTRATION_SRC}/" "${DEST}/"

run chmod +x \
  "${DEST}/build-package.sh" \
  "${DEST}/scripts/"*.sh \
  "${DEST}/ci/"*.sh 2>/dev/null || true

[[ -f "${DEST}/scripts/service-repos.list" ]] || {
  echo "Error: missing ${DEST}/scripts/service-repos.list" >&2
  exit 1
}

log "Bootstrap deploy/ and guesttek-camsuite-edge/ from bundles"
run "${DEST}/ci/bootstrap-orchestration.sh" --root "$DEST" --bundles-dir "$DEST"

if [[ "$CLONE_REMOTES" -eq 1 ]]; then
  if [[ "$PIN_MANIFEST" -eq 1 && -f "${DEST}/release-manifest.yaml" ]]; then
    log "Pin repos to optional release-manifest.yaml in workspace"
    run "${DEST}/scripts/checkout-from-manifest.sh" \
      --root "$DEST" \
      --manifest "${DEST}/release-manifest.yaml" \
      --bundles-dir "$DEST" \
      --clone-remotes \
      --strict
  else
    log "Clone/fetch service repos from scripts/service-repos.list"
    FETCH_ARGS=(--root "$DEST" --clone-missing)
    [[ "$SERVICE_BRANCHES" -eq 1 ]] && FETCH_ARGS+=(--service-branches)
    run "${DEST}/scripts/fetch-monorepo.sh" "${FETCH_ARGS[@]}"
  fi
elif [[ "$SERVICE_BRANCHES" -eq 1 ]]; then
  run "${DEST}/scripts/checkout-service-branches.sh"
fi

log "Workspace ready: ${DEST} (release-manifest.yaml will be generated at build time)"
