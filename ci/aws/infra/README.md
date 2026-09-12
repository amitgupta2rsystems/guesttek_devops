# AWS infrastructure for `guesttek-camsuite-edge` CodeBuild

Version-controlled IAM policies and provisioning scripts. The **build pipeline** itself lives in `ci/aws/buildspec.yml`; this directory defines the AWS resources that run it.

## Layout

```
ci/aws/infra/
  config.env.example          # account-specific settings (copy → config.env)
  provision.sh                # run all steps
  create-artifact-bucket.sh
  create-codebuild-project.sh
  codebuild-service-role/
    trust-policy.json
    role-policy.json.template
    create-role.sh
  iam-trigger-user/
    policy.json.template
    create-user.sh
```

`config.env` is gitignored (account IDs, connection ARNs). Commit changes to `config.env.example` when defaults change.

## First-time setup (admin)

```bash
cd ci/aws/infra
cp config.env.example config.env
# edit config.env if needed

./provision.sh
CREATE_TRIGGER_USER=1 ./provision.sh   # also create guesttek-build user
```

## Update after policy/project changes

```bash
cd ci/aws/infra
./codebuild-service-role/create-role.sh    # refresh IAM role policy
./create-codebuild-project.sh              # refresh project settings
./iam-trigger-user/create-user.sh          # refresh trigger user policy
```

## Start a build

```bash
aws codebuild start-build \
  --project-name guesttek-camsuite-edge \
  --region ap-south-1
```

## LabSmoke stage (CodePipeline)

After the Build stage, **LabSmoke** SSHs to the lab EC2 host and runs `lab-smoke-test.sh`
(install `.deb` + 21 validation checks).

```bash
cd ci/aws/infra
cp config.env.example config.env   # if needed

./create-lab-smoke-ssh-secret.sh   # ~/.ssh/id_ed25519 → Secrets Manager
./create-lab-smoke-codebuild-project.sh
./update-codepipeline-labsmoke.sh

aws codepipeline start-pipeline-execution \
  --name guesttek-camsuite-edge-pipeline --region ap-south-1
```

Pipeline: **Source → Build → LabSmoke → Publish**

LabSmoke must pass before **Publish** runs (CodePipeline stops on stage failure).

## S3 artifact policy

| Prefix | When | Retention |
|--------|------|-----------|
| `builds/dev_<ver>-<n>/camsuite-edge-deb` | End of **Build** (post_build archive) | **Kept** — even if LabSmoke fails |
| `guesttek-camsuite-edge/dev_<ver>-<n>/camsuite-edge-deb` | **Publish** after LabSmoke passes | **One latest** — older published releases replaced |

Build IDs: `dev_1.0.0-1`, `dev_1.0.0-2`, … (from `.deb` version + auto-increment).

```bash
cd ci/aws/infra
./update-codepipeline-stages.sh
```

- **LabSmoke fails** → build archived in `builds/`, published release unchanged, Publish skipped.
- **LabSmoke passes** → Publish promotes to `guesttek-camsuite-edge/` (replaces previous release).

### Standalone LabSmoke (pick artifact from S3)

```bash
./start-lab-smoke.sh
# or explicit zip:
./start-lab-smoke.sh s3://guesttek-camsuite-edge-artifacts-ACCT/guesttek-camsuite-edge/BUILD_ID/camsuite-edge-deb
```

## Notes

- Service repo clones remain **read-only** (never commit/push from CodeBuild).
- Build archive: `s3://guesttek-camsuite-edge-artifacts-<account>/builds/dev_1.0.0-1/`
- Published release (one latest): `s3://guesttek-camsuite-edge-artifacts-<account>/guesttek-camsuite-edge/dev_1.0.0-1/`
- Bundles (deploy / guesttek-camsuite-edge): `s3://guesttek-edge-bundles-<account>/guesttek/bundles/`
