#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib.sh
source "${SCRIPT_DIR}/../lib.sh"
load_config

USER_NAME="${1:-${TRIGGER_USER_NAME}}"
POLICY_DIR="${SCRIPT_DIR}"
TMP_POLICY="$(mktemp)"
trap 'rm -f "$TMP_POLICY"' EXIT

render_template "${POLICY_DIR}/policy.json.template" "$TMP_POLICY"

echo "Creating/updating IAM user: ${USER_NAME}"
if ! aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  aws iam create-user --user-name "$USER_NAME"
fi

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${TRIGGER_POLICY_NAME}"
if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  aws iam create-policy \
    --policy-name "$TRIGGER_POLICY_NAME" \
    --policy-document "file://${TMP_POLICY}"
else
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document "file://${TMP_POLICY}" \
    --set-as-default >/dev/null
fi

aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN"

echo ""
echo "User ready: ${USER_NAME}"
echo "  aws iam create-access-key --user-name ${USER_NAME}"
echo "  aws codebuild start-build --project-name ${CODEBUILD_PROJECT_NAME} --region ${AWS_REGION}"
