#!/usr/bin/env -S guile --no-auto-compile
!#
;;; start-container.scm — Start a guix-dev Docker container for local
;;; development and testing.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Usage:
;;;
;;;   guile .github/docker/start-container.scm [OPTIONS]
;;;
;;; Options:
;;;   -i, --image IMAGE   Docker image to use   (default: guix-dev:latest)
;;;   -n, --name  NAME    Container name         (default: guix-dev)
;;;   -h, --help          Show this help
;;;
;;; The container is started with --privileged (required for guix-daemon) and
;;; the repository checkout mounted at /workspace.

(use-modules (ice-9 format)
             (ice-9 getopt-long))

(include "docker-lib.scm")

(define option-spec
  '((image (single-char #\i) (value #t))
    (name  (single-char #\n) (value #t))
    (help  (single-char #\h) (value #f))))

(define (main args)
  (let* ((options (getopt-long args option-spec))
         (help?   (option-ref options 'help #f))
         (image   (option-ref options 'image %default-image))
         (name    (option-ref options 'name  %default-container-name)))

    (when help?
      (display "Usage: guile .github/docker/start-container.scm [OPTIONS]\n")
      (display "  -i, --image IMAGE  Docker image (default: guix-dev:latest)\n")
      (display "  -n, --name  NAME   Container name (default: guix-dev)\n")
      (display "  -h, --help         Show this help\n")
      (exit 0))

    ;; Remove any existing container with the same name.
    (docker-stop+rm name)

    (format #t "==> Creating container '~a' from '~a'~%" name image)
    (docker-create image name #:workspace %repo-root)
    (format #t "==> Starting container~%")
    (docker-start name)

    (format #t "==> Container started: ~a~%" name)
    (format #t "    Connect:  docker exec -ti ~a ~a/bash --login~%"
            name %system-profile)
    (format #t "    Stop:     guile .github/docker/stop-container.scm --name ~a~%"
            name)))

(main (command-line))
