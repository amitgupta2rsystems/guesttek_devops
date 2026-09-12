#!/usr/bin/env bash
# Set pipeline to: Source → Build → LabSmoke → Publish
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

PIPELINE_NAME="${PIPELINE_NAME:-guesttek-camsuite-edge-pipeline}"
BUILD_PROJECT="${CODEBUILD_PROJECT_NAME:-guesttek-camsuite-edge}"
LAB_SMOKE_PROJECT="${LAB_SMOKE_PROJECT_NAME:-guesttek-camsuite-edge-lab-smoke}"
PUBLISH_PROJECT="${PUBLISH_PROJECT_NAME:-guesttek-camsuite-edge-publish}"
export BUILD_PROJECT LAB_SMOKE_PROJECT PUBLISH_PROJECT AWS_REGION \
  CODECONNECTIONS_ARN ORCHESTRATION_REPO GITHUB_BRANCH

GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
export GITHUB_BRANCH

echo "==> Ensure Build, LabSmoke and Publish CodeBuild projects exist"
"${SCRIPT_DIR}/create-codebuild-project.sh"
"${SCRIPT_DIR}/create-lab-smoke-codebuild-project.sh"
"${SCRIPT_DIR}/create-publish-codebuild-project.sh"

echo "==> Update pipeline definition (remove ArchiveBuild if present)"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" --output json \
  | python3 "${SCRIPT_DIR}/patch-pipeline-stages.py" > /tmp/pipeline-stages-update.json

aws codepipeline update-pipeline --cli-input-json file:///tmp/pipeline-stages-update.json --region "$AWS_REGION" >/dev/null

echo "Pipeline ${PIPELINE_NAME}: Source → Build → LabSmoke → Publish"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" \
  --query 'pipeline.stages[*].name' --output text
