#!/usr/bin/env bash
# Store EC2 lab SSH private key in SSM Parameter Store (SecureString) for LabSmoke CodeBuild.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

LAB_SMOKE_SSH_PARAM="${LAB_SMOKE_SSH_PARAM:-/guesttek/lab-smoke/ssh-private-key}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519}"

[[ -f "$SSH_KEY_PATH" ]] || { echo "Missing SSH key: ${SSH_KEY_PATH}" >&2; exit 1; }

if aws ssm get-parameter --name "$LAB_SMOKE_SSH_PARAM" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Updating SSM parameter ${LAB_SMOKE_SSH_PARAM}..."
  aws ssm put-parameter \
    --name "$LAB_SMOKE_SSH_PARAM" \
    --type SecureString \
    --value "file://${SSH_KEY_PATH}" \
    --overwrite \
    --region "$AWS_REGION" >/dev/null
else
  echo "Creating SSM parameter ${LAB_SMOKE_SSH_PARAM}..."
  aws ssm put-parameter \
    --name "$LAB_SMOKE_SSH_PARAM" \
    --type SecureString \
    --value "file://${SSH_KEY_PATH}" \
    --description "SSH private key for guesttek-camsuite-edge lab smoke (EC2)" \
    --region "$AWS_REGION" >/dev/null
fi

echo "SSM parameter ready: ${LAB_SMOKE_SSH_PARAM}"
