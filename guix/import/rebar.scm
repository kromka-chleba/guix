;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Igorj Gorjaĉev <igor@goryachev.org>
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

(define-module (guix import rebar)
  #:use-module (guix import rebar rebar-lock)
  #:use-module (guix base16)
  #:use-module (guix base32)
  #:use-module (guix read-print)
  #:use-module (guix scripts download)
  #:autoload   (guix utils) (find-definition-location)
  #:use-module (ice-9 match)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-71)
  #:use-module (guix build-system rebar)
  #:export (rebar-lock->expressions
            rebar-inputs-from-lockfile
            find-rebar-inputs-location
            extract-rebar-inputs))


;;;
;;; Convert ‘rebar.lock’ to Guix sources.
;;;

(define (rebar-lock->expressions lockfile package-name)
  "Given LOCKFILE, a 'rebar.lock' file, import its content as source
expressions.  Return a source list and a mix inputs entry for PACKAGE-NAME
referencing all imported sources."
  (define (rebar-lock-entry->guix-source rebar-lock-entry)
    (match rebar-lock-entry
      (('rebar-lock-entry
        ('entry-name entry-name)
        ('entry-hexpm
         ('hexpm-name hexpm-name)
         ('hexpm-version hexpm-version)
         ('hexpm-checksum hexpm-checksum)))
       `(define
          ,(string->symbol
            (string-append
             (beam-name->package-name entry-name) "-" hexpm-version))
          (hexpm-source ,entry-name ,hexpm-name ,hexpm-version
                        ,(bytevector->nix-base32-string
                          (base16-string->bytevector hexpm-checksum)))))
      ;; Git snapshot.
      (('rebar-lock-entry
        ('entry-name entry-name)
        ('entry-git
         ('git-url git-url)
         ('git-commit git-commit)))
       (begin
         (let* ((version (string-append "snapshot." (string-take git-commit 7)))
                (checksum
                 (second
                  (string-split
                   (with-output-to-string
                     (lambda _
                       (guix-download "-g" git-url
                                      (string-append "--commit=" git-commit))))
                   #\newline))))
           `(define
              ,(string->symbol
                (string-append
                 (beam-name->package-name entry-name) "-" version))
              (origin
                (method git-fetch)
                (uri (git-reference
                       (url ,git-url)
                       (commit ,git-commit)))
                (file-name
                 (git-file-name
                  ,(beam-name->package-name entry-name) ,version))
                (sha256 (base32 ,checksum)))))))
      (else #f)))

  (let* ((source-expressions
          (filter-map rebar-lock-entry->guix-source
                      (rebar-lock-string->scm
                       (call-with-input-file lockfile get-string-all))))
         (beam-inputs-entry
          `(,(string->symbol package-name) =>
            (list ,@(map second source-expressions)))))
    (values source-expressions beam-inputs-entry)))

(define* (rebar-inputs-from-lockfile #:optional (lockfile "mix.lock"))
  "Given LOCKFILE (default to \"mix.lock\" in current directory), return a
source list imported from it, to be used as package inputs.  This procedure
can be used for adding a manifest file within the source tree of a BEAM
application."
  (let ((source-expressions
         rebar-inputs-entry
         (rebar-lock->expressions lockfile "rebar-inputs-temporary")))
    (eval-string
     (call-with-output-string
       (lambda (port)
         (for-each
          (cut pretty-print-with-comments port <>)
          `((use-modules (guix build-system mix))
            ,@source-expressions
            (define-rebar-inputs lookup-rebar-inputs ,rebar-inputs-entry)
            (lookup-rebar-inputs 'rebar-inputs-temporary))))))))

(define (find-rebar-inputs-location file)
  "Search in FILE for a top-level definition of mix inputs.  Return the
location if found, or #f otherwise."
  (find-definition-location file 'lookup-rebar-inputs
                            #:define-prefix 'define-rebar-inputs))

(define* (extract-rebar-inputs file #:key exclude)
  "Search in FILE for a top-level definition of mix inputs.  If found,
return its entries excluding EXCLUDE, or an empty list otherwise."
  (call-with-input-file file
    (lambda (port)
      (do ((syntax (read-syntax port)
                   (read-syntax port)))
          ((match (syntax->datum syntax)
             (('define-rebar-inputs 'lookup-rebar-inputs _ ...) #t)
             ((? eof-object?) #t)
             (_ #f))
           (or (and (not (eof-object? syntax))
                    (match (syntax->datum syntax)
                      (('define-rebar-inputs 'lookup-rebar-inputs inputs ...)
                       (remove (lambda (rebar-input-entry)
                                 (eq? exclude (first rebar-input-entry)))
                               inputs))))
               '()))))))
