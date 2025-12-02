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
  #:use-module (guix build utils)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix utils))

(define %re2c-bootstrap-files-backup
  (let ((revision "0")
        (commit "1c7768c64ebe72a22475ca5f90e37d1fc15747b8"))
    (origin
      (method git-fetch)
      (uri (git-reference
             (url "https://codeberg.org/museoa/re2c-bootstrap-backup-sha1")
             (commit commit)))
      (file-name (git-file-name "re2c-bootstrap-files"
                                (git-version "0" revision commit)))
      (sha256
       (base32 "1dknwsbmcj8w605w6f36wg2y1zdwmgksqvqs1kibxd19zzdm6rg1")))))

(define %re2c-bootstrap-files
  (let ((revision "0")
        (commit "48eaf3d50515e2fbb61fdfb4cce6234b79131b8bf0718fa36f766b7d6cb255a6"))
    (origin
      (method git-fetch)
      (uri (git-reference
             (url "https://git.stikonas.eu/andrius/re2c-bootstrap")
             (commit commit)))
      (file-name (git-file-name "re2c-bootstrap-files"
                                (git-version "0" revision commit)))
      (sha256
       (base32 "1dknwsbmcj8w605w6f36wg2y1zdwmgksqvqs1kibxd19zzdm6rg1")))))

(define-public re2c-step-0
  (package
    (name "re2c-step-0")
    (version "0.13.7.5")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/skvadrik/re2c")
              (commit version)))
       (modules '((guix build utils)))
       (snippet
        #~(begin
            (for-each delete-file-recursively (find-files "bootstrap"))))
       (sha256
        (base32
         "08jl4vgh275d8lmqvbi9wyixbplbdqqiy6j8bl15qbc5i5lb6zsz"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:configure-flags
      #~(list "--enable-docs=no")
      #:make-flags
      #~(list "re2c")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'change-directory
            (lambda _
              (chdir "re2c")))
          (add-before 'bootstrap 'backup-scanner-re
            (lambda _
              (rename-file "scanner.re" "scanner_re.bak")))
          (add-after 'configure 'inject-re2c-bootstrap-files
            (lambda* (#:key inputs #:allow-other-keys)
              (copy-file (search-input-file inputs "scanner.cc") "scanner.cc")
              (copy-file (search-input-file inputs "scanner.re") "scanner.re")
              (invoke "touch" "scanner.cc")
              (chmod "scanner.cc" #o755)))
          (add-after 'inject-re2c-bootstrap-files 'build-pass-0
            (assoc-ref %standard-phases 'build))
          (add-after 'build-pass-0 'touch-scanner-re-pass-1
            (lambda _
              (invoke "touch" "scanner.re")))
          (add-after 'touch-scanner-re-pass-1 'build-pass-1
            (assoc-ref %standard-phases 'build))
          (add-after 'build-pass-1 'touch-scanner-re-pass-2
            (lambda _
              (invoke "touch" "scanner.re")))
          (add-after 'touch-scanner-re-pass-2 'build-pass-2
            (assoc-ref %standard-phases 'build))
          (add-after 'build-pass-2 'bring-back-scanner-re
            (lambda _
              (delete-file "scanner.re")
              (rename-file "scanner_re.bak" "scanner.re")))
          ;; (replace 'install
          ;;   (let ((bin (string-append #$output "/bin")))
          ;;     (mkdir-p bin)
          ;;     (copy-file "re2c" bin)))
          )))
    (native-inputs
     (list autoconf
           automake
           libtool
           %re2c-bootstrap-files))
    (synopsis "Lexer generator - step 0")
    (description "")
    (home-page "https://re2c.org/")
    (license license:public-domain)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; (define %re2c-bootstrap-steps                                                  ;;
;;   (vector                                                                      ;;
;;    (re2c-data                                                                  ;;
;; )                                                                              ;;
;;    (re2c-data                                                                  ;;
;;     (version "1.1")                                                            ;;
;;     (revision "0")                                                             ;;
;;     (commit "ab647f6b5302170bd2b70d8d6de04d57804c5d04")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "1.1.1")                                                          ;;
;;     (revision "1")                                                             ;;
;;     (commit "c0ec8b25ba025c1c03a29c9f334eefe5eb446fdf")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "1.1.1")                                                          ;;
;;     (revision "2")                                                             ;;
;;     (commit "55d9c87a54358736ebc61d935e3a6b178816ca23")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "1.2.1")                                                          ;;
;;     (revision "0")                                                             ;;
;;     (commit "b644493b0548f15ff47ef56e5e7ea09ab0c56796")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "1.3")                                                            ;;
;;     (revision "1")                                                             ;;
;;     (commit "5d130e89cce845a993e342139338293b397eb129")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "2.1")                                                            ;;
;;     (revision "0")                                                             ;;
;;     (commit "ddae31d386ebdf327559d8d659d50cbf642d3d57")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "2.1.1")                                                          ;;
;;     (revision "1")                                                             ;;
;;     (commit "fd2e96394fd573a60d1a5ec430c520771db3d035")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "2.2")                                                            ;;
;;     (revision "0")                                                             ;;
;;     (commit "aa2da70299b7807391a8a27b7e1ab3e9f494a205")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "3.0")                                                            ;;
;;     (revision "0")                                                             ;;
;;     (commit "3a7c3fedf26557c0db79e0dcece0b50bee495142")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    (re2c-data                                                                  ;;
;;     (version "3.1")                                                            ;;
;;     (revision "0")                                                             ;;
;;     (commit "ece4bb76e39db7071d5dd374d166008d5f982c3f")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))             ;;
;;    ;; Optional, since 3.1 builds 4.x; but let's be more conservative           ;;
;;    (re2c-data                                                                  ;;
;;     (version "4.0")                                                            ;;
;;     (revision "0")                                                             ;;
;;     (commit "b8a4cddf80692486e8780d2a3ffc8a7e82acebbc")                        ;;
;;     (hash "0000000000000000000000000000000000000000000000000000"))))           ;;
;;                                                                                ;;
;; (define re2c-data->package record                                              ;;
;;   (package                                                                     ;;
;;     (name "re2c-for-bootstrap")                                                ;;
;;     (version                                                                   ;;
;;      (if (eq? (re2c-data-revision record) "0")                                 ;;
;;          (git-version (re2c-data-version record)                               ;;
;;                       (re2c-data-revision record)                              ;;
;;                       (re2c-data-commit record))                               ;;
;;          (re2c-data-version record)))                                          ;;
;;     (source                                                                    ;;
;;      (origin                                                                   ;;
;;        (method git-fetch)                                                      ;;
;;        (uri (git-reference                                                     ;;
;;               (url "https://github.com/skvadrik/re2c")                         ;;
;;               (commit (re2c-data-commit record))))                             ;;
;;        (sha256                                                                 ;;
;;         (base32 (re2c-data-hash record)))                                      ;;
;;        (snippet                                                                ;;
;;         #~(begin                                                               ;;
;;             (use-modules (guix build utils))                                   ;;
;;             (for-each (lambda (f)                                              ;;
;;                         (delete-file f))                                       ;;
;;                       (find-files "bootstrap"))))))                            ;;
;;     (build-system gnu-build-system)                                            ;;
;;     (arguments                                                                 ;;
;;      (list                                                                     ;;
;;       #:tests? #f))                     ; Enable it on a case-by-case basis    ;;
;;     (native-inputs                                                             ;;
;;      (list autoconf                                                            ;;
;;            automake                                                            ;;
;;            libtool))                                                           ;;
;;     (synopsis "Lexer generator")                                               ;;
;;     (description                                                               ;;
;;      "@code{re2c} generates minimalistic hard-coded state machine (as opposed  ;;
;; to full-featured table-based lexers).  A flexible API allows generated code to ;;
;; be wired into virtually any environment.  Instead of exposing a traditional    ;;
;; @code{yylex()} style API, re2c exposes its internals.")                        ;;
;;     (home-page "https://re2c.org/")                                            ;;
;;     (license license:public-domain)))                                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
