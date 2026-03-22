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

(use-modules (ice-9 getopt-long))

(include "docker-lib.scm")

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
         (image      (option-ref options 'image %default-image))
         (cname      "guix-dev-test"))

    (when help?
      (display "Usage: guile .github/docker/test-image.scm [OPTIONS]\n")
      (display "  -i, --image IMAGE    Docker image to test\n")
      (display "      --no-privileged  Skip --privileged flag\n")
      (display "  -h, --help           Show this help\n")
      (exit 0))

    (format #t "==> Testing image: ~a~%" image)

    ;; Clean up any pre-existing test container with the same name.
    (docker-stop+rm cname)

    ;; Create and start the container.
    (format #t "==> Creating container ~a~%" cname)
    (docker-create image cname #:privileged? privileged)
    (format #t "==> Starting container~%")
    (docker-start cname)

    (wait-for-daemon cname)

    ;; Run tests.
    (let ((results
           (list
            (run-command/check
             "Guix system root exists"
             (container-exec cname
              (string-append %system-profile "/test") "-d" "/run/current-system"))

            (run-command/check
             "guix --version"
             (container-exec cname
              (string-append %system-profile "/guix") "--version"))

            (run-command/check
             "guix package description lookup (hello)"
             (container-exec cname
              (string-append %system-profile "/guix") "show" "hello"))

            (run-command/check
             "guix build hello"
             (container-exec cname
              (string-append %system-profile "/guix") "build" "hello")))))

      ;; Cleanup.
      (format #t "==> Stopping and removing container~%")
      (docker-stop+rm cname)

      ;; Summary.
      (let ((pass  (length (filter identity results)))
            (total (length results)))
        (format #t "~%==> Results: ~a/~a tests passed~%" pass total)
        (unless (= pass total)
          (exit 1))))))

(main (command-line))
