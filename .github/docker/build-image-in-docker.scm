#!/usr/bin/env -S guile --no-auto-compile
!#
;;; build-image-in-docker.scm — Build the Guix dev Docker image by running
;;;                             `guix system image` inside a bootstrap container.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Usage:
;;;
;;;   guile .github/docker/build-image-in-docker.scm [OPTIONS]
;;;
;;; This script launches a temporary bootstrap container from an existing Guix
;;; Docker image, prepares the repository build system inside it
;;; (./bootstrap && ./configure && make), then runs `build-image.scm` to
;;; produce a new image tarball, and optionally loads and tags the result.
;;; This is the normal steady-state build path used by CI and for local use.
;;;
;;; Use `build-image.scm` instead when bootstrapping from a native Guix
;;; installation (i.e., no Docker bootstrap image is available yet).
;;;
;;; Options:
;;;   -b, --bootstrap-image IMAGE  Docker image to use as the build environment
;;;                                (default: ghcr.io/kromka-chleba/guix-dev:latest)
;;;   -n, --container-name NAME    Name for the temporary build container
;;;                                (default: guix-dev-build)
;;;   -c, --system-config PATH     Guix OS config file (relative to repo root)
;;;                                (default: .github/docker/guix-dev-system.scm)
;;;   -o, --output PATH            Output tarball path (relative to repo root)
;;;                                (default: guix-system-docker-image.tar.gz)
;;;   -t, --tag TAG                Docker tag to apply after loading
;;;                                (default: guix-dev:latest)
;;;   --no-load                    Only build; do not load into Docker
;;;   -h, --help                   Show this help

(use-modules (ice-9 getopt-long))

(include "docker-lib.scm")

;;; ---------------------------------------------------------------------------
;;; Constants
;;; ---------------------------------------------------------------------------

;;; Seconds to wait for guix-daemon to start inside the bootstrap container.
(define %daemon-startup-timeout 120)

;;; Verbosity level passed to `guix shell` during dev-environment preparation.
(define %guix-shell-verbosity 2)

;;; ---------------------------------------------------------------------------
;;; Main
;;; ---------------------------------------------------------------------------

(define option-spec
  '((bootstrap-image (single-char #\b) (value #t))
    (container-name  (single-char #\n) (value #t))
    (system-config   (single-char #\c) (value #t))
    (output          (single-char #\o) (value #t))
    (tag             (single-char #\t) (value #t))
    (no-load         (value #f))
    (help            (single-char #\h) (value #f))))

(define (main args)
  (let* ((options         (getopt-long args option-spec))
         (help?           (option-ref options 'help #f))
         (no-load?        (option-ref options 'no-load #f))
         (bootstrap-image (option-ref options 'bootstrap-image
                                       (string-append %ghcr-image ":latest")))
         (container-name  (option-ref options 'container-name "guix-dev-build"))
         (system-config   (option-ref options 'system-config
                                       ".github/docker/guix-dev-system.scm"))
         (output          (option-ref options 'output
                                       "guix-system-docker-image.tar.gz"))
         (tag             (option-ref options 'tag %default-image))
         ;; Absolute path to the tarball on the host.  The output path is
         ;; relative to the repo root, which is mounted as /workspace inside
         ;; the container.
         (host-tarball    (string-append %repo-root "/" output)))

    (when help?
      (display "Usage: guile .github/docker/build-image-in-docker.scm [OPTIONS]\n")
      (display "  -b, --bootstrap-image IMAGE  Bootstrap Docker image\n")
      (display "  -n, --container-name  NAME   Build container name\n")
      (display "  -c, --system-config   PATH   Guix OS config (relative to repo root)\n")
      (display "  -o, --output          PATH   Output tarball (relative to repo root)\n")
      (display "  -t, --tag             TAG    Docker tag (default: guix-dev:latest)\n")
      (display "      --no-load                Skip loading into Docker\n")
      (display "  -h, --help                   Show this help\n")
      (exit 0))

    ;; Remove any leftover container with the same name.
    (system (string-append "docker rm -f " container-name " >/dev/null 2>&1"))

    (format #t "==> Starting bootstrap container ~a from ~a~%"
            container-name bootstrap-image)
    (docker-create bootstrap-image container-name #:workspace %repo-root)
    (docker-start container-name)
    ;; Use a generous timeout to allow the Guix system to fully boot.
    (wait-for-daemon container-name %daemon-startup-timeout)

    (format #t "==> Preparing dev environment inside container ~a~%" container-name)
    (let ((prep-cmd
           (string-append
            "export PATH=" %system-profile ":$PATH && "
            "set -ex && "
            "guix shell --verbosity=" (number->string %guix-shell-verbosity) " --no-grafts -D guix -- sh -c \""
            "set -ex && "
            "./bootstrap && "
            "./configure --localstatedir=/var && "
            "make V=1\"")))
      (unless (zero? (system (string-append
                              "docker exec -w /workspace " container-name
                              " /bin/sh -c '" prep-cmd "'")))
        (docker-stop+rm container-name)
        (error "Dev-environment preparation failed inside bootstrap container")))

    (format #t "==> Building Guix Docker image inside container ~a~%" container-name)
    (let* ((build-cmd
            (string-append
             "export PATH=" %system-profile ":$PATH && "
             "set -ex && "
             "./pre-inst-env guile .github/docker/build-image.scm"
             " --system-config " system-config
             " --output " output
             " --no-load"))
           (exec-cmd
            (string-append
             "docker exec -w /workspace " container-name
             " /bin/sh -c '" build-cmd "'")))
      (unless (zero? (system exec-cmd))
        (docker-stop+rm container-name)
        (error "Build failed inside bootstrap container")))

    (docker-stop+rm container-name)

    (format #t "==> Image tarball written to ~a~%" host-tarball)

    (unless no-load?
      (format #t "==> Loading image into Docker and tagging as ~a~%" tag)
      (let* ((load-out  (read-command-output "docker" "load" "<" host-tarball))
             ;; docker load prints "Loaded image ID: sha256:..." or
             ;; "Loaded image: name:tag" — extract the last word.
             (words     (string-split load-out #\space))
             (image-id  (string-trim-right (list-ref words (1- (length words))))))
        (format #t "    Loaded image: ~a (retagging as ~a)~%" image-id tag)
        (run-command "docker" "tag" image-id tag)
        (format #t "==> Tagged as ~a~%" tag)
        ;; Remove the original embedded tag when it differs from the
        ;; requested one, so "docker images" shows only the desired name.
        (unless (equal? image-id tag)
          (run-command "docker" "rmi" image-id)
          (format #t "==> Removed embedded tag ~a~%" image-id))))

    (format #t "==> Done.~%")))

(main (command-line))
