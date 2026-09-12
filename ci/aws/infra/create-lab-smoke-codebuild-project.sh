#!/usr/bin/env bash
# CodeBuild project: LabSmoke stage (SSH to lab EC2, run lab-smoke-test.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

LAB_SMOKE_PROJECT_NAME="${LAB_SMOKE_PROJECT_NAME:-guesttek-camsuite-edge-lab-smoke}"
LAB_SMOKE_ROLE_NAME="${LAB_SMOKE_ROLE_NAME:-codebuild-guesttek-camsuite-edge-lab-smoke-role}"
LAB_SMOKE_HOST="${LAB_SMOKE_HOST:-43.204.233.245}"
LAB_SMOKE_USER="${LAB_SMOKE_USER:-ubuntu}"
LAB_SMOKE_SSH_SECRET="${LAB_SMOKE_SSH_SECRET:-guesttek/lab-smoke-ssh-key}"
BUILDSPEC_PATH="${SCRIPT_DIR}/../buildspec-lab-smoke.yml"
SMOKE_SCRIPT="${SCRIPT_DIR}/../../jenkins/lab-smoke-test.sh"

[[ -f "$BUILDSPEC_PATH" ]] || { echo "Missing ${BUILDSPEC_PATH}" >&2; exit 1; }
[[ -f "$SMOKE_SCRIPT" ]] || { echo "Missing ${SMOKE_SCRIPT}" >&2; exit 1; }

REMOTE_SCRIPT="${SCRIPT_DIR}/../ec2-lab-smoke-remote.sh"
[[ -f "$REMOTE_SCRIPT" ]] || { echo "Missing ${REMOTE_SCRIPT}" >&2; exit 1; }

echo "==> Upload lab smoke scripts to S3"
aws s3 cp "$SMOKE_SCRIPT" "s3://${BUNDLES_BUCKET}/guesttek/ci/lab-smoke-test.sh" --region "$AWS_REGION"
aws s3 cp "$REMOTE_SCRIPT" "s3://${BUNDLES_BUCKET}/guesttek/ci/ec2-lab-smoke-remote.sh" --region "$AWS_REGION"

echo "==> IAM role ${LAB_SMOKE_ROLE_NAME}"
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$LAB_SMOKE_ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$LAB_SMOKE_ROLE_NAME" \
    --assume-role-policy-document "$TRUST" >/dev/null
fi

POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": [
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/${LAB_SMOKE_PROJECT_NAME}",
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/${LAB_SMOKE_PROJECT_NAME}:*"
      ]
    },
    {
      "Sid": "PipelineArtifacts",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::guesttek-edge-pipeline-artifacts-${AWS_ACCOUNT_ID}",
        "arn:aws:s3:::guesttek-edge-pipeline-artifacts-${AWS_ACCOUNT_ID}/*"
      ]
    },
    {
      "Sid": "ReadBuildArtifacts",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${ARTIFACTS_BUCKET}",
        "arn:aws:s3:::${ARTIFACTS_BUCKET}/*"
      ]
    },
    {
      "Sid": "ReadLabSmokeScript",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${BUNDLES_BUCKET}",
        "arn:aws:s3:::${BUNDLES_BUCKET}/*"
      ]
    },
    {
      "Sid": "ReadLabSmokeSshKey",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:${LAB_SMOKE_SSH_SECRET}*"
    }
  ]
}
EOF
)
aws iam put-role-policy --role-name "$LAB_SMOKE_ROLE_NAME" \
  --policy-name "${LAB_SMOKE_PROJECT_NAME}-inline" \
  --policy-document "$POLICY"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAB_SMOKE_ROLE_NAME}"
export ROLE_ARN LAB_SMOKE_PROJECT_NAME LAB_SMOKE_HOST LAB_SMOKE_USER LAB_SMOKE_SSH_SECRET BUNDLES_BUCKET ARTIFACTS_BUCKET AWS_ACCOUNT_ID
export S3_ARTIFACT_URI="${S3_ARTIFACT_URI:-}"
export BUILDSPEC
BUILDSPEC=$(python3 -c "import json, pathlib; print(json.dumps(pathlib.Path('${BUILDSPEC_PATH}').read_text()))")

python3 - <<'PY' > /tmp/lab-smoke-codebuild.json
import json, os
buildspec = json.loads(os.environ["BUILDSPEC"])
print(json.dumps({
  "name": os.environ["LAB_SMOKE_PROJECT_NAME"],
  "description": "Lab smoke: install .deb on lab EC2 (pipeline or standalone S3_ARTIFACT_URI)",
  "source": {
    "type": "NO_SOURCE",
    "buildspec": buildspec,
    "insecureSsl": False,
  },
  "artifacts": {"type": "NO_ARTIFACTS"},
  "cache": {"type": "NO_CACHE"},
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "privilegedMode": False,
    "imagePullCredentialsType": "CODEBUILD",
    "environmentVariables": [
      {"name": "LAB_SMOKE_HOST", "value": os.environ["LAB_SMOKE_HOST"], "type": "PLAINTEXT"},
      {"name": "LAB_SMOKE_USER", "value": os.environ["LAB_SMOKE_USER"], "type": "PLAINTEXT"},
      {"name": "LAB_SMOKE_SSH_SECRET", "value": os.environ["LAB_SMOKE_SSH_SECRET"], "type": "PLAINTEXT"},
      {"name": "LAB_SMOKE_SCRIPT_S3", "value": f"s3://{os.environ['BUNDLES_BUCKET']}/guesttek/ci/lab-smoke-test.sh", "type": "PLAINTEXT"},
      {"name": "LAB_SMOKE_REMOTE_S3", "value": f"s3://{os.environ['BUNDLES_BUCKET']}/guesttek/ci/ec2-lab-smoke-remote.sh", "type": "PLAINTEXT"},
      {"name": "ARTIFACTS_BUCKET", "value": os.environ.get("ARTIFACTS_BUCKET", f"guesttek-camsuite-edge-artifacts-{os.environ['AWS_ACCOUNT_ID']}"), "type": "PLAINTEXT"},
      {"name": "S3_ARTIFACT_URI", "value": os.environ.get("S3_ARTIFACT_URI", ""), "type": "PLAINTEXT"},
    ],
  },
  "serviceRole": os.environ["ROLE_ARN"],
  "timeoutInMinutes": 30,
  "queuedTimeoutInMinutes": 60,
}))
PY

EXISTS=$(aws codebuild batch-get-projects --names "$LAB_SMOKE_PROJECT_NAME" --region "$AWS_REGION" \
  --query 'projects[0].name' --output text 2>/dev/null || true)

if [[ "$EXISTS" == "$LAB_SMOKE_PROJECT_NAME" ]]; then
  echo "Updating CodeBuild project ${LAB_SMOKE_PROJECT_NAME}..."
  aws codebuild update-project --cli-input-json file:///tmp/lab-smoke-codebuild.json --region "$AWS_REGION" >/dev/null
else
  echo "Creating CodeBuild project ${LAB_SMOKE_PROJECT_NAME}..."
  aws codebuild create-project --cli-input-json file:///tmp/lab-smoke-codebuild.json --region "$AWS_REGION" >/dev/null
fi

echo "Lab smoke CodeBuild project ready: ${LAB_SMOKE_PROJECT_NAME}"
