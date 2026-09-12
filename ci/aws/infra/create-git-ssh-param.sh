#!/usr/bin/env bash
# Store Git deploy SSH private key in SSM Parameter Store (SecureString) for CodeBuild.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

GIT_SSH_PARAM="${GIT_SSH_PARAM:-/guesttek/codebuild/git-ssh-private-key}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519}"
LEGACY_SECRET="${GIT_SSH_SECRET_NAME:-guesttek/git-ssh-key}"

if [[ ! -f "$SSH_KEY_PATH" ]] && aws secretsmanager get-secret-value \
  --secret-id "$LEGACY_SECRET" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Loading key from legacy Secrets Manager secret ${LEGACY_SECRET}..."
  TMP="$(mktemp)"
  aws secretsmanager get-secret-value \
    --secret-id "$LEGACY_SECRET" \
    --region "$AWS_REGION" \
    --query SecretString --output text > "$TMP"
  SSH_KEY_PATH="$TMP"
  trap 'rm -f "$TMP"' EXIT
fi

[[ -f "$SSH_KEY_PATH" ]] || { echo "Missing SSH key: ${SSH_KEY_PATH}" >&2; exit 1; }

if aws ssm get-parameter --name "$GIT_SSH_PARAM" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Updating SSM parameter ${GIT_SSH_PARAM}..."
  aws ssm put-parameter \
    --name "$GIT_SSH_PARAM" \
    --type SecureString \
    --value "file://${SSH_KEY_PATH}" \
    --overwrite \
    --region "$AWS_REGION" >/dev/null
else
  echo "Creating SSM parameter ${GIT_SSH_PARAM}..."
  aws ssm put-parameter \
    --name "$GIT_SSH_PARAM" \
    --type SecureString \
    --value "file://${SSH_KEY_PATH}" \
    --description "Git deploy SSH private key for guesttek CodeBuild (Bitbucket/GitHub clones)" \
    --region "$AWS_REGION" >/dev/null
fi

echo "SSM parameter ready: ${GIT_SSH_PARAM}"
