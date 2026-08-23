#!/usr/bin/env bash
# Package edge .deb: assemble-env -> save-images -> dpkg-buildpackage.
# Expects monorepo layout under CLONE_ROOT (services + deploy + guesttek-camsuite-edge).
set -euo pipefail

ROOT="${CLONE_ROOT:-/tmp/repos}"
export CAMSUITE_BUNDLE_ARCH="${CAMSUITE_BUNDLE_ARCH:-amd64}"
# Optional: force DATE_TAG; otherwise assemble-env discovers from docker images
if [[ -n "${DATE_TAG:-}" ]]; then
  export DATE_TAG
fi

cd "$ROOT"

if [[ ! -x deploy/assemble-env.sh ]]; then
  echo "Missing deploy/assemble-env.sh under $ROOT" >&2
  exit 1
fi
if [[ ! -d guesttek-camsuite-edge/debian ]]; then
  echo "Missing guesttek-camsuite-edge/debian under $ROOT" >&2
  exit 1
fi

chmod +x deploy/assemble-env.sh deploy/save-images.sh

echo "==== ./deploy/assemble-env.sh ===="
./deploy/assemble-env.sh

echo "==== ./deploy/save-images.sh ===="
./deploy/save-images.sh

echo "==== dpkg-buildpackage (guesttek-camsuite-edge) ===="
(
  cd guesttek-camsuite-edge
  dpkg-buildpackage -us -uc -b
)

echo "==== Package artifacts ===="
ls -lah "$ROOT"/guesttek-camsuite-edge_*.deb "$ROOT"/guesttek-camsuite-edge_*.buildinfo "$ROOT"/guesttek-camsuite-edge_*.changes 2>/dev/null || \
  ls -lah "$ROOT"/*.deb 2>/dev/null || true
ls -lah "$ROOT/deploy"/guesttek-camsuite-edge-*.tar "$ROOT/guesttek-camsuite-edge/docker"/camsuite-images-*.tar 2>/dev/null || true

echo "==== Packaging complete ===="
