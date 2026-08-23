#!/usr/bin/env bash
# Generate release-manifest.yaml after a successful package build.
set -euo pipefail

MONOREPO_ROOT="${CLONE_ROOT:-/tmp/repos}"
ORCHESTRATION_SRC="${ORCHESTRATION_SRC:-${CODEBUILD_SRC_DIR:-.}}"
PLATFORM="${PLATFORM:-amd64}"
MANIFEST="${MONOREPO_ROOT}/release-manifest.yaml"

DATE_TAG=""
if [[ -f "${MONOREPO_ROOT}/deploy/.env" ]]; then
  DATE_TAG="$(grep -m1 '^DATE_TAG=' "${MONOREPO_ROOT}/deploy/.env" | cut -d= -f2- | tr -d ' "'\''')"
fi

echo "==== Generating release-manifest.yaml ===="
MONOREPO_ROOT="$MONOREPO_ROOT" \
  "${ORCHESTRATION_SRC}/scripts/release-manifest.sh" generate \
  --output "$MANIFEST" \
  --platform "$PLATFORM" \
  ${DATE_TAG:+--date-tag "$DATE_TAG"}

echo "==== release-manifest.yaml ===="
sed -n '1,40p' "$MANIFEST"
