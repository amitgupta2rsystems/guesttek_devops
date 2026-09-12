#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

START_BUILD="${START_BUILD:-0}"
"${SCRIPT_DIR}/codebuild-service-role/create-role.sh"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CODEBUILD_ROLE_NAME}"
export ROLE_ARN CODEBUILD_PROJECT_NAME ORCHESTRATION_REPO CODECONNECTIONS_ARN \
  ARTIFACTS_BUCKET CODEBUILD_COMPUTE_TYPE CODEBUILD_TIMEOUT_MINUTES \
  GIT_SSH_PARAM BUNDLES_BUCKET BUNDLES_PREFIX BUILDS_ARCHIVE_PREFIX RELEASE_PREFIX

BUILDSPEC_PATH="${SCRIPT_DIR}/../buildspec.yml"
DEV_BUILD_ID_SCRIPT="${SCRIPT_DIR}/../resolve-dev-build-id.sh"

[[ -f "$BUILDSPEC_PATH" ]] || { echo "Missing ${BUILDSPEC_PATH}" >&2; exit 1; }

if [[ -f "$DEV_BUILD_ID_SCRIPT" ]]; then
  echo "==> Upload resolve-dev-build-id.sh to S3"
  aws s3 cp "$DEV_BUILD_ID_SCRIPT" "s3://${BUNDLES_BUCKET}/guesttek/ci/resolve-dev-build-id.sh" --region "$AWS_REGION"
fi

export BUILDSPEC
BUILDSPEC=$(python3 -c "import json, pathlib; print(json.dumps(pathlib.Path('${BUILDSPEC_PATH}').read_text()))")

python3 - <<'PY' > /tmp/codebuild-project.json
import json, os
buildspec = json.loads(os.environ["BUILDSPEC"])
print(json.dumps({
  "name": os.environ["CODEBUILD_PROJECT_NAME"],
  "description": "guesttek_devops orchestration (pipeline: Source from GitHub → BuildOutput)",
  "source": {
    "type": "CODEPIPELINE",
    "buildspec": buildspec,
    "insecureSsl": False,
  },
  "artifacts": {
    "type": "CODEPIPELINE",
  },
  "cache": {"type": "NO_CACHE"},
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": os.environ["CODEBUILD_COMPUTE_TYPE"],
    "privilegedMode": True,
    "imagePullCredentialsType": "CODEBUILD",
    "environmentVariables": [
      {"name": "GIT_SSH_PARAM", "value": os.environ.get("GIT_SSH_PARAM", "/guesttek/codebuild/git-ssh-private-key"), "type": "PLAINTEXT"},
      {"name": "CLONE_ROOT", "value": "/tmp/repos", "type": "PLAINTEXT"},
      {"name": "ORCHESTRATION_DIR", "value": "/tmp/repos/guesttek_devops", "type": "PLAINTEXT"},
      {"name": "PLATFORM", "value": "amd64", "type": "PLAINTEXT"},
      {"name": "CAMSUITE_BUNDLE_ARCH", "value": "amd64", "type": "PLAINTEXT"},
      {"name": "BUNDLES_BUCKET", "value": os.environ["BUNDLES_BUCKET"], "type": "PLAINTEXT"},
      {"name": "BUNDLES_PREFIX", "value": os.environ["BUNDLES_PREFIX"], "type": "PLAINTEXT"},
      {"name": "ARTIFACTS_BUCKET", "value": os.environ["ARTIFACTS_BUCKET"], "type": "PLAINTEXT"},
      {"name": "BUILDS_PREFIX", "value": os.environ.get("BUILDS_ARCHIVE_PREFIX", "builds"), "type": "PLAINTEXT"},
      {"name": "RELEASE_PREFIX", "value": os.environ.get("RELEASE_PREFIX", "guesttek-camsuite-edge"), "type": "PLAINTEXT"},
      {"name": "DEV_BUILD_ID_SCRIPT_S3", "value": f"s3://{os.environ['BUNDLES_BUCKET']}/guesttek/ci/resolve-dev-build-id.sh", "type": "PLAINTEXT"},
    ],
  },
  "serviceRole": os.environ["ROLE_ARN"],
  "timeoutInMinutes": int(os.environ["CODEBUILD_TIMEOUT_MINUTES"]),
  "queuedTimeoutInMinutes": 480,
}))
PY

EXISTS=$(aws codebuild batch-get-projects --names "$CODEBUILD_PROJECT_NAME" --region "$AWS_REGION" \
  --query 'projects[0].name' --output text 2>/dev/null || true)

if [[ "$EXISTS" == "$CODEBUILD_PROJECT_NAME" ]]; then
  echo "Updating CodeBuild project ${CODEBUILD_PROJECT_NAME}..."
  aws codebuild update-project \
    --cli-input-json file:///tmp/codebuild-project.json \
    --region "$AWS_REGION" >/dev/null
else
  echo "Creating CodeBuild project ${CODEBUILD_PROJECT_NAME}..."
  aws codebuild create-project \
    --cli-input-json file:///tmp/codebuild-project.json \
    --region "$AWS_REGION" >/dev/null
fi

echo "Project: ${CODEBUILD_PROJECT_NAME} (${AWS_REGION})"

if [[ "$START_BUILD" == "1" ]]; then
  BUILD_ID=$(aws codebuild start-build --project-name "$CODEBUILD_PROJECT_NAME" --region "$AWS_REGION" \
    --query 'build.id' --output text)
  echo "Started build: ${BUILD_ID}"
fi
