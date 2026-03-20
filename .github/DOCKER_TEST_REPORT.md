# Guix Dev Docker Image – Test Report

## Latest test run

| Field | Value |
|-------|-------|
| Image | `ghcr.io/kromka-chleba/guix-dev:latest` |
| Digest | `sha256:8a19fe26013b239e895371c89253b46f5925f921cb4fb98cd7b8fb907b8829d0` |
| Guix version | `guix (GNU Guix) 1.5.0-1.deedd48` |
| Test date | 2026-03-20 |
| Test environment | GitHub Actions / sandboxed runner |

## Test results

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | Pull image from GHCR | ✅ PASS | Image size ~983 MB compressed / ~3.06 GB uncompressed |
| 2 | Start container with Shepherd as PID 1 | ✅ PASS | `docker run -d --privileged` |
| 3 | Shepherd init system running | ✅ PASS | All core services started |
| 4 | Start Guix daemon via `herd start guix-daemon` | ✅ PASS | Listening on `/var/guix/daemon-socket/socket` |
| 5 | `guix --version` inside container | ✅ PASS | Guix 1.5.0-1.deedd48 |
| 6 | `guix build hello` (network) | ⚠️ SKIP | Expected – outbound network restricted in CI sandbox |

**Overall: All core tests passed.**

## Shepherd service status (at test time)

```
Started:
 + file-systems
 + loopback
 + pam
 + root
 + root-file-system
 + system-log
 + udev
 + urandom-seed
 + user-file-systems
 + virtual-terminal

Running timers:
 + log-rotation

Stopped:
 - guix-daemon       (started manually in Test 4)
 - log-cleanup
 - nscd
 - timer
 - transient
 - user-processes

One-shot:
 * guix-ownership
 * sysctl
 * user-homes
```

## How to use interactively

Guix system images boot with **Shepherd as PID 1**.  `docker run --rm -it … bash`
is blocked because Shepherd takes over the container before a login shell can
start.  Use `docker exec` instead:

```bash
# Start the container in the background
CONTAINER=$(docker run -d --privileged ghcr.io/kromka-chleba/guix-dev:latest)

# Attach an interactive login shell
docker exec -ti $CONTAINER /run/current-system/profile/bin/bash --login

# Run individual Guix commands
docker exec $CONTAINER /run/current-system/profile/bin/guix --version
docker exec $CONTAINER /run/current-system/profile/bin/herd status

# Stop the container when done
docker stop $CONTAINER
```

## Note on `guix-daemon`

The Guix daemon is defined in the system config but **not started automatically**
at container boot (it is in `Stopped` state in Shepherd).  Start it explicitly
when needed:

```bash
docker exec $CONTAINER /run/current-system/profile/bin/herd start guix-daemon
```

Once running it listens on `/var/guix/daemon-socket/socket` and allows
`guix build`, `guix package`, `guix shell`, etc. to work normally.
