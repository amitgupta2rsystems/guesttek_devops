#!/usr/bin/env bash
# Apply local monorepo patches for amd64 packaging builds (see patches/README.md).
#
# series line formats:
#   name.patch                  — apply with patch -p1 at monorepo root
#   name.patch|subdir           — apply with patch -p1 inside ROOT/subdir
#                                (for verbatim repo-root patches, e.g. Smriti alert)
#
# Usage:
#   ./scripts/apply-patches.sh
#   ./scripts/apply-patches.sh --dry-run
#   ./scripts/apply-patches.sh --check   # exit 1 if any patch is not applied

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="${ROOT}/patches"
STAMP="${ROOT}/patches/.applied"
DRY_RUN=0
CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -d "$PATCH_DIR" ]] || { echo "Missing ${PATCH_DIR}" >&2; exit 1; }
[[ -f "${PATCH_DIR}/series" ]] || { echo "Missing ${PATCH_DIR}/series" >&2; exit 1; }

# Parse series entry → patch file + apply directory (absolute).
parse_entry() {
  local entry="$1"
  PATCH_FILE="${entry%%|*}"
  local sub=""
  if [[ "$entry" == *"|"* ]]; then
    sub="${entry#*|}"
  fi
  PATCH_PATH="${PATCH_DIR}/${PATCH_FILE}"
  if [[ -n "$sub" ]]; then
    APPLY_DIR="${ROOT}/${sub}"
  else
    APPLY_DIR="$ROOT"
  fi
}

apply_one() {
  local entry="$1"
  parse_entry "$entry"
  [[ -f "$PATCH_PATH" ]] || { echo "Missing patch: ${PATCH_PATH}" >&2; exit 1; }
  [[ -d "$APPLY_DIR" ]] || { echo "Missing apply dir: ${APPLY_DIR}" >&2; exit 1; }

  local label="$PATCH_FILE"
  [[ "$APPLY_DIR" != "$ROOT" ]] && label="${PATCH_FILE} (in ${APPLY_DIR#"${ROOT}"/})"

  if patch -p1 --dry-run -N -s -f -d "$APPLY_DIR" < "$PATCH_PATH" >/dev/null 2>&1; then
    echo "  apply ${label}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      patch -p1 -N -s -f -d "$APPLY_DIR" < "$PATCH_PATH"
    fi
    return 0
  fi

  if patch -p1 --reverse --dry-run -N -s -f -d "$APPLY_DIR" < "$PATCH_PATH" >/dev/null 2>&1; then
    echo "  skip  ${label} (already applied)"
    return 0
  fi

  echo "  FAIL  ${label} (context mismatch — repo may have drifted)" >&2
  return 1
}

check_one() {
  local entry="$1"
  parse_entry "$entry"
  local label="$PATCH_FILE"
  [[ "$APPLY_DIR" != "$ROOT" ]] && label="${PATCH_FILE} (in ${APPLY_DIR#"${ROOT}"/})"

  if patch -p1 --reverse --dry-run -N -s -f -d "$APPLY_DIR" < "$PATCH_PATH" >/dev/null 2>&1; then
    echo "  OK    ${label}"
    return 0
  fi
  echo "  MISS  ${label}" >&2
  return 1
}

if [[ "$CHECK" -eq 1 ]]; then
  echo "==> Checking applied patches under ${ROOT}"
  failed=0
  while IFS= read -r entry || [[ -n "${entry:-}" ]]; do
    [[ -z "${entry// }" ]] && continue
    [[ "${entry#\#}" != "$entry" ]] && continue
    check_one "$entry" || failed=1
  done < "${PATCH_DIR}/series"
  exit "$failed"
fi

echo "==> Applying patches from ${PATCH_DIR}"
while IFS= read -r entry || [[ -n "${entry:-}" ]]; do
  [[ -z "${entry// }" ]] && continue
  [[ "${entry#\#}" != "$entry" ]] && continue
  apply_one "$entry"
done < "${PATCH_DIR}/series"

if [[ "$DRY_RUN" -eq 0 ]]; then
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STAMP"
  echo "==> Patches applied. Stamp: ${STAMP}"
fi
