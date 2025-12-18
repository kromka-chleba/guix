;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013, 2015, 2020, 2023 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2018 Mark H Weaver <mhw@netris.org>
;;; Copyright © 2025 Efraim Flashner <efraim@flashner.co.il>
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

(define-module (guix build gnu-dist)
  #:use-module (guix build utils)
  #:use-module (guix build gnu-build-system)
  #:use-module (srfi srfi-1)
  #:export (%dist-phases))

;;; Commentary:
;;;
;;; Build phases to build a source tarball with the GNU build system, as with
;;; "make distcheck".
;;;
;;; Code:

(define* (build #:key make-flags (dist-target "distcheck")
                #:allow-other-keys
                #:rest args)
  (format #t "building target `~a'~%" dist-target)
  (setenv "DISTCHECK_CONFIGURE_FLAGS"
          (string-append "SHELL=" (which "sh")))
  (apply invoke "make" dist-target make-flags))

(define* (install-dist #:key outputs #:allow-other-keys)
  (let ((out (assoc-ref outputs "out")))
    (for-each (lambda (tarball)
                (install-file tarball out))
              (find-files "." "\\.tar\\."))
    #t))

;; Back up the source so that patch-shebang modifications in it can be reverted later.
;; This assumes that the source is not changed by `make dist`, new files can
;; be created, but existing ones cannot be modified.
(define %bootstrap-sources
  (cons*
   "git-version-gen"
   %bootstrap-scripts))

;; Copy over the files that are patched during bootstrap.
(define* (backup-source #:key outputs #:allow-other-keys)
  (mkdir "../source.bcp")
  (copy-recursively
   "." "../source.bcp"
   #:keep-mtime? #t))

;; Copy over only the files that weren't copied yet, ie.
;; what boostrap or configure has made.
(define* (backup-new-files #:key outputs #:allow-other-keys)
  (let ((source ".")
        (target "../source.bcp"))
    (copy-recursively
     source target
     #:keep-mtime? #t
     ;; Do not copy over sources that were already copied.
     #:select?
     (lambda (file st)
       (let* ((relative-path (string-drop file (string-length source)))
              (target-path (string-append target relative-path)))
         (or (eq? (stat:type st) 'directory)
             (not (file-exists? target-path))))))))

;; Restore the saved source without the patched shebangs.
(define* (restore-source #:key outputs #:allow-other-keys)
  (copy-recursively
   "../source.bcp" "."
   #:keep-mtime? #t
   #:copy-file
   (lambda (from to)
     (delete-file to)
     (copy-file from to))
   ;; Skip symlinks.
   #:select?
   (lambda (file st)
     (not (eq? (stat:type st) 'symlink)))))

(define %dist-phases
  ;; Phases for building a source tarball.
  (modify-phases %standard-phases
    (delete 'strip)

    (add-after 'unpack 'backup-source backup-source)
    ;; Back up files made by bootstrap phase, before they are patched.
    (add-after 'bootstrap 'backup-bootstrap-files backup-new-files)
    ;; Back up files made by configure phase, before they are patched.
    (add-after 'configure 'backup-configure-files backup-new-files)

    ;; Restore the backed up source, removing the patched shebangs.
    (add-after 'build 'restore-source restore-source)

    (replace 'install install-dist)
    ;; Ensure the dist is made only after the source is restored.
    ;; This ensures there are no store paths in the tarball.
    (add-after 'restore-source 'build-dist build)
    (delete 'install-license-files)))            ;don't create 'OUT/share/doc'

;;; gnu-dist.scm ends here
