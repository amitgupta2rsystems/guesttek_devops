# Local patches — GuestTek Camsuite Edge amd64 build
#
# **Active (`series`):** `001`/`001b` inference (Smriti), `002`/`002b` alert (Smriti), `003` provisioning exit-code, `004`/`004b` video-capture `camsuite:` tag.
# Inference/alert applied inside each service dir via `name.patch|subdir`.
#
# These patches fix packaging builds on **amd64** hosts without changing upstream
# GitHub/Bitbucket repos permanently. Nothing here is committed to those remotes.

## Problems addressed

| Patch | Issue | Fix |
|-------|-------|-----|
| `001` / `001b` | Inference arm64 + wasp registry (Smriti) | `IMAGE_REF=camsuite:inference-*`, `PLATFORM`, compose OTA path |
| `002` / `002b` | Alert manager (Smriti) | Applied inside `alert_manager_service/` via `patch\|subdir` |
| `003` | Provisioning `build-docker.sh` exits 1 when `REGISTRY_IMAGE` empty | `if`/`fi` instead of trailing `[[ ]]&&` |
| `004` / `004b` | Video-capture still tags `registry.guesttek-camsuite.local:5000/camsuite:…` | `IMAGE_REF=camsuite:video-capture-cpp-*`, compose image line |

Former CI patches live under `patches/archive-ci/` (not in `series`).
## Bitbucket empty `master` branches

Not a patch — run branch checkout after clone:

```bash
./scripts/checkout-service-branches.sh
```

| Repo | Branch |
|------|--------|
| `camsuite-emb-ip-camera` | `feature/ip-camera-service-approach-b` |
| `camsuite-emb-video-capture` | `feature/Packaging` |
| `camsuite-emb-video-upload-manager` | `dev` |

## Usage

Fresh monorepo layout (after cloning all repos):

```bash
cd /path/to/guestek

# 1. Check out service branches with real code
./scripts/checkout-service-branches.sh

# 2. Apply local patches
./scripts/apply-patches.sh

# 3. Pin SHAs (GitHub + Bitbucket services only)
./scripts/release-manifest.sh generate --output release-manifest.yaml --platform amd64

# 4. Build
./build-package.sh --platform amd64 --manifest release-manifest.yaml

# Or use the full pipeline (install → patches → build → artifacts):
./ci/run-pipeline.sh --platform amd64 --in-place --skip-checkout
```

Check patch status:

```bash
./scripts/apply-patches.sh --check
```

Revert all patches (restore upstream file content):

```bash
./scripts/revert-patches.sh
```

## Patch order (`series`)

Apply in numeric order. Revert with `revert-patches.sh` (reverse order).

## Orchestration-only changes (not in `patches/`)

These live only under the monorepo root (not cloned service repos):

- `scripts/release-manifest.sh` — GitHub/Bitbucket repos only, writes `remote:`
- `release-manifest.example.yaml` — same scope
- `scripts/checkout-service-branches.sh` — dev branch checkout helper

## System dependency

For the `.deb` step:

```bash
sudo apt-get install -y debhelper
```

(`build-package.sh` checks for debhelper and prints a clear error if missing.)
