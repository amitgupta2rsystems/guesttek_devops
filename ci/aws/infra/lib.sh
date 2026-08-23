#!/usr/bin/env bash
# Shared helpers for ci/aws/infra scripts.
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_config() {
  local cfg="${INFRA_DIR}/config.env"
  if [[ ! -f "$cfg" ]]; then
    echo "Missing ${cfg}. Copy config.env.example to config.env and edit." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$cfg"
  AWS_REGION="${AWS_REGION:-ap-south-1}"
  AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
  CODECONNECTIONS_ID="${CODECONNECTIONS_ARN##*/}"
  export AWS_REGION AWS_ACCOUNT_ID CODECONNECTIONS_ID
}

render_template() {
  local template="$1" output="$2"
  envsubst < "$template" > "$output"
}
