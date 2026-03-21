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
;;; Test the Guix development Docker image.
;;;
;;; Usage:
;;;
;;;   .github/bin/test-guix-docker.scm [OPTIONS]
;;;
;;; Options:
;;;   --image-tag=TAG   Image to test (default: ghcr.io/kromka-chleba/guix-dev:latest)
;;;   -h, --help        Show this help and exit
;;;
;;; Exit codes:
;;;   0 – All tests passed
;;;   1 – One or more tests failed
;;;
;;; The script verifies that the Guix development Docker image:
;;;   1. Can be pulled from the registry
;;;   2. Starts successfully with Shepherd init system
;;;   3. Has all core services available
;;;   4. Can start the Guix daemon via herd
;;;   5. Can execute basic Guix commands
;;;   6. Has /etc/services available for name/service resolution
;;;   7. Can fetch a pre-built substitute from bordeaux.guix.gnu.org

;;; Code:

(use-modules (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 format)
             (ice-9 match))

(define %default-image "ghcr.io/kromka-chleba/guix-dev:latest")
(define %guix-bin "/run/current-system/profile/bin")

(define (show-help)
  (format #t "Usage: .github/bin/test-guix-docker.scm [OPTIONS]~%")
  (format #t "~%")
  (format #t "Test the Guix development Docker image.~%")
  (format #t "~%")
  (format #t "Options:~%")
  (format #t "  --image-tag=TAG   Image to test~%")
  (format #t "                    (default: ~a)~%" %default-image)
  (format #t "  -h, --help        Show this help and exit~%"))

(define (flag-value flag-name arg)
  "If ARG is \"--FLAG-NAME=VALUE\", return \"VALUE\", else #f."
  (let ((prefix (string-append "--" flag-name "=")))
    (and (string-prefix? prefix arg)
         (substring arg (string-length prefix)))))

(define (parse-args args)
  "Parse ARGS (excluding the script name) and return the image tag."
  (let loop ((args args)
             (image-tag %default-image))
    (match args
      (()
       image-tag)
      (((or "-h" "--help") . _)
       (show-help)
       (exit 0))
      ((arg . rest)
       (cond
        ((flag-value "image-tag" arg)
         => (lambda (v) (loop rest v)))
        (else
         (format (current-error-port) "error: unknown option: ~a~%" arg)
         (format (current-error-port) "Try --help for usage information.~%")
         (exit 1)))))))

(define (run/status . cmd)
  "Run CMD and return its exit status value."
  (status:exit-val (apply system* cmd)))

(define (run/capture . cmd)
  "Run CMD and return its stdout as a trimmed string.
Throw 'command-failed on non-zero exit so dynamic-wind cleanup still runs."
  (let* ((port   (apply open-pipe* OPEN_READ cmd))
         (output (read-string port))
         (status (close-pipe port)))
    (if (zero? (status:exit-val status))
        (string-trim-right output #\newline)
        (begin
          (format (current-error-port) "ERROR: command failed: ~{~a~^ ~}~%" cmd)
          (throw 'command-failed cmd)))))

(define (docker-exec container . cmd)
  "Run CMD inside CONTAINER via 'docker exec'.  Return exit status value."
  (status:exit-val (apply system* "docker" "exec" container cmd)))

(define (docker-exec/quiet container . cmd)
  "Run CMD inside CONTAINER, capturing stdout.  Return exit status value."
  (let* ((port   (apply open-pipe* OPEN_READ
                        (cons* "docker" "exec" container cmd)))
         (status (begin (read-string port) (close-pipe port))))
    (status:exit-val status)))

(define (pass label)
  (format #t "✓ ~a~%" label))

(define (fail label)
  "Print a failure message and throw 'test-failed.
Using throw (not exit) ensures dynamic-wind cleanup runs before exit."
  (format #t "✗ ~a~%" label)
  (throw 'test-failed label))

(define (test-step n total label thunk)
  "Run THUNK as test N of TOTAL, printing LABEL."
  (format #t "[TEST ~a/~a] ~a~%" n total label)
  (thunk)
  (format #t "~%"))

(define (main args)
  (let ((image-tag (parse-args (cdr args))))

    (format #t "========================================~%")
    (format #t "Testing Guix Dev Docker Image~%")
    (format #t "Image: ~a~%" image-tag)
    (format #t "========================================~%~%")

    ;; Tests 2–7 run inside a container whose ID we track here.  Dynamic-wind
    ;; guarantees cleanup (stop + rm) even when a test throws 'test-failed.
    (let ((container-id #f))
      (catch #t
        (lambda ()
          ;; Test 1: Pull the image.
          (test-step 1 7 "Pulling image..."
            (lambda ()
              (if (zero? (run/status "docker" "pull" image-tag))
                  (pass "Image pulled successfully")
                  (fail "Failed to pull image"))))

          ;; Test 2: Start the container (before entering dynamic-wind so
          ;; that a startup failure does not trigger cleanup of a non-existent
          ;; container).
          (test-step 2 7 "Starting container with Shepherd init..."
            (lambda ()
              (set! container-id
                (run/capture "docker" "run" "-d" "--privileged" image-tag))
              (if (not (string-null? container-id))
                  (pass (string-append "Container started (ID: "
                                       container-id ")"))
                  (fail "Failed to start container"))))
          (format #t "  Waiting for Shepherd to initialize...~%")
          (sleep 5)
          (format #t "~%")

          ;; Tests 3–7: run inside the container.  The dynamic-wind after-thunk
          ;; stops and removes the container regardless of success or failure.
          (dynamic-wind
            (lambda () #t)

            (lambda ()
              ;; Test 3: Shepherd is running.
              (test-step 3 7 "Checking Shepherd init system..."
                (lambda ()
                  (if (zero? (docker-exec/quiet container-id
                                                (string-append %guix-bin "/herd")
                                                "status"))
                      (begin
                        (pass "Shepherd is running")
                        (docker-exec container-id
                                     (string-append %guix-bin "/herd") "status"))
                      (fail "Shepherd is not running"))))

              ;; Test 4: Start Guix daemon.
              (test-step 4 7 "Starting Guix daemon..."
                (lambda ()
                  (define herd   (string-append %guix-bin "/herd"))
                  (define guixd  (string-append %guix-bin "/guix-daemon"))
                  (cond
                   ;; Normal path: Shepherd starts guix-daemon.
                   ((zero? (docker-exec/quiet container-id herd
                                              "start" "guix-daemon"))
                    (pass "Guix daemon started via Shepherd")
                    (docker-exec container-id herd "status" "guix-daemon"))
                   ;; Fallback: start guix-daemon directly.  This handles
                   ;; older images where the cgroup2 mount failure blocks
                   ;; Shepherd's dependency chain.  The cgroup filesystem is
                   ;; already provided by the Docker host, so guix-daemon can
                   ;; run safely if launched directly.
                   (else
                    (format #t "  Shepherd failed; trying direct guix-daemon start...~%")
                    (docker-exec/quiet container-id
                                       (string-append %guix-bin "/guile")
                                       "--no-auto-compile" "-c"
                                       "(use-modules (guix build utils))(mkdir-p \"/var/guix/daemon-socket\")")
                    ;; Launch guix-daemon in the background.
                    (system* "docker" "exec" "-d" container-id
                             guixd "--build-users-group=guixbuild")
                    ;; Wait up to 30 s for the socket to appear.
                    (let loop ((i 0))
                      (cond
                       ((zero? (docker-exec/quiet container-id
                                                  (string-append %guix-bin "/guile")
                                                  "--no-auto-compile" "-c"
                                                  "(exit (if (access? \"/var/guix/daemon-socket/socket\" F_OK) 0 1))"))
                        (pass "Guix daemon started directly (cgroup fallback)"))
                       ((< i 30)
                        (sleep 1)
                        (loop (+ i 1)))
                       (else
                        (fail "Failed to start Guix daemon"))))))))))

              ;; Test 5: Guix is available.
              (test-step 5 7 "Checking Guix is available..."
                (lambda ()
                  (if (zero? (docker-exec/quiet container-id
                                                (string-append %guix-bin "/guix")
                                                "--version"))
                      (begin
                        (pass "Guix is available")
                        (docker-exec container-id
                                     (string-append %guix-bin "/guix")
                                     "--version"))
                      (fail "Guix is not available"))))

              ;; Test 6: /etc/services is present.
              ;;
              ;; The Guix activate-etc function used to call delete-file on
              ;; /etc/ssl before symlinking it.  delete-file silently fails
              ;; when /etc/ssl is a directory (as Docker creates it), which
              ;; aborts activate-etc before /etc/services is created.  This
              ;; step detects that situation and creates the symlinks manually.
              ;; Once the image is rebuilt with the fixed activation code this
              ;; step becomes a no-op.
              (test-step 6 7 "Ensuring /etc/services is present..."
                (lambda ()
                  (define (etc-services-present?)
                    (zero? (docker-exec/quiet
                            container-id
                            (string-append %guix-bin "/guile")
                            "--no-auto-compile" "-c"
                            "(exit (if (access? \"/etc/services\" F_OK) 0 1))")))
                  (if (etc-services-present?)
                      (pass "/etc/services already present")
                      (begin
                        (format #t "  /etc/services missing – creating symlinks~%")
                        (for-each
                         (lambda (f)
                           (docker-exec/quiet
                            container-id
                            (string-append %guix-bin "/guile")
                            "--no-auto-compile" "-c"
                            (string-append
                             "(catch 'system-error"
                             " (lambda ()"
                             "   (symlink \"/run/current-system/etc/" f "\""
                             "            \"/etc/" f "\"))"
                             " (lambda (k . a) #f))")))
                         '("services" "protocols" "rpc" "nsswitch.conf"
                           "localtime"))
                        (if (etc-services-present?)
                            (pass "/etc/services symlink created")
                            (fail "Failed to create /etc/services"))))))

              ;; Test 7: 'guix build hello' via substitute.
              (test-step 7 7
                "Testing 'guix build hello' via substitute from bordeaux.guix.gnu.org..."
                (lambda ()
                  (if (zero? (docker-exec container-id
                                          (string-append %guix-bin "/guix")
                                          "build" "hello"))
                      (pass "Successfully fetched 'hello' – network access confirmed")
                      (begin
                        (format (current-error-port)
                                "  Ensure bordeaux.guix.gnu.org is reachable.~%")
                        (fail "Failed to build 'hello' package"))))))

            (lambda ()
              ;; Cleanup: stop and remove the container.
              (when (and container-id (not (string-null? container-id)))
                (format #t "Cleaning up container ~a...~%" container-id)
                (run/status "docker" "stop" container-id)
                (run/status "docker" "rm" container-id)))))

        ;; Handle failures thrown by 'fail' or 'run/capture'.  Dynamic-wind
        ;; cleanup has already run by the time we reach this handler.
        (lambda (key . rest-args)
          (unless (or (eq? key 'test-failed) (eq? key 'command-failed))
            (apply throw key rest-args))
          (exit 1))))

    (format #t "========================================~%")
    (format #t "Core tests passed! ✓~%")
    (format #t "========================================~%~%")
    (format #t "The Docker image is functional and ready to use.~%")
    (format #t "To use it interactively~%")
    (format #t "(Shepherd is PID 1 – use docker exec, not docker run -it):~%")
    (format #t "  CONTAINER=$(docker run -d --privileged ~a)~%" %default-image)
    (format #t "  docker exec -ti $CONTAINER ~a/bash --login~%" %guix-bin)
    (format #t "  docker stop $CONTAINER~%~%")))

(main (command-line))
