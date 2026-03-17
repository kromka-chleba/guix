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
  #:use-module (gnu system vm)
  #:use-module (gnu tests)
  #:use-module (guix gexp)
  #:export (%test-clamav))

(define (run-clamav-test)
  "Run tests for the ClamAV service, focusing on the activation service."
  (define os
    (marionette-operating-system
     (simple-operating-system
      (service clamav-service-type))
     #:imported-modules '((gnu services herd)
                          (guix combinators))))

  (define test
    (with-imported-modules '((gnu build marionette))
      #~(begin
          (use-modules (gnu build marionette)
                       (srfi srfi-1)
                       (srfi srfi-64))

          (define marionette
            (make-marionette
             (list #$(virtual-machine
                      (operating-system os)
                      (port-forwardings '())))))

          (test-runner-current (system-test-runner #$output))
          (test-begin "clamav")

          ;; User and group
          (test-assert "clamav user exists"
            (marionette-eval
             '(begin
                (getpwnam "clamav")
                #t)
             marionette))

          (test-assert "clamav group exists"
            (marionette-eval
             '(begin
                (getgrnam "clamav")
                #t)
             marionette))

          ;; Runtime directory
          (test-assert "/run/clamav exists"
            (marionette-eval
             '(eq? (stat:type (stat "/run/clamav")) 'directory)
             marionette))

          (test-assert "/run/clamav has correct ownership"
            (marionette-eval
             '(let ((dir (stat "/run/clamav"))
                    (uid (passwd:uid (getpwnam "clamav")))
                    (gid (group:gid (getgrnam "clamav"))))
                (and (eqv? (stat:uid dir) uid)
                     (eqv? (stat:gid dir) gid)))
             marionette))

          (test-assert "/run/clamav has expected permissions"
            (marionette-eval
             '(eqv? (stat:perms (stat "/run/clamav")) #o755)
             marionette))

          ;; Virus database directory
          (test-assert "/var/lib/clamav exists"
            (marionette-eval
             '(eq? (stat:type (stat "/var/lib/clamav")) 'directory)
             marionette))

          (test-assert "/var/lib/clamav has correct ownership"
            (marionette-eval
             '(let ((dir (stat "/var/lib/clamav"))
                    (uid (passwd:uid (getpwnam "clamav")))
                    (gid (group:gid (getgrnam "clamav"))))
                (and (eqv? (stat:uid dir) uid)
                     (eqv? (stat:gid dir) gid)))
             marionette))

          (test-assert "/var/lib/clamav has expected permissions"
            (marionette-eval
             '(eqv? (stat:perms (stat "/var/lib/clamav")) #o755)
             marionette))

          ;; Log directory
          (test-assert "/var/log/clamav exists"
            (marionette-eval
             '(eq? (stat:type (stat "/var/log/clamav")) 'directory)
             marionette))

          (test-assert "/var/log/clamav has correct ownership"
            (marionette-eval
             '(let ((dir (stat "/var/log/clamav"))
                    (uid (passwd:uid (getpwnam "clamav")))
                    (gid (group:gid (getgrnam "clamav"))))
                (and (eqv? (stat:uid dir) uid)
                     (eqv? (stat:gid dir) gid)))
             marionette))

          (test-assert "/var/log/clamav has expected permissions"
            (marionette-eval
             '(eqv? (stat:perms (stat "/var/log/clamav")) #o755)
             marionette))

          ;; Shepherd services
          (test-assert "clamd shepherd service is registered"
            (marionette-eval
             '(begin
                (use-modules (gnu services herd)
                             (srfi srfi-1))
                (any (lambda (service)
                       (memq 'clamd (live-service-provision service)))
                     (current-services)))
             marionette))

          (test-assert "freshclam shepherd service is registered"
            (marionette-eval
             '(begin
                (use-modules (gnu services herd)
                             (srfi srfi-1))
                (any (lambda (service)
                       (memq 'freshclam (live-service-provision service)))
                     (current-services)))
             marionette))

          (test-end))))

  (gexp->derivation "clamav-test" test))

(define %test-clamav
  (system-test
   (name "clamav")
   (description "Test the ClamAV antivirus service, focusing on activation.")
   (value (run-clamav-test))))
