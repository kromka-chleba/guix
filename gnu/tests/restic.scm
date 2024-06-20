;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2024 Richard Sent <richard@freakingpenguin.com>.
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

(define-module (gnu tests restic)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader grub)
  #:use-module (gnu packages)
  #:use-module (gnu packages sync)      ;rclone
  #:use-module (gnu services)
  #:use-module (gnu services backup)    ;restic
  #:use-module (gnu system)
  #:use-module (gnu system vm)
  #:use-module (gnu tests)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (srfi srfi-1)
  #:export (%test-restic))

(define password "password")

(define password-file
  (plain-file "password-file" password))

(define password-command
  (program-file "password-command" #~(display #$password)))

(define (run-restic-test)
  "Run tests in %restic-os."

  (define os
    (marionette-operating-system
     (simple-operating-system (extra-special-file "/root/.restic-test"
                                                  (plain-file "restic-test"
                                                              "Hello world!"))
                              ;; restic-backup-service only takes a string to avoid putting
                              ;; plaintext entries in the store. Ergo, symlink it.
                              (extra-special-file "/root/password-file"
                                                  password-file)
                              (service restic-backup-service-type
                                       (restic-backup-configuration
                                        (jobs
                                         (list (restic-backup-job
                                                (name "password-file-backup")
                                                (repository "/root/restic-password-file-repo")
                                                (schedule #~'(next-second '(0 15 30 45)))
                                                (password-file "/root/password-file")
                                                (files '("/root/.restic-test"))
                                                (init? #t))
                                               (restic-backup-job
                                                (name "password-command-backup")
                                                (repository "/root/restic-password-command-repo")
                                                (schedule #~'(next-second '(0 15 30 45)))
                                                (password-command password-command)
                                                (files '("/root/.restic-test"))
                                                (init? #t)))))))
     #:imported-modules '((gnu services herd)
                          (guix combinators))))

  (define vm (virtual-machine
              (operating-system os)
              (memory-size 512)))

  (define test
    (with-imported-modules (source-module-closure
                            '((gnu build marionette)))
      #~(begin
          (use-modules (gnu build marionette)
                       (srfi srfi-26)
                       (srfi srfi-64))

          (let ((marionette (make-marionette (list #$vm))))

            (test-runner-current (system-test-runner #$output))
            (test-begin "restic")

            (test-assert "backup-file-created"
              (wait-for-file "/root/.restic-test" marionette))

            (test-assert "mcron running"
              (marionette-eval
               '(begin
                  (use-modules (gnu services herd))
                  (start-service 'mcron))
               marionette))

            (test-assert "password-file backup completed"
              (wait-for-file "/root/restic-password-file-repo/config" marionette
                             ;; Restic takes a second to run, give it a bit
                             ;; more time.
                             #:timeout 20))

            (test-assert "password-comand backup completed"
              (wait-for-file "/root/restic-password-file-repo/config" marionette
                             #:timeout 20))

            (test-end)))))

  (gexp->derivation "restic-test" test))

(define %test-restic
  (system-test
   (name "restic")
   (description "Basic tests for the restic service.")
   (value (run-restic-test))))
