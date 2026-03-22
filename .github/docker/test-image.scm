#!/usr/bin/env -S guile --no-auto-compile
!#
;;; test-image.scm — Smoke-test the Guix dev Docker container.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Usage:
;;;
;;;   guile .github/docker/test-image.scm [OPTIONS]
;;;
;;; Options:
;;;   --image IMAGE     Docker image name/tag to test (default: guix-dev:latest)
;;;   --no-privileged   Do NOT run the container with --privileged.
;;;                     By default the container runs privileged so that
;;;                     guix-daemon can set up build sandboxes.
;;;   --help            Show this help message
;;;
;;; The script:
;;;   1. Creates and starts a container from IMAGE (privileged by default).
;;;   2. Verifies that /run/current-system exists (Guix system booted).
;;;   3. Runs `guix --version` inside the container.
;;;   4. Attempts a basic package description lookup.
;;;   5. Waits for guix-daemon to start (up to 30 s).
;;;   6. Builds the GNU hello package.
;;;   7. Stops and removes the test container.

(use-modules (ice-9 format)
             (ice-9 getopt-long)
             (ice-9 popen)
             (ice-9 rdelim))

;;; ---------------------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------------------

(define (run-command/check desc . args)
  "Run a shell command silently, print DESC with PASS/FAIL, return #t on success."
  (let* ((cmd (string-append (string-join args " ") " >/dev/null 2>&1"))
         (ret (system cmd)))
    (if (zero? (status:exit-val ret))
        (begin (format #t "  [PASS] ~a~%" desc) #t)
        (begin (format #t "  [FAIL] ~a (exit ~a)~%" desc (status:exit-val ret)) #f))))

(define (container-exec container . cmd-args)
  "Build a 'docker exec' command string for CONTAINER running CMD-ARGS."
  (string-append
   "docker exec " container " "
   (string-join cmd-args " ")))

;;; ---------------------------------------------------------------------------
;;; Main
;;; ---------------------------------------------------------------------------

(define option-spec
  '((image         (single-char #\i) (value #t))
    (no-privileged (value #f))
    (help          (single-char #\h) (value #f))))

(define (main args)
  (let* ((options    (getopt-long args option-spec))
         (help?      (option-ref options 'help #f))
         (privileged (not (option-ref options 'no-privileged #f)))
         (image      (option-ref options 'image "guix-dev:latest"))
         (cname      "guix-dev-test"))

    (when help?
      (display "Usage: guile .github/docker/test-image.scm [OPTIONS]\n")
      (display "  -i, --image IMAGE    Docker image to test\n")
      (display "      --no-privileged  Skip --privileged flag\n")
      (display "  -h, --help           Show this help\n")
      (exit 0))

    (format #t "==> Testing image: ~a~%" image)

    ;; Clean up any pre-existing test container with the same name.
    (system (string-append "docker rm -f " cname " 2>/dev/null || true"))

    ;; Create container.
    (let* ((priv-flag (if privileged "--privileged" ""))
           (create-cmd (string-append
                        "docker create --name " cname " "
                        priv-flag " "
                        image)))
      (format #t "==> Creating container ~a~%" cname)
      (unless (zero? (system (string-append create-cmd " >/dev/null")))
        (error "Failed to create container")))

    ;; Start container.
    (format #t "==> Starting container~%")
    (unless (zero? (system (string-append "docker start " cname " >/dev/null")))
      (error "Failed to start container"))

    ;; Poll until guix-daemon is started (up to 30 s), then run tests.
    ;; Without --privileged, guix-daemon cannot create build sandboxes and
    ;; will stay stopped; in that case the build test will fail as expected.
    (format #t "==> Waiting for guix-daemon...~%")
    (let wait-loop ((remaining 30))
      (cond
       ((zero? remaining)
        (format #t "  [WARN] guix-daemon did not start within 30 s; build test may fail~%"))
       ((zero? (system
                (string-append
                 "docker exec " cname
                 " /run/current-system/profile/bin/herd"
                 " status guix-daemon 2>&1 | grep -q started")))
        (format #t "  [OK] guix-daemon is running~%"))
       (else
        (sleep 1)
        (wait-loop (- remaining 1)))))

    ;; Run tests.
    (let ((results
           (list
            (run-command/check
             "Guix system root exists"
             (container-exec cname
              "/run/current-system/profile/bin/test" "-d" "/run/current-system"))

            (run-command/check
             "guix --version"
             (container-exec cname
              "/run/current-system/profile/bin/guix" "--version"))

            (run-command/check
             "guix package description lookup (hello)"
             (container-exec cname
              "/run/current-system/profile/bin/guix" "show" "hello"))

            (run-command/check
             "guix build hello"
             (container-exec cname
              "/run/current-system/profile/bin/guix" "build" "hello")))))

      ;; Cleanup.
      (format #t "==> Stopping and removing container~%")
      (system (string-append "docker stop " cname " >/dev/null"))
      (system (string-append "docker rm " cname " >/dev/null"))

      ;; Summary.
      (let ((pass (length (filter identity results)))
            (total (length results)))
        (format #t "~%==> Results: ~a/~a tests passed~%" pass total)
        (unless (= pass total)
          (exit 1))))))

(main (command-line))
