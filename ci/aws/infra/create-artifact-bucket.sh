#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

echo "Ensuring artifact bucket: ${ARTIFACTS_BUCKET}"
if aws s3api head-bucket --bucket "$ARTIFACTS_BUCKET" 2>/dev/null; then
  echo "Bucket already exists"
else
  aws s3api create-bucket \
    --bucket "$ARTIFACTS_BUCKET" \
    --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
  echo "Created bucket"
fi

aws s3api put-public-access-block --bucket "$ARTIFACTS_BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

aws s3api put-bucket-encryption --bucket "$ARTIFACTS_BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Release retention is managed by the Publish pipeline stage (keep latest only).
# Remove legacy expiry rule if present so the current release is not auto-deleted.
if aws s3api get-bucket-lifecycle-configuration --bucket "$ARTIFACTS_BUCKET" >/dev/null 2>&1; then
  aws s3api delete-bucket-lifecycle --bucket "$ARTIFACTS_BUCKET"
  echo "Removed bucket lifecycle (Publish stage keeps one latest artifact)"
fi

echo "s3://${ARTIFACTS_BUCKET}/"
