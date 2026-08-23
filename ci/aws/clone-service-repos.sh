#!/usr/bin/env bash
# Clone service repos listed in scripts/service-repos.list (read-only; never push).
set -euo pipefail

ORCHESTRATION_SRC="${ORCHESTRATION_SRC:-${CODEBUILD_SRC_DIR:-.}}"
CLONE_ROOT="${CLONE_ROOT:-/tmp/repos}"
LIST_FILE="${SERVICE_REPOS_LIST:-$ORCHESTRATION_SRC/scripts/service-repos.list}"

if [[ ! -f "$LIST_FILE" ]]; then
  echo "Missing service list: $LIST_FILE" >&2
  exit 1
fi

mkdir -p "$CLONE_ROOT"
FAILED=0

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  IFS='|' read -r NAME PATH_REL REMOTE BRANCH <<< "$line"
  DEST="${CLONE_ROOT}/${PATH_REL}"
  echo "==== Cloning ${REMOTE} -> ${DEST} (branch=${BRANCH}) ===="
  rm -rf "$DEST"
  CLONE_ARGS=(--depth 1)
  if [[ -n "$BRANCH" && "$BRANCH" != "-" ]]; then
    CLONE_ARGS+=(--branch "$BRANCH")
  fi
  if git clone "${CLONE_ARGS[@]}" "$REMOTE" "$DEST"; then
    git -C "$DEST" remote set-url --push origin DISABLED
    git -C "$DEST" config user.name "codebuild-readonly"
    git -C "$DEST" config user.email "noreply@invalid"
    git -C "$DEST" log -1 --oneline
    git -C "$DEST" remote -v
  else
    echo "FAILED: $REMOTE"
    FAILED=1
  fi
done < "$LIST_FILE"

echo "==== Clone summary ===="
ls -la "$CLONE_ROOT"
for d in "$CLONE_ROOT"/*; do
  [[ -d "$d" ]] || continue
  if [[ -d "$d/.git" ]]; then
    echo "OK  $(basename "$d")"
  else
    echo "MISS $(basename "$d")"
  fi
done

if [[ "$FAILED" -ne 0 ]]; then
  echo "One or more service clones failed" >&2
  exit 1
fi
