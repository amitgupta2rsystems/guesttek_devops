# guesttek_devops

Orchestration recipes for GuestTek edge CodeBuild (fetch/clone only).

## Layout

- `ci/aws/buildspec.yml` — CodeBuild buildspec
- `ci/aws/setup-git-ssh.sh` — load `guesttek/git-ssh-key` and configure SSH
- `ci/aws/clone-service-repos.sh` — clone repos from `scripts/service-repos.list`
- `scripts/service-repos.list` — service remotes (read-only)

## Policy

CodeBuild clones of **service** remotes are **read-only**. Do not commit or push to those GitHub/Bitbucket remotes from CI.

After a successful build, CodeBuild may push generated `repos-manifest.yaml` / `release-manifest.yaml` back to `amitgupta2rsystems/guesttek_devops` using `guesttek/git-ssh-key-codebuild` (`ci/aws/push-repos-manifest.sh`).
