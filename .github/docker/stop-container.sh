#!/usr/bin/env bash
# Stop and remove a guix-dev Docker container.
#
# Usage: .github/docker/stop-container.sh [NAME]
#
#   NAME  Container name (default: guix-dev)

set -euo pipefail

NAME="${1:-guix-dev}"

echo "==> Stopping container '$NAME'"
docker stop "$NAME"

echo "==> Removing container '$NAME'"
docker rm "$NAME"

echo "==> Done."
