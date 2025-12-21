;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Danny Milosavljevic <dannym@friendly-machines.com>
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

(define-module (gnu packages graal)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system ant)
  #:use-module (gnu packages)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages java)
  #:use-module (gnu packages python)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages icu4c)
  #:use-module (gnu packages java-compression)
  #:use-module (gnu packages libffi)
  #:use-module (gnu packages ninja)
  #:use-module (gnu packages cmake)
  #:use-module (gnu packages version-control))

;;;
;;; Packages
;;;

;; The mx build tool is used to build all GraalVM projects.
;; It has no external Python dependencies (stdlib only).
(define-public graalvm-mx
  (package
    (name "graalvm-mx")
    (version "7.68.2")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/graalvm/mx")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0y7qqc8374vq6sg9icfm0jlfx8fb447p9blpm18ji95qrm9ywzx0"))
              (patches (search-patches "graalvm-mx-check-failed-after-join.patch"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("." "lib/mx/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'create-missing-directories
            ;; mx's suite.py defines native projects that expect certain
            ;; directories to exist.  Create them so mx doesn't fail when
            ;; initializing.
            (lambda* (#:key outputs #:allow-other-keys)
              (let ((lib (string-append (assoc-ref outputs "out") "/lib/mx")))
                (mkdir-p (string-append lib "/java/com.oracle.jvmtiasmagent/include")))))
          (add-after 'create-missing-directories 'install-ninja-syntax
            ;; mx needs ninja_syntax Python module for native projects.
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let ((ninja-syntax (search-input-file inputs "misc/ninja_syntax.py"))
                    (lib (string-append (assoc-ref outputs "out") "/lib/mx")))
                (copy-file ninja-syntax (string-append lib "/ninja_syntax.py")))))
          (add-after 'install-ninja-syntax 'create-wrapper
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (bin (string-append out "/bin"))
                     (lib (string-append out "/lib/mx"))
                     (python (search-input-file inputs "/bin/python3")))
                (mkdir-p bin)
                (call-with-output-file (string-append bin "/mx")
                  (lambda (port)
                    (format port "#!~a~%exec ~a ~a/mx.py \"$@\"~%"
                            (search-input-file inputs "/bin/bash")
                            python
                            lib)))
                (chmod (string-append bin "/mx")
                       #o755)))))))
    (native-inputs (list (package-source ninja)))
    (inputs (list bash-minimal python-3))
    (home-page "https://github.com/graalvm/mx")
    (synopsis "Build tool for GraalVM projects")
    (description "mx is a command-line tool used for the development of
GraalVM projects.  It provides commands for building, testing, and packaging
polyglot language implementations built on the Truffle framework.")
    (license license:gpl2)))
