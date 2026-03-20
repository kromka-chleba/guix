#!/bin/sh
# -*- mode: scheme; -*-
exec guix repl -- "$0" "$@"
!#
;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Guix Contributors
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;;
;;; Build a Guix system Docker image for Guix development.
;;;
;;; Usage:
;;;
;;;   .github/bin/build-guix-docker.scm [OPTIONS]
;;;
;;; Options:
;;;   --image-tag=TAG         Docker image tag (default: guix-dev:latest)
;;;   --registry=REGISTRY     Registry prefix, e.g. ghcr.io/your-org
;;;   --config=PATH           Path to Guix system config
;;;                           (default: .github/guix-dev-docker.scm)
;;;   --guix-flag=FLAG        Extra flag for 'guix system image' (repeatable)
;;;   -h, --help              Show this help and exit
;;;
;;; Prerequisites:
;;;   * GNU Guix installed and on PATH
;;;   * Docker (or Podman) installed and daemon accessible
;;;   * Sufficient disk space for the store and resulting image
;;;
;;; Example:
;;;
;;;   .github/bin/build-guix-docker.scm --registry=ghcr.io/my-org --image-tag=guix-dev:latest

;;; Code:

(use-modules (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 format)
             (ice-9 match)
             (srfi srfi-1))

(define (show-help)
  (format #t "Usage: .github/bin/build-guix-docker.scm [OPTIONS]~%")
  (format #t "~%")
  (format #t "Build a Guix system Docker image for Guix development.~%")
  (format #t "~%")
  (format #t "Options:~%")
  (format #t "  --image-tag=TAG         Docker image tag (default: guix-dev:latest)~%")
  (format #t "  --registry=REGISTRY     Registry prefix, e.g. ghcr.io/your-org~%")
  (format #t "  --config=PATH           Path to Guix system config~%")
  (format #t "                          (default: .github/guix-dev-docker.scm)~%")
  (format #t "  --guix-flag=FLAG        Extra flag for 'guix system image' (repeatable)~%")
  (format #t "  -h, --help              Show this help and exit~%"))

(define (flag-value flag-name arg)
  "If ARG is \"--FLAG-NAME=VALUE\", return \"VALUE\", else #f."
  (let ((prefix (string-append "--" flag-name "=")))
    (and (string-prefix? prefix arg)
         (substring arg (string-length prefix)))))

(define (parse-args args)
  "Parse ARGS (excluding the script name) and return an alist of options."
  (let loop ((args args)
             (image-tag "guix-dev:latest")
             (registry "")
             (config ".github/guix-dev-docker.scm")
             (guix-flags '()))
    (match args
      (()
       `((image-tag  . ,image-tag)
         (registry   . ,registry)
         (config     . ,config)
         (guix-flags . ,(reverse guix-flags))))
      (((or "-h" "--help") . _)
       (show-help)
       (exit 0))
      ((arg . rest)
       (cond
        ((flag-value "image-tag" arg)
         => (lambda (v) (loop rest v registry config guix-flags)))
        ((flag-value "registry" arg)
         => (lambda (v) (loop rest image-tag v config guix-flags)))
        ((flag-value "config" arg)
         => (lambda (v) (loop rest image-tag registry v guix-flags)))
        ((flag-value "guix-flag" arg)
         => (lambda (v) (loop rest image-tag registry config (cons v guix-flags))))
        (else
         (format (current-error-port) "error: unknown option: ~a~%" arg)
         (format (current-error-port) "Try --help for usage information.~%")
         (exit 1)))))))

(define (command-on-path? cmd)
  "Return #t if CMD is found on PATH."
  (zero? (status:exit-val
          (system* "sh" "-c"
                   (string-append "command -v " cmd " >/dev/null 2>&1")))))

(define (run/capture . cmd)
  "Run CMD and return its stdout as a trimmed string.  Exit on failure."
  (let* ((port   (apply open-pipe* OPEN_READ cmd))
         (output (read-string port))
         (status (close-pipe port)))
    (if (zero? (status:exit-val status))
        (string-trim-right output #\newline)
        (begin
          (format (current-error-port) "ERROR: command failed: ~{~a~^ ~}~%" cmd)
          (exit 1)))))

(define (run/check . cmd)
  "Run CMD, let output stream to the terminal, and exit on failure."
  (let ((status (apply system* cmd)))
    (unless (zero? (status:exit-val status))
      (format (current-error-port) "ERROR: command failed: ~{~a~^ ~}~%" cmd)
      (exit 1))))

(define (extract-loaded-image-ref load-output)
  "Extract the image reference from 'docker load' stdout.
Output is either 'Loaded image: NAME:TAG' or 'Loaded image ID: sha256:...'."
  (let* ((lines (string-split load-output #\newline))
         (line  (find (lambda (l) (string-contains l "Loaded image")) lines)))
    (and line
         (let ((idx (string-contains line ": ")))
           (and idx
                (string-trim-right (substring line (+ idx 2))))))))

(define (main args)
  (let* ((opts       (parse-args (cdr args)))    ; skip script name
         (image-tag  (assoc-ref opts 'image-tag))
         (registry   (assoc-ref opts 'registry))
         (config     (assoc-ref opts 'config))
         (guix-flags (assoc-ref opts 'guix-flags))
         (full-tag   (if (string-null? registry)
                         image-tag
                         (string-append registry "/" image-tag)))
         (docker     (if (command-on-path? "docker") "docker" "podman")))

    ;; Validate inputs.
    (unless (file-exists? config)
      (format (current-error-port) "ERROR: config not found: ~a~%" config)
      (exit 1))
    (unless (command-on-path? "guix")
      (format (current-error-port)
              "ERROR: 'guix' is not on PATH.  Please install GNU Guix first.~%")
      (exit 1))
    (unless (or (command-on-path? "docker") (command-on-path? "podman"))
      (format (current-error-port)
              "ERROR: Neither 'docker' nor 'podman' found on PATH.~%")
      (exit 1))

    (format #t "==> Building Guix system Docker image from: ~a~%" config)
    (format #t "    Target tag: ~a~%~%" full-tag)

    ;; Build the tarball.  'guix system image' prints build progress to stderr
    ;; (which flows to the terminal) and the store path to stdout (captured).
    (let ((tarball (apply run/capture
                          "guix" "system" "image" "--image-type=docker"
                          (append guix-flags (list config)))))
      (when (string-null? tarball)
        (format (current-error-port)
                "ERROR: 'guix system image' produced no output.~%")
        (exit 1))
      (unless (file-exists? tarball)
        (format (current-error-port)
                "ERROR: tarball not found: ~a~%" tarball)
        (exit 1))
      (format #t "==> Tarball produced: ~a~%" tarball)

      ;; Load into Docker / Podman.
      (format #t "==> Loading image into ~a...~%" docker)
      (let* ((load-output (run/capture docker "load" "-i" tarball))
             (image-ref   (or (extract-loaded-image-ref load-output)
                              ;; Fallback: ID of the most recently loaded image.
                              (run/capture docker "images" "-q" "--no-trunc"))))
        (when (or (not image-ref) (string-null? image-ref))
          (format (current-error-port)
                  "ERROR: could not determine loaded image reference.~%")
          (exit 1))

        ;; Tag with the desired name.
        (format #t "==> Tagging image as ~a...~%" full-tag)
        (run/check docker "tag" image-ref full-tag)

        (format #t "~%==> Image available as: ~a~%~%" full-tag)
        (format #t "    To run an interactive shell~%")
        (format #t "    (Guix images use Shepherd as PID 1 – use docker exec,~%")
        (format #t "    not docker run --rm -it):~%")
        (format #t "      CONTAINER=$(~a run -d --privileged ~a)~%"
                docker full-tag)
        (format #t "      ~a exec -ti $CONTAINER /run/current-system/profile/bin/bash --login~%"
                docker)
        (format #t "      ~a stop $CONTAINER~%~%" docker)
        (format #t "    To push to a registry (manual step):~%")
        (format #t "      ~a push ~a~%~%" docker full-tag)))))

(main (command-line))
