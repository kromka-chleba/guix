#!/usr/bin/env -S guile --no-auto-compile
!#
;;; test-reproducibility.scm — Verify that the two Guix Docker image build
;;;                            paths produce bit-for-bit identical output.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Two code paths exist for building the Guix dev Docker image:
;;;
;;;   1. Bootstrap path  (build-image.scm)
;;;      Intended for first-time / recovery use when no Docker bootstrap image
;;;      is available yet.  A developer with a native Guix installation runs:
;;;
;;;        ./pre-inst-env guile .github/docker/build-image.scm
;;;
;;;      In CI (where the runner does not have Guix installed natively) this
;;;      is simulated by exec-ing directly into the bootstrap container and
;;;      calling build-image.scm from there, without the extra
;;;      `guix shell -D guix` wrapper.
;;;
;;;   2. Container-rebuild path  (build-image-in-docker.scm)
;;;      The steady-state CI path.  build-image-in-docker.scm orchestrates
;;;      the full container lifecycle (create → start → wait-for-daemon →
;;;      `guix shell -D guix` → build-image.scm → stop/rm).
;;;
;;; Both paths ultimately call `./pre-inst-env guile build-image.scm`, which
;;; calls `guix system image --image-type=docker`.  Guix warrants that this
;;; command produces bit-for-bit identical output for the same inputs:
;;;
;;;   * All archive timestamps are normalised to SOURCE_DATE_EPOCH (1970-01-01).
;;;   * Archive entries are sorted deterministically.
;;;   * The Docker image manifest contains no host-specific metadata.
;;;
;;; PREREQUISITES
;;;
;;;   The host checkout must already be configured and built before running
;;;   this test.  Run the following on the host (not inside any container):
;;;
;;;     ./bootstrap
;;;     ./configure --localstatedir=/var
;;;     make
;;;
;;;   Running these inside the container (as root) would leave root-owned files
;;;   in the bind-mounted workspace, breaking subsequent host `make` runs.
;;;
;;; This test builds the image once via each path and compares SHA-256 hashes.
;;; A mismatch signals a setup problem that breaks Guix's reproducibility
;;; guarantee.
;;;
;;; Potential non-reproducibility sources to watch for:
;;;
;;;   1. The `%guix-dev-packages` list in guix-dev-system.scm is computed at
;;;      load time from `package-native-inputs`/`package-inputs`.  Both paths
;;;      use the same Guix checkout mounted at the same host path, so the list
;;;      is identical within a single test run.
;;;
;;;   2. Substitute availability: store paths are content-addressed, so it
;;;      does not matter whether a derivation is served from cache or built
;;;      locally — the resulting store path is identical.
;;;
;;;   3. gzip metadata: Guix sets SOURCE_DATE_EPOCH when producing archives,
;;;      so gzip headers are deterministic.
;;;
;;; Usage:
;;;
;;;   guile .github/docker/test-reproducibility.scm [OPTIONS]
;;;
;;; Options:
;;;   -b, --bootstrap-image IMAGE  Docker image to use as the build environment
;;;                                (default: ghcr.io/kromka-chleba/guix-dev:latest)
;;;   -c, --system-config PATH     Guix OS config file (relative to repo root)
;;;                                (default: .github/docker/guix-dev-system.scm)
;;;   -h, --help                   Show this help

(use-modules (ice-9 getopt-long))

(include "docker-lib.scm")

;;; ---------------------------------------------------------------------------
;;; Constants
;;; ---------------------------------------------------------------------------

;;; Seconds to wait for guix-daemon to start inside each build container.
(define %daemon-startup-timeout 120)

;;; ---------------------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------------------

(define (sha256sum path)
  "Return the hex SHA-256 digest of the file at PATH."
  (let* ((cmd  (string-append "sha256sum " path))
         (port (open-input-pipe cmd))
         (line (read-line port)))
    (close-pipe port)
    (if (eof-object? line)
        (error (format #f "sha256sum returned no output for ~a" path))
        ;; sha256sum output: "<digest>  <filename>"
        (car (string-split (string-trim-right line) #\space)))))

(define (build-bootstrap-path bootstrap-image system-config output-rel)
  "Bootstrap path: simulate running build-image.scm from a native Guix system.

In CI the bootstrap container plays the role of the native Guix host: we
exec directly into it and call build-image.scm without the extra
`guix shell -D guix` wrapper that build-image-in-docker.scm adds.  This
mirrors what a developer would do on a workstation where Guix is already
installed:

  ./pre-inst-env /run/current-system/profile/bin/guile .github/docker/build-image.scm ...

bootstrap/configure/make are NOT run inside the container.  They must have
been run on the host beforehand; running them inside the container (as root)
would leave root-owned files in the bind-mounted workspace."
  (let ((cname "repro-bootstrap-ctr"))
    (format #t "  [bootstrap path] container: ~a~%" cname)
    (system (string-append "docker rm -f " cname " >/dev/null 2>&1"))
    (docker-create bootstrap-image cname #:workspace %repo-root)
    (docker-start cname)
    (wait-for-daemon cname %daemon-startup-timeout)

    ;; Run build-image.scm directly — no `guix shell -D guix` wrapper.
    ;; The bootstrap container already has all Guix build-time deps in its
    ;; system profile, so pre-inst-env works without an extra shell wrapper.
    ;;
    ;; IMPORTANT: pass the guile binary as an absolute path rather than just
    ;; "guile".  pre-inst-env prepends $abs_top_builddir to PATH, so a bare
    ;; "guile" would resolve to the host-compiled guile binary in the builddir;
    ;; that binary links against host libraries (libgcc_s.so.1, etc.) that do
    ;; not exist at those paths inside the container.  Passing the absolute
    ;; path bypasses the PATH lookup entirely and uses the container's own
    ;; Guix-built guile.
    (let* ((container-guile (string-append %system-profile "/guile"))
           (inner-cmd
            (string-append
             "set -ex && "
             "./pre-inst-env " container-guile " .github/docker/build-image.scm"
             " --system-config '" system-config "'"
             " --output '" output-rel "'"
             " --no-load"))
           (exec-cmd
            (string-append
             "docker exec -w " %repo-root
             " -e PATH=" %system-profile
             " " cname
             " /bin/sh -c '" inner-cmd "'")))
      (unless (zero? (system exec-cmd))
        (docker-stop+rm cname)
        (error "Bootstrap-path build failed")))

    (docker-stop+rm cname)))

(define (build-container-path bootstrap-image system-config output-rel)
  "Container-rebuild path: invoke build-image-in-docker.scm.

This is the steady-state CI path.  build-image-in-docker.scm creates its
own temporary container, wraps the build in `guix shell -D guix`, calls
build-image.scm inside that shell, then cleans up."
  (let* ((script (string-append %repo-root
                                "/.github/docker/build-image-in-docker.scm"))
         (cmd    (string-append
                  "guile " script
                  " --bootstrap-image '" bootstrap-image "'"
                  " --container-name repro-container-ctr"
                  " --system-config '" system-config "'"
                  " --output '" output-rel "'"
                  " --no-load")))
    (format #t "  [container-rebuild path] invoking build-image-in-docker.scm~%")
    (unless (zero? (system cmd))
      (error "Container-rebuild-path build failed"))))

;;; ---------------------------------------------------------------------------
;;; Main
;;; ---------------------------------------------------------------------------

(define option-spec
  '((bootstrap-image (single-char #\b) (value #t))
    (system-config   (single-char #\c) (value #t))
    (help            (single-char #\h) (value #f))))

(define (main args)
  (let* ((options         (getopt-long args option-spec))
         (help?           (option-ref options 'help #f))
         (bootstrap-image (option-ref options 'bootstrap-image
                                       (string-append %ghcr-image ":latest")))
         (system-config   (option-ref options 'system-config
                                       ".github/docker/guix-dev-system.scm")))

    (when help?
      (display "Usage: guile .github/docker/test-reproducibility.scm [OPTIONS]\n")
      (display "\nBuilds the Docker image via both code paths and compares SHA-256 hashes.\n\n")
      (display "  Build 1: bootstrap path  (build-image.scm, simulating native Guix)\n")
      (display "  Build 2: container-rebuild path  (build-image-in-docker.scm)\n\n")
      (display "  -b, --bootstrap-image IMAGE  Bootstrap Docker image\n")
      (display "  -c, --system-config   PATH   Guix OS config (relative to repo root)\n")
      (display "  -h, --help                   Show this help\n")
      (exit 0))

    ;; Pre-flight: the host checkout must have been configured and built.
    ;; bootstrap/configure/make are intentionally NOT run inside the container
    ;; because doing so as root leaves root-owned files in the bind-mounted
    ;; workspace, which breaks subsequent host `make` runs.
    (unless (file-exists? (string-append %repo-root "/pre-inst-env"))
      (display "error: pre-inst-env not found.\n")
      (display "pre-inst-env is generated by ./configure and sets up Guile module\n")
      (display "paths so the Guix checkout is found inside the container.\n")
      (display "Please run the following on the host before running this test:\n")
      (display "  ./bootstrap && ./configure --localstatedir=/var && make\n")
      (exit 1))

    (format #t "==> Reproducibility test~%")
    (format #t "    Config:          ~a~%" system-config)
    (format #t "    Bootstrap image: ~a~%" bootstrap-image)
    (format #t "    Build 1: bootstrap path  (build-image.scm)~%")
    (format #t "    Build 2: container-rebuild path  (build-image-in-docker.scm)~%")

    (let ((out1 "repro-bootstrap.tar.gz")
          (out2 "repro-container.tar.gz"))

      ;; ------------------------------------------------------------------
      ;; Build 1 — bootstrap path (build-image.scm, native Guix simulation).
      ;; ------------------------------------------------------------------
      (format #t "~%==> Build 1/2  [bootstrap path]~%")
      (build-bootstrap-path bootstrap-image system-config out1)
      (format #t "    Written: ~a~%" out1)

      ;; ------------------------------------------------------------------
      ;; Build 2 — container-rebuild path (build-image-in-docker.scm).
      ;; ------------------------------------------------------------------
      (format #t "~%==> Build 2/2  [container-rebuild path]~%")
      (build-container-path bootstrap-image system-config out2)
      (format #t "    Written: ~a~%" out2)

      ;; ------------------------------------------------------------------
      ;; Compare digests.
      ;; ------------------------------------------------------------------
      (let ((hash1 (sha256sum (string-append %repo-root "/" out1)))
            (hash2 (sha256sum (string-append %repo-root "/" out2))))
        (format #t "~%==> Results~%")
        (format #t "    Bootstrap path SHA-256:         ~a~%" hash1)
        (format #t "    Container-rebuild path SHA-256: ~a~%" hash2)

        ;; Always remove the temporary tarballs.
        (system (string-append "rm -f "
                               %repo-root "/" out1 " "
                               %repo-root "/" out2))

        (if (string=? hash1 hash2)
            (begin
              (format #t "  [PASS] Both paths produce identical output.~%")
              (format #t "         Guix's reproducibility guarantee holds for this setup.~%"))
            (begin
              (format #t "  [FAIL] The two build paths produce DIFFERENT output (SHA-256 mismatch).~%")
              (format #t "~%")
              (format #t "  Possible causes:~%")
              (format #t "    - Non-determinism in `guix system image' output~%")
              (format #t "      (e.g. timestamps not normalised to SOURCE_DATE_EPOCH).~%")
              (format #t "    - `guix shell --no-grafts' vs grafts: the container-rebuild path~%")
              (format #t "      passes --no-grafts but the bootstrap path does not; a pending~%")
              (format #t "      graft could change store paths.~%")
              (format #t "    - Different Guix channels or revisions used by each path.~%")
              (format #t "    - The system config references time- or host-dependent values.~%")
              (format #t "~%")
              (format #t "  Next steps:~%")
              (format #t "    1. Unpack both tarballs and diff their contents:~%")
              (format #t "       tar xf repro-bootstrap.tar.gz -C /tmp/b1~%")
              (format #t "       tar xf repro-container.tar.gz -C /tmp/b2~%")
              (format #t "       diff -r /tmp/b1 /tmp/b2~%")
              (format #t "    2. Run `guix challenge PACKAGE' on suspect packages.~%")
              (format #t "    3. Check `guix describe' inside each container to confirm~%")
              (format #t "       both use the same channel revision.~%")
              (exit 1)))))))

(main (command-line))
