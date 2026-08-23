#!/usr/bin/env bash
# Apply orchestration patches/series onto cloned service repos (local only; never commit).
set -euo pipefail

ORCHESTRATION_SRC="${ORCHESTRATION_SRC:-${CODEBUILD_SRC_DIR:-.}}"
CLONE_ROOT="${CLONE_ROOT:-/tmp/repos}"
SERIES_FILE="${ORCHESTRATION_SRC}/patches/series"
PATCH_DIR="${ORCHESTRATION_SRC}/patches"

if [[ ! -f "$SERIES_FILE" ]]; then
  echo "No patches/series at $SERIES_FILE — skipping patches"
  exit 0
fi

echo "==== Applying local patches from $SERIES_FILE ===="
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  PATCH_NAME="${line%%|*}"
  SUBDIR=""
  if [[ "$line" == *"|"* ]]; then
    SUBDIR="${line#*|}"
  fi
  PATCH_FILE="${PATCH_DIR}/${PATCH_NAME}"
  if [[ ! -f "$PATCH_FILE" ]]; then
    echo "MISSING patch file: $PATCH_FILE" >&2
    exit 1
  fi
  if [[ -n "$SUBDIR" ]]; then
    TARGET="${CLONE_ROOT}/${SUBDIR}"
    echo "-> patch -p1 in ${TARGET} < ${PATCH_NAME}"
    (cd "$TARGET" && patch -p1 --forward --reject-file=- < "$PATCH_FILE") || {
      echo "FAILED applying $PATCH_NAME in $SUBDIR" >&2
      exit 1
    }
  else
    echo "-> patch -p1 in ${CLONE_ROOT} < ${PATCH_NAME}"
    (cd "$CLONE_ROOT" && patch -p1 --forward --reject-file=- < "$PATCH_FILE") || {
      echo "FAILED applying $PATCH_NAME at clone root" >&2
      exit 1
    }
  fi
done < "$SERIES_FILE"

echo "==== Patches applied ===="
