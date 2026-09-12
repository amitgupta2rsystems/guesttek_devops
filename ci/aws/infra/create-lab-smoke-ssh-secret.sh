#!/usr/bin/env bash
# Store EC2 lab SSH private key in Secrets Manager for LabSmoke CodeBuild.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

LAB_SMOKE_SSH_SECRET="${LAB_SMOKE_SSH_SECRET:-guesttek/lab-smoke-ssh-key}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519}"

[[ -f "$SSH_KEY_PATH" ]] || { echo "Missing SSH key: ${SSH_KEY_PATH}" >&2; exit 1; }

if aws secretsmanager describe-secret --secret-id "$LAB_SMOKE_SSH_SECRET" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Updating secret ${LAB_SMOKE_SSH_SECRET}..."
  aws secretsmanager put-secret-value \
    --secret-id "$LAB_SMOKE_SSH_SECRET" \
    --secret-string "file://${SSH_KEY_PATH}" \
    --region "$AWS_REGION" >/dev/null
else
  echo "Creating secret ${LAB_SMOKE_SSH_SECRET}..."
  aws secretsmanager create-secret \
    --name "$LAB_SMOKE_SSH_SECRET" \
    --description "SSH private key for guesttek-camsuite-edge lab smoke (EC2)" \
    --secret-string "file://${SSH_KEY_PATH}" \
    --region "$AWS_REGION" >/dev/null
fi

echo "Secret ready: ${LAB_SMOKE_SSH_SECRET}"
