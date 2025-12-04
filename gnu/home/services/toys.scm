;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 unwox <me@unwox.com>
;;; Copyright © 2025 jgart <jgart@dismail.de>
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

(define-module (gnu home services toys)
  #:use-module (guix gexp)
  #:use-module (gnu packages package-management)
  #:use-module (gnu home services)
  #:use-module (gnu home services mcron)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu services configuration)
  #:export (home-toys-service-type
            home-toys-configuration))


(define (mcron-spec? a-thing)
  (or (procedure? a-thing)
      (list? a-thing)
      (string? a-thing)))

(define-configuration/no-serialization home-toys-configuration
  (toys
   (file-like toys)
   "The toys package to use.")
  (channels-file
   (file-like #f)
   "The channels file with the list of toys boxes.")
  (pull-interval
   (mcron-spec "* */2 * * *")
   "The mcron specification (see @command{info mcron 'Guile Syntax'} for more
details) for the toys pull interval.  Defines how often the toys database
will be updated.  The default interval is every 2 hours."))

(define (home-toys-shepherd-services config)
  (list (shepherd-service
         (provision '(toys))
         (documentation "Run toys, a Guix channel webring.")
         (start #~(make-forkexec-constructor
                   (list (string-append
                           (getenv "HOME")
                           "/.config/guix/current/bin/guix")
                         "toys" "serve")))
         (stop #~(make-kill-destructor)))))

(define (home-toys-mcron-services config)
  (list #~(job #$(home-toys-configuration-pull-interval config)
               (string-append
                (getenv "HOME")
                "/.config/guix/current/bin/guix toys pull "
                #$(home-toys-configuration-channels-file config)))))

(define (home-toys-profile-packages config)
  (list (home-toys-configuration-toys config)))

(define home-toys-service-type
  (service-type
   (name 'home-toys)
   (default-value '())
   (extensions
    (list (service-extension home-shepherd-service-type
                             home-toys-shepherd-services)
          (service-extension home-mcron-service-type
                             home-toys-mcron-services)
          (service-extension home-profile-service-type
                             home-toys-profile-packages)))
   (description "Run toys, a Guix channel search engine.")))

