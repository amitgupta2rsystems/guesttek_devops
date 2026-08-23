#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib.sh
source "${SCRIPT_DIR}/../lib.sh"
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

aws s3api put-bucket-lifecycle-configuration --bucket "$ARTIFACTS_BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-artifacts-30d",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "Expiration": {"Days": 30}
    }]
  }'

echo "s3://${ARTIFACTS_BUCKET}/"
