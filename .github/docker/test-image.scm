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
;;;   --image IMAGE   Docker image name/tag to test (default: guix-dev:latest)
;;;   --privileged    Run the test container with --privileged (required for
;;;                   building software with Guix inside the container)
;;;   --help          Show this help message
;;;
;;; The script:
;;;   1. Creates and starts a container from IMAGE.
;;;   2. Verifies that /run/current-system exists (Guix system booted).
;;;   3. Runs `guix --version` inside the container.
;;;   4. Attempts a basic package description lookup.
;;;   5. Builds the GNU hello package (requires --privileged).
;;;   6. Stops and removes the test container.

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
  '((image      (single-char #\i) (value #t))
    (privileged (value #f))
    (help       (single-char #\h) (value #f))))

(define (main args)
  (let* ((options    (getopt-long args option-spec))
         (help?      (option-ref options 'help #f))
         (privileged (option-ref options 'privileged #f))
         (image      (option-ref options 'image "guix-dev:latest"))
         (cname      "guix-dev-test"))

    (when help?
      (display "Usage: guile .github/docker/test-image.scm [OPTIONS]\n")
      (display "  -i, --image IMAGE   Docker image to test\n")
      (display "      --privileged    Use --privileged flag\n")
      (display "  -h, --help          Show this help\n")
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

    ;; Allow a moment for Shepherd/init to settle.
    (sleep 3)

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
