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

(define-module (guix fossil-download)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (guix monads)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (guix store)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-34)
  #:use-module (srfi srfi-35)
  #:export (fossil-reference
            fossil-reference?
            fossil-reference-uri
            fossil-reference-version

            fossil-fetch
            fossil-version
            fossil-file-name))

;;; Commentary:
;;;
;;; An <origin> method that open Fossil checkout at a specific version.
;;; The repository URI and version are specified
;;; with a <fossil-reference> object.
;;;
;;; Code:

(define-record-type* <fossil-reference>
  fossil-reference make-fossil-reference fossil-reference?
  (uri     fossil-reference-uri)
  (version fossil-reference-version))

(define (fossil-package)
  "Return the default Fossil package."
  (let ((distro (resolve-interface '(gnu packages version-control))))
    (module-ref distro 'fossil)))

(define (fossil-version version revision checkin)
  "Return the version string for packages using fossil-download."
  ;; fossil-version is almost exclusively executed while modules
  ;; are being loaded, leading to any errors hiding their backtrace.
  ;; Avoid the mysterious error "Value out of range 0 to N: 10"
  ;; when the checkin ID is too short, which can happen, for example,
  ;; when the user swapped the revision and checkin arguments by mistake.
  (when (< (string-length checkin) 10)
    (raise
      (condition
       (&message (message "fossil-version: checkin ID unexpectedly short")))))
  (string-append version "-" revision "." (string-take checkin 10)))

(define (fossil-file-name name version)
  "Return the file-name for packages using fossil-download."
  (string-append name "-" version "-checkout"))

(define* (fossil-fetch ref hash-algo hash
                       #:optional name
                       #:key (system (%current-system))
                             (guile (default-guile))
                             (fossil (fossil-package)))
  "Return a fixed-output derivation that fetches REF, a <fossil-reference>
object.  The output is expected to have recursive hash HASH of type
HASH-ALGO (a symbol).  Use NAME as the file name, or a generic name if #f."
  (define guile-lzlib
    (module-ref (resolve-interface '(gnu packages guile)) 'guile-lzlib))

  (define guile-json
    (module-ref (resolve-interface '(gnu packages guile)) 'guile-json-4))

  (define gnutls
    (module-ref (resolve-interface '(gnu packages tls)) 'guile-gnutls))

  (define nss-certs
    (module-ref (resolve-interface '(gnu packages nss)) 'nss-certs))

  (define modules
    (source-module-closure '((guix build fossil)
                             (guix build download)
                             (guix build download-nar))))

  (define build
    (with-imported-modules modules
      (with-extensions (list guile-json gnutls ;for (guix swh)
                             guile-lzlib)
        #~(begin
            (use-modules (guix build fossil)
                         ((guix build download)
                          #:select (download-method-enabled?))
                         (guix build download-nar))
            (or (and (download-method-enabled? 'upstream)
                     (fossil-fetch #$(fossil-reference-uri ref)
                                   #$(fossil-reference-version ref)
                                   #$output
                                   #:fossil-command
                                   #+(file-append fossil "/bin/fossil")
                                   #:tls-cert-dir
                                   #+(file-append nss-certs "/etc/ssl/certs")))
                (and (download-method-enabled? 'nar)
                     (download-nar #$output)))))))

  (mlet %store-monad ((guile (package->derivation guile system)))
    (gexp->derivation (or name "fossil-checkout") build
                      #:leaked-env-vars '("http_proxy" "https_proxy"
                                          "COLUMNS" "USER")
                      #:env-vars (match (getenv "GUIX_DOWNLOAD_METHODS")
                                   (#f '())
                                   (value
                                    `(("GUIX_DOWNLOAD_METHODS" . ,value))))
                      #:system system
                      #:hash-algo hash-algo
                      #:hash hash
                      #:recursive? #t
                      #:guile-for-build guile
                      #:local-build? #t)))
