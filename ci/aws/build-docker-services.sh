#!/usr/bin/env bash
# Build Docker images for camsuite edge services (read-only clones; never push remotes).
set -euo pipefail

CLONE_ROOT="${CLONE_ROOT:-/tmp/repos}"
# Accept PLATFORM=amd64 or PLATFORM=linux/amd64
PLATFORM="${PLATFORM:-amd64}"
if [[ "$PLATFORM" != */* ]]; then
  PLATFORM="linux/${PLATFORM}"
fi
export PLATFORM

echo "==== Docker service builds (PLATFORM=${PLATFORM}) ===="
cd "$CLONE_ROOT"

run_build() {
  local dir="$1"
  local script="$2"
  echo ""
  echo "======== Building ${dir} (${script}) ========"
  if [[ ! -d "$dir" ]]; then
    echo "MISSING directory: ${CLONE_ROOT}/${dir}" >&2
    return 1
  fi
  if [[ ! -x "$dir/$script" && ! -f "$dir/$script" ]]; then
    echo "MISSING build script: ${CLONE_ROOT}/${dir}/${script}" >&2
    return 1
  fi
  chmod +x "$dir/$script"
  (cd "$dir" && ./"$script")
}

run_build camsuite-emb-ip-camera build-docker.sh
run_build camsuite-emb-video-capture build-docker.sh
run_build suspicious_objects_inference_service build-docker.sh
run_build alert_manager_service build-docker.sh
run_build camsuite-emb-mqtt-client build-docker.sh
run_build camsuite-emb-video-upload-manager scripts/build-docker.sh
run_build camsuite-emb-provisioning build-docker.sh

echo ""
echo "==== All Docker service builds finished ===="
docker images | head -50 || true
