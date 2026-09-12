# Local amd64 pipeline

Self-contained scripts to clone GuestTek edge services, apply local patches, and build Docker images on **linux/amd64**.

No `release-manifest.yaml`. Nothing is committed or pushed.

## Quick start

```bash
cd /path/to/guesttek_devops-2
./ci/local/run.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| `run.sh` | Main entry — runs all steps |
| `01-clone.sh` | Clone/fetch repos from `scripts/service-repos.list` |
| `02-patch.sh` | Apply `patches/series` to the work copy |
| `03-build.sh` | Run each service `build-docker.sh` (pauses after each) |
| `config.sh` | Paths, platform, service list |
| `lib/common.sh` | Shared helpers |

## Options

```bash
./ci/local/run.sh --work-root /tmp/guesttek-amd64-build
./ci/local/run.sh --fresh-clone          # delete and re-clone all repos
./ci/local/run.sh --skip-clone           # reuse existing clones
./ci/local/run.sh --skip-patches         # upstream sources only
./ci/local/run.sh --no-pause             # no Enter between builds
./ci/local/run.sh --dry-run
```

Run individual steps:

```bash
WORK_ROOT=/tmp/guesttek-amd64-build ./ci/local/01-clone.sh
WORK_ROOT=/tmp/guesttek-amd64-build ./ci/local/02-patch.sh
WORK_ROOT=/tmp/guesttek-amd64-build ./ci/local/03-build.sh
```

## Requirements

- `git`, `docker`, `patch`
- Docker daemon running
- SSH keys for Bitbucket + GitHub remotes in `scripts/service-repos.list`

## Default work directory

`/tmp/guesttek-amd64-build`
