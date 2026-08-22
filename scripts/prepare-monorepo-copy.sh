#!/usr/bin/env bash
# Copy the GuestTek monorepo, then clean only the copy. The source tree is never modified.
#
# Usage:
#   ./scripts/prepare-monorepo-copy.sh --dest /tmp/guesttek-build
#   ./scripts/prepare-monorepo-copy.sh --source /home/proximus2/GuestTek --dest /var/lib/jenkins/workspace/.../guestek-build
#   ./scripts/prepare-monorepo-copy.sh --dest ./guestek-build --skip-git-reset
#
# Typical flow:
#   1. rsync source → dest (mirror with --delete, skip huge build outputs)
#   2. remove leftover build artifacts inside dest
#   3. reset each git repo in dest to release-manifest.yaml pins

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEST=""
RESET_GIT=1
DRY_RUN=0

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

log() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --skip-git-reset) RESET_GIT=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$DEST" ]] || { echo "Error: --dest is required" >&2; usage 1; }
[[ -d "$SOURCE" ]] || { echo "Error: source not found: ${SOURCE}" >&2; exit 1; }

SOURCE="$(cd "$SOURCE" && pwd)"
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
  --exclude 'deploy/guesttek-camsuite-edge-*.tar'
  --exclude 'guesttek-camsuite-edge/docker/camsuite-images-*.tar'
)

log "Copy ${SOURCE}/ → ${DEST}/"
run rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${SOURCE}/" "${DEST}/"

log "Remove build outputs in copy only"
run rm -rf "${DEST}/artifacts"
run find "${DEST}" -maxdepth 1 -type f \( \
  -name 'guesttek-camsuite-edge_*.deb' \
  -o -name '*.buildinfo' \
  -o -name '*.changes' \
  -o -name 'build.log' \
  -o -name 'build-deb.log' \
  \) -delete 2>/dev/null || true
run rm -f "${DEST}"/deploy/guesttek-camsuite-edge-*.tar 2>/dev/null || true
run rm -f "${DEST}"/guesttek-camsuite-edge/docker/camsuite-images-*.tar 2>/dev/null || true
run rm -f "${DEST}/patches/.applied" 2>/dev/null || true

if [[ "$RESET_GIT" -eq 1 ]]; then
  MANIFEST="${DEST}/release-manifest.yaml"
  [[ -f "$MANIFEST" ]] || { echo "Error: missing ${MANIFEST}" >&2; exit 1; }
  log "Reset git repos in copy from ${MANIFEST}"
  run "${DEST}/scripts/checkout-from-manifest.sh" \
    --root "$DEST" \
    --manifest "$MANIFEST" \
    --bundles-dir "$DEST" \
    --strict
fi

run chmod +x \
  "${DEST}/build-package.sh" \
  "${DEST}/scripts/"*.sh \
  "${DEST}/ci/"*.sh 2>/dev/null || true

[[ -f "${DEST}/release-manifest.yaml" ]] || { echo "Error: release-manifest.yaml missing in copy" >&2; exit 1; }
log "Copy ready: ${DEST}"
