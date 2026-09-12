#!/usr/bin/env bash
# Lab smoke test for guesttek-camsuite-edge .deb on amd64 (no TPM / factory provisioning).
#
# Default install path: apt purge (if present) then apt install — simulates clean install.
#
# Usage:
#   ./ci/jenkins/lab-smoke-test.sh --host 10.67.254.52 --user proximus2 --jenkins-build 28
#   ./ci/jenkins/lab-smoke-test.sh --local --jenkins-build 28
#   ./ci/jenkins/lab-smoke-test.sh --local --jenkins-build 28 --no-purge   # upgrade in place

set -euo pipefail

REMOTE_HOST=""
REMOTE_USER="${LAB_USER:-}"
ARTIFACTS_DIR=""
DEB_PATH=""
SUMS_PATH=""
MANIFEST_PATH=""
JENKINS_BUILD=""
IMAGE_TAR_PATH=""
IMAGE_TAR_STAGING=""
IMAGE_TAR_REL="guesttek-camsuite-edge/docker/camsuite-images-amd64.tar"
INSTALL=1
PURGE_FIRST=1
REMOTE_WORK=""
SSH_IDENTITY="${LAB_SSH_KEY:-}"
LOCAL=0

log() { echo "==> $*"; }
die() { echo "Error: $*" >&2; exit 2; }

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) REMOTE_HOST="$2"; shift 2 ;;
    --user) REMOTE_USER="$2"; shift 2 ;;
    --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
    --jenkins-build) JENKINS_BUILD="$2"; shift 2 ;;
    --deb) DEB_PATH="$2"; shift 2 ;;
    --sums) SUMS_PATH="$2"; shift 2 ;;
    --manifest) MANIFEST_PATH="$2"; shift 2 ;;
    --remote-work) REMOTE_WORK="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --no-install) INSTALL=0; shift ;;
    --no-purge) PURGE_FIRST=0; shift ;;
    --purge-first) PURGE_FIRST=1; shift ;;  # default; kept for compatibility
    --local) LOCAL=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

[[ -n "$REMOTE_HOST" || "$LOCAL" -eq 1 ]] || die "Set --host or --local"

resolve_artifacts() {
  if [[ -n "$JENKINS_BUILD" ]]; then
    ARTIFACTS_DIR="/var/lib/jenkins/jobs/guesttek-camsuite-edge/builds/${JENKINS_BUILD}/archive/artifacts"
  fi
  if [[ -n "$ARTIFACTS_DIR" ]]; then
    [[ -d "$ARTIFACTS_DIR" ]] || die "Artifacts dir not found: ${ARTIFACTS_DIR}"
    DEB_PATH="${DEB_PATH:-$(ls -1 "${ARTIFACTS_DIR}"/guesttek-camsuite-edge_*_amd64.deb 2>/dev/null | head -1)}"
    SUMS_PATH="${SUMS_PATH:-$(ls -1 "${ARTIFACTS_DIR}"/SHA256SUMS-amd64-* 2>/dev/null | head -1)}"
    MANIFEST_PATH="${MANIFEST_PATH:-${ARTIFACTS_DIR}/release-manifest.yaml}"
  fi
  [[ -n "$DEB_PATH" && -f "$DEB_PATH" ]] || die "Set --deb or --artifacts-dir / --jenkins-build"
  resolve_image_tar
}

# Locate standalone image tarball for SHA256SUMS (Jenkins artifacts use flat name).
resolve_image_tar() {
  IMAGE_TAR_PATH=""
  if [[ -n "${SUMS_PATH:-}" && -f "$SUMS_PATH" ]]; then
    IMAGE_TAR_REL=$(awk 'NF>=2 && $2 ~ /\.tar$/ {print $2; exit}' "$SUMS_PATH")
    [[ -n "$IMAGE_TAR_REL" ]] || IMAGE_TAR_REL="guesttek-camsuite-edge/docker/camsuite-images-amd64.tar"
  fi
  local base="" candidates=()
  [[ -n "$ARTIFACTS_DIR" ]] && base="$ARTIFACTS_DIR"
  [[ -z "$base" && -n "$DEB_PATH" ]] && base="$(dirname "$DEB_PATH")"
  if [[ -n "$base" ]]; then
    candidates+=(
      "${base}/camsuite-images-amd64.tar"
      "${base}/${IMAGE_TAR_REL}"
      "${base}/guesttek-camsuite-edge/docker/camsuite-images-amd64.tar"
    )
  fi
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      IMAGE_TAR_PATH="$c"
      return 0
    fi
  done
}

ssh_target() {
  if [[ -n "$REMOTE_USER" ]]; then
    echo "${REMOTE_USER}@${REMOTE_HOST}"
  else
    echo "${REMOTE_HOST}"
  fi
}

ssh_opts() {
  local -a opts=(-o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new)
  [[ -n "$SSH_IDENTITY" ]] && opts+=(-i "$SSH_IDENTITY")
  # shellcheck disable=SC2207
  [[ -n "${LAB_SSH_OPTS:-}" ]] && read -r -a extra <<< "${LAB_SSH_OPTS}" && opts+=("${extra[@]}")
  printf '%s\n' "${opts[@]}"
}

ssh_cmd() {
  mapfile -t opts < <(ssh_opts)
  ssh "${opts[@]}" "$(ssh_target)" "$@"
}

scp_to_remote() {
  local src="$1" dest="$2"
  mapfile -t opts < <(ssh_opts)
  scp "${opts[@]}" "$src" "$(ssh_target):${dest}"
}

# Smoke checks run on the target host (local or via ssh bash -s).
# Expects WORK, DEB, INSTALL, PURGE_FIRST in the environment.
SMOKE_SCRIPT=$(cat <<'SMOKE'
set -euo pipefail
: "${WORK:?}" "${DEB:?}" "${INSTALL:?}" "${PURGE_FIRST:?}"

pass=0; fail=0; warn=0
ok()   { echo "  PASS  $*"; pass=$((pass + 1)); }
bad()  { echo "  FAIL  $*" >&2; fail=$((fail + 1)); }
note() { echo "  WARN  $*"; warn=$((warn + 1)); }
section() { echo ""; echo "=== $* ==="; }

section "Prerequisites"
[[ "$(dpkg --print-architecture 2>/dev/null)" == "amd64" ]] && ok "architecture amd64" || bad "not amd64"
command -v docker >/dev/null && docker info >/dev/null 2>&1 && ok "docker running" || bad "docker not running"
docker compose version >/dev/null 2>&1 && ok "docker compose" || note "no docker compose plugin"

section "Package integrity"
if ls "${WORK}"/SHA256SUMS-amd64-* >/dev/null 2>&1; then
  sums=$(ls "${WORK}"/SHA256SUMS-amd64-* | head -1)
  filtered="${WORK}/SHA256SUMS.present"
  : >"$filtered"
  while read -r hash path; do
    [[ -z "${path:-}" || "$hash" =~ ^# ]] && continue
    if [[ -f "${WORK}/${path}" ]]; then
      echo "${hash}  ${path}" >>"$filtered"
    else
      note "SHA256SUMS skip missing ${path}"
    fi
  done <"$sums"
  if [[ -s "$filtered" ]]; then
    ( cd "${WORK}" && sha256sum -c SHA256SUMS.present ) && ok "SHA256SUMS (present files)" || bad "SHA256SUMS mismatch"
  else
    note "SHA256SUMS has no present files — skip"
  fi
else
  note "no SHA256SUMS — skip"
fi
dpkg-deb -I "$DEB" >/dev/null 2>&1 && ok "dpkg-deb readable" || bad "invalid deb"
arch=$(dpkg-deb -f "$DEB" Architecture)
[[ "$arch" == "amd64" ]] && ok "Architecture=amd64" || bad "arch=$arch"

section "Uninstall + install"
if [[ "$INSTALL" -eq 1 ]]; then
  if [[ "$PURGE_FIRST" -eq 1 ]]; then
    if dpkg-query -W guesttek-camsuite-edge >/dev/null 2>&1; then
      sudo apt-get purge -y guesttek-camsuite-edge >/dev/null 2>&1 && ok "apt purge ok" || note "apt purge failed (continuing)"
    else
      ok "purge skipped (package not installed)"
    fi
  else
    note "purge skipped (--no-purge)"
  fi
  ilog="${WORK}/install.log"
  if sudo apt-get install -y "$DEB" >"$ilog" 2>&1; then
    ok "apt install ok"
  elif command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    # Lab hosts often run docker-ce; package Depends: docker.io conflicts.
    note "apt blocked (docker.io vs docker-ce) — dpkg --force-depends"
    if sudo dpkg --force-depends -i "$DEB" >>"$ilog" 2>&1; then
      ok "dpkg install ok (docker already present)"
    else
      bad "install failed"
      tail -25 "$ilog" >&2
    fi
  else
    bad "install failed"
    tail -25 "$ilog" >&2
  fi
  grep -q 'TPM device missing' "$ilog" 2>/dev/null && ok "TPM skip (expected)" || note "no TPM skip in log"
  grep -q 'ERROR: Device provisioning failed' "$ilog" 2>/dev/null && bad "provisioning error" || ok "no provisioning error"
else
  note "skip install"
  dpkg-query -W guesttek-camsuite-edge >/dev/null 2>&1 && ok "package installed" || bad "not installed"
fi

section "Layout"
[[ -s /opt/guesttek-camsuite-edge/docker/camsuite-images.tar ]] && ok "image tar" || bad "missing image tar"
[[ -f /usr/share/guesttek-camsuite-edge/docker-compose.yml ]] && ok "compose yml" || bad "missing compose"
[[ -x /usr/bin/guesttek-camsuite-edge-assemble-env ]] && ok "assemble-env bin" || bad "missing assemble-env"
[[ $(ls /etc/guesttek-camsuite-edge/*.json 2>/dev/null | wc -l) -ge 3 ]] && ok "seeded json" || bad "missing json"

section "Docker + env"
docker images --format '{{.Repository}}:{{.Tag}}' camsuite 2>/dev/null | grep -q . && ok "camsuite images" || bad "no images"
[[ -f /etc/guesttek-camsuite-edge/env ]] && ok "env exists" || bad "no env"
grep -q '^DATE_TAG=' /etc/guesttek-camsuite-edge/env 2>/dev/null && ok "DATE_TAG in env" || bad "no DATE_TAG"
alog="${WORK}/assemble.log"
sudo guesttek-camsuite-edge-assemble-env >"$alog" 2>&1 && ok "assemble-env ok" || { bad "assemble-env failed"; tail -15 "$alog" >&2; }

section "Systemd (lab)"
systemctl is-enabled guesttek-camsuite-edge.service >/dev/null 2>&1 && ok "unit enabled" || note "unit not enabled"
[[ -f /etc/guesttek-camsuite-edge/certs/guesttek-camsuite-edge.pem ]] && note "cert present" || ok "no cert (expected)"
systemctl is-active guesttek-camsuite-edge.service >/dev/null 2>&1 && note "stack active" || ok "stack inactive (expected)"

section "Summary"
echo "Passed: $pass  Failed: $fail  Warnings: $warn"
echo "Work: ${WORK}"
[[ $fail -eq 0 ]] && echo "LAB SMOKE OK" && exit 0
echo "LAB SMOKE FAILED" && exit 1
SMOKE
)

# Jenkins archives may be jenkins:jenkins mode 600 — make a readable copy for scp/cp.
prepare_image_tar_for_copy() {
  [[ -n "${IMAGE_TAR_PATH:-}" && -f "$IMAGE_TAR_PATH" ]] || return 0
  [[ -r "$IMAGE_TAR_PATH" ]] && return 0
  IMAGE_TAR_STAGING=$(mktemp /tmp/camsuite-images-amd64.XXXXXX.tar)
  sudo cp "$IMAGE_TAR_PATH" "$IMAGE_TAR_STAGING"
  sudo chmod a+r "$IMAGE_TAR_STAGING"
  IMAGE_TAR_PATH="$IMAGE_TAR_STAGING"
}

cleanup_image_tar_staging() {
  [[ -n "${IMAGE_TAR_STAGING:-}" && -f "$IMAGE_TAR_STAGING" ]] && rm -f "$IMAGE_TAR_STAGING" || true
}

resolve_artifacts
REMOTE_WORK="${REMOTE_WORK:-/tmp/guesttek-lab-smoke-$$}"
DEB_Basename="$(basename "$DEB_PATH")"
trap cleanup_image_tar_staging EXIT

prepare_image_tar_for_copy

stage_files() {
  mkdir -p "$REMOTE_WORK"
  cp "$DEB_PATH" "${REMOTE_WORK}/${DEB_Basename}"
  [[ -f "${SUMS_PATH:-}" ]] && cp "$SUMS_PATH" "${REMOTE_WORK}/"
  [[ -f "${MANIFEST_PATH:-}" ]] && cp "$MANIFEST_PATH" "${REMOTE_WORK}/release-manifest.yaml"
  if [[ -n "${IMAGE_TAR_PATH:-}" && -f "$IMAGE_TAR_PATH" ]]; then
    local dest="${REMOTE_WORK}/${IMAGE_TAR_REL}"
    mkdir -p "$(dirname "$dest")"
    log "Staging image tarball ($(du -h "$IMAGE_TAR_PATH" | awk '{print $1}')) → ${IMAGE_TAR_REL}"
    cp "$IMAGE_TAR_PATH" "$dest"
  else
    log "No image tarball in artifacts — SHA256SUMS may warn for tar path"
  fi
}

if [[ "$LOCAL" -eq 1 ]]; then
  log "Local smoke on $(hostname)"
  stage_files
  export WORK="$REMOTE_WORK" DEB="${REMOTE_WORK}/${DEB_Basename}" INSTALL="$INSTALL" PURGE_FIRST="$PURGE_FIRST"
  bash -c "$SMOKE_SCRIPT"
  exit $?
fi

log "Remote: $(ssh_target)"
ssh_cmd "mkdir -p '${REMOTE_WORK}'"
scp_to_remote "$DEB_PATH" "${REMOTE_WORK}/${DEB_Basename}"
[[ -f "${SUMS_PATH:-}" ]] && scp_to_remote "$SUMS_PATH" "${REMOTE_WORK}/$(basename "$SUMS_PATH")"
[[ -f "${MANIFEST_PATH:-}" ]] && scp_to_remote "$MANIFEST_PATH" "${REMOTE_WORK}/release-manifest.yaml"
if [[ -n "${IMAGE_TAR_PATH:-}" && -f "$IMAGE_TAR_PATH" ]]; then
  ssh_cmd "mkdir -p '${REMOTE_WORK}/$(dirname "$IMAGE_TAR_REL")'"
  log "Copying image tarball ($(du -h "$IMAGE_TAR_PATH" | awk '{print $1}')) → ${IMAGE_TAR_REL}"
  scp_to_remote "$IMAGE_TAR_PATH" "${REMOTE_WORK}/${IMAGE_TAR_REL}"
else
  log "No standalone image tarball in artifacts (SHA256SUMS tar line may warn)"
fi

set +e
ssh_cmd "WORK='${REMOTE_WORK}' DEB='${REMOTE_WORK}/${DEB_Basename}' INSTALL='${INSTALL}' PURGE_FIRST='${PURGE_FIRST}' bash -s" <<<"$SMOKE_SCRIPT"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  log "Lab smoke passed on $(ssh_target)"
  exit 0
fi
log "Lab smoke FAILED on $(ssh_target)" >&2
exit "$rc"
