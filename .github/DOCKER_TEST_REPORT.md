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
| 6 | `/etc/services` present (workaround for activation bug) | ✅ PASS | Symlink created manually; see note below |
| 7 | `guix build hello` via substitute from bordeaux.guix.gnu.org | ✅ PASS | Downloaded glibc-2.41, gcc-14.3.0-lib, hello-2.12.2 (11.7 MB) |

**Overall: All 7 tests passed.**

## Shepherd service status (at test time)

```
Started:
 + file-systems
 + guix-daemon
 + loopback
 + pam
 + root
 + root-file-system
 + system-log
 + udev
 + urandom-seed
 + user-file-systems
 + user-processes
 + virtual-terminal

Running timers:
 + log-rotation

Stopped:
 - log-cleanup
 - nscd
 - timer
 - transient

One-shot:
 * guix-ownership
 * sysctl
 * user-homes
```

## Note on `/etc/services` activation bug

The currently published image has a bug where `/etc/services` (and several other
`/etc` files like `protocols`, `rpc`, `nsswitch.conf`) are not symlinked into
`/etc` at container startup.

**Root cause:** `activate-etc` in `gnu/build/activation.scm` calls
`(rm-f "/etc/ssl")` before creating the `/etc/ssl → …/profile/etc/ssl` symlink.
`rm-f` uses `delete-file`, which silently fails when `/etc/ssl` is a real
directory (Docker creates it as a directory for certificate storage).  The
subsequent `symlink` call then raises "File exists", aborting the entire
`activate-etc` function before the per-file loop creates `/etc/services` etc.

Without `/etc/services`, Guile's `getaddrinfo hostname "https"` fails with
`Servname not supported for ai_socktype`, breaking all Guix substitute fetches.

**Fix applied in `gnu/build/activation.scm`:** The `rm-f "/etc/ssl"` call is
replaced with `(false-if-exception (delete-file-recursively "/etc/ssl"))` which
correctly removes directories as well as plain files/symlinks.  This fix will
take effect the next time the Docker image is rebuilt.

**Workaround in test script:** `test-guix-docker.sh` detects when `/etc/services`
is absent and creates the required symlinks from `/run/current-system/etc/`
before running the `guix build hello` test.

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
