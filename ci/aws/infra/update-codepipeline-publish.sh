#!/usr/bin/env bash
# Add Publish stage after LabSmoke (promote BuildOutput to release S3, keep one artifact).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

PIPELINE_NAME="${PIPELINE_NAME:-guesttek-camsuite-edge-pipeline}"
PIPELINE_ROLE="${PIPELINE_ROLE:-codepipeline-guesttek-camsuite-edge-role}"
PUBLISH_PROJECT="${PUBLISH_PROJECT_NAME:-guesttek-camsuite-edge-publish}"
PUBLISH_ROLE="${PUBLISH_ROLE_NAME:-codebuild-guesttek-camsuite-edge-publish-role}"
export PUBLISH_PROJECT PUBLISH_ROLE AWS_REGION AWS_ACCOUNT_ID

echo "==> Ensure Publish CodeBuild project exists"
"${SCRIPT_DIR}/create-publish-codebuild-project.sh"

echo "==> Extend pipeline role for Publish CodeBuild"
POLICY=$(aws iam get-role-policy --role-name "$PIPELINE_ROLE" \
  --policy-name codepipeline-camsuite-edge-inline --output json | python3 -c "
import json, sys, os
doc = json.load(sys.stdin)['PolicyDocument']
region = os.environ['AWS_REGION']
account = os.environ['AWS_ACCOUNT_ID']
publish = os.environ['PUBLISH_PROJECT']
publish_role = os.environ.get('PUBLISH_ROLE', 'codebuild-guesttek-camsuite-edge-publish-role')

for st in doc['Statement']:
    if st.get('Sid') == 'StartCodeBuild':
        resources = st['Resource']
        for r in [
            f'arn:aws:codebuild:{region}:{account}:project/{publish}',
            f'arn:aws:codebuild:{region}:{account}:build/{publish}:*',
        ]:
            if r not in resources:
                resources.append(r)
        break

pass_resources = None
for st in doc['Statement']:
    if st.get('Sid') == 'PassCodeBuildRole':
        pass_resources = st['Resource']
        break

publish_role_arn = f'arn:aws:iam::{account}:role/{publish_role}'
if pass_resources is not None:
    if isinstance(pass_resources, str):
        pass_resources = [pass_resources, publish_role_arn]
    elif publish_role_arn not in pass_resources:
        pass_resources.append(publish_role_arn)
else:
    doc['Statement'].append({
        'Sid': 'PassPublishCodeBuildRole',
        'Effect': 'Allow',
        'Action': 'iam:PassRole',
        'Resource': publish_role_arn,
        'Condition': {'StringEqualsIfExists': {'iam:PassedToService': 'codebuild.amazonaws.com'}},
    })

print(json.dumps(doc))
")

aws iam put-role-policy --role-name "$PIPELINE_ROLE" \
  --policy-name codepipeline-camsuite-edge-inline \
  --policy-document "$POLICY"

echo "==> Update pipeline definition"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" --output json \
  | python3 "${SCRIPT_DIR}/patch-pipeline-publish.py" > /tmp/pipeline-publish-update.json

aws codepipeline update-pipeline --cli-input-json file:///tmp/pipeline-publish-update.json --region "$AWS_REGION" >/dev/null

echo "Pipeline ${PIPELINE_NAME} updated: Source → Build → LabSmoke → Publish"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" \
  --query 'pipeline.stages[*].name' --output text
