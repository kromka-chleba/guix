#!/usr/bin/env bash
# Start a guix-dev Docker container for local development and testing.
#
# Usage: .github/docker/start-container.sh [IMAGE [NAME]]
#
#   IMAGE  Docker image to use  (default: guix-dev:latest)
#   NAME   Container name       (default: guix-dev)
#
# The container is started with:
#   --privileged  so that guix-daemon can set up build sandboxes.
#   -v REPO:/workspace  mounts the repository checkout at /workspace.
#   -w /workspace  sets the working directory inside the container.
#
# Connect to the running container with:
#   docker exec -ti NAME /run/current-system/profile/bin/bash --login

set -euo pipefail

IMAGE="${1:-guix-dev:latest}"
NAME="${2:-guix-dev}"

# Resolve the repository root (two levels up from this script).
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Remove any existing container with the same name.
docker rm -f "$NAME" 2>/dev/null || true

echo "==> Creating container '$NAME' from '$IMAGE'"
container_id="$(docker create \
    --name "$NAME" \
    --privileged \
    -v "$REPO_ROOT:/workspace" \
    -w /workspace \
    "$IMAGE")"

echo "==> Starting container"
docker start "$container_id" >/dev/null

echo "==> Container started: $NAME ($container_id)"
echo "    Connect:  docker exec -ti $NAME /run/current-system/profile/bin/bash --login"
echo "    Stop:     .github/docker/stop-container.sh $NAME"
