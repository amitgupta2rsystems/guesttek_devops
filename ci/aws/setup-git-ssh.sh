#!/usr/bin/env bash
# Load deploy key from AWS Secrets Manager and configure SSH for Bitbucket + GitHub.
set -euo pipefail

SECRET_NAME="${GIT_SSH_SECRET_NAME:-guesttek/git-ssh-key}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query SecretString \
  --output text | tr -d '\r' > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519

PUB="$(ssh-keygen -y -f ~/.ssh/id_ed25519)"
if echo "$PUB" | grep -q '^ssh-rsa '; then
  mv ~/.ssh/id_ed25519 ~/.ssh/id_rsa
  KEYFILE=~/.ssh/id_rsa
else
  KEYFILE=~/.ssh/id_ed25519
fi
chmod 600 "$KEYFILE"

echo "SSH public key fingerprint:"
ssh-keygen -lf "$KEYFILE"

ssh-keyscan -t rsa,ed25519 bitbucket.org github.com >> ~/.ssh/known_hosts 2>/dev/null
chmod 644 ~/.ssh/known_hosts

cat > ~/.ssh/config <<CFG
Host bitbucket.org
  HostName bitbucket.org
  User git
  IdentitiesOnly yes
  IdentityFile ${KEYFILE}
Host github.com
  HostName github.com
  User git
  IdentitiesOnly yes
  IdentityFile ${KEYFILE}
CFG
chmod 600 ~/.ssh/config

ssh -T git@bitbucket.org 2>&1 || true
ssh -T git@github.com 2>&1 || true
