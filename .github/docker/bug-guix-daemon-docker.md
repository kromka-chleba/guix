# Bug: `guix-daemon` does not start in Docker containers

## Prior state

When running a Guix System Docker image, `guix-daemon` reliably failed
to start.  Shepherd would report it as stopped and no builds were
possible.  The failure was silent — no obvious error message, just
`guix-daemon` never becoming available.

## Root cause

The root cause was in `gnu/build/activation.scm`, in the `activate-etc`
procedure that populates `/etc` during system activation.

Docker bind-mounts several files into the container at start-up
(e.g. `/etc/hostname`, `/etc/resolv.conf`) and pre-populates `/etc/ssl`
with host certificates that are held open as busy files.  The original
`activate-etc` code:

1. Tried to delete `/etc/ssl` with `delete-file-recursively` — this
   silently failed because the bind-mounted certificate files inside it
   are busy (`EBUSY`), so `/etc/ssl` remained.
2. Then unconditionally called `symlink … "/etc/ssl"` — which threw
   `EEXIST` because `/etc/ssl` still existed.
3. That unhandled `EEXIST` **aborted the entire `/etc` population loop**,
   so files created later in the loop — including `/etc/nsswitch.conf`
   and `/etc/pam.d/` — were never created.

Without `/etc/nsswitch.conf`, the C library's name-service switch is
unconfigured, so `getpwuid`/`getgrgid` calls return nothing.
`guix-daemon` checks file ownership of the store on startup and relies
on these calls; with them broken it exited immediately, never reaching
the point where shepherd could consider it running.

## Fix

Two guarded changes in `gnu/build/activation.scm`:

1. **`/etc/ssl` symlink** — wrapped in `unless (false-if-exception
   (lstat "/etc/ssl"))` so that if Docker's busy files prevent removal
   of the directory the symlink step is skipped instead of raising
   `EEXIST`:

   ```scheme
   (false-if-exception (delete-file-recursively "/etc/ssl"))
   (unless (false-if-exception (lstat "/etc/ssl"))
     (symlink "/run/current-system/profile/etc/ssl" "/etc/ssl"))
   ```

2. **General `/etc` loop** — added an `unless (file-exists? target)`
   guard after each `rm-f` call so that if a Docker bind-mount prevents
   deletion (returns `EBUSY`) the loop continues to the next file rather
   than letting the subsequent `symlink` call throw `EEXIST` and abort:

   ```scheme
   (rm-f target)
   (unless (file-exists? target)   ; skip if Docker bind-mount is busy
     (symlink source target))
   ```

Together these changes ensure that `/etc` is fully populated even when
Docker holds some entries busy, which in turn lets `guix-daemon` start
normally.

---

# Bug: Docker image build runner gets stuck on entropy

## Symptom

The CI step that runs `guix system image` inside the bootstrap container
hangs with:

```
Please wait while gathering entropy to generate the key pair;
this may take time...
```

## Root cause

Two interlocking issues:

### 1 — System activation blocks on entropy

`guix system image --image-type=docker` builds an image whose Docker
`Entrypoint` is set to `[boot-program-path, os-store-path]`
(`gnu/system/image.scm`, `system-docker-image`).  When `docker run IMAGE
sh -c '...'` is used, Docker appends `sh -c '...'` to the Entrypoint
rather than replacing it.  The Guix system therefore boots normally
(activation + Shepherd), regardless of the extra arguments.

During system activation, `guix-activation` (`gnu/services/base.scm`)
calls `guix archive --generate-key` unless `generate-substitute-key? #f`
is set.  That call uses `gcrypt` to generate an RSA key pair, which reads
from `/dev/random` and **blocks indefinitely** in an entropy-starved
Docker container.

The `rngd-service-type` configured in `guix-dev-system.scm` was intended
to mitigate this, but `rngd` is a Shepherd-managed service that starts
**after** activation completes — too late to help.

### 2 — The shell command passed to `docker run` is silently ignored

Because the Entrypoint is `[boot-program, os-path]` and the `docker run`
command `sh -c '...'` merely appends to it, boot-program receives
`[boot-program, os-path, sh, -c, "..."]` as its argv.  It reads only
`(cadr (command-line))` (the OS store path) and calls `execl` with
exactly that — the extra `sh -c '...'` arguments are discarded.  As a
result, `./pre-inst-env guix system image` is **never executed** by the
workflow step.

## Fix (entropy)

Set `(generate-substitute-key? #f)` in the `guix-configuration` inside
`guix-dev-system.scm`.  A Docker dev/build container has no need to sign
substitutes, so generating a key pair on first boot is unnecessary.  This
eliminates the activation-time entropy blockage entirely.

The now-redundant `rngd-service-type` entry is also removed.

## Outstanding issue (command not running)

The `docker run IMAGE sh -c '...'` pattern in the CI workflow does not
execute the shell command.  The workflow needs to be redesigned: start
the container so Shepherd and `guix-daemon` come up, then use
`docker exec` (or a similar mechanism) to run `guix system image` inside
the live container.
