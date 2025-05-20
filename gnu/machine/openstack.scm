;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2019 Jakob L. Kreuze <zerodaysfordays@sdf.org>
;;; Copyright © 2020 Brice Waegeneire <brice@waegenei.re>
;;; Copyright © 2022 Matthew James Kraai <kraai@ftbfs.org>
;;; Copyright © 2022 Ricardo Wurmus <rekado@elephly.net>
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

(define-module (gnu machine openstack)
  #:use-module (guix records)
  #:use-module (gnu machine ssh)
  #:use-module (gnu machine)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services networking)
  #:use-module (gnu system)
  #:use-module (gnu system pam)
  #:use-module (guix base32)
  #:use-module (guix derivations)
  #:use-module (guix i18n)
  #:use-module ((guix diagnostics) #:select (formatted-message))
  #:use-module (guix import json)
  #:use-module (guix monads)
  #:use-module (guix ssh)
  #:use-module (guix store)
  #:use-module (ice-9 format)
  #:use-module (ice-9 iconv)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 receive)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-2)
  #:use-module (srfi srfi-34)
  #:use-module (srfi srfi-35)
  #:use-module (srfi srfi-43)
  #:use-module (ssh key)
  #:use-module (ssh sftp)
  #:use-module (ssh shell)
  #:use-module (web client)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web uri)
  #:use-module (openstack)              ;

  #:export (openstack-configuration
            openstack-configuration?

            openstack-configuration-ssh-key
            openstack-configuration-tags
            openstack-configuration-region
            openstack-configuration-size
            openstack-configuration-enable-ipv6?

            openstack-environment-type))



;;;
;;; Parameters for instance creation.
;;;

(define-record-type* <openstack-configuration> openstack-configuration
  make-openstack-configuration
  openstack-configuration?
  this-openstack-configuration
  ;; (ssh-key     openstack-configuration-ssh-key)      ; string
  (name           openstack-configuration-name)       ; string
  (region         openstack-configuration-region)       ; string
  (flavor         openstack-configuration-flavor)
  (ssh-key        openstack-configuration-ssh-key)       ; string
  (keypair        openstack-configuration-keypair)       ; string
  (network        openstack-configuration-network)       ; string
  (image          openstack-configuration-image)
  (credentials    openstack-configuration-credentials #f))

(define-public (read-key-fingerprint file-name)
  "Read the private key at FILE-NAME and return the key's fingerprint as a hex
string."
  (let* ((privkey (private-key-from-file file-name))
         (pubkey (private-key->public-key privkey))
         (hash (get-public-key-hash pubkey 'md5)))
    (bytevector->hex-string hash)))

(define-public (machine-instance machine)
  "Return an alist describing the instance allocated to MACHINE."
  (openstack-server-by-name #:name (openstack-configuration-name (machine-configuration machine))))

;; TODO: Support non-initialized server
(define-public (machine-public-ipv4 machine)
  "Return the public IPv4 network interface of the instance allocated to
MACHINE as an alist. The expected fields are 'ip_address', 'netmask', and
'gateway'."
  (let ((addresses (openstack-server-ip-addresses (machine-instance machine))))
    (if (null? addresses)
        #f
        (assoc-ref (find
                    (lambda (ip-block) (equal? (assoc-ref ip-block "version") 4))
                    (vector->list
                     (assoc-ref
                      addresses
                      (openstack-configuration-network (machine-configuration machine)))))
                   "addr"))))


;;;
;;; Remote evaluation.
;;;

(define-public (openstack-remote-eval target exp)
  "Internal implementation of 'machine-remote-eval' for MACHINE instances with
an environment type of 'openstack-environment-type'."
  (let* ((address (machine-public-ipv4 target))
         (ssh-key (openstack-configuration-ssh-key
                   (machine-configuration target)))
         (delegate (machine
                    (inherit target)
                    (environment managed-host-environment-type)
                    (configuration
                     (machine-ssh-configuration
                      (host-name address)
                      (identity ssh-key)
                      (system "x86_64-linux"))))))
    (machine-remote-eval delegate exp)))


;;;
;;; System deployment.
;;;

;; XXX Copied from (gnu services base)
(define* (ip+netmask->cidr ip netmask #:optional (family AF_INET))
  "Return the CIDR notation (a string) for @var{ip} and @var{netmask}, two
@var{family} address strings, where @var{family} is @code{AF_INET} or
@code{AF_INET6}."
  (let* ((netmask (inet-pton family netmask))
         (bits    (logcount netmask)))
    (string-append ip "/" (number->string bits))))

(define-public (machine-wait-until-available machine)
  "Block until the initial Debian image has been installed on the instance
named INSTANCE-NAME."
    (let loop ()
        (unless (machine-public-ipv4 machine)
          (display "Instance is still spawning.")
          (sleep 5)
          (loop))))

;; TODO: Variabilize user
(define-public (wait-for-ssh address ssh-key)
  "Block until the an SSH session can be made as 'root' with SSH-KEY at ADDRESS."
  (let loop ()
    (catch #t
      (lambda ()
        (open-ssh-session address #:user "root" #:identity ssh-key)
        (display (format #t "Successfully connected to SSH using user root@~a.\n" address)))
      (lambda args
        (display (format #f "Waiting for SSH on root@~a to be open with key ~a...\n" address ssh-key))
        (sleep 5)
        (loop)))))

;; TODO: Ensure we get a valid id for each of the resources and use good errors
(define-public (create-instance target)
  (let* ((config (machine-configuration target))
        (flavor-name (openstack-configuration-flavor config))
        (image-name (openstack-configuration-image config))
        (network-name (openstack-configuration-network config))
        (keypair-name (openstack-configuration-keypair config)))
    (display "Starting creating the instance")
    (openstack-create-server
      #:name    (openstack-configuration-name config)
      #:flavor  (openstack-flavor-id  (openstack-flavor-by-name  #:name flavor-name))
      #:image   (openstack-image-id   (openstack-image-by-name   #:name image-name))
      #:network (openstack-network-id (openstack-network-by-name #:name network-name))
      #:keypair keypair-name)))

(define-public (deploy-openstack target)
  "Internal implementation of 'deploy-machine' for 'machine' instances with an
environment type of 'openstack-environment-type'."
  (maybe-raise-unsupported-configuration-error target)
  (if (not (machine-instance target))
      (create-instance target))
  (machine-wait-until-available target)
  (let ((address (machine-public-ipv4 target))
        (ssh-key (openstack-configuration-ssh-key (machine-configuration target))))
    (wait-for-ssh address ssh-key)
    (let ((delegate (machine
                      (operating-system (machine-operating-system target))
                      (environment managed-host-environment-type)
                      (configuration
                       (machine-ssh-configuration
                         (host-name address)
                         (identity ssh-key)
                         (system "x86_64-linux"))))))
      (deploy-machine delegate))))


;;;
;;; Roll-back.
;;;

(define-public (roll-back-openstack target)
  "Internal implementation of 'roll-back-machine' for MACHINE instances with an
environment type of 'openstack-environment-type'."
  (let* ((address (machine-public-ipv4 target))
         (ssh-key (openstack-configuration-ssh-key
                   (machine-configuration target)))
         (delegate (machine
                    (inherit target)
                    (environment managed-host-environment-type)
                    (configuration
                     (machine-ssh-configuration
                      (host-name address)
                      (identity ssh-key)
                      (system "x86_64-linux"))))))
    (roll-back-machine delegate)))


;;;
;;; Environment type.
;;;

(define-public openstack-environment-type
  (environment-type
   (machine-remote-eval openstack-remote-eval)
   (deploy-machine      deploy-openstack)
   (roll-back-machine   roll-back-openstack)
   (name                'openstack-environment-type)
   (description         "Provisioning of virtual machine servers on any OpenStack-compatible service.")))


(define-public (maybe-raise-unsupported-configuration-error machine)
  "Raise an error if MACHINE's configuration is not an instance of
<openstack-configuration>."
  (let ((config (machine-configuration machine))
        (environment (environment-type-name (machine-environment machine))))
    (unless (and config (openstack-configuration? config))
      (raise (formatted-message
              (G_ "unsupported machine configuration '~a' for environment of type '~a'")
              config
              environment)))))
