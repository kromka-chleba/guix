;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Sharlatan Hellseher <sharlatanus@gmail.com>
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

;;; This file returns a manifest of packages built using the python-build-system.
;;; It is used to assist continuous integration of the python-team branch.

(use-modules (guix packages)
             (guix profiles)
             (guix build-system)
             (srfi srfi-1))

;; Commentary:
;;
;; This script provides a manfiest of packages where
;; %default-input-package-name% is one of inputs, native-inputs or
;; propagated-inputs; optionally checks for particular version as well set by
;; %default-input-package-version%.
;;
;; ;; Check agains CI for missing derivatons:
;;
;; Current master:
;; guix weather \
;;   --display-missing \
;;   --substitute-urls=https://ci.guix.gnu.org \
;;   --manifest=etc/teams/python/python-package-with-input-manifest.scm
;;
;; Current python-team:
;; guix time-machine --branch=python-team -- \
;;   weather \
;;   --display-missing \
;;   --substitute-urls=https://ci.guix.gnu.org \
;;   --manifest=etc/teams/python/python-package-with-input-manifest.scm
;;
;; Buiild locally:
;; > ./pre-inst-env guix build \
;;   --verbosity=1 \
;;   --keep-going \
;;   --max-jobs=2 \
;;   --manifest=etc/teams/python/python-package-with-input-manifest.scm


(define %default-input-package-name "python-numpy")
(define %default-input-package-version "")

(define* (package-with-input? package
                              #:optional
                              (name %default-input-package-name)
                              (version %default-input-package-version))
  (any (lambda (input)
         (and (pair? input)
              (package? (cadr input))
              (if (string=? version "")
                  (string=? name (package-name (cadr input)))
                  (string=? (string-append name version)
                            (string-append (package-name (cadr input))
                                           (package-version (cadr input)))))))
       (package-direct-inputs package)))

;;
(manifest
  (map package->manifest-entry
       (fold-packages
         (lambda (package lst)
           (if (package-with-input? package)
               (cons package lst)
               lst))
         '())))
