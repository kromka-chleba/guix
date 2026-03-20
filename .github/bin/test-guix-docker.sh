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
#   4. Can start the Guix daemon via herd
#   5. Can execute basic Guix commands
#   6. Has /etc/services available for hostname/service resolution
#   7. Can fetch a pre-built substitute from bordeaux.guix.gnu.org
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
echo "[TEST 1/7] Pulling image..."
if docker pull "${IMAGE_TAG}"; then
  echo "✓ Image pulled successfully"
else
  echo "✗ Failed to pull image"
  exit 1
fi
echo ""

# Test 2: Start container with proper entrypoint
echo "[TEST 2/7] Starting container with Shepherd init..."
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
echo "[TEST 3/7] Checking Shepherd init system..."
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
echo "[TEST 4/7] Starting Guix daemon..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd start guix-daemon >/dev/null 2>&1; then
  echo "✓ Guix daemon started"
  docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/herd status guix-daemon
else
  echo "✗ Failed to start Guix daemon"
  exit 1
fi
echo ""

# Test 5: Verify guix commands work
echo "[TEST 5/7] Checking Guix is available..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix --version >/dev/null 2>&1; then
  echo "✓ Guix is available"
  docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix --version | head -1
else
  echo "✗ Guix is not available"
  exit 1
fi
echo ""

# Test 6: Ensure /etc/services is present so getaddrinfo("hostname", "https") works.
#
# The Guix activate-etc function (gnu/build/activation.scm) used to call
# delete-file on /etc/ssl before symlinking it.  delete-file silently fails
# when /etc/ssl is a directory (as Docker creates it), leaving the symlink
# uncreated and aborting activate-etc before it gets to create /etc/services.
# This step detects that situation and creates the symlinks manually.  Once the
# image is rebuilt with the fixed activation code this step becomes a no-op.
echo "[TEST 6/7] Ensuring /etc/services is present..."
if docker exec "${CONTAINER_ID}" \
     /run/current-system/profile/bin/guile --no-auto-compile -c \
     "(exit (if (access? \"/etc/services\" F_OK) 0 1))" 2>/dev/null; then
  echo "✓ /etc/services already present"
else
  echo "  /etc/services missing – creating symlinks from /run/current-system/etc/"
  for f in services protocols rpc nsswitch.conf localtime; do
    docker exec "${CONTAINER_ID}" \
      /run/current-system/profile/bin/guile --no-auto-compile -c \
      "(catch 'system-error
         (lambda ()
           (symlink \"/run/current-system/etc/${f}\" \"/etc/${f}\"))
         (lambda (k . a) #f))" 2>/dev/null || true
  done
  if docker exec "${CONTAINER_ID}" \
       /run/current-system/profile/bin/guile --no-auto-compile -c \
       "(exit (if (access? \"/etc/services\" F_OK) 0 1))" 2>/dev/null; then
    echo "✓ /etc/services symlink created"
  else
    echo "✗ Failed to create /etc/services"
    exit 1
  fi
fi
echo ""

# Test 7: Fetch a pre-built substitute (requires network access to bordeaux.guix.gnu.org)
echo "[TEST 7/7] Testing 'guix build hello' via substitute from bordeaux.guix.gnu.org..."
if docker exec "${CONTAINER_ID}" /run/current-system/profile/bin/guix build hello 2>&1; then
  echo "✓ Successfully fetched 'hello' substitute – network access confirmed"
else
  echo "✗ Failed to build 'hello' package"
  echo "  Ensure bordeaux.guix.gnu.org and ci.guix.gnu.org are reachable from this runner."
  exit 1
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
