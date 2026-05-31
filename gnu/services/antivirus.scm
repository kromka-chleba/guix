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

(define-module (gnu services antivirus)
  #:use-module (gnu services)
  #:use-module (gnu services configuration)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system shadow)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages antivirus)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (guix packages)
  #:export (clamav-configuration
            clamav-configuration?
            clamav-configuration-clamav
            clamav-configuration-user
            clamav-configuration-group
            clamav-configuration-clamd-config-file
            clamav-configuration-freshclam-config-file
            clamav-service-type
            generate-documentation))

;;;
;;; ClamAV antivirus daemon
;;;

(define-maybe/no-serialization string)

(define-configuration/no-serialization clamav-configuration
  (clamav
   (package clamav)
   "The ClamAV package to use.")
  (user
   (string "clamav")
   "User account under which ClamAV daemons run.")
  (group
   (string "clamav")
   "Group under which ClamAV daemons run.")
  (clamd-config-file
   (maybe-string)
   "The @command{clamd} configuration file to use.  If unset, use
the default @file{clamd.conf} provided by @code{clamav}.")
  (freshclam-config-file
   (maybe-string)
   "The @command{freshclam} configuration file to use.  If unset, use
the default @file{freshclam.conf} provided by @code{clamav}."))

(define (clamav-accounts config)
  "Return user and group accounts for ClamAV daemons."
  (let ((user (clamav-configuration-user config))
        (group (clamav-configuration-group config)))
    (list (user-group (name group) (system? #t))
          (user-account
           (name user)
           (group group)
           (system? #t)
           (comment "ClamAV daemon user")
           (home-directory "/var/lib/clamav")
           (shell (file-append shadow "/sbin/nologin"))))))

(define (clamd-config-file config)
  (maybe-value (clamav-configuration-clamd-config-file config)
               (file-append (clamav-configuration-clamav config)
                            "/etc/clamav/clamd.conf")))

(define (freshclam-config-file config)
  (maybe-value (clamav-configuration-freshclam-config-file config)
               (file-append (clamav-configuration-clamav config)
                            "/etc/clamav/freshclam.conf")))

(define (clamav-activation config)
  "Return a gexp to set up the ClamAV directory structure."
  (let ((user (clamav-configuration-user config)))
  (with-imported-modules (source-module-closure '((gnu build activation)
                                                  (guix build utils)))
    #~(begin
        (use-modules (gnu build activation)
                     (guix build utils))
        (let ((user (getpwnam #$user)))
          ;; Runtime directory for socket and PID files.
          (mkdir-p/perms "/run/clamav" user #o755)
          ;; Virus database directory.
          (mkdir-p/perms "/var/lib/clamav" user #o755)
          ;; Log directory.
          (mkdir-p/perms "/var/log/clamav" user #o755))))))

(define (clamav-shepherd-services config)
  "Return a list of <shepherd-service> for the ClamAV daemons."
  (let ((clamav             (clamav-configuration-clamav config))
        (user               (clamav-configuration-user config))
        (group              (clamav-configuration-group config))
        (clamd-config       (clamd-config-file config))
       (freshclam-config    (freshclam-config-file config))
       (freshclam-pid-file  "/run/clamav/freshclam.pid")
       (bootstrap-delay     30))
    (list
     (shepherd-service
      (documentation
       "Fetch the initial ClamAV virus database before starting clamd.")
      (provision '(clamav-database-ready))
      (requirement '(user-processes networking))
      (one-shot? #t)
      (start #~(lambda _
                (define database-directory "/var/lib/clamav")
                (define (database-ready?)
                  (or (file-exists? (string-append database-directory
                                                    "/main.cvd"))
                       (file-exists? (string-append database-directory
                                                    "/main.cld"))))
                 (let loop ()
                   (let ((status (system* (string-append #$clamav "/bin/freshclam")
                                          "--config-file" #$freshclam-config)))
                     (if (or (zero? status) (database-ready?))
                         #t
                         (begin
                           (sleep #$bootstrap-delay)
                           (loop)))))))
      (auto-start? #t))

     (shepherd-service
      (documentation "ClamAV virus scanning daemon (clamd).")
      (provision '(clamd))
      (requirement '(clamav-database-ready user-processes))
      (start #~(let ((start-clamd
                      (make-forkexec-constructor
                       (list (string-append #$clamav "/sbin/clamd")
                             "--config-file" #$clamd-config
                             "--foreground")
                       #:user #$user
                       #:group #$group
                       #:log-file "/var/log/clamav/clamd.log")))
                (lambda args
                  (system* (string-append #$clamav "/bin/freshclam")
                           "--config-file" #$freshclam-config)
                  (apply start-clamd args))))
      (stop #~(make-kill-destructor)))

     (shepherd-service
      (documentation "ClamAV virus database updater (freshclam).")
      (provision '(freshclam))
      (requirement '(user-processes networking))
      (start #~(make-forkexec-constructor
                (list (string-append #$clamav "/bin/freshclam")
                      "--config-file" #$freshclam-config
                      "--daemon"
                      #$(string-append "--pid=" freshclam-pid-file))
                #:pid-file #$freshclam-pid-file
                #:user #$user
                #:group #$group
                #:environment-variables
                (list "SSL_CERT_DIR=/etc/ssl/certs"
                      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt")))
      (stop #~(make-kill-destructor))))))

(define clamav-service-type
  (service-type
   (name 'clamav)
   (description "Run the ClamAV antivirus daemon and the @command{freshclam}
virus database updater.  On boot, an initial @command{freshclam} run is
attempted before @command{clamd} starts, retrying every 30 seconds until the
database files are available.")
   (extensions
    (list (service-extension shepherd-root-service-type
                            clamav-shepherd-services)
          (service-extension account-service-type
                             clamav-accounts)
          (service-extension activation-service-type
                             clamav-activation)))
   (default-value (clamav-configuration))))

(define (generate-documentation)
  "Generate Texinfo documentation for the @code{clamav-configuration} record."
  (configuration->documentation 'clamav-configuration))
