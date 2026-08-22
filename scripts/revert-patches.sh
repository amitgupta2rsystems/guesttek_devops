#!/usr/bin/env bash
# Revert local monorepo patches (reverse order of patches/series).
#
# Usage:
#   ./scripts/revert-patches.sh
#   ./scripts/revert-patches.sh --dry-run

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="${ROOT}/patches"
STAMP="${ROOT}/patches/.applied"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,6p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mapfile -t PATCHES < <(grep -v '^[[:space:]]*$' "${PATCH_DIR}/series" | grep -v '^#' || true)

echo "==> Reverting patches (newest first)"
for (( i=${#PATCHES[@]}-1; i>=0; i-- )); do
  patch="${PATCHES[$i]}"
  path="${PATCH_DIR}/${patch}"
  [[ -f "$path" ]] || continue

  if patch -p1 --reverse --dry-run -N -s -f -d "$ROOT" < "$path" >/dev/null 2>&1; then
    echo "  revert ${patch}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      patch -p1 --reverse -N -s -f -d "$ROOT" < "$path"
    fi
  else
    echo "  skip  ${patch} (not applied or already reverted)"
  fi
done

if [[ "$DRY_RUN" -eq 0 && -f "$STAMP" ]]; then
  rm -f "$STAMP"
  echo "==> Patches reverted."
fi
