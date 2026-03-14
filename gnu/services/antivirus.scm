;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Guix Contributors <guix-patches@gnu.org>
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
  #:use-module (gnu services shepherd)
  #:use-module (gnu system shadow)
  #:use-module (gnu packages antivirus)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:export (clamav-configuration
            clamav-configuration?
            clamav-configuration-clamav
            clamav-configuration-clamd-config-file
            clamav-configuration-freshclam-config-file
            %clamav-accounts
            clamav-service-type))

;;;
;;; ClamAV antivirus daemon
;;;

(define %default-clamd-config
  (plain-file "clamd.conf"
              "# ClamAV daemon configuration.
# See clamd.conf(5) for a description of each option.

# Required: comment out the \"Example\" line for clamd to run.
# Example

LocalSocket /run/clamav/clamd.ctl
PidFile /run/clamav/clamd.pid
DatabaseDirectory /var/lib/clamav
LogFile /var/log/clamav/clamd.log
LogTime yes
MaxConnectionQueueLength 30
MaxThreads 12
ReadTimeout 300
MaxDirectoryRecursion 20
FollowDirectorySymlinks yes
FollowFileSymlinks yes
DetectPUA yes
ScanPE yes
ScanELF yes
ScanOLE2 yes
ScanHTML yes
ScanXMLDOCS yes
ScanHWP3 yes
ScanArchive yes
"))

(define %default-freshclam-config
  (plain-file "freshclam.conf"
              "# Freshclam configuration.
# See freshclam.conf(5) for a description of each option.

# Required: comment out the \"Example\" line for freshclam to run.
# Example

DatabaseDirectory /var/lib/clamav
UpdateLogFile /var/log/clamav/freshclam.log
LogTime yes
# Check for updates this many times per 24 hours.
Checks 12
DatabaseMirror database.clamav.net
"))

(define %clamav-accounts
  ;; User and group for the ClamAV daemons.
  (list (user-group (name "clamav") (system? #t))
        (user-account
         (name "clamav")
         (group "clamav")
         (system? #t)
         (comment "ClamAV daemon user")
         (home-directory "/var/lib/clamav")
         (shell (file-append shadow "/sbin/nologin")))))

(define-record-type* <clamav-configuration>
  clamav-configuration make-clamav-configuration
  clamav-configuration?
  (clamav                  clamav-configuration-clamav
                           (default clamav))
  (clamd-config-file       clamav-configuration-clamd-config-file
                           (default %default-clamd-config))
  (freshclam-config-file   clamav-configuration-freshclam-config-file
                           (default %default-freshclam-config)))

(define (clamav-activation config)
  "Return a gexp to set up the ClamAV directory structure."
  (with-imported-modules (source-module-closure '((gnu build activation)
                                                  (guix build utils)))
    #~(begin
        (use-modules (gnu build activation)
                     (guix build utils))
        (let ((user (getpwnam "clamav")))
          ;; Runtime directory for socket and PID files.
          (mkdir-p/perms "/run/clamav" user #o755)
          ;; Virus database directory.
          (mkdir-p/perms "/var/lib/clamav" user #o755)
          ;; Log directory.
          (mkdir-p/perms "/var/log/clamav" user #o755)))))

(define (clamav-shepherd-services config)
  "Return a list of <shepherd-service> for the ClamAV daemons."
  (let ((clamav             (clamav-configuration-clamav config))
        (clamd-config       (clamav-configuration-clamd-config-file config))
        (freshclam-config   (clamav-configuration-freshclam-config-file config))
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
                #:user "clamav"
                #:group "clamav"
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
                #:user "clamav"
                #:group "clamav"
                #:pid-file #$freshclam-pid-file))
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
                             (const %clamav-accounts))
          (service-extension activation-service-type
                             clamav-activation)))
   (default-value (clamav-configuration))))
