# Bug: `wait-for-daemon` always timed out

## Prior state

`wait-for-daemon` in `docker-lib.scm` polled the container by running:

```sh
herd status guix-daemon 2>&1 | grep -q started
```

Because the pattern `started` never appeared in shepherd's output, the
function always timed out (after 30 s) even when the daemon was fully up
and running.  Any test that depended on `guix-daemon` being available
therefore failed immediately after the timeout warning.

## Root cause

shepherd reports service status as `"It is running"`, not `"started"`.
The grep pattern was simply wrong.

## Fix

Changed `grep -q started` → `grep -q running` so the poll matches the
actual output shepherd produces:

```scheme
(string-append "docker exec " container
               " " %system-profile "/herd"
               " status guix-daemon 2>&1 | grep -q running")
```
