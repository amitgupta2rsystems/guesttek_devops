#!/usr/bin/env bash
# Apply orchestration patches/patches/series onto cloned repos (work copy only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SKIP_PATCHES="${SKIP_PATCHES:-0}"

apply_one() {
  local entry="$1"
  local patch_name="${entry%%|*}"
  local subdir=""
  [[ "$entry" == *"|"* ]] && subdir="${entry#*|}"

  local patch_file="${PATCH_DIR}/${patch_name}"
  local apply_dir="${WORK_ROOT}"
  [[ -n "$subdir" ]] && apply_dir="${WORK_ROOT}/${subdir}"

  [[ -f "$patch_file" ]] || die "Missing patch file: ${patch_file}"
  [[ -d "$apply_dir" ]] || die "Missing apply directory: ${apply_dir}"

  local label="$patch_name"
  [[ -n "$subdir" ]] && label="${patch_name} (in ${subdir})"

  if patch -p1 --dry-run -N -s -f -d "$apply_dir" < "$patch_file" >/dev/null 2>&1; then
    log "Apply ${label}"
    [[ "${DRY_RUN:-0}" -eq 0 ]] && patch -p1 -N -s -f -d "$apply_dir" < "$patch_file"
    return 0
  fi

  if patch -p1 --reverse --dry-run -N -s -f -d "$apply_dir" < "$patch_file" >/dev/null 2>&1; then
    log "Skip ${label} (already applied)"
    return 0
  fi

  die "Patch failed (context mismatch): ${label}"
}

main() {
  [[ "$SKIP_PATCHES" -eq 1 ]] && { log "Skip patches (SKIP_PATCHES=1)"; return 0; }
  [[ -f "$PATCH_SERIES" ]] || die "Missing patch series: ${PATCH_SERIES}"

  log "Apply patches from ${PATCH_SERIES}"
  while IFS= read -r entry || [[ -n "${entry:-}" ]]; do
    [[ -z "${entry// }" ]] && continue
    [[ "${entry#\#}" != "$entry" ]] && continue
    apply_one "$entry"
  done < "$PATCH_SERIES"

  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "${WORK_ROOT}/.patches-applied"
  fi
  log "Patches done"
}

main "$@"
