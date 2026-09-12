#!/usr/bin/env bash
# Runs on lab EC2: download artifact zip from S3 and execute lab-smoke-test.sh --local
set -euo pipefail

: "${S3_ARTIFACT_URI:?S3_ARTIFACT_URI required}"
: "${AWS_REGION:?AWS_REGION required}"
: "${LAB_SMOKE_SCRIPT_S3:?LAB_SMOKE_SCRIPT_S3 required}"

sudo rm -rf /tmp/guesttek-lab-smoke-* /tmp/guesttek-s3-build 2>/dev/null || true
df -h /tmp /

WORK="/tmp/guesttek-lab-smoke-$$"
ARTIFACTS="${WORK}/artifacts"
mkdir -p "${ARTIFACTS}/guesttek-camsuite-edge/docker"

aws s3 cp "${LAB_SMOKE_SCRIPT_S3}" /tmp/lab-smoke-test.sh --region "${AWS_REGION}"
chmod +x /tmp/lab-smoke-test.sh

aws s3 cp "${S3_ARTIFACT_URI}" "${WORK}/camsuite-edge-deb.zip" --region "${AWS_REGION}"
unzip -q "${WORK}/camsuite-edge-deb.zip" -d "${WORK}/unzip"

OUT="${WORK}/unzip/out"
[[ -d "$OUT" ]] || OUT="${WORK}/unzip"
DEB="$(ls -1 "${OUT}"/guesttek-camsuite-edge_*_amd64.deb | head -1)"

cp "$DEB" "${ARTIFACTS}/"
cp "${OUT}/release-manifest.yaml" "${ARTIFACTS}/"
if [[ -f "${OUT}/camsuite-images-amd64.tar" ]]; then
  cp "${OUT}/camsuite-images-amd64.tar" "${ARTIFACTS}/guesttek-camsuite-edge/docker/"
else
  cp "${OUT}/guesttek-camsuite-edge/docker/camsuite-images-amd64.tar" \
    "${ARTIFACTS}/guesttek-camsuite-edge/docker/"
fi

VER="$(dpkg-deb -f "$DEB" Version)"
{
  ( cd "$ARTIFACTS" && sha256sum "$(basename "$DEB")" release-manifest.yaml )
  ( cd "${ARTIFACTS}/guesttek-camsuite-edge/docker" && \
    sha256sum camsuite-images-amd64.tar | \
    awk '{print $1 "  guesttek-camsuite-edge/docker/camsuite-images-amd64.tar"}' )
} > "${ARTIFACTS}/SHA256SUMS-amd64-${VER}"

exec /tmp/lab-smoke-test.sh --local --artifacts-dir "$ARTIFACTS" --purge-first
