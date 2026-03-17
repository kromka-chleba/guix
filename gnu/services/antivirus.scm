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
            clamav-configuration-clamd-config-file
            clamav-configuration-freshclam-config-file
            clamav-configuration-user
            clamav-configuration-group
            clamav-accounts
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
  (clamd-config-file
   maybe-string
   "The clamd configuration file to use.  When unspecified, the ClamAV
package's default configuration file is used.

When specifying a custom configuration file, make sure it contains a
@code{User clamav} directive so that clamd drops privileges from root
to the @code{clamav} user after reading the configuration.")
  (freshclam-config-file
   maybe-string
   "The freshclam configuration file to use.  When unspecified, the ClamAV
package's default configuration file is used.

When specifying a custom configuration file, make sure it contains a
@code{DatabaseOwner clamav} directive so that freshclam drops privileges
from root to the @code{clamav} user after reading the configuration.")
  (user
   (string "clamav")
   "The user account under which to run the ClamAV daemons.")
  (group
   (string "clamav")
   "The group under which to run the ClamAV daemons."))

(define (clamav-accounts config)
  "Return the user and group accounts for the ClamAV daemons."
  (let ((user (clamav-configuration-user config))
        (group (clamav-configuration-group config)))
    (filter identity
            (list
             (and (equal? group "clamav")
                  (user-group (name "clamav") (system? #t)))
             (and (equal? user "clamav")
                  (user-account
                   (name "clamav")
                   (group group)
                   (system? #t)
                   (comment "ClamAV daemon user")
                   (home-directory "/var/lib/clamav")
                   (shell (file-append shadow "/sbin/nologin"))))))))

(define (clamav-activation config)
  "Return a gexp to set up the ClamAV directory structure."
  (let ((user (clamav-configuration-user config))
        (group (clamav-configuration-group config)))
    (with-imported-modules (source-module-closure '((gnu build activation)
                                                    (guix build utils)))
      #~(begin
          (use-modules (gnu build activation)
                       (guix build utils))
          (let* ((pw (getpwnam #$user))
                 (uid (passwd:uid pw))
                 (gid (group:gid (getgrnam #$group))))
            (for-each (lambda (directory)
                        (mkdir-p/perms directory pw #o755)
                        (chown directory uid gid))
                      '("/run/clamav" "/var/lib/clamav" "/var/log/clamav")))))))

(define (clamav-shepherd-services config)
  "Return a list of <shepherd-service> for the ClamAV daemons."
  (let* ((clamav               (clamav-configuration-clamav config))
         (clamd-config-raw     (clamav-configuration-clamd-config-file config))
         (freshclam-config-raw (clamav-configuration-freshclam-config-file config))
         (clamd-config         (if (maybe-value-set? clamd-config-raw)
                                   clamd-config-raw
                                   (file-append clamav "/etc/clamav/clamd.conf")))
         (freshclam-config     (if (maybe-value-set? freshclam-config-raw)
                                   freshclam-config-raw
                                   (file-append clamav "/etc/clamav/freshclam.conf")))
         (user                 (clamav-configuration-user config))
         (group                (clamav-configuration-group config))
         (freshclam-pid-file "/run/clamav/freshclam.pid"))
    (list
     (shepherd-service
      (documentation "ClamAV virus scanning daemon (clamd).")
      (provision '(clamd))
      (requirement '(user-processes))
      (start #~(make-forkexec-constructor
                (list (string-append #$clamav "/sbin/clamd")
                      "--config-file" #$clamd-config
                      "--foreground")
                #:user #$user
                #:group #$group
                #:log-file "/var/log/clamav/clamd.log"))
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
virus database updater.")
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
