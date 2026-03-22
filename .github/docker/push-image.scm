#!/usr/bin/env -S guile --no-auto-compile
!#
;;; push-image.scm — Tag and push the Guix dev Docker image to GHCR.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Usage:
;;;
;;;   guile .github/docker/push-image.scm [OPTIONS]
;;;
;;; Options:
;;;   -i, --image IMAGE   Local image to push (default: guix-dev:latest)
;;;   -t, --tag TAG       Remote tag to push as
;;;                       (default: ghcr.io/kromka-chleba/guix-dev:latest)
;;;       --sha SHA       Also push as :SHA tag (e.g. a git commit SHA)
;;;   -h, --help          Show this help
;;;
;;; Docker credentials are read from ~/.docker/config.json as managed by
;;; `docker login`.  No manual token handling is required.

(use-modules (ice-9 getopt-long))

(include "docker-lib.scm")

(define option-spec
  '((image (single-char #\i) (value #t))
    (tag   (single-char #\t) (value #t))
    (sha                     (value #t))
    (help  (single-char #\h) (value #f))))

(define (main args)
  (let* ((options    (getopt-long args option-spec))
         (help?      (option-ref options 'help #f))
         (image      (option-ref options 'image %default-image))
         (remote-tag (option-ref options 'tag   (string-append %ghcr-image ":latest")))
         (sha        (option-ref options 'sha   #f)))

    (when help?
      (display "Usage: guile .github/docker/push-image.scm [OPTIONS]\n")
      (display "  -i, --image IMAGE  Local image (default: guix-dev:latest)\n")
      (display "  -t, --tag TAG      Remote tag (default: ghcr.io/.../guix-dev:latest)\n")
      (display "      --sha SHA      Also push as :SHA tag\n")
      (display "  -h, --help         Show this help\n")
      (exit 0))

    ;; Retag the local image as the remote tag when they differ.
    (unless (equal? image remote-tag)
      (format #t "==> Tagging ~a as ~a~%" image remote-tag)
      (run-command "docker" "tag" image remote-tag))

    ;; Push :latest (or whatever remote-tag resolves to).
    (format #t "==> Pushing ~a~%" remote-tag)
    (run-command "docker" "push" remote-tag)

    ;; Optionally push as an additional :SHA tag.
    (when sha
      (let ((sha-tag (string-append %ghcr-image ":" sha)))
        (format #t "==> Tagging ~a as ~a~%" remote-tag sha-tag)
        (run-command "docker" "tag" remote-tag sha-tag)
        (format #t "==> Pushing ~a~%" sha-tag)
        (run-command "docker" "push" sha-tag)))

    (format #t "==> Done.~%")))

(main (command-line))
