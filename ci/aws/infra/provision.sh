#!/usr/bin/env bash
# Provision GuestTek camsuite edge CodeBuild infrastructure (idempotent).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==== Artifact bucket ===="
"${SCRIPT_DIR}/create-artifact-bucket.sh"

echo "==== CodeBuild service role ===="
"${SCRIPT_DIR}/codebuild-service-role/create-role.sh"

echo "==== CodeBuild project ===="
START_BUILD="${START_BUILD:-0}" "${SCRIPT_DIR}/create-codebuild-project.sh"

echo "==== Trigger IAM user (optional) ===="
if [[ "${CREATE_TRIGGER_USER:-0}" == "1" ]]; then
  "${SCRIPT_DIR}/iam-trigger-user/create-user.sh"
else
  echo "Skip (set CREATE_TRIGGER_USER=1 to create ${TRIGGER_USER_NAME:-guesttek-build})"
fi

echo "==== Done ===="
