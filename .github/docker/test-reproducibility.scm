#!/usr/bin/env -S guile --no-auto-compile
!#
;;; test-reproducibility.scm — Verify that Guix Docker image builds are
;;;                            reproducible.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Builds the same Guix Docker image TWICE using the same bootstrap container
;;; and system configuration, then compares the SHA-256 digests of the two
;;; resulting tarballs.  Reproducibility is one of Guix's core guarantees;
;;; this test verifies that our Docker build setup honours it.
;;;
;;; Why this matters
;;; ----------------
;;; `guix system image --image-type=docker` is a pure, content-addressed
;;; build.  Given the same system configuration and the same Guix channel
;;; revision, it should always produce bit-for-bit identical output:
;;;
;;;   * All timestamps in the generated archive are normalised to
;;;     SOURCE_DATE_EPOCH (1970-01-01).
;;;   * Archive entries are sorted deterministically.
;;;   * The Docker image manifest contains no host-specific metadata.
;;;
;;; Potential non-reproducibility sources to watch for:
;;;
;;;   1. The `%guix-dev-packages` list in guix-dev-system.scm is computed
;;;      at load time from `package-native-inputs`/`package-inputs`.  If the
;;;      Guix checkout changes between runs these lists diverge; but within a
;;;      single workflow run they are identical.
;;;
;;;   2. `guix shell --no-grafts` prevents graft application divergence
;;;      between the two builds; both builds use the same flag.
;;;
;;;   3. Substitute availability: as long as the content-addressed store path
;;;      for a derivation is the same, it does not matter whether a build is
;;;      served from cache or built locally.
;;;
;;;   4. gzip metadata: Guix sets SOURCE_DATE_EPOCH when producing archives,
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

;;; Verbosity level passed to `guix shell` during dev-environment preparation.
(define %guix-shell-verbosity 2)

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

(define (build-once bootstrap-image system-config container-name output-rel)
  "Run one build of SYSTEM-CONFIG inside BOOTSTRAP-IMAGE.
The tarball is written to OUTPUT-REL (a path relative to the repo root).
Signals an error if the build fails."
  (format #t "  Starting container ~a from ~a~%" container-name bootstrap-image)
  ;; Remove any leftover container with the same name.
  (system (string-append "docker rm -f " container-name " >/dev/null 2>&1"))
  (docker-create bootstrap-image container-name #:workspace %repo-root)
  (docker-start container-name)
  (wait-for-daemon container-name %daemon-startup-timeout)

  (let* ((inner-cmd
          ;; Commands run inside `guix shell -D guix`:
          ;;   1. Regenerate pre-inst-env with /workspace paths.
          ;;   2. Run build-image.scm → `guix system image`.
          (string-append
           "set -ex && "
           "./bootstrap && "
           "./configure --localstatedir=/var && "
           "make V=1 && "
           "./pre-inst-env guile .github/docker/build-image.scm"
           " --system-config '" system-config "'"
           " --output '" output-rel "'"
           " --no-load"))
         (shell-cmd
          (string-append
           "export PATH=" %system-profile ":$PATH && "
           "set -ex && "
           "guix shell --verbosity=" (number->string %guix-shell-verbosity)
           " --no-grafts -D guix -- sh -c \"" inner-cmd "\""))
         (exec-cmd
          (string-append
           "docker exec -w /workspace " container-name
           " /bin/sh -c '" shell-cmd "'")))
    (unless (zero? (system exec-cmd))
      (docker-stop+rm container-name)
      (error (format #f "Build failed inside container ~a" container-name))))

  (docker-stop+rm container-name))

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
      (display "\nBuilds the same Docker image twice and compares SHA-256 hashes.\n\n")
      (display "  -b, --bootstrap-image IMAGE  Bootstrap Docker image\n")
      (display "  -c, --system-config   PATH   Guix OS config (relative to repo root)\n")
      (display "  -h, --help                   Show this help\n")
      (exit 0))

    (format #t "==> Reproducibility test~%")
    (format #t "    Config:          ~a~%" system-config)
    (format #t "    Bootstrap image: ~a~%" bootstrap-image)

    (let ((out1 "repro-build-1.tar.gz")
          (out2 "repro-build-2.tar.gz"))

      ;; ------------------------------------------------------------------
      ;; Build #1
      ;; ------------------------------------------------------------------
      (format #t "~%==> Build 1/2~%")
      (build-once bootstrap-image system-config "repro-build-ctr-1" out1)
      (format #t "    Written: ~a~%" out1)

      ;; ------------------------------------------------------------------
      ;; Build #2 — same bootstrap image and config; result must be identical.
      ;; ------------------------------------------------------------------
      (format #t "~%==> Build 2/2~%")
      (build-once bootstrap-image system-config "repro-build-ctr-2" out2)
      (format #t "    Written: ~a~%" out2)

      ;; ------------------------------------------------------------------
      ;; Compare digests.
      ;; ------------------------------------------------------------------
      (let ((hash1 (sha256sum (string-append %repo-root "/" out1)))
            (hash2 (sha256sum (string-append %repo-root "/" out2))))
        (format #t "~%==> Results~%")
        (format #t "    Build 1 SHA-256: ~a~%" hash1)
        (format #t "    Build 2 SHA-256: ~a~%" hash2)

        ;; Always remove the temporary tarballs.
        (system (string-append "rm -f "
                               %repo-root "/" out1 " "
                               %repo-root "/" out2))

        (if (string=? hash1 hash2)
            (begin
              (format #t "  [PASS] Builds are reproducible (identical SHA-256).~%")
              (format #t "         Guix's reproducibility guarantee holds for this setup.~%"))
            (begin
              (format #t "  [FAIL] Builds are NOT reproducible (SHA-256 mismatch).~%")
              (format #t "~%")
              (format #t "  Possible causes:~%")
              (format #t "    - Non-determinism in `guix system image' output~%")
              (format #t "      (e.g. embedded timestamps not normalised to SOURCE_DATE_EPOCH).~%")
              (format #t "    - The system config references time- or host-dependent values.~%")
              (format #t "    - Different substitutes were used (store paths should still match~%")
              (format #t "      if the derivation is identical — investigate with~%")
              (format #t "      `guix gc --list-dead' and `guix challenge').~%")
              (format #t "~%")
              (format #t "  Next steps:~%")
              (format #t "    1. Re-run with --verbose to inspect build output.~%")
              (format #t "    2. Unpack both tarballs and diff their contents.~%")
              (format #t "    3. Run `guix challenge PACKAGE' on suspect packages.~%")
              (exit 1)))))))

(main (command-line))
