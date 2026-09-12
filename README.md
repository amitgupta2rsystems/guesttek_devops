# guesttek_devops

Orchestration recipes for GuestTek edge CodeBuild (fetch/clone only).

## Layout

- `ci/aws/buildspec.yml` — CodeBuild buildspec
- `ci/aws/setup-git-ssh.sh` — load Git deploy key from SSM and configure SSH
- `ci/aws/clone-service-repos.sh` — clone repos from `scripts/service-repos.list`
- `scripts/service-repos.list` — service remotes (read-only)

## Policy

CodeBuild clones are **read-only**. Do not commit or push to service GitHub/Bitbucket remotes from CI.
