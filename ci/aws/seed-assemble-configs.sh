#!/usr/bin/env bash
# Seed example configs required by deploy/assemble-env.sh when missing.
set -euo pipefail

ROOT="${CLONE_ROOT:-/tmp/repos}"

seed() {
  local target="$1"
  local example="$2"
  if [[ -f "$target" ]]; then
    echo "OK exists: $target"
    return 0
  fi
  if [[ -f "$example" ]]; then
    mkdir -p "$(dirname "$target")"
    cp -f "$example" "$target"
    echo "Seeded $target from $(basename "$example")"
    return 0
  fi
  echo "WARN missing config and example: $target / $example" >&2
}

seed "$ROOT/alert_manager_service/config/camera_config.json" \
     "$ROOT/alert_manager_service/config/camera_config.json.example"
seed "$ROOT/alert_manager_service/config/alert_rules.json" \
     "$ROOT/alert_manager_service/config/alert_rules.json.example"

# Prefer committed configs when present; otherwise try .example
seed "$ROOT/suspicious_objects_inference_service/config.json" \
     "$ROOT/suspicious_objects_inference_service/config.json.example"
seed "$ROOT/camsuite-emb-mqtt-client/config/config.json" \
     "$ROOT/camsuite-emb-mqtt-client/config/config.json.example"
seed "$ROOT/camsuite-emb-provisioning/config/config.json" \
     "$ROOT/camsuite-emb-provisioning/config/config.json.example"

echo "==== Config seed done ===="
