;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 jgart <jgart@dismail.de>
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

(define-module (guix scripts new)
  #:use-module (guix scripts)
  #:use-module (guix ui)
  #:use-module (guix build utils)
  #:use-module (srfi srfi-37)
  #:export (guix-new))

(define (show-help)
  (display (G_ "Usage: guix new [DIRECTORY]
Create a new channel template in DIRECTORY.\n"))
  (newline)
  (display (G_ "
  -h, --help             display this help and exit"))
  (display (G_ "
  -V, --version          display version information and exit"))
  (newline)
  (show-bug-report-information))

(define %options
  (list (option '(#\h "help") #f #f
                (lambda (opt name arg result)
                  (leave-on-EPIPE (show-help))
                  (exit 0)))
        (option '(#\V "version") #f #f
                (lambda (opt name arg result)
                  (show-version-and-exit "guix new")))))

(define-command (guix-new . args)
  (category development)
  (synopsis "create new channel template")

  (define (handle-argument arg result)
    (alist-cons 'directory arg result))

  (let* ((opts (parse-command-line args %options (list '())
                                   #:argument-handler handle-argument))
         (directory (or (assoc-ref opts 'directory) ".")))
    (create-channel-template directory)))

(define (create-guix-authorizations-file directory)
  (call-with-output-file (string-append directory "/.guix-authorizations")
    (lambda (port)
      (format port "(authorizations
 (version 0)
 ((\"ADD YOUR GPG FINGERPRINT HERE\"
   (name \"user\"))))~%"))))

(define (create-guix-channel-file directory)
  (call-with-output-file (string-append directory "/.guix-channel")
    (lambda (port)
      (format port "(channel
  (version 0)
  (keyring-reference \"keyring\"))~%"))))

(define (create-channel-template directory)
  "Create a channel template in DIRECTORY."
  (mkdir-p directory)
  (create-guix-authorizations-file directory)
  (create-guix-channel-file directory)
  (format #t (G_ "Channel template created in ~a.~%") directory))

