#!/usr/bin/env bash
# Resolve dev build IDs: dev_<upstream>-<seq>  e.g. dev_1.0.0-1, dev_1.0.0-2
#
# Usage:
#   assign <deb>     — next ID for package version; stores tag for CODEPIPELINE_EXECUTION_ID
#   read             — read tag for current CODEPIPELINE_EXECUTION_ID (Publish stage)
#   latest [prefix]  — highest dev_* folder under prefix (default: guesttek-camsuite-edge)
set -euo pipefail

ARTIFACTS_BUCKET="${ARTIFACTS_BUCKET:?ARTIFACTS_BUCKET required}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
BUILDS_PREFIX="${BUILDS_PREFIX:-builds}"
RELEASE_PREFIX="${RELEASE_PREFIX:-guesttek-camsuite-edge}"
TAGS_PREFIX="${BUILDS_PREFIX}/.tags"

deb_upstream_version() {
  local deb="$1"
  local ver
  ver="$(dpkg-deb -f "$deb" Version)"
  echo "${ver%-*}"
}

list_dev_seq() {
  local upstream="$1"
  local pfx="$2"
  local upstream_re="${upstream//./\\.}"
  local max=0
  local n
  while IFS= read -r line; do
    [[ "$line" =~ PRE[[:space:]]+(dev_${upstream_re}-([0-9]+))/? ]] || continue
    n="${BASH_REMATCH[2]}"
    (( n > max )) && max=$n
  done < <(aws s3 ls "s3://${ARTIFACTS_BUCKET}/${pfx}/" --region "$AWS_REGION" 2>/dev/null || true)
  echo "$max"
}

next_dev_build_id() {
  local deb="$1"
  local upstream seq max_build max_release
  upstream="$(deb_upstream_version "$deb")"
  max_build="$(list_dev_seq "$upstream" "$BUILDS_PREFIX")"
  max_release="$(list_dev_seq "$upstream" "$RELEASE_PREFIX")"
  seq=$(( max_build > max_release ? max_build : max_release ))
  seq=$((seq + 1))
  echo "dev_${upstream}-${seq}"
}

tag_uri() {
  [[ -n "${CODEPIPELINE_EXECUTION_ID:-}" ]] || return 1
  echo "s3://${ARTIFACTS_BUCKET}/${TAGS_PREFIX}/${CODEPIPELINE_EXECUTION_ID}"
}

cmd_assign() {
  local deb="${1:?deb path required}"
  local uri tag
  if uri="$(tag_uri)" && aws s3 ls "$uri" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws s3 cp "$uri" - --region "$AWS_REGION"
    return
  fi
  tag="$(next_dev_build_id "$deb")"
  if uri="$(tag_uri)"; then
    echo "$tag" | aws s3 cp - "$uri" --region "$AWS_REGION"
  fi
  echo "$tag"
}

cmd_read() {
  local uri tag
  uri="$(tag_uri)" || { echo "CODEPIPELINE_EXECUTION_ID not set" >&2; exit 1; }
  tag="$(aws s3 cp "$uri" - --region "$AWS_REGION")"
  [[ -n "$tag" ]] || { echo "No dev build tag for execution ${CODEPIPELINE_EXECUTION_ID}" >&2; exit 1; }
  echo "$tag"
}

cmd_latest() {
  local pfx="${1:-$RELEASE_PREFIX}"
  local best="" best_n=-1 upstream n line name
  while IFS= read -r line; do
    [[ "$line" =~ PRE[[:space:]]+(dev_([^/]+)-([0-9]+))/? ]] || continue
    name="${BASH_REMATCH[1]}"
    n="${BASH_REMATCH[3]}"
    (( n > best_n )) && { best_n=$n; best="$name"; }
  done < <(aws s3 ls "s3://${ARTIFACTS_BUCKET}/${pfx}/" --region "$AWS_REGION" 2>/dev/null || true)
  [[ -n "$best" ]] || { echo "No dev_* builds under ${pfx}/" >&2; exit 1; }
  echo "$best"
}

case "${1:-}" in
  assign) shift; cmd_assign "$@" ;;
  read)   cmd_read ;;
  latest) shift; cmd_latest "${1:-}" ;;
  *)
    echo "Usage: $0 assign <deb>|read|latest [prefix]" >&2
    exit 1
    ;;
esac
