;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Luis Guilherme Coelho <lgcoelho@disroot.org>
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

(define-module (gnu packages fish-xyz)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (guix build-system trivial)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix utils))

(define-public fish-foreign-env
  (package
    (name "fish-foreign-env")
    (version "0.20230823")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/oh-my-fish/plugin-foreign-env")
             (commit "7f0cf099ae1e1e4ab38f46350ed6757d54471de7")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0d16mdgjdwln41zk44qa5vcilmlia4w15r8z2rc3p49i5ankksg3"))))
    (build-system trivial-build-system)
    (arguments
     '(#:modules ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils))
         (let* ((source (assoc-ref %build-inputs "source"))
                (out (assoc-ref %outputs "out"))
                (func-path (string-append out "/share/fish/functions")))
           (mkdir-p func-path)
           (copy-recursively (string-append source "/functions")
                             func-path)

           ;; Embed absolute paths.
           (substitute* `(,(string-append func-path "/fenv.fish")
                          ,(string-append func-path "/fenv.main.fish"))
             (("bash")
              (search-input-file %build-inputs "/bin/bash"))
             (("sed")
              (search-input-file %build-inputs "/bin/sed"))
             ((" tr ")
              (string-append " "
                             (search-input-file %build-inputs "/bin/tr")
                             " ")))))))
    (inputs
     (list bash coreutils sed))
    (home-page "https://github.com/oh-my-fish/plugin-foreign-env")
    (synopsis "Foreign environment interface for fish shell")
    (description "@code{fish-foreign-env} wraps bash script execution in a way
that environment variables that are exported or modified get imported back
into fish.")
    (license license:expat)))
