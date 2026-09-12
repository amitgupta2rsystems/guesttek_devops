#!/usr/bin/env bash
# Start LabSmoke CodeBuild standalone — fetches .deb zip from S3 and runs smoke on lab EC2.
#
# Usage:
#   ./start-lab-smoke.sh
#   ./start-lab-smoke.sh s3://guesttek-camsuite-edge-artifacts-ACCT/guesttek-camsuite-edge/BUILD_ID/camsuite-edge-deb
#   S3_ARTIFACT_URI=s3://... ./start-lab-smoke.sh
#
# List recent build artifacts:
#   aws s3 ls s3://guesttek-camsuite-edge-artifacts-705959604310/guesttek-camsuite-edge/ --recursive

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

PROJECT="${LAB_SMOKE_PROJECT_NAME:-guesttek-camsuite-edge-lab-smoke}"
DEFAULT_S3="${ARTIFACTS_BUCKET:-guesttek-camsuite-edge-artifacts-${AWS_ACCOUNT_ID}}"
S3_URI="${1:-${S3_ARTIFACT_URI:-}}"

if [[ -z "$S3_URI" ]]; then
  echo "No S3 URI given — using latest published dev build"
  RESOLVE_SCRIPT="${SCRIPT_DIR}/../resolve-dev-build-id.sh"
  [[ -f "$RESOLVE_SCRIPT" ]] || { echo "Missing ${RESOLVE_SCRIPT}" >&2; exit 1; }
  export ARTIFACTS_BUCKET="$DEFAULT_S3" RELEASE_PREFIX="${RELEASE_PREFIX:-guesttek-camsuite-edge}"
  DEV_BUILD_ID="$("$RESOLVE_SCRIPT" latest "$RELEASE_PREFIX")"
  S3_URI="s3://${DEFAULT_S3}/${RELEASE_PREFIX}/${DEV_BUILD_ID}/camsuite-edge-deb"
fi

echo "==> Starting ${PROJECT}"
echo "    Artifact: ${S3_URI}"
echo "    Lab:      ${LAB_SMOKE_USER:-ubuntu}@${LAB_SMOKE_HOST:-13.201.192.139}"

BUILD_ID=$(aws codebuild start-build \
  --project-name "$PROJECT" \
  --region "$AWS_REGION" \
  --environment-variables-override \
    "name=S3_ARTIFACT_URI,value=${S3_URI},type=PLAINTEXT" \
  --query 'build.id' --output text)

echo "Build started: ${BUILD_ID}"
echo "Logs: https://${AWS_REGION}.console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT}/build/${BUILD_ID}/log"
