#!/usr/bin/env bash
# Insert ArchiveBuild after Build — keeps every build in S3 even if LabSmoke fails.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

PIPELINE_NAME="${PIPELINE_NAME:-guesttek-camsuite-edge-pipeline}"
PIPELINE_ROLE="${PIPELINE_ROLE:-codepipeline-guesttek-camsuite-edge-role}"
ARCHIVE_PROJECT="${ARCHIVE_PROJECT_NAME:-guesttek-camsuite-edge-archive-build}"
ARCHIVE_ROLE="${ARCHIVE_ROLE_NAME:-codebuild-guesttek-camsuite-edge-archive-build-role}"
export ARCHIVE_PROJECT ARCHIVE_ROLE AWS_REGION AWS_ACCOUNT_ID

echo "==> Ensure ArchiveBuild CodeBuild project exists"
"${SCRIPT_DIR}/create-archive-build-codebuild-project.sh"

echo "==> Extend pipeline role for ArchiveBuild CodeBuild"
POLICY=$(aws iam get-role-policy --role-name "$PIPELINE_ROLE" \
  --policy-name codepipeline-camsuite-edge-inline --output json | python3 -c "
import json, sys, os
doc = json.load(sys.stdin)['PolicyDocument']
region = os.environ['AWS_REGION']
account = os.environ['AWS_ACCOUNT_ID']
archive = os.environ['ARCHIVE_PROJECT']
archive_role = os.environ['ARCHIVE_ROLE']

for st in doc['Statement']:
    if st.get('Sid') == 'StartCodeBuild':
        resources = st['Resource']
        for r in [
            f'arn:aws:codebuild:{region}:{account}:project/{archive}',
            f'arn:aws:codebuild:{region}:{account}:build/{archive}:*',
        ]:
            if r not in resources:
                resources.append(r)
        break

for st in doc['Statement']:
    if st.get('Sid') == 'PassCodeBuildRole':
        r = f'arn:aws:iam::{account}:role/{archive_role}'
        if isinstance(st['Resource'], str):
            st['Resource'] = [st['Resource'], r]
        elif r not in st['Resource']:
            st['Resource'].append(r)
        break
else:
    doc['Statement'].append({
        'Sid': 'PassArchiveBuildCodeBuildRole',
        'Effect': 'Allow',
        'Action': 'iam:PassRole',
        'Resource': f'arn:aws:iam::{account}:role/{archive_role}',
        'Condition': {'StringEqualsIfExists': {'iam:PassedToService': 'codebuild.amazonaws.com'}},
    })

print(json.dumps(doc))
")

aws iam put-role-policy --role-name "$PIPELINE_ROLE" \
  --policy-name codepipeline-camsuite-edge-inline \
  --policy-document "$POLICY"

echo "==> Update pipeline definition"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" --output json \
  | python3 "${SCRIPT_DIR}/patch-pipeline-archive-build.py" > /tmp/pipeline-archive-update.json

aws codepipeline update-pipeline --cli-input-json file:///tmp/pipeline-archive-update.json --region "$AWS_REGION" >/dev/null

echo "Pipeline ${PIPELINE_NAME} updated (ArchiveBuild inserted after Build)"
aws codepipeline get-pipeline --name "$PIPELINE_NAME" --region "$AWS_REGION" \
  --query 'pipeline.stages[*].name' --output text
