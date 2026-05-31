;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Jan Wielkiewicz <tona_kosmicznego_smiecia@interia.pl>
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

(define-module (gnu tests antivirus)
  #:use-module (gnu services)
  #:use-module (gnu services antivirus)
  #:use-module (gnu system)
  #:use-module (gnu system vm)
  #:use-module (gnu tests)
  #:use-module (guix gexp)
  #:export (%test-clamav))

(define (run-clamav-test)
  (define test-user "avtest")
  (define test-group "avtest")

  (define os
    (marionette-operating-system
     (simple-operating-system
      (service clamav-service-type
               (clamav-configuration
                (user test-user)
                (group test-group))))))

  (define test
    (with-imported-modules '((gnu build marionette))
      #~(begin
          (use-modules (gnu build marionette)
                       (srfi srfi-64))

          (define marionette
            (make-marionette
             (list #$(virtual-machine
                      (operating-system os)
                      (port-forwardings '())))))

          (test-runner-current (system-test-runner #$output))
          (test-begin "clamav")

          (test-assert "Configured ClamAV user exists"
            (marionette-eval
             `(begin
                (getpwnam ,test-user)
                #t)
             marionette))

          (test-assert "Configured ClamAV group exists"
            (marionette-eval
             `(begin
                (getgrnam ,test-group)
                #t)
             marionette))

          (define (directory-has-owner? directory)
            (marionette-eval
             `(let ((st (stat ,directory))
                    (user (getpwnam ,test-user))
                    (group (getgrnam ,test-group)))
                (and (eq? (stat:type st) 'directory)
                     (eqv? (stat:uid st) (passwd:uid user))
                     (eqv? (stat:gid st) (group:gid group))
                     (eqv? (stat:perms st) #o755)))
             marionette))

          (test-assert "/run/clamav ownership and permissions"
            (directory-has-owner? "/run/clamav"))
          (test-assert "/var/lib/clamav ownership and permissions"
            (directory-has-owner? "/var/lib/clamav"))
          (test-assert "/var/log/clamav ownership and permissions"
            (directory-has-owner? "/var/log/clamav"))

          (test-end))))

  (gexp->derivation "clamav-test" test))

(define %test-clamav
  (system-test
   (name "clamav")
   (description "Test ClamAV activation directories and service accounts.")
   (value (run-clamav-test))))
