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

## Notes

- Service repo clones remain **read-only** (never commit/push from CodeBuild).
- Artifacts: `s3://guesttek-camsuite-edge-artifacts-<account>/guesttek-camsuite-edge/<build-id>/`
- Bundles (deploy / guesttek-camsuite-edge): `s3://guesttek-edge-bundles-<account>/guesttek/bundles/`
