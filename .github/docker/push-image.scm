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
;;;   -i, --image IMAGE       Local image to push (default: guix-dev:latest)
;;;   -t, --tag TAG           Remote tag to push as
;;;                           (default: ghcr.io/kromka-chleba/guix-dev:latest)
;;;   -u, --username USER     GHCR username (default: kromka-chleba)
;;;   -f, --token-file FILE   File containing the GHCR personal access token
;;;                           (default: ~/.github-token)
;;;       --sha SHA           Also push as :SHA tag (e.g. a git commit SHA)
;;;   -h, --help              Show this help
;;;
;;; Token setup (one-time):
;;;
;;;   Create a GitHub personal access token (classic) with write:packages
;;;   scope and save it to ~/.github-token:
;;;
;;;     echo "ghp_YourTokenHere" > ~/.github-token
;;;     chmod 600 ~/.github-token

(use-modules (ice-9 format)
             (ice-9 getopt-long))

(define %here (dirname (canonicalize-path (car (command-line)))))
(load (string-append %here "/docker-lib.scm"))

(define option-spec
  '((image      (single-char #\i) (value #t))
    (tag        (single-char #\t) (value #t))
    (username   (single-char #\u) (value #t))
    (token-file (single-char #\f) (value #t))
    (sha                          (value #t))
    (help       (single-char #\h) (value #f))))

(define (main args)
  (let* ((options    (getopt-long args option-spec))
         (help?      (option-ref options 'help #f))
         (image      (option-ref options 'image      %default-image))
         (remote-tag (option-ref options 'tag        (string-append %ghcr-image ":latest")))
         (username   (option-ref options 'username   "kromka-chleba"))
         (token-file (option-ref options 'token-file %default-token-file))
         (sha        (option-ref options 'sha        #f)))

    (when help?
      (display "Usage: guile .github/docker/push-image.scm [OPTIONS]\n")
      (display "  -i, --image IMAGE       Local image (default: guix-dev:latest)\n")
      (display "  -t, --tag TAG           Remote tag (default: ghcr.io/.../guix-dev:latest)\n")
      (display "  -u, --username USER     GHCR username (default: kromka-chleba)\n")
      (display "  -f, --token-file FILE   Token file (default: ~/.github-token)\n")
      (display "      --sha SHA           Also push as :SHA tag\n")
      (display "  -h, --help              Show this help\n")
      (exit 0))

    ;; Read the GHCR personal access token from file.
    (unless (file-exists? token-file)
      (format (current-error-port)
              "error: token file not found: ~a~%~
Create it with:~%~
  echo 'ghp_...' > ~a~%~
  chmod 600 ~a~%"
              token-file token-file token-file)
      (exit 1))
    (let ((token (read-file-trimmed token-file)))

      ;; Log in to the registry by piping the token directly to docker login,
      ;; avoiding any shell expansion of the token value.
      (format #t "==> Logging in to ~a as ~a~%" %ghcr-registry username)
      (pipe-to-command token
                       "docker" "login" %ghcr-registry
                       "-u" username "--password-stdin"))

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
