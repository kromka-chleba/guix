#!/usr/bin/env -S guile --no-auto-compile
!#
;;; build-image.scm — Build and tag the Guix dev Docker image.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Usage (from the repository root, using pre-inst-env):
;;;
;;;   ./pre-inst-env guile .github/docker/build-image.scm [OPTIONS]
;;;
;;; Options:
;;;   --system-config PATH   Path to the Guix OS config (default:
;;;                          .github/docker/guix-dev-system.scm)
;;;   --output PATH          Where to write the image tarball
;;;                          (default: guix-system-docker-image.tar.gz)
;;;   --tag TAG              Docker tag to apply after loading
;;;                          (default: guix-dev:latest)
;;;   --no-load              Only build; do not load into Docker
;;;
;;; See "22.4 Running Guix Before It Is Installed" in the Guix manual for
;;; the ./pre-inst-env requirement.

(use-modules (ice-9 format)
             (ice-9 getopt-long)
             (ice-9 popen)
             (ice-9 rdelim))

;;; ---------------------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------------------

(define (run-command . args)
  "Run a shell command given as a list of strings.  Signal an error on
non-zero exit status."
  (let* ((cmd (string-join args " "))
         (ret (system cmd)))
    (unless (zero? (status:exit-val ret))
      (error (format #f "Command failed (exit ~a): ~a"
                     (status:exit-val ret) cmd)))))

(define (read-command-output . args)
  "Return the last non-empty trimmed line of stdout produced by running ARGS
as a shell command.  All lines are drained before closing the pipe to avoid
sending SIGPIPE to the child process.  Signals an error if the command exits
non-zero."
  (let* ((cmd    (string-join args " "))
         (port   (open-input-pipe cmd))
         ;; Collect every line; keep the last non-empty one.
         (last   (let loop ((last ""))
                   (let ((line (read-line port)))
                     (if (eof-object? line)
                         last
                         (loop (if (string-null? (string-trim-right line))
                                   last
                                   (string-trim-right line)))))))
         (ret    (close-pipe port)))
    (unless (zero? (status:exit-val ret))
      (error (format #f "Command failed (exit ~a): ~a"
                     (status:exit-val ret) cmd)))
    last))

;;; ---------------------------------------------------------------------------
;;; Main
;;; ---------------------------------------------------------------------------

(define option-spec
  '((system-config (single-char #\c) (value #t))
    (output        (single-char #\o) (value #t))
    (tag           (single-char #\t) (value #t))
    (no-load       (value #f))
    (help          (single-char #\h) (value #f))))

(define (main args)
  (let* ((options       (getopt-long args option-spec))
         (help?         (option-ref options 'help #f))
         (no-load?      (option-ref options 'no-load #f))
         (system-config (option-ref options 'system-config
                                    ".github/docker/guix-dev-system.scm"))
         (output        (option-ref options 'output
                                    "guix-system-docker-image.tar.gz"))
         (tag           (option-ref options 'tag "guix-dev:latest")))

    (when help?
      (display "Usage: ./pre-inst-env guile .github/docker/build-image.scm [OPTIONS]\n")
      (display "  -c, --system-config PATH  Guix OS config file\n")
      (display "  -o, --output PATH         Output tarball path\n")
      (display "  -t, --tag TAG             Docker tag (default: guix-dev:latest)\n")
      (display "      --no-load             Skip loading into Docker\n")
      (display "  -h, --help                Show this help\n")
      (exit 0))

    (format #t "==> Building Guix Docker image from ~a~%" system-config)
    ;; 'guix system image' prints the store path of the result to stdout.
    ;; Capture it, then copy the actual image file to the requested output path.
    (let ((store-path (read-command-output
                       "./pre-inst-env" "guix" "system" "image"
                       "--image-type=docker"
                       "--system=x86_64-linux"
                       system-config)))
      (run-command "cp" store-path output))

    (format #t "==> Image tarball written to ~a~%" output)

    (unless no-load?
      (format #t "==> Loading image into Docker and tagging as ~a~%" tag)
      (let* ((load-out (read-command-output "docker" "load" "<" output))
             ;; docker load prints e.g. "Loaded image ID: sha256:..." or
             ;; "Loaded image: name:tag" — extract the last whitespace-delimited word.
             (words    (string-split load-out #\space))
             (image-id (string-trim-right
                        (list-ref words (1- (length words))))))
        ;; The Guix docker image builder hardcodes the repository name as
        ;; "guix" in the tarball, so image-id may be "guix:latest".  We
        ;; immediately retag it to the user-specified tag and then remove
        ;; the embedded name so that only the desired tag remains.
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
