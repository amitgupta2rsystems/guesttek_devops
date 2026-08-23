#!/usr/bin/env bash
# Fetch deploy/ and guesttek-camsuite-edge/ git bundles from S3 into CLONE_ROOT.
set -euo pipefail

CLONE_ROOT="${CLONE_ROOT:-/tmp/repos}"
BUNDLES_BUCKET="${BUNDLES_BUCKET:-guesttek-edge-bundles-705959604310}"
BUNDLES_PREFIX="${BUNDLES_PREFIX:-guesttek/bundles/}"
AWS_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}"
BUNDLE_WORKDIR="${BUNDLE_WORKDIR:-/tmp/edge-bundles}"

mkdir -p "$CLONE_ROOT" "$BUNDLE_WORKDIR"

fetch_bundle() {
  local name="$1"
  local branch="${2:-}"
  local dest="${CLONE_ROOT}/${name}"
  local bundle="${BUNDLE_WORKDIR}/${name}.bundle"

  echo "==== Fetching s3://${BUNDLES_BUCKET}/${BUNDLES_PREFIX}${name}.bundle ===="
  aws s3 cp "s3://${BUNDLES_BUCKET}/${BUNDLES_PREFIX}${name}.bundle" "$bundle" --region "$AWS_REGION"
  rm -rf "$dest"
  git clone "$bundle" "$dest"
  if [[ -n "$branch" ]]; then
    git -C "$dest" checkout -B "$branch" "origin/${branch}" 2>/dev/null \
      || git -C "$dest" checkout -B "$branch" "$branch" 2>/dev/null \
      || true
  fi
  # Prefer Development when HEAD is empty / detached without files
  if [[ ! -e "$dest/README.md" && ! -e "$dest/assemble-env.sh" && ! -e "$dest/debian" ]]; then
    git -C "$dest" checkout -B Development origin/Development 2>/dev/null \
      || git -C "$dest" checkout Development 2>/dev/null \
      || true
  fi
  git -C "$dest" remote set-url --push origin DISABLED 2>/dev/null || true
  git -C "$dest" log -1 --oneline || true
  ls -la "$dest" | head -20
}

fetch_bundle deploy Development
fetch_bundle guesttek-camsuite-edge Development

echo "==== Packaging repos ready under ${CLONE_ROOT} ===="
