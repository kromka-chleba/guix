#!/usr/bin/env bash
# build-guix-docker.sh – Build a Guix system Docker image for Guix development.
#
# Usage:
#   .github/bin/build-guix-docker.sh [IMAGE_TAG]
#
# Environment variables:
#   IMAGE_TAG          – Docker image tag (default: guix-dev:latest)
#   REGISTRY           – Docker registry prefix, e.g. ghcr.io/your-org (default: empty)
#   GUIX_SYSTEM_CONFIG – Path to the Guix system config (default: .github/guix-dev-docker.scm)
#   EXTRA_GUIX_FLAGS   – Additional flags passed verbatim to 'guix system image'
#
# Prerequisites (on the host running this script):
#   * GNU Guix installed and on PATH
#   * Docker (or podman) installed and the daemon accessible
#   * Sufficient disk space for the store and the resulting image (~several GB)
#
# The image is built with 'guix system image --image-type=docker', which
# produces a gzip-compressed tarball that can be loaded with 'docker load'.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
IMAGE_TAG="${1:-${IMAGE_TAG:-guix-dev:latest}}"
REGISTRY="${REGISTRY:-}"
GUIX_SYSTEM_CONFIG="${GUIX_SYSTEM_CONFIG:-${REPO_ROOT}/.github/guix-dev-docker.scm}"
EXTRA_GUIX_FLAGS="${EXTRA_GUIX_FLAGS:-}"

if [[ -n "${REGISTRY}" ]]; then
  FULL_IMAGE_TAG="${REGISTRY}/${IMAGE_TAG}"
else
  FULL_IMAGE_TAG="${IMAGE_TAG}"
fi

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
if [[ ! -f "${GUIX_SYSTEM_CONFIG}" ]]; then
  echo "ERROR: Guix system config not found: ${GUIX_SYSTEM_CONFIG}" >&2
  exit 1
fi

if ! command -v guix &>/dev/null; then
  echo "ERROR: 'guix' is not on PATH.  Please install GNU Guix first." >&2
  exit 1
fi

if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null; then
  echo "ERROR: Neither 'docker' nor 'podman' found on PATH." >&2
  exit 1
fi

DOCKER_CMD="docker"
command -v docker &>/dev/null || DOCKER_CMD="podman"

# ---------------------------------------------------------------------------
# Build the Docker image tarball
# ---------------------------------------------------------------------------
echo "==> Building Guix system Docker image from: ${GUIX_SYSTEM_CONFIG}"
echo "    Target tag: ${FULL_IMAGE_TAG}"
echo ""

# 'guix system image --image-type=docker' writes a store path (a .tar.gz) and prints it.
# shellcheck disable=SC2086
TARBALL="$(guix system image --image-type=docker \
              ${EXTRA_GUIX_FLAGS} \
              "${GUIX_SYSTEM_CONFIG}")"

if [[ -z "${TARBALL}" || ! -f "${TARBALL}" ]]; then
  echo "ERROR: 'guix system image --image-type=docker' did not produce a tarball." >&2
  exit 1
fi

echo "==> Tarball produced: ${TARBALL}"

# ---------------------------------------------------------------------------
# Load into Docker / Podman
# ---------------------------------------------------------------------------
echo "==> Loading image into ${DOCKER_CMD}..."
LOADED_TAG="$("${DOCKER_CMD}" load -i "${TARBALL}" \
                | grep -oP '(?<=Loaded image: ).*' \
                || true)"

# Re-tag with the desired name
echo "==> Tagging image as ${FULL_IMAGE_TAG}..."
if [[ -n "${LOADED_TAG}" ]]; then
  "${DOCKER_CMD}" tag "${LOADED_TAG}" "${FULL_IMAGE_TAG}"
else
  # Fallback: inspect the most-recently loaded image
  LATEST_ID="$("${DOCKER_CMD}" images -q | head -1)"
  "${DOCKER_CMD}" tag "${LATEST_ID}" "${FULL_IMAGE_TAG}"
fi

echo ""
echo "==> Image available as: ${FULL_IMAGE_TAG}"
echo ""
echo "    To run an interactive shell:"
echo "      ${DOCKER_CMD} run --rm -it ${FULL_IMAGE_TAG} /run/current-system/profile/bin/bash"
echo ""
echo "    To push to a registry (manual step):"
echo "      ${DOCKER_CMD} push ${FULL_IMAGE_TAG}"
