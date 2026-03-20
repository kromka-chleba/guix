#!/bin/sh
# -*- mode: scheme; -*-
exec ./pre-inst-env guix repl -- "$0" "$@"
!#
;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Guix Contributors
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

;;; Commentary:
;;;
;;; This script lists all source URLs for the given packages and their
;;; transitive dependencies.  It is useful for preparing a list of URLs to
;;; allow in a network firewall so that a coding agent can download package
;;; sources.
;;;
;;; Usage:
;;;
;;;   .github/list-sources.scm PACKAGE...
;;;   .github/list-sources.scm --all
;;;
;;; (The script must be run from the top of the Guix source tree after
;;; building it with 'make', so that './pre-inst-env' is available.)
;;;
;;; With PACKAGE arguments, only the transitive dependencies of those packages
;;; are included.  With --all, every package in the distribution is scanned.
;;;
;;; mirror:// URLs are expanded to the actual mirror URLs.
;;;
;;; Example:
;;;
;;;   .github/list-sources.scm hello clamav > urls.txt

;;; Code:

(use-modules (guix packages)
             (guix download)
             (guix git-download)
             (guix hg-download)
             (guix svn-download)
             (guix bzr-download)
             (gnu packages)
             (srfi srfi-1)
             (ice-9 match)
             (ice-9 format))

(define (uri-vicinity dir file)
  ;; Same as 'uri-vicinity' in (guix build download): join base URL and path
  ;; keeping exactly one slash between them.
  (string-append (string-trim-right dir #\/) "/"
                 (string-trim file #\/)))

(define (origin-source-urls origin mirrors)
  "Return a list of source URLs for ORIGIN, expanding mirror:// as needed."
  (define (expand url)
    (if (string-prefix? "mirror://" url)
        (let* ((rest      (string-drop url (string-length "mirror://")))
               (slash-pos (string-index rest #\/))
               (mirror-id (string->symbol (substring rest 0 slash-pos)))
               (path      (substring rest (+ slash-pos 1)))
               (mirror-list (assoc-ref mirrors mirror-id)))
          (if mirror-list
              (map (lambda (base) (uri-vicinity base path)) mirror-list)
              (list url)))
        (list url)))

  (match (origin-uri origin)
    ((? git-reference? ref)
     (list (git-reference-url ref)))
    ((? hg-reference? ref)
     (list (hg-reference-url ref)))
    ((? svn-reference? ref)
     (list (svn-reference-url ref)))
    ((? svn-multi-reference? ref)
     (list (svn-multi-reference-url ref)))
    ((? bzr-reference? ref)
     (list (bzr-reference-url ref)))
    ;; url-fetch: URI is either a single string or a list of strings.
    ((? string? uri)
     (expand uri))
    ((uris ...)
     (append-map expand uris))
    (_ '())))

(define (collect-urls packages mirrors)
  "Return the sorted, deduplicated list of source URLs for all PACKAGES and
their transitive dependencies."
  (let ((seen-packages (make-hash-table))
        (seen-urls     (make-hash-table))
        (urls          '()))
    (define (visit! pkg)
      (unless (hashq-ref seen-packages pkg)
        (hashq-set! seen-packages pkg #t)
        ;; Visit inputs first.
        (for-each (match-lambda
                    ((_ (? package? dep) _ ...)
                     (visit! dep))
                    (_ #f))
                  (package-direct-inputs pkg))
        ;; Then collect this package's source URLs.
        (let ((origin (package-source pkg)))
          (when (origin? origin)
            (for-each (lambda (url)
                        (unless (hash-ref seen-urls url)
                          (hash-set! seen-urls url #t)
                          (set! urls (cons url urls))))
                      (origin-source-urls origin mirrors))))))
    (for-each visit! packages)
    (sort urls string<?)))

(define (main args)
  (match args
    ((_)
     ;; No arguments: show an error.
     (format (current-error-port)
             "error: no package names given; try --help or --all~%")
     (exit 1))
    ((_ "--help")
     (format #t "Usage: .github/list-sources.scm [--all | PACKAGE...]~%")
     (format #t "~%")
     (format #t "Print, one per line, all source URLs required to build PACKAGE and its~%")
     (format #t "transitive dependencies.  With --all, process every package in the~%")
     (format #t "distribution.  mirror:// URLs are expanded to their actual mirrors.~%")
     (format #t "~%")
     (format #t "The script must be run from the Guix source tree top directory~%")
     (format #t "after building with 'make', so that './pre-inst-env' is available.~%"))
    ((_ "--all")
     (let ((all (fold-packages cons '())))
       (for-each (lambda (url) (format #t "~a~%" url))
                 (collect-urls all %mirrors))))
    ((_ names ...)
     (let ((packages (filter-map (lambda (name)
                                   (match (find-packages-by-name name)
                                     (() (begin
                                           (format (current-error-port)
                                                   "warning: package '~a' not found~%"
                                                   name)
                                           #f))
                                     ((pkg . _) pkg)))
                                 names)))
       (for-each (lambda (url) (format #t "~a~%" url))
                 (collect-urls packages %mirrors))))))

(main (command-line))
