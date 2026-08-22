#!/usr/bin/env bash
# Fetch-only pipeline — clone orchestration + all service repos (no Docker / .deb build).
#
# Mirrors CodeBuild fetch steps from buildspec.yml without the build phase.
# Use to validate SSH keys, service-repos.list, and network access before full builds.
#
# Local:
#   ./ci/aws/fetch-code-only.sh --orchestration-src /home/proximus2/GuestTek
#
# CodeBuild (after GitHub source checkout):
#   ORCHESTRATION_SRC=$CODEBUILD_SRC_DIR ./ci/aws/fetch-code-only.sh
#
# Environment (optional):
#   ORCHESTRATION_SRC, MONOREPO, GIT_SSH_SECRET_NAME, BUNDLES_BUCKET, BUNDLES_PREFIX
#   CLONE_REMOTES=1, SERVICE_BRANCHES=1, AWS_REGION=ap-south-1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_SRC="${ORCHESTRATION_SRC:-${CODEBUILD_SRC_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}}"
MONOREPO="${MONOREPO:-/codebuild/output/guestek-build}"
REPORT_DIR="${REPORT_DIR:-/codebuild/output/fetch-report}"
CLONE_REMOTES="${CLONE_REMOTES:-1}"
SERVICE_BRANCHES="${SERVICE_BRANCHES:-1}"
GIT_SSH_SECRET_NAME="${GIT_SSH_SECRET_NAME:-guesttek/git-ssh-key}"
AWS_REGION="${AWS_REGION:-ap-south-1}"

log() { echo "==> $*"; }

usage() {
  cat <<'EOF'
Fetch GuestTek service repos only (no package build).

Usage:
  ./ci/aws/fetch-code-only.sh [options]

Options:
  --orchestration-src DIR   Recipe repo path (default: GuestTek root or CODEBUILD_SRC_DIR)
  --dest DIR                Workspace for clones (default: /codebuild/output/guestek-build)
  --report-dir DIR          Write fetch-report.txt here
  --no-clone-remotes        Skip git clone (only copy orchestration)
  --no-service-branches     Skip Bitbucket dev branch checkout
  -h, --help

Requires: git, openssh-client, aws (for Secrets Manager + optional S3 bundles in CodeBuild).
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --orchestration-src) ORCHESTRATION_SRC="$2"; shift 2 ;;
    --dest) MONOREPO="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --no-clone-remotes) CLONE_REMOTES=0; shift ;;
    --no-service-branches) SERVICE_BRANCHES=0; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -d "$ORCHESTRATION_SRC" ]] || { echo "Error: orchestration not found: ${ORCHESTRATION_SRC}" >&2; exit 1; }

setup_ssh() {
  [[ "$CLONE_REMOTES" == "1" ]] || return 0
  if ssh-add -l >/dev/null 2>&1; then
    log "SSH agent already has keys"
    return 0
  fi
  if [[ -z "${GIT_SSH_SECRET_NAME:-}" ]]; then
    echo "Error: set GIT_SSH_SECRET_NAME or load SSH key into agent" >&2
    exit 1
  fi
  command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI required for Secrets Manager" >&2; exit 1; }
  log "Load SSH key from Secrets Manager: ${GIT_SSH_SECRET_NAME}"
  eval "$(ssh-agent -s)"
  aws secretsmanager get-secret-value \
    --secret-id "$GIT_SSH_SECRET_NAME" \
    --region "$AWS_REGION" \
    --query SecretString --output text | tr -d '\r' | ssh-add -
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keyscan -H github.com bitbucket.org >> ~/.ssh/known_hosts 2>/dev/null || true
}

fetch_bundles_from_s3() {
  [[ -n "${BUNDLES_BUCKET:-}" ]] || return 0
  for bundle in deploy.bundle guesttek-camsuite-edge.bundle; do
    if [[ ! -f "${MONOREPO}/${bundle}" ]]; then
      log "S3 bundle: s3://${BUNDLES_BUCKET}/${BUNDLES_PREFIX:-}${bundle}"
      aws s3 cp "s3://${BUNDLES_BUCKET}/${BUNDLES_PREFIX:-}${bundle}" "${MONOREPO}/${bundle}" || true
    fi
  done
}

write_report() {
  local report="${REPORT_DIR}/fetch-report.txt"
  mkdir -p "$REPORT_DIR"
  {
    echo "GuestTek fetch-only report"
    echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Orchestration: ${ORCHESTRATION_SRC}"
    echo "Workspace: ${MONOREPO}"
    echo ""
    echo "Service repos (from scripts/service-repos.list):"
  } > "$report"

  local repo_list="${MONOREPO}/scripts/service-repos.list"
  [[ -f "$repo_list" ]] || { echo "Missing ${repo_list}" >> "$report"; return 1; }

  local ok=0 fail=0
  while IFS='|' read -r name path remote branch _rest; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    local dir="${MONOREPO}/${path}"
    if [[ -d "${dir}/.git" ]]; then
      local sha branch_head
      sha="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
      branch_head="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      echo "  OK   ${name}  ${branch_head}@${sha}  ${remote}" >> "$report"
      ok=$((ok + 1))
    else
      echo "  FAIL ${name}  (not cloned)  ${remote}" >> "$report"
      fail=$((fail + 1))
    fi
  done < "$repo_list"

  echo "" >> "$report"
  echo "Summary: ${ok} ok, ${fail} failed" >> "$report"
  cat "$report"
  [[ "$fail" -eq 0 ]]
}

main() {
  log "Fetch-only — orchestration: ${ORCHESTRATION_SRC}"
  log "Workspace: ${MONOREPO}"

  setup_ssh

  rm -rf "$MONOREPO"
  mkdir -p "$MONOREPO" "$REPORT_DIR"

  PREP_ARGS=(--orchestration-src "$ORCHESTRATION_SRC" --dest "$MONOREPO")
  [[ "$CLONE_REMOTES" != "1" ]] && PREP_ARGS+=(--no-clone-remotes)
  [[ "$SERVICE_BRANCHES" == "1" ]] && PREP_ARGS+=(--service-branches)

  log "prepare-workspace-monorepo.sh"
  bash "${ORCHESTRATION_SRC}/scripts/prepare-workspace-monorepo.sh" "${PREP_ARGS[@]}"

  fetch_bundles_from_s3

  log "Verify clones"
  write_report

  log "Fetch-only complete — no build ran"
}

main "$@"
