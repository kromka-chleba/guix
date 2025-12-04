;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 firefly707 <firejet707@gmail.com>
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

(define-module (gnu home services emacs)
  #:use-module (gnu home services)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu services)
  #:use-module (gnu services configuration)
  #:autoload   (gnu packages emacs) (emacs)
  #:use-module (guix records)
  #:use-module (guix gexp)
  #:use-module (guix profiles)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  
  #:export (emacs-server-configuration
            emacs-server-service-type))

(define-record-type* <emacs-server-configuration>
  emacs-server-configuration make-emacs-server-configuration
  emacs-server-configuration?
  (emacs emacs-server-emacs
         (default emacs)
         (documentation "The @code{emacs} package to use."))
  (packages emacs-server-packages
            (default (manifest '()))
            (documentation "A manifest containing @code{emacs} plugins to install."))
  (args emacs-server-args
        (default '())
        (documentation "Extra arguments to pass to @code{emacs}."))
  (server-name emacs-server-server-name
               (default #f)
               (documentation "\
The name of the @code{emacs} server to open.  By default, doesn't specify a name,
 and uses whatever default name @code{emacs} chooses."))
  (service-name emacs-server-service-name
                (default 'emacs-server)
                (documentation "\
The name to give the shepherd service.  By default, emacs-server.  This is
 useful if you want to run multiple servers, for example if one is a computational
 server."))
  (load-files emacs-server-load-files
              (default '())
              (documentation "\
A list of files for emacs to load before startup.  These will be byte-compiled.")))

(define (file-name file)
  (if (file-append? file)
      (string-append
       (file-name (file-append-base file))
       (file-append-suffix file))
      ((match file
         (local-file? local-file-name)
         (plain-file? plain-file-name)
         (computed-file? computed-file-name)
         (program-file? program-file-name)
         (scheme-file? scheme-file-name))
       file)))

(define profile-modules
  '((guix base16)
    (guix base32)
    (guix base64)
    (guix build syscalls)
    (guix build utils)
    (guix build-system)
    (guix colors)
    (guix combinators)
    (guix config)
    (guix derivations)
    (guix deprecation)
    (guix describe)
    (guix diagnostics)
    (guix discovery)
    (guix gexp)
    (guix grafts)
    (guix i18n)
    (guix licenses)
    (guix memoization)
    (guix modules)
    (guix monads)
    (guix packages)
    (guix profiles)
    (guix profiling)
    (guix read-print)
    (guix records)
    (guix search-paths)
    (guix serialization)
    (guix sets)
    (guix store)
    (guix ui)
    (guix utils)))

(define (emacs-server-shepherd-service config)
  (match-record config <emacs-server-configuration>
                (emacs packages args server-name service-name load-files)
    (let* ((emacs-exe (file-append
                       emacs
                       "/bin/emacs"))
           (emacs-profile (with-imported-modules profile-modules
                            #~#$(profile
                                  (name (string-append (symbol->string service-name) "-profile"))
                                  (content (manifest
                                            (cons
                                             (package->manifest-entry emacs)
                                             (manifest-entries packages))))))))
      (list
       (shepherd-service
         (provision (list service-name))
         (modules '((shepherd support)))
         (start
          #~(make-forkexec-constructor
             '(#$(program-file
                  "run-server"
                  #~(begin
                      (use-modules (guix build utils)
                                   (guix profiles))
                      (load-profile #$emacs-profile)
                      (invoke
                       #$emacs-exe
                       #$(string-append
                          "--fg-daemon"
                          (if
                           server-name
                           (string-append "=" server-name)
                           ""))
                       #$@(concatenate
                           (map
                            (compose
                             (lambda (v) (list "--load" v))
                             (lambda (file)
                               (file-append
                                (computed-file
                                 (file-name file)
                                 #~(begin
                                     (use-modules (guix build utils)
                                                  (guix profiles))
                                     (mkdir #$output)
                                     (chdir #$output)
                                     (symlink #$file "load.el")
                                     (load-profile #$emacs-profile)
                                     (invoke
                                      #$emacs-exe
                                      "--batch"
                                      "--execute"
                                      "(byte-compile-file \"load.el\")")
                                     (delete-file "load.el")))
                                "/load.elc")))
                            load-files))
                       #$@args))))
             #:log-file
             (string-append
              %user-log-dir
              #$(string-append "/"
                               (symbol->string service-name)
                               ".log"))))
         (stop #~(make-kill-destructor)))))))

(define (add-emacs-package config)
  (list (emacs-server-emacs config)))

(define emacs-server-service-type
  (service-type
   (name 'emacs-server)
   (extensions
    (list
     (service-extension home-profile-service-type
                        add-emacs-package)
     (service-extension home-shepherd-service-type
                        emacs-server-shepherd-service)))
   (default-value (emacs-server-configuration))
   (description "Run @code{emacs} as a daemon on user login, and provide emacs in
 the home profile.")))
