#!/usr/bin/env bash
# CodeBuild project: Publish stage (promote BuildOutput to release S3, replace old artifact).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

PUBLISH_PROJECT_NAME="${PUBLISH_PROJECT_NAME:-guesttek-camsuite-edge-publish}"
PUBLISH_ROLE_NAME="${PUBLISH_ROLE_NAME:-codebuild-guesttek-camsuite-edge-publish-role}"
BUILDSPEC_PATH="${SCRIPT_DIR}/../buildspec-publish.yml"

DEV_BUILD_ID_SCRIPT="${SCRIPT_DIR}/../resolve-dev-build-id.sh"

[[ -f "$BUILDSPEC_PATH" ]] || { echo "Missing ${BUILDSPEC_PATH}" >&2; exit 1; }
[[ -f "$DEV_BUILD_ID_SCRIPT" ]] || { echo "Missing ${DEV_BUILD_ID_SCRIPT}" >&2; exit 1; }

echo "==> Upload resolve-dev-build-id.sh to S3"
aws s3 cp "$DEV_BUILD_ID_SCRIPT" "s3://${BUNDLES_BUCKET}/guesttek/ci/resolve-dev-build-id.sh" --region "$AWS_REGION"

echo "==> IAM role ${PUBLISH_ROLE_NAME}"
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$PUBLISH_ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$PUBLISH_ROLE_NAME" \
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
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/${PUBLISH_PROJECT_NAME}",
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/${PUBLISH_PROJECT_NAME}:*"
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
      "Sid": "ReleaseArtifacts",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${ARTIFACTS_BUCKET}",
        "arn:aws:s3:::${ARTIFACTS_BUCKET}/*"
      ]
    }
  ]
}
EOF
)
aws iam put-role-policy --role-name "$PUBLISH_ROLE_NAME" \
  --policy-name "${PUBLISH_PROJECT_NAME}-inline" \
  --policy-document "$POLICY"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PUBLISH_ROLE_NAME}"
export ROLE_ARN PUBLISH_PROJECT_NAME ARTIFACTS_BUCKET
export BUILDSPEC
BUILDSPEC=$(python3 -c "import json, pathlib; print(json.dumps(pathlib.Path('${BUILDSPEC_PATH}').read_text()))")

python3 - <<'PY' > /tmp/publish-codebuild.json
import json, os
buildspec = json.loads(os.environ["BUILDSPEC"])
print(json.dumps({
  "name": os.environ["PUBLISH_PROJECT_NAME"],
  "description": "Publish release artifact to S3 (replace older releases after LabSmoke)",
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
      {"name": "RELEASE_PREFIX", "value": "guesttek-camsuite-edge", "type": "PLAINTEXT"},
    ],
  },
  "serviceRole": os.environ["ROLE_ARN"],
  "timeoutInMinutes": 15,
  "queuedTimeoutInMinutes": 60,
}))
PY

EXISTS=$(aws codebuild batch-get-projects --names "$PUBLISH_PROJECT_NAME" --region "$AWS_REGION" \
  --query 'projects[0].name' --output text 2>/dev/null || true)

if [[ "$EXISTS" == "$PUBLISH_PROJECT_NAME" ]]; then
  echo "Updating CodeBuild project ${PUBLISH_PROJECT_NAME}..."
  aws codebuild update-project --cli-input-json file:///tmp/publish-codebuild.json --region "$AWS_REGION" >/dev/null
else
  echo "Creating CodeBuild project ${PUBLISH_PROJECT_NAME}..."
  aws codebuild create-project --cli-input-json file:///tmp/publish-codebuild.json --region "$AWS_REGION" >/dev/null
fi

echo "Publish CodeBuild project ready: ${PUBLISH_PROJECT_NAME}"
