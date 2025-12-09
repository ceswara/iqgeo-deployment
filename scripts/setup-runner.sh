#!/bin/bash
# Script to configure GitHub Actions runner on EC2 instance
# Run this script as root or with sudo

set -e

GITHUB_REPO_URL="${1:-https://github.com/ceswara/iqgeo-deployment}"
RUNNER_TOKEN="${2}"

if [ -z "$RUNNER_TOKEN" ]; then
    echo "Usage: $0 <GITHUB_REPO_URL> <RUNNER_TOKEN>"
    echo "Get the token from: ${GITHUB_REPO_URL}/settings/actions/runners/new"
    exit 1
fi

echo "=== Configuring GitHub Actions Runner ==="

# Switch to runner user and configure
sudo -u runner bash << EOF
cd /home/runner/actions-runner
./config.sh --url ${GITHUB_REPO_URL} --token ${RUNNER_TOKEN} --unattended --name "eks-runner" --labels "self-hosted,Linux,X64,eks"
EOF

# Enable and start the service
systemctl enable github-runner
systemctl start github-runner

echo "=== Runner Status ==="
systemctl status github-runner

echo ""
echo "GitHub Actions runner is now configured and running!"
echo "Check runners at: ${GITHUB_REPO_URL}/settings/actions/runners"

