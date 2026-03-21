#!/usr/bin/env -S guile --no-auto-compile
!#
;;; list-source-urls.scm — List source URLs for a package and its transitive
;;; dependencies.
;;;
;;; NOT official Guix infrastructure.  Personal dev tooling for
;;; kromka-chleba/guix.  Useful for building network allowlists when running
;;; Guix builds in restricted environments.
;;;
;;; Usage (from the repository root, using pre-inst-env):
;;;
;;;   ./pre-inst-env guile .github/docker/list-source-urls.scm PACKAGE...
;;;
;;; Example:
;;;
;;;   ./pre-inst-env guile .github/docker/list-source-urls.scm hello gcc
;;;
;;; Prints one URL per line to stdout.  Duplicate URLs are suppressed.
;;;
;;; See "22.4 Running Guix Before It Is Installed" for the ./pre-inst-env
;;; requirement.

(use-modules (guix)
             (guix packages)
             (guix store)
             (guix grafts)
             (guix monads)
             (guix gexp)
             (guix utils)
             (gnu packages)
             (srfi srfi-1)
             (ice-9 format)
             (ice-9 match))

;;; ---------------------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------------------

(define (package-source-url pkg)
  "Return the source URL string for PKG, or #f if unavailable."
  (let ((src (package-source pkg)))
    (and src
         (origin? src)
         (match (origin-uri src)
           ((? string? url) url)
           ((urls ...)
            (find string? urls))
           (_ #f)))))

(define (transitive-packages pkg)
  "Return the list of PKG and all its transitive dependencies (packages only)."
  (let loop ((todo (list pkg))
             (seen '())
             (result '()))
    (match todo
      (() result)
      ((p . rest)
       (if (member p seen)
           (loop rest seen result)
           (let* ((deps (filter package?
                                (map (match-lambda
                                       ((label (? package? dep) . _) dep)
                                       (_ #f))
                                     (package-direct-inputs p))))
                  (new-seen (cons p seen))
                  (new-result (cons p result)))
             (loop (append rest deps) new-seen new-result)))))))

;;; ---------------------------------------------------------------------------
;;; Main
;;; ---------------------------------------------------------------------------

(define (main args)
  (let ((pkg-names (cdr args)))   ; drop argv[0]
    (when (null? pkg-names)
      (display "Usage: ./pre-inst-env guile .github/docker/list-source-urls.scm PACKAGE...\n")
      (exit 1))

    (let* ((pkgs (filter-map
                  (lambda (name)
                    (let ((p (false-if-exception
                              (specification->package name))))
                      (unless p
                        (format (current-error-port)
                                "warning: unknown package '~a', skipping~%" name))
                      p))
                  pkg-names))
           (all-pkgs (delete-duplicates
                      (append-map transitive-packages pkgs)))
           (urls     (delete-duplicates
                      (filter-map package-source-url all-pkgs))))
      (for-each (lambda (url) (format #t "~a~%" url)) urls))))

(main (command-line))
