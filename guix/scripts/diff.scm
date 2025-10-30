;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2025 Romain Garbage <romain.garbage@inria.fr>
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

(define-module (guix scripts diff)
  #:use-module (guix i18n)
  #:use-module (guix diagnostics)
  #:use-module (guix channels)
  #:use-module (guix describe)
  #:use-module (guix status)
  #:use-module (guix store)
  #:autoload   (guix git) (with-git-error-handling)
  #:autoload   (guix inferior) (inferior-for-channels
                                inferior-available-packages
                                close-inferior)
  #:use-module ((guix utils) #:select (%current-system
                                       version>?))
  #:use-module (guix ui)
  #:use-module (guix scripts)
  #:use-module ((guix scripts build)
                #:select (%standard-build-options
                          set-build-options-from-command-line
                          show-build-options-help))
  #:use-module ((guix scripts pull)
                #:select (channel-list))
  #:autoload   (gnu packages) (fold-available-packages)
  #:use-module (ice-9 match)
  #:use-module (ice-9 vlist)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-37)
  #:use-module (srfi srfi-71)
  #:export (guix-diff))

(define (new/upgraded-packages alist1 alist2)
  "Compare ALIST1 and ALIST2, both of which are lists of package name/version
pairs, and return two values: the list of packages new in ALIST2, and the list
of packages upgraded in ALIST2."
  (let* ((old      (fold (match-lambda*
                           (((name . version) table)
                            (match (vhash-assoc name table)
                              (#f
                               (vhash-cons name version table))
                              ((_ . previous-version)
                               (if (version>? version previous-version)
                                   (vhash-cons name version table)
                                   table)))))
                         vlist-null
                         alist1))
         (new      (remove (match-lambda
                             ((name . _)
                              (vhash-assoc name old)))
                           alist2))
         (upgraded (filter-map (match-lambda
                                 ((name . new-version)
                                  (match (vhash-assoc name old)
                                    (#f #f)
                                    ((_ . old-version)
                                     (and (version>? new-version old-version)
                                          `(,name . ,new-version))))))
                               alist2)))
    (values new upgraded)))

(define (display-new/upgraded-packages old new)
  "Display the list of new/upgraded packages in the form of a
name/version specification."
  (let ((new upgraded (new/upgraded-packages old new)))
    (for-each (match-lambda
                ((name . version)
                 (format #t "~a@~a~%"
                         name
                         version)))
              (append new upgraded))))

(define* (display-profile-news inferior #:key
                               current-is-newer?)
  "Display what's up in PROFILE--new packages, and all that.  If
CURRENT-IS-NEWER? is true, assume that the current process represents the
newest generation of PROFILE.  Return true when there's more info to display."
  (let ((these (fold-available-packages
                (lambda* (name version result
                               #:key supported? deprecated?
                               #:allow-other-keys)
                  (if (and supported? (not deprecated?))
                      (alist-cons name version result)
                      result))
                '()))
        (those (inferior-available-packages inferior)))
    (let ((old (if current-is-newer? those these))
          (new (if current-is-newer? these those)))
      (display-new/upgraded-packages old new))))



(define (show-help)
  (display (G_ "Usage: guix diff [OPTION]
Compute the differences between this Guix revision (including channel
configuration) and the target.\n"))
  (newline)

  (display (G_ "
  -C, --channels         compare against Guix built from this set of channels"))
  (display (G_ "
      --url=URL          use the Git repository at URL"))
  (display (G_ "
      --commit=COMMIT    use the specified COMMIT"))
  (display (G_ "
      --branch=BRANCH    use the tip of the specified BRANCH"))
  (display (G_ "
      --disable-authentication
                         disable channel authentication"))
  (display (G_ "
      --no-check-certificate
                         do not validate the certificate of HTTPS servers"))
  (display (G_ "
  -r, --reverse          reverse diff (consider this Guix is newer)"))

  (display (G_ "
  -h, --help             display this help and exit"))
  (display (G_ "
  -V, --version          display version information and exit"))
  (newline)
  (show-bug-report-information))

(define %options
  ;; Specifications of the command-line options.
  (cons* (option '(#\C "channels") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'channel-file arg result)))
         (option '("url") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'repository-url arg
                               (alist-delete 'repository-url result))))
         (option '("commit") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'ref `(tag-or-commit . ,arg) result)))
         (option '("branch") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'ref `(branch . ,arg) result)))
         (option '("disable-authentication") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'authenticate-channels? #f result)))
         (option '("no-check-certificate") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'verify-certificate? #f result)))
         (option '(#\r "reverse") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'current-is-newer? #t result)))

         (option '(#\h "help") #f #f
                 (lambda args
                   (leave-on-EPIPE (show-help))
                   (exit 0)))
         (option '(#\V "version") #f #f
                 (lambda args
                   (show-version-and-exit "guix time-machine")))

         %standard-build-options))

(define %default-options
  ;; Alist of default option values.
  `((system . ,(%current-system))
    (substitutes? . #t)
    (offload? . #t)
    (print-build-trace? . #t)
    (print-extended-build-trace? . #t)
    (multiplexed-build-output? . #t)
    (authenticate-channels? . #t)
    (verify-certificate? . #t)
    (graft? . #t)
    (debug . 0)
    (verbosity . 1)))


(define-command (guix-diff . args)
  (synopsis "compute the differences between this Guix and the target")

  (define (no-arguments arg _)
    (leave (G_ "~A: extraneous argument~%") arg))

  (with-error-handling
    (with-git-error-handling
     (let* ((opts         (parse-command-line args %options
                                              (list %default-options)
                                              #:argument-handler
                                              no-arguments))
            (channels     (channel-list opts))
            (current-channels (current-channels))
            (substitutes?     (assoc-ref opts 'substitutes?))
            (authenticate?    (assoc-ref opts 'authenticate-channels?))
            (current-is-newer? (assoc-ref opts 'current-is-newer?))
            (verify-certificate? (assoc-ref opts 'verify-certificate?)))
       (let* ((inferior
               (with-store store
                 (with-status-verbosity (assoc-ref opts 'verbosity)
                   (with-build-handler (build-notifier #:use-substitutes?
                                                       substitutes?
                                                       #:verbosity
                                                       (assoc-ref opts 'verbosity)
                                                       #:dry-run? #f)
                     (set-build-options-from-command-line store opts)
                     (inferior-for-channels channels))))))
         (display-profile-news inferior #:current-is-newer? current-is-newer?))))))
