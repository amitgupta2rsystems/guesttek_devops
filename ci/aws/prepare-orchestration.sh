#!/usr/bin/env bash
# Prepare orchestration checkout paths (read-only remotes).
set -euo pipefail

echo "==== Orchestration source (guesttek_devops) ===="
echo "CODEBUILD_SRC_DIR=${CODEBUILD_SRC_DIR}"
ls -la "${CODEBUILD_SRC_DIR}"
ls -la "${CODEBUILD_SRC_DIR}/ci/aws" "${CODEBUILD_SRC_DIR}/scripts"
git -C "${CODEBUILD_SRC_DIR}" remote -v || true
git -C "${CODEBUILD_SRC_DIR}" log -1 --oneline || true
git -C "${CODEBUILD_SRC_DIR}" remote set-url --push origin DISABLED 2>/dev/null || true

CLONE_ROOT="${CLONE_ROOT:-/tmp/repos}"
ORCHESTRATION_DIR="${ORCHESTRATION_DIR:-/tmp/repos/guesttek_devops}"
mkdir -p "${CLONE_ROOT}"
rm -rf "${ORCHESTRATION_DIR}"
cp -a "${CODEBUILD_SRC_DIR}" "${ORCHESTRATION_DIR}"
git -C "${ORCHESTRATION_DIR}" remote set-url --push origin DISABLED 2>/dev/null || true
