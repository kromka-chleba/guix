;;; docker-lib.scm — Shared helpers for Docker dev-environment scripts.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.
;;;
;;; Load from a sibling script with:
;;;
;;;   (include "docker-lib.scm")

(use-modules (ice-9 format)
             (ice-9 popen)
             (ice-9 rdelim))

;;; ---------------------------------------------------------------------------
;;; Constants
;;; ---------------------------------------------------------------------------

(define %default-image          "guix-dev:latest")
(define %default-container-name "guix-dev")
(define %ghcr-registry          "ghcr.io")
(define %ghcr-image             "ghcr.io/kromka-chleba/guix-dev")
(define %system-profile         "/run/current-system/profile/bin")

;;; Absolute path to the directory that contains the scripts (and this file).
;;; Uses (car (command-line)) so it always refers to the top-level invoked
;;; script, which must live in the same directory as docker-lib.scm.
(define %docker-dir
  (dirname (canonicalize-path (car (command-line)))))

;;; Repository root: walk up from %docker-dir looking for .git or pre-inst-env.
(define %repo-root
  (let loop ((dir %docker-dir))
    (cond
     ((or (file-exists? (string-append dir "/.git"))
          (file-exists? (string-append dir "/pre-inst-env")))
      dir)
     (else
      (let ((parent (dirname dir)))
        ;; Stop at filesystem root to avoid an infinite loop.
        (if (string=? parent dir)
            %docker-dir
            (loop parent)))))))

;;; ---------------------------------------------------------------------------
;;; Generic shell helpers
;;; ---------------------------------------------------------------------------

(define (run-command . args)
  "Run a shell command (ARGS joined with spaces).  Signal an error on
non-zero exit status."
  (let* ((cmd (string-join args " "))
         (ret (system cmd)))
    (unless (zero? (status:exit-val ret))
      (error (format #f "Command failed (exit ~a): ~a"
                     (status:exit-val ret) cmd)))))

(define* (run-command/check desc cmd #:key (verbose? #f))
  "Run shell command CMD, print DESC with [PASS]/[FAIL], return #t/#f.
When VERBOSE? is #t the command's stdout and stderr are shown; otherwise
they are suppressed."
  (let* ((full-cmd (if verbose? cmd (string-append cmd " >/dev/null 2>&1")))
         (ret      (system full-cmd)))
    (if (zero? (status:exit-val ret))
        (begin (format #t "  [PASS] ~a~%" desc) #t)
        (begin (format #t "  [FAIL] ~a (exit ~a)~%" desc (status:exit-val ret)) #f))))

(define (read-command-output . args)
  "Return the last non-empty trimmed line of stdout produced by ARGS as a
shell command.  Signal an error if the command exits non-zero."
  (let* ((cmd  (string-join args " "))
         (port (open-input-pipe cmd))
         (last (let loop ((last ""))
                 (let ((line (read-line port)))
                   (if (eof-object? line)
                       last
                       (loop (if (string-null? (string-trim-right line))
                                 last
                                 (string-trim-right line)))))))
         (ret  (close-pipe port)))
    (unless (zero? (status:exit-val ret))
      (error (format #f "Command failed (exit ~a): ~a"
                     (status:exit-val ret) cmd)))
    last))

;;; ---------------------------------------------------------------------------
;;; Docker container helpers
;;; ---------------------------------------------------------------------------

(define* (docker-create image name #:key (privileged? #t) (workspace #f))
  "Create (but do not start) a Docker container from IMAGE named NAME.
Pass --privileged when PRIVILEGED? is #t.
When WORKSPACE is a non-empty string, bind-mount it at /workspace inside the
container and set /workspace as the working directory."
  (let ((cmd (string-append
              "docker create"
              " --name " name
              (if privileged? " --privileged" "")
              (if (and workspace (not (string-null? workspace)))
                  (string-append " -v " workspace ":/workspace -w /workspace")
                  "")
              " " image
              " >/dev/null")))
    (unless (zero? (system cmd))
      (error (format #f "Failed to create container '~a' from '~a'"
                     name image)))))

(define (docker-start name)
  "Start the Docker container NAME."
  (run-command "docker" "start" name ">/dev/null"))

(define (docker-stop+rm name)
  "Stop and remove the Docker container NAME; ignore errors (e.g. already
stopped or not present)."
  (system (string-append "docker stop " name " >/dev/null 2>&1"))
  (system (string-append "docker rm   " name " >/dev/null 2>&1")))

(define (container-exec container . cmd-args)
  "Return a 'docker exec CONTAINER ...' shell command string."
  (string-append "docker exec " container " " (string-join cmd-args " ")))

(define* (wait-for-daemon container #:optional (timeout 30))
  "Poll until guix-daemon has started inside CONTAINER, waiting up to TIMEOUT
seconds.  Prints progress lines.  Returns #t if started, #f if timed out."
  (format #t "==> Waiting for guix-daemon...~%")
  (let loop ((remaining timeout))
    (cond
     ((zero? remaining)
      (format #t
              "  [WARN] guix-daemon did not start within ~a s; build tests may fail~%"
              timeout)
      #f)
     ((zero? (system
              (string-append "docker exec " container
                             " " %system-profile "/herd"
                             " status guix-daemon 2>&1 | grep -q running")))
      (format #t "  [OK] guix-daemon is running~%")
      #t)
     (else
      (sleep 1)
      (loop (- remaining 1))))))
