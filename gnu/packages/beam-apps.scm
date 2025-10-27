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

(define-module (gnu packages beam-apps)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages erlang)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages serialization)
  #:use-module (gnu packages tls)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system mix)
  #:use-module (guix build-system rebar))

(define-public ejabberd-vendor
  (package
    (name "ejabberd-vendor")
    (version "25.08")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/processone/ejabberd")
             (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0cr9s37a1v06i3bqb471r4dw1hdv49ph3pwjjrmnm8xkhyplaaly"))))
    (build-system rebar-build-system)
    (inputs (list bash-minimal coreutils procps sed))
    (native-inputs
     (list autoconf
           automake
           erlang-pc
           erlang-proper
           erlang-provider-asn1
           libyaml
           linux-pam
           openssl))
    (arguments
     (list
      #:vendorize? #t
      #:vendor-inputs `(("." . ,(rebar-inputs 'ejabberd)))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'set-environment
            (lambda _
              (setenv "HOME" "/tmp")
              (setenv "CC" "gcc")))
          (add-after 'unpack 'bootstrap
            (lambda _
              (invoke "aclocal" "-I" "m4")
              (invoke "autoconf" "-f")))
          (add-after 'bootstrap 'make-various-fixes
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((sh (search-input-file inputs "/bin/sh")))
                ;; Fix shell locations.
                (substitute* "configure" (("/bin/sh") sh))
                (substitute* "rebar.config.script"
                  (("sh -c '") (string-append sh " -c '")))
                ;; Do not recompile dependences.
                (substitute* "rebar.config"
                  (("\\[\\{\"eimp\", \\[\\]\\},") "[]}.\n{nop, ["))
                ;; Do not include source files into release.
                (substitute* "rebar.config"
                  (("\\{include_src, true\\},") "{include_src, false},"))
                ;; Do not install erl wrapper, we will do it ourselves.
                (substitute* "rebar.config"
                  (("\\{copy, \"rel/files/erl\",")
                   "%{copy, \"rel/files/erl\","))
                ;; It seems ejabberd still needs jiffy due to p1_acme.
                (substitute* "rebar.config"
                  (("\\{if_version_below, \"27\",") "{if_version_below, \"30\","))
                ;; Unpin pinned dependences.
                (substitute* "rebar.lock"
                  ((",1\\}") ",0}"))
                ;; Set proper paths.
                (substitute* "vars.config.in"
                  (("\\{sysconfdir, \".*\"\\}\\.")
                   "{sysconfdir, \"/etc\"}."))
                (substitute* "vars.config.in"
                  (("\\{localstatedir, \".*\"\\}\\.")
                   "{sysconfdir, \"/var\"}."))
                (substitute* "vars.config.in"
                  (("\\{config_dir, \".*\"\\}\\.")
                   "{config_dir, \"/etc/ejabberd\"}."))
                (substitute* "vars.config.in"
                  (("\\{logs_dir, \".*\"\\}\\.")
                   "{logs_dir, \"/var/log/ejabberd\"}."))
                (substitute* "vars.config.in"
                  (("\\{spool_dir, \".*\"\\}\\.")
                   "{spool_dir, \"/var/lib/ejabberd\"}.")))))
          (add-after 'make-various-fixes 'configure
            (lambda _
              (invoke "./configure"
                      (string-append "--prefix=" #$output))))
          (replace 'build
            (lambda _
              (invoke "make" "rel")))
          (replace 'install
            (lambda _
              (let ((ejabberd "_build/prod/rel/ejabberd"))
                (copy-recursively
                 (string-append ejabberd "/conf")
                 (string-append ejabberd "/share/doc/ejabberd-"
                                #$version "/examples"))
                (for-each
                 (lambda (rmdir)
                   (delete-file-recursively
                    (string-append ejabberd "/" rmdir)))
                 '("conf" "database" "logs"))
                (delete-file
                 (string-append (string-append ejabberd "/ejabberd-"
                                               #$version ".tar.gz")))
                (let ((erts (car (find-files ejabberd "erts-.*"
                                             #:directories? #t))))
                  (delete-file (string-append erts "/bin/erl"))
                  (install-file "rel/files/erl"
                                (string-append erts "/bin")))
                (chmod (string-append ejabberd
                                      "/bin/install_upgrade.escript") #o755)
                (copy-recursively ejabberd #$output))))
          (add-after 'install 'wrap-program
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let ((out (assoc-ref outputs "out")))
                (wrap-program (string-append out "/bin/ejabberdctl")
                  `("PATH" ":" suffix
                    ,(map (lambda (command)
                            (dirname
                             (search-input-file
                              inputs (string-append "bin/" command))))
                          (list "date" "dirname" "grep"
                                "id" "pgrep" "sed"))))))))))
    (synopsis "Robust, Ubiquitous and Massively Scalable Messaging Platform")
    (description "This package provides Ejabberd -- Robust, Ubiquitous and
Massively Scalable Messaging Platform.  It supports XMPP, MQTT and SIP
protocols.")
    (home-page "https://www.ejabberd.im")
    (license license:gpl2+)))
