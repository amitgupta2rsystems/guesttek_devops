#!/usr/bin/env bash
# Check out every repo pinned in release-manifest.yaml (CI or reproducible local builds).
#
# Usage:
#   ./scripts/checkout-from-manifest.sh --manifest release-manifest.yaml
#   ./scripts/checkout-from-manifest.sh --manifest release-manifest.yaml --bundles-dir /path/to/bundles
#   ./scripts/checkout-from-manifest.sh --manifest release-manifest.yaml --clone-remotes
#   ./scripts/checkout-from-manifest.sh --manifest release-manifest.yaml --dry-run
#
# Clone sources (first match wins for missing dirs):
#   1. bundle: field in manifest
#   2. <bundles-dir>/<path>.bundle
#   3. <bundles-dir>/<name>.bundle
#   4. remote: field (requires --clone-remotes or set on each repo)
#
# Requires: git, python3

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${ROOT}/release-manifest.yaml"
BUNDLES_DIR="${ROOT}"
CLONE_REMOTES=0
DRY_RUN=0
STRICT=0

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

log() { echo "==> $*"; }
die() { echo "Error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --bundles-dir) BUNDLES_DIR="$2"; shift 2 ;;
    --clone-remotes) CLONE_REMOTES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --strict) STRICT=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "Unknown argument: $1 (try --help)" ;;
  esac
done

[[ -f "$MANIFEST" ]] || die "Manifest not found: ${MANIFEST}"
command -v git >/dev/null 2>&1 || die "git is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

repo_clean() {
  local dir="$1"
  git -C "$dir" diff --quiet 2>/dev/null && git -C "$dir" diff --cached --quiet 2>/dev/null
}

find_bundle() {
  local path="$1" name="$2" explicit="${3:-}"
  local candidate
  if [[ -n "$explicit" && -f "$explicit" ]]; then
    echo "$explicit"
    return 0
  fi
  for candidate in \
    "${BUNDLES_DIR}/${path}.bundle" \
    "${BUNDLES_DIR}/${name}.bundle"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

checkout_existing() {
  local dir="$1" commit="$2" branch="$3" name="$4"
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    return 1
  fi
  if ! repo_clean "$dir"; then
    log "${name}: discarding uncommitted changes before checkout (${dir})"
    run git -C "$dir" reset --hard
    run git -C "$dir" clean -fd
  fi
  log "${name}: checking out ${commit:0:12}… in ${dir}"
  run git -C "$dir" fetch --all --tags --prune 2>/dev/null || true
  if ! run git -C "$dir" cat-file -e "${commit}^{commit}" 2>/dev/null; then
    run git -C "$dir" fetch --all --tags --prune
    run git -C "$dir" cat-file -e "${commit}^{commit}"
  fi
  run git -C "$dir" checkout --detach "$commit"
  local head
  head="$(git -C "$dir" rev-parse HEAD)"
  [[ "$head" == "$commit" ]] || die "${name}: checkout failed (HEAD ${head:0:12} != ${commit:0:12})"
  echo "  OK   ${name}: ${commit:0:12}…"
}

clone_from_bundle() {
  local bundle="$1" dir="$2" commit="$3" name="$4"
  log "${name}: cloning from bundle ${bundle}"
  [[ -d "$dir" ]] && die "${name}: destination already exists: ${dir}"
  run git clone "$bundle" "$dir"
  checkout_existing "$dir" "$commit" "" "$name"
}

clone_from_remote() {
  local remote="$1" dir="$2" commit="$3" name="$4"
  log "${name}: cloning from ${remote}"
  [[ -d "$dir" ]] && die "${name}: destination already exists: ${dir}"
  run git clone "$remote" "$dir"
  checkout_existing "$dir" "$commit" "" "$name"
}

while IFS=$'\t' read -r name path branch commit remote bundle; do
  [[ -z "$name" ]] && continue

  dest="${ROOT}/${path}"
  placeholder="0000000000000000000000000000000000000000"

  if [[ "$commit" == "$placeholder" ]]; then
    if [[ "$STRICT" -eq 1 ]]; then
      die "${name}: placeholder commit in manifest (strict mode)"
    fi
    echo "  SKIP ${name}: placeholder commit"
    continue
  fi

  if [[ -d "$dest" ]]; then
    if checkout_existing "$dest" "$commit" "$branch" "$name"; then
      continue
    fi
    die "${name}: ${dest} exists but is not a git repository"
  fi

  resolved_bundle=""
  if resolved_bundle="$(find_bundle "$path" "$name" "$bundle")"; then
    clone_from_bundle "$resolved_bundle" "$dest" "$commit" "$name"
    continue
  fi

  if [[ -n "$remote" ]]; then
    if [[ "$CLONE_REMOTES" -eq 1 ]]; then
      clone_from_remote "$remote" "$dest" "$commit" "$name"
      continue
    fi
    die "${name}: missing ${dest}; set remote clone with --clone-remotes or provide a .bundle in ${BUNDLES_DIR}"
  fi

  die "${name}: missing ${dest}; add bundle (${path}.bundle) or remote: in manifest"
done < <(
  python3 - "$MANIFEST" <<'PY'
import json
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
repos = []
current = {}
for line in text.splitlines():
    m = re.match(r"^\s*-\s+name:\s+(\S+)", line)
    if m:
        if current:
            repos.append(current)
        current = {"name": m.group(1)}
        continue
    for key in ("path", "branch", "commit", "remote", "bundle"):
        m = re.match(rf'^\s+{key}:\s+"?([^"#]+?)"?\s*(#.*)?$', line)
        if m and current is not None:
            current[key] = m.group(1).strip().strip('"')
            break
if current:
    repos.append(current)

for repo in repos:
    print("\t".join([
        repo.get("name", ""),
        repo.get("path", ""),
        repo.get("branch", ""),
        repo.get("commit", ""),
        repo.get("remote", ""),
        repo.get("bundle", ""),
    ]))
PY
)

log "All manifest repos checked out under ${ROOT}"
if [[ "$DRY_RUN" -eq 0 ]]; then
  "${ROOT}/scripts/release-manifest.sh" verify --manifest "$MANIFEST" --strict
fi
