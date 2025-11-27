;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Nguyễn Gia Phong <cnx@loang.net>
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

(define-module (guix build fossil)
  #:use-module (guix build utils)
  #:use-module (srfi srfi-1)
  #:export (fossil-fetch))

;;; Commentary:
;;;
;;; This is the build-side support code of (guix fossil-download).
;;; It allows a Fossil repository to be opened at a specific revision.
;;;
;;; Code:

(define (uri-of-any-scheme? uri . schemes)
  (any (lambda (scheme)
         (string= uri scheme 0 (string-length scheme)))
       schemes))

(define* (fossil-fetch uri version directory
                       #:key (fossil-command "fossil")
                       (tls-cert-dir "/etc/ssl/certs"))
  "Fetch VERSION from URI into DIRECTORY.  VERSION must be a valid Fossil
version identifier.  Return #t on success, else throw an exception."
  (when (uri-of-any-scheme? uri "https")
    (setenv "SSL_CERT_DIR" tls-cert-dir))
    (setenv "FOSSIL_HOME" "/tmp")
    (apply invoke fossil-command "open" uri version "--workdir" directory
           (if (uri-of-any-scheme? uri "file" "http" "https" "ssh")
               '("--repodir" "/tmp")
               '("--nosync")))
    (with-directory-excursion directory
      (invoke fossil-command "close"))
  #t)
