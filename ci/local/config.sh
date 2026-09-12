# Shared settings for the local amd64 pipeline.
# Source this file from other scripts:  source "$(dirname "$0")/config.sh"

PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "${PIPELINE_DIR}/../.." && pwd)"

WORK_ROOT="${WORK_ROOT:-/tmp/guesttek-amd64-build}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
REPO_LIST="${REPO_LIST:-${ORCHESTRATION_ROOT}/scripts/service-repos.list}"
PATCH_SERIES="${PATCH_SERIES:-${ORCHESTRATION_ROOT}/patches/series}"
PATCH_DIR="${PATCH_DIR:-${ORCHESTRATION_ROOT}/patches}"

# repo_directory|build_script_path (relative to repo)
SERVICE_BUILDS=(
  "camsuite-emb-ip-camera|build-docker.sh"
  "camsuite-emb-video-capture|build-docker.sh"
  "suspicious_objects_inference_service|build-docker.sh"
  "alert_manager_service|build-docker.sh"
  "camsuite-emb-mqtt-client|build-docker.sh"
  "camsuite-emb-video-upload-manager|scripts/build-docker.sh"
  "camsuite-emb-provisioning|build-docker.sh"
)
