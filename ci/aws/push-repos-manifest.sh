#!/usr/bin/env bash
# Push generated repos-manifest.yaml (and release-manifest.yaml if present)
# to amitgupta2rsystems/guesttek_devops using the orchestration write SSH key.
#
# Uses GIT_SSH_WRITE_SECRET_NAME (default: guesttek/git-ssh-key-codebuild).
# Skips the commit when repo pins are unchanged (ignores built_at / built_by).
set -euo pipefail

CLONE_ROOT="${CLONE_ROOT:-/tmp/repos}"
REPOS_MANIFEST="${REPOS_MANIFEST:-${CLONE_ROOT}/repos-manifest.yaml}"
RELEASE_MANIFEST="${RELEASE_MANIFEST:-${CLONE_ROOT}/release-manifest.yaml}"
MANIFEST_REPO_URL="${MANIFEST_REPO_URL:-git@github.com:amitgupta2rsystems/guesttek_devops.git}"
MANIFEST_PUSH_BRANCH="${MANIFEST_PUSH_BRANCH:-main}"
WRITE_SECRET="${GIT_SSH_WRITE_SECRET_NAME:-guesttek/git-ssh-key-codebuild}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}"
GIT_AUTHOR_NAME="${MANIFEST_GIT_AUTHOR_NAME:-guesttek-codebuild}"
GIT_AUTHOR_EMAIL="${MANIFEST_GIT_AUTHOR_EMAIL:-noreply@guesttek.invalid}"

if [[ ! -f "$REPOS_MANIFEST" ]]; then
  echo "Missing repos-manifest.yaml at $REPOS_MANIFEST" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
KEYFILE="${WORKDIR}/id_ed25519"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==== Loading write SSH key from ${WRITE_SECRET} ===="
aws secretsmanager get-secret-value \
  --secret-id "$WRITE_SECRET" \
  --region "$REGION" \
  --query SecretString \
  --output text | tr -d '\r' > "$KEYFILE"
chmod 600 "$KEYFILE"
ssh-keygen -lf "$KEYFILE"

export GIT_SSH_COMMAND="ssh -i ${KEYFILE} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${WORKDIR}/known_hosts"
ssh-keyscan -t rsa,ed25519 github.com > "${WORKDIR}/known_hosts" 2>/dev/null
chmod 644 "${WORKDIR}/known_hosts"

echo "==== Cloning ${MANIFEST_REPO_URL} (${MANIFEST_PUSH_BRANCH}) ===="
git clone --depth 1 --branch "$MANIFEST_PUSH_BRANCH" "$MANIFEST_REPO_URL" "${WORKDIR}/repo"
REPO="${WORKDIR}/repo"

cp -f "$REPOS_MANIFEST" "${REPO}/repos-manifest.yaml"
if [[ -f "$RELEASE_MANIFEST" ]]; then
  cp -f "$RELEASE_MANIFEST" "${REPO}/release-manifest.yaml"
fi

# Compare substantive content (ignore volatile build metadata / timestamps).
changed="$(
  python3 - "$REPO" <<'PY'
import pathlib
import re
import subprocess
import sys

repo = pathlib.Path(sys.argv[1])
files = ["repos-manifest.yaml", "release-manifest.yaml"]


def normalize(text: str) -> str:
    lines = []
    for line in text.splitlines():
        if re.match(r"^\s*built_at:\s*", line):
            continue
        if re.match(r"^\s*built_by:\s*", line):
            continue
        if re.match(r"^\s*generated_at:\s*", line):
            continue
        lines.append(line.rstrip())
    return "\n".join(lines).strip() + "\n"


changed = False
for name in files:
    path = repo / name
    if not path.is_file():
        continue
    new = normalize(path.read_text(encoding="utf-8"))
    # staged working tree vs HEAD
    try:
        old_raw = subprocess.check_output(
            ["git", "-C", str(repo), "show", f"HEAD:{name}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        old = normalize(old_raw)
    except subprocess.CalledProcessError:
        old = ""
    if new != old:
        changed = True
        print(f"CHANGED {name}")
    else:
        print(f"UNCHANGED {name}")

print("RESULT", "yes" if changed else "no")
sys.exit(0 if changed else 0)
PY
)"
echo "$changed"
if ! echo "$changed" | grep -q '^RESULT yes$'; then
  echo "==== No substantive manifest changes; skip push ===="
  exit 0
fi

cd "$REPO"
git config user.name "$GIT_AUTHOR_NAME"
git config user.email "$GIT_AUTHOR_EMAIL"
git add repos-manifest.yaml
[[ -f release-manifest.yaml ]] && git add release-manifest.yaml

if git diff --cached --quiet; then
  echo "==== Nothing staged; skip push ===="
  exit 0
fi

BUILD_ID="${CODEBUILD_BUILD_ID:-local}"
git commit -m "$(cat <<EOF
Update build manifests from CodeBuild.

[ci-manifest] build=${BUILD_ID}
EOF
)"

echo "==== Pushing manifests to ${MANIFEST_PUSH_BRANCH} ===="
git push origin "HEAD:${MANIFEST_PUSH_BRANCH}"
echo "==== Manifest push complete ===="
git log -1 --oneline
git show --stat --oneline HEAD
