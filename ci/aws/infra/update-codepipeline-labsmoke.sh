#!/usr/bin/env bash
# Add LabSmoke stage to guesttek-camsuite-edge CodePipeline.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

PIPELINE_NAME="${PIPELINE_NAME:-guesttek-camsuite-edge-pipeline}"
PIPELINE_ROLE="${PIPELINE_ROLE:-codepipeline-guesttek-camsuite-edge-role}"
BUILD_PROJECT="${CODEBUILD_PROJECT_NAME:-guesttek-camsuite-edge}"
LAB_SMOKE_PROJECT="${LAB_SMOKE_PROJECT_NAME:-guesttek-camsuite-edge-lab-smoke}"
LAB_SMOKE_ROLE="${LAB_SMOKE_ROLE_NAME:-codebuild-guesttek-camsuite-edge-lab-smoke-role}"
PIPELINE_BUCKET="guesttek-edge-pipeline-artifacts-${AWS_ACCOUNT_ID}"
export LAB_SMOKE_PROJECT BUILD_PROJECT LAB_SMOKE_ROLE AWS_REGION AWS_ACCOUNT_ID

echo "==> Extend pipeline role for lab-smoke CodeBuild"
POLICY=$(aws iam get-role-policy --role-name "$PIPELINE_ROLE" \
  --policy-name codepipeline-camsuite-edge-inline --output json | python3 -c "
import json, sys, os
doc = json.load(sys.stdin)['PolicyDocument']
region = os.environ['AWS_REGION']
account = os.environ['AWS_ACCOUNT_ID']
lab = os.environ['LAB_SMOKE_PROJECT']
build = os.environ['BUILD_PROJECT']
lab_role = os.environ['LAB_SMOKE_ROLE']

# StartCodeBuild — add lab-smoke project
for st in doc['Statement']:
    if st.get('Sid') == 'StartCodeBuild':
        resources = st['Resource']
        for r in [
            f'arn:aws:codebuild:{region}:{account}:project/{lab}',
            f'arn:aws:codebuild:{region}:{account}:build/{lab}:*',
        ]:
            if r not in resources:
                resources.append(r)
        break

# PassCodeBuildRole — add lab-smoke role
for st in doc['Statement']:
    if st.get('Sid') == 'PassCodeBuildRole':
        r = f'arn:aws:iam::{account}:role/{lab_role}'
        if r not in st['Resource']:
            if isinstance(st['Resource'], str):
                st['Resource'] = [st['Resource'], r]
            else:
                st['Resource'].append(r)
        break
else:
    doc['Statement'].append({
        'Sid': 'PassLabSmokeCodeBuildRole',
        'Effect': 'Allow',
        'Action': 'iam:PassRole',
        'Resource': f'arn:aws:iam::{account}:role/{lab_role}',
        'Condition': {'StringEqualsIfExists': {'iam:PassedToService': 'codebuild.amazonaws.com'}},
    })

print(json.dumps(doc))
")

aws iam put-role-policy --role-name "$PIPELINE_ROLE" \
  --policy-name codepipeline-camsuite-edge-inline \
  --policy-document "$POLICY"

echo "==> Update pipeline definition"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" --output json \
  | python3 "${SCRIPT_DIR}/patch-pipeline-labsmoke.py" > /tmp/pipeline-update.json

aws codepipeline update-pipeline --cli-input-json file:///tmp/pipeline-update.json --region "$AWS_REGION" >/dev/null

echo "Pipeline ${PIPELINE_NAME} updated: Source → Build → LabSmoke"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" \
  --query 'pipeline.stages[*].name' --output text
