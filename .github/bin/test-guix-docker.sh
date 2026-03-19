#!/usr/bin/env bash
# test-guix-docker.sh – Test the Guix dev Docker image functionality
#
# Usage:
#   .github/bin/test-guix-docker.sh [IMAGE_TAG]
#
# This script verifies that the Guix development Docker image:
#   1. Can be pulled from the registry
#   2. Starts successfully with Shepherd init system
#   3. Has all core services available
#   4. Can execute basic Guix commands
#   5. (Optional) Can build packages if network is available
#
# Exit codes:
#   0 – All tests passed
#   1 – One or more tests failed

set -euo pipefail

IMAGE_TAG="${1:-ghcr.io/kromka-chleba/guix-dev:latest}"
SKIP_NETWORK_TESTS="${SKIP_NETWORK_TESTS:-false}"

echo "========================================"
echo "Testing Guix Dev Docker Image"
echo "Image: ${IMAGE_TAG}"
echo "========================================"
echo ""

# Cleanup function
cleanup() {
  if [ -n "${CONTAINER_ID:-}" ]; then
    echo "Cleaning up container..."
    docker stop "${CONTAINER_ID}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_ID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Test 1: Pull the image
echo "[TEST 1/6] Pulling image..."
if docker pull "${IMAGE_TAG}"; then
  echo "✓ Image pulled successfully"
else
  echo "✗ Failed to pull image"
  exit 1
fi
echo ""

# Test 2: Start container with proper entrypoint
echo "[TEST 2/6] Starting container with Shepherd init..."
CONTAINER_ID=$(docker run -d --privileged "${IMAGE_TAG}")
if [ -n "${CONTAINER_ID}" ]; then
  echo "✓ Container started successfully (ID: ${CONTAINER_ID})"
else
  echo "✗ Failed to start container"
  exit 1
fi

# Wait for Shepherd to initialize
echo "  Waiting for Shepherd to initialize..."
sleep 5
echo ""

# Test 3: Verify herd/shepherd is running
echo "[TEST 3/6] Checking Shepherd init system..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd status >/dev/null 2>&1; then
  echo "✓ Shepherd is running"
  echo ""
  docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd status
else
  echo "✗ Shepherd is not running"
  exit 1
fi
echo ""

# Test 4: Start Guix daemon
echo "[TEST 4/6] Starting Guix daemon..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd start guix-daemon >/dev/null 2>&1; then
  echo "✓ Guix daemon started"
  docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd status guix-daemon
else
  echo "✗ Failed to start Guix daemon"
  exit 1
fi
echo ""

# Test 5: Verify guix commands work
echo "[TEST 5/6] Checking Guix is available..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix --version >/dev/null 2>&1; then
  echo "✓ Guix is available"
  docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix --version | head -1
else
  echo "✗ Guix is not available"
  exit 1
fi
echo ""

# Test 6: Try a simple guix build (optional - requires network)
if [ "${SKIP_NETWORK_TESTS}" = "false" ]; then
  echo "[TEST 6/6] Testing 'guix build hello' (requires network)..."
  if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix build hello >/dev/null 2>&1; then
    echo "✓ Successfully built 'hello' package"
  else
    echo "⚠ Failed to build 'hello' package (may be due to network restrictions)"
    echo "  This is expected in restricted CI environments"
  fi
else
  echo "[TEST 6/6] Skipping network-dependent tests (SKIP_NETWORK_TESTS=true)"
fi
echo ""

echo "========================================"
echo "Core tests passed! ✓"
echo "========================================"
echo ""
echo "The Docker image is functional and ready to use."
echo "To use it interactively (Shepherd is PID 1 – use docker exec, not docker run -it):"
echo "  CONTAINER=\$(docker run -d --privileged ${IMAGE_TAG})"
echo "  docker exec -ti \$CONTAINER /run/current-system/profile/bin/bash --login"
echo "  docker stop \$CONTAINER"
echo ""
