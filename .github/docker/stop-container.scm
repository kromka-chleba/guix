#!/usr/bin/env -S guile --no-auto-compile
!#
;;; stop-container.scm — Stop and remove a guix-dev Docker container.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Usage:
;;;
;;;   guile .github/docker/stop-container.scm [OPTIONS]
;;;
;;; Options:
;;;   -n, --name NAME   Container name (default: guix-dev)
;;;   -h, --help        Show this help

(use-modules (ice-9 format)
             (ice-9 getopt-long))

(include "docker-lib.scm")

(define option-spec
  '((name (single-char #\n) (value #t))
    (help (single-char #\h) (value #f))))

(define (main args)
  (let* ((options (getopt-long args option-spec))
         (help?   (option-ref options 'help #f))
         (name    (option-ref options 'name %default-container-name)))

    (when help?
      (display "Usage: guile .github/docker/stop-container.scm [OPTIONS]\n")
      (display "  -n, --name NAME  Container name (default: guix-dev)\n")
      (display "  -h, --help       Show this help\n")
      (exit 0))

    (format #t "==> Stopping container '~a'~%" name)
    (run-command "docker" "stop" name)
    (format #t "==> Removing container '~a'~%" name)
    (run-command "docker" "rm" name)
    (format #t "==> Done.~%")))

(main (command-line))
