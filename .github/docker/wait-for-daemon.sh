#!/bin/sh
# wait-for-daemon.sh — Poll until guix-daemon is running in CONTAINER.
#
# Usage: wait-for-daemon.sh CONTAINER [TIMEOUT_SECONDS]
#
# Exits 0 when guix-daemon reports "running", 1 if the timeout is reached.

set -e

CONTAINER="${1:?Usage: wait-for-daemon.sh CONTAINER [TIMEOUT]}"
TIMEOUT="${2:-120}"

HERD=/run/current-system/profile/bin/herd

echo "Waiting for guix-daemon in container '${CONTAINER}' (timeout: ${TIMEOUT}s)..."

elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
  if docker exec "$CONTAINER" "$HERD" status guix-daemon 2>&1 | grep -q running; then
    echo "guix-daemon is running."
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

echo "::error::guix-daemon did not start within ${TIMEOUT}s in container '${CONTAINER}'" >&2
exit 1
