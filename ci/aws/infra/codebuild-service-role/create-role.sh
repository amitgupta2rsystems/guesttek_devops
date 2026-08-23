#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib.sh
source "${SCRIPT_DIR}/../lib.sh"
load_config

ROLE_DIR="${SCRIPT_DIR}"
TMP_POLICY="$(mktemp)"
trap 'rm -f "$TMP_POLICY"' EXIT

render_template "${ROLE_DIR}/role-policy.json.template" "$TMP_POLICY"

echo "Ensuring IAM role: ${CODEBUILD_ROLE_NAME}"
if ! aws iam get-role --role-name "$CODEBUILD_ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$CODEBUILD_ROLE_NAME" \
    --assume-role-policy-document "file://${ROLE_DIR}/trust-policy.json"
  echo "Waiting for role propagation..."
  sleep 10
fi

aws iam put-role-policy \
  --role-name "$CODEBUILD_ROLE_NAME" \
  --policy-name codebuild-camsuite-edge-inline \
  --policy-document "file://${TMP_POLICY}"

echo "Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CODEBUILD_ROLE_NAME}"
