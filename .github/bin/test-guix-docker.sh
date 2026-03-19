#!/usr/bin/env bash
# test-guix-docker.sh – Test the Guix dev Docker image functionality
#
# Usage:
#   .github/bin/test-guix-docker.sh [IMAGE_TAG]
#
# This script verifies that the Guix development Docker image:
#   1. Can be pulled from the registry
#   2. Starts successfully
#   3. Has the Guix daemon running
#   4. Can execute basic Guix commands
#
# Exit codes:
#   0 – All tests passed
#   1 – One or more tests failed

set -euo pipefail

IMAGE_TAG="${1:-ghcr.io/kromka-chleba/guix-dev:latest}"

echo "========================================"
echo "Testing Guix Dev Docker Image"
echo "Image: ${IMAGE_TAG}"
echo "========================================"
echo ""

# Test 1: Pull the image
echo "[TEST 1/5] Pulling image..."
if docker pull "${IMAGE_TAG}"; then
  echo "✓ Image pulled successfully"
else
  echo "✗ Failed to pull image"
  exit 1
fi
echo ""

# Test 2: Start container and check if it runs
echo "[TEST 2/5] Starting container..."
CONTAINER_ID=$(docker run -d --privileged "${IMAGE_TAG}" /run/current-system/profile/bin/sleep 60)
if [ -n "${CONTAINER_ID}" ]; then
  echo "✓ Container started successfully (ID: ${CONTAINER_ID})"
else
  echo "✗ Failed to start container"
  exit 1
fi
echo ""

# Test 3: Verify herd/shepherd is running
echo "[TEST 3/5] Checking Shepherd init system..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd status >/dev/null 2>&1; then
  echo "✓ Shepherd is running"
  docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd status
else
  echo "✗ Shepherd is not running"
  docker stop "${CONTAINER_ID}" >/dev/null 2>&1
  docker rm "${CONTAINER_ID}" >/dev/null 2>&1
  exit 1
fi
echo ""

# Test 4: Verify guix daemon is available
echo "[TEST 4/5] Checking Guix daemon..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix --version >/dev/null 2>&1; then
  echo "✓ Guix is available"
  docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix --version | head -1
else
  echo "✗ Guix is not available"
  docker stop "${CONTAINER_ID}" >/dev/null 2>&1
  docker rm "${CONTAINER_ID}" >/dev/null 2>&1
  exit 1
fi
echo ""

# Test 5: Try a simple guix build
echo "[TEST 5/5] Testing 'guix build hello'..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix build hello >/dev/null 2>&1; then
  echo "✓ Successfully built 'hello' package"
else
  echo "✗ Failed to build 'hello' package"
  docker stop "${CONTAINER_ID}" >/dev/null 2>&1
  docker rm "${CONTAINER_ID}" >/dev/null 2>&1
  exit 1
fi
echo ""

# Cleanup
echo "Cleaning up container..."
docker stop "${CONTAINER_ID}" >/dev/null 2>&1
docker rm "${CONTAINER_ID}" >/dev/null 2>&1
echo ""

echo "========================================"
echo "All tests passed! ✓"
echo "========================================"
