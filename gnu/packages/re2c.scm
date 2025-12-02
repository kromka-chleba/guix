;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2017, 2020 Sergei Trofimovich <slyfox@inbox.ru>
;;; Copyright © 2021 Sergei Trofimovich <slyich@gmail.com>
;;; Copyright © 2018 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2025 Alexey Abramov <levenson@mmer.org>
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

(define-module (gnu packages re2c)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages python)
  #:use-module (gnu packages)
  #:use-module (guix build-system gnu)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix utils))

(define-public re2c
  (package
    (name "re2c")
    (version "4.3.1")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/skvadrik/re2c")
              (commit version)))
       (sha256
        (base32
         "02r7bcgw1ybbpz3qmw9srvyb47246lnig3sjz1bqi0fbl43l06wa"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests?
      (not (or (%current-target-system)
               (system-hurd?)))))       ; TODO run_tests.py hangs
    (native-inputs
     (list autoconf
           automake
           libtool
           python))                     ; For the test driver
    (synopsis "Lexer generator for C/C++")
    (description
     "@code{re2c} generates minimalistic hard-coded state machine (as opposed
to full-featured table-based lexers).  A flexible API allows generated code to
be wired into virtually any environment.  Instead of exposing a traditional
@code{yylex()} style API, re2c exposes its internals.")
    (home-page "https://re2c.org/")
    (license license:public-domain)))
