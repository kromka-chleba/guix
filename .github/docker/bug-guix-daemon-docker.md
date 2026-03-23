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
