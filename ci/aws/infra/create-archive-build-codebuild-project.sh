#!/usr/bin/env bash
# CodeBuild project: ArchiveBuild stage (store every build under builds/ in S3).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

ARCHIVE_PROJECT_NAME="${ARCHIVE_PROJECT_NAME:-guesttek-camsuite-edge-archive-build}"
ARCHIVE_ROLE_NAME="${ARCHIVE_ROLE_NAME:-codebuild-guesttek-camsuite-edge-archive-build-role}"
BUILDSPEC_PATH="${SCRIPT_DIR}/../buildspec-archive-build.yml"
DEV_BUILD_ID_SCRIPT="${SCRIPT_DIR}/../resolve-dev-build-id.sh"

[[ -f "$BUILDSPEC_PATH" ]] || { echo "Missing ${BUILDSPEC_PATH}" >&2; exit 1; }
[[ -f "$DEV_BUILD_ID_SCRIPT" ]] || { echo "Missing ${DEV_BUILD_ID_SCRIPT}" >&2; exit 1; }

echo "==> Upload resolve-dev-build-id.sh to S3"
aws s3 cp "$DEV_BUILD_ID_SCRIPT" "s3://${BUNDLES_BUCKET}/guesttek/ci/resolve-dev-build-id.sh" --region "$AWS_REGION"

echo "==> IAM role ${ARCHIVE_ROLE_NAME}"
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$ARCHIVE_ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ARCHIVE_ROLE_NAME" \
    --assume-role-policy-document "$TRUST" >/dev/null
fi

PIPELINE_BUCKET="guesttek-edge-pipeline-artifacts-${AWS_ACCOUNT_ID}"
POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": [
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/${ARCHIVE_PROJECT_NAME}",
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/${ARCHIVE_PROJECT_NAME}:*"
      ]
    },
    {
      "Sid": "PipelineArtifacts",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${PIPELINE_BUCKET}",
        "arn:aws:s3:::${PIPELINE_BUCKET}/*"
      ]
    },
    {
      "Sid": "ReadCiScripts",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${BUNDLES_BUCKET}",
        "arn:aws:s3:::${BUNDLES_BUCKET}/*"
      ]
    },
    {
      "Sid": "ArchiveBuilds",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${ARTIFACTS_BUCKET}",
        "arn:aws:s3:::${ARTIFACTS_BUCKET}/${BUILDS_ARCHIVE_PREFIX:-builds}/*"
      ]
    }
  ]
}
EOF
)
aws iam put-role-policy --role-name "$ARCHIVE_ROLE_NAME" \
  --policy-name "${ARCHIVE_PROJECT_NAME}-inline" \
  --policy-document "$POLICY"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ARCHIVE_ROLE_NAME}"
export ROLE_ARN ARCHIVE_PROJECT_NAME ARTIFACTS_BUCKET BUILDS_ARCHIVE_PREFIX
export BUILDS_ARCHIVE_PREFIX="${BUILDS_ARCHIVE_PREFIX:-builds}"
export BUILDSPEC
BUILDSPEC=$(python3 -c "import json, pathlib; print(json.dumps(pathlib.Path('${BUILDSPEC_PATH}').read_text()))")

python3 - <<'PY' > /tmp/archive-build-codebuild.json
import json, os
buildspec = json.loads(os.environ["BUILDSPEC"])
print(json.dumps({
  "name": os.environ["ARCHIVE_PROJECT_NAME"],
  "description": "Archive build output to S3 builds/ (retained even if LabSmoke fails)",
  "source": {
    "type": "CODEPIPELINE",
    "buildspec": buildspec,
    "insecureSsl": False,
  },
  "artifacts": {"type": "CODEPIPELINE"},
  "cache": {"type": "NO_CACHE"},
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "privilegedMode": False,
    "imagePullCredentialsType": "CODEBUILD",
    "environmentVariables": [
      {"name": "ARTIFACTS_BUCKET", "value": os.environ["ARTIFACTS_BUCKET"], "type": "PLAINTEXT"},
      {"name": "BUILDS_PREFIX", "value": os.environ.get("BUILDS_ARCHIVE_PREFIX", "builds"), "type": "PLAINTEXT"},
    ],
  },
  "serviceRole": os.environ["ROLE_ARN"],
  "timeoutInMinutes": 15,
  "queuedTimeoutInMinutes": 60,
}))
PY

EXISTS=$(aws codebuild batch-get-projects --names "$ARCHIVE_PROJECT_NAME" --region "$AWS_REGION" \
  --query 'projects[0].name' --output text 2>/dev/null || true)

if [[ "$EXISTS" == "$ARCHIVE_PROJECT_NAME" ]]; then
  echo "Updating CodeBuild project ${ARCHIVE_PROJECT_NAME}..."
  aws codebuild update-project --cli-input-json file:///tmp/archive-build-codebuild.json --region "$AWS_REGION" >/dev/null
else
  echo "Creating CodeBuild project ${ARCHIVE_PROJECT_NAME}..."
  aws codebuild create-project --cli-input-json file:///tmp/archive-build-codebuild.json --region "$AWS_REGION" >/dev/null
fi

echo "ArchiveBuild CodeBuild project ready: ${ARCHIVE_PROJECT_NAME}"
