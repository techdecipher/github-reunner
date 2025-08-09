#!/bin/bash

# Set variables (passed from Terraform)
GH_OWNER="${GH_OWNER}"
GH_REPO="${GH_REPO}"
GH_PAT="${GH_PAT}"
RUNNER_LABELS="${RUNNER_LABELS}"  # Reference RUNNER_LABELS here
GH_RUNNER_URL="${GH_RUNNER_URL}"
RUNNER_VERSION="${RUNNER_VERSION}"

# Create runner user if not exists
id -u runner &>/dev/null || sudo useradd -m -s /bin/bash runner

# Install dependencies
apt-get update -y
apt-get install -y curl jq unzip libicu-dev libssl-dev libcurl4-openssl-dev software-properties-common

# Setup GitHub runner as runner user
sudo -i -u runner bash <<EOF2
cd ~
mkdir -p actions-runner && cd actions-runner

curl -L -H "Accept: application/octet-stream" \
  -o actions-runner-linux-x64.tar.gz \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

tar -xzf actions-runner-linux-x64.tar.gz

TOKEN=\$(curl -s -H "Authorization: token ${GH_PAT}" \
  https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token | jq -r .token)

./config.sh --url ${GH_RUNNER_URL} \
  --token \$TOKEN \
  --unattended --labels ${RUNNER_LABELS} --name runner-eks
EOF2

# Enable & start the runner
sudo -i -u runner bash -c '~/actions-runner/run.sh &' 
