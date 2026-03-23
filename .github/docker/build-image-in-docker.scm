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
;;; Docker image and runs `./pre-inst-env guile build-image.scm` inside it to
;;; produce a new image tarball.  It optionally loads and tags the result.
;;; This is the normal steady-state build path used by CI and for local use.
;;;
;;; PREREQUISITES
;;;
;;;   The host checkout must already be configured and built before invoking
;;;   this script.  Run the following on the host (not inside any container):
;;;
;;;     ./bootstrap
;;;     ./configure --localstatedir=/var
;;;     make
;;;
;;;   These steps must be run on the host because running them inside the
;;;   container (as root) would leave root-owned files in the bind-mounted
;;;   workspace, which breaks subsequent host `make` runs.  Only guix commands
;;;   are invoked via `./pre-inst-env` inside the container.
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
         ;; relative to the repo root, which is mounted at the same absolute
         ;; path inside the container.
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

    ;; Pre-flight: require that the developer has already run
    ;; ./bootstrap && ./configure && make on the host.  Running them inside
    ;; the container (as root) would leave root-owned files in the
    ;; bind-mounted workspace, breaking subsequent host `make` runs.
    (unless (file-exists? (string-append %repo-root "/pre-inst-env"))
      (display "error: pre-inst-env not found.\n")
      (display "pre-inst-env is generated by ./configure and sets up Guile module\n")
      (display "paths so the Guix checkout is found inside the container.\n")
      (display "Please run the following on the host before using this script:\n")
      (display "  ./bootstrap && ./configure --localstatedir=/var && make\n")
      (exit 1))

    ;; Remove any leftover container with the same name.
    (system (string-append "docker rm -f " container-name " >/dev/null 2>&1"))

    (format #t "==> Starting bootstrap container ~a from ~a~%"
            container-name bootstrap-image)
    (docker-create bootstrap-image container-name #:workspace %repo-root)
    (docker-start container-name)
    ;; Use a generous timeout to allow the Guix system to fully boot.
    (wait-for-daemon container-name %daemon-startup-timeout)

    ;; Both the dev-environment setup and the actual image build must run
    ;; inside `guix shell -D guix` so that ./pre-inst-env (and everything it
    ;; invokes) always has the correct Guix build-time dependencies on PATH.
    (format #t "==> Building Guix Docker image inside container ~a~%" container-name)
    (let* ((inner-cmd
            ;; Run build-image.scm via pre-inst-env.
            ;; bootstrap/configure/make are NOT run here — they must be run
            ;; on the host beforehand to avoid leaving root-owned files in the
            ;; bind-mounted workspace.
            ;;
            ;; IMPORTANT: pass the guile binary as an absolute path rather
            ;; than just "guile".  pre-inst-env prepends $abs_top_builddir to
            ;; PATH, so a bare "guile" would resolve to the host-compiled
            ;; guile binary in the builddir; that binary links against host
            ;; libraries (libgcc_s.so.1, etc.) that do not exist at those
            ;; paths inside the container.  Passing the absolute path bypasses
            ;; the PATH lookup entirely and uses the container's own
            ;; Guix-built guile.
            (string-append
             "set -ex && "
             "./pre-inst-env " %system-profile "/guile"
             " .github/docker/build-image.scm"
             " --system-config '" system-config "'"
             " --output '" output "'"
             " --no-load"))
           (shell-cmd
            (string-append
             "export PATH=" %system-profile ":$PATH && "
             "set -ex && "
             "guix shell --verbosity=" (number->string %guix-shell-verbosity)
             " --no-grafts -D guix -- sh -c \"" inner-cmd "\""))
           (exec-cmd
            (string-append
             "docker exec -w " %repo-root " " container-name
             " /bin/sh -c '" shell-cmd "'")))
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
