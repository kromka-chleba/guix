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
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 iconv)
  #:use-module (ice-9 ports)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:export (%dist-phases))

;;; Commentary:
;;;
;;; Build phases to build a source tarball with the GNU build system, as with
;;; "make distcheck".
;;;
;;; Code:

(define* (build-dist #:key make-flags (dist-target "distcheck")
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

(define %backup-folder
  "../source.bcp")

;; Copy over only the files that weren't copied yet, ie.
;; what boostrap or configure has made.
(define* (backup-new-files #:key outputs #:allow-other-keys)
  "Copy over to backup, but only files that aren't yet
in the backup directory"
  (let ((source ".")
        (target %backup-folder))
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
(define (starts-with-gnu-store-shebang? filename)
  (let ((shebang-prefix (string-append "#!" (%store-directory))))
    (call-with-input-file filename
      (lambda (port)
        (let ((bytes (get-bytevector-n port (string-length shebang-prefix))))
          (equal? (string->bytevector shebang-prefix "UTF-8") bytes))))))

(define (try-restore-shebang backup target)
  (let ((st (stat target)))
    (if (eq? (stat:type st) 'directory)
        #t
        ;; Validate backup has shebang
        (let ((original-shebang (call-with-input-file backup get-line)))
          ;; Process target
          (let ((temp-file (string-append target ".tmp")))
            (call-with-output-file temp-file
              (lambda (out)
                (format out "~a~%" original-shebang)
                (call-with-input-file target
                  (lambda (in)
                    (get-line in) ; skip first line
                    (dump-port in out)))))

            ;; Preserve permissions and replace
            (chmod temp-file (stat:mode st))
            (rename-file temp-file target)
            (format #t "Restored shebang in ~a.~%" target))))))

(define* (restore-source #:key (file-name-suffix? #f) #:allow-other-keys)
  "Restore shebangs from backed up sources."
  (let ((source %backup-folder)
        (target "."))
    (copy-recursively
     source target
     #:keep-mtime? #t
     #:copy-file
     try-restore-shebang
     #:select?
     (lambda (file st)
       (or (eq? (stat:type st) 'directory)
           (and
            ;; Skip symlinks.
            (not (eq? (stat:type st) 'symlink))
            (or (not file-name-suffix?)
                (string-suffix? file-name-suffix? file))
            ;; Only files with /gnu/store shebang.
            (let* ((relative-path (string-drop file (string-length source)))
                   (target-path (string-append target relative-path)))
              (starts-with-gnu-store-shebang? target-path))))))))

(define* (restore-in-files #:rest args)
  "Commonly .in files are used to generate a file,
such files should never get a shebang, because the generated
file would also receive a shebang."
  (apply restore-source (cons*
                         #:file-name-suffix? ".in"
                         args)))

(define (restore-configure . _)
  "Restores all configure files with original contents."
  (for-each (lambda (file)
              (copy-file (string-append %backup-folder "/" file)
                         file))
            (find-files "." "^configure$")))

(define %dist-phases
  ;; Phases for building a source tarball.
  (modify-phases %standard-phases
    (delete 'strip)

    ;; Do not allow ".in" files to get patched shebangs.
    (add-after 'patch-source-shebangs 'restore-in-files-1 restore-in-files)

    ;; Revert patch-usr-bin-file
    (add-after 'build 'restore-configure restore-configure)

    (add-after 'unpack 'backup-source backup-new-files)
    ;; Back up files made by bootstrap phase, before they are patched.
    (add-after 'bootstrap 'backup-bootstrap-files backup-new-files)
    ;; Back up files made by configure phase, before they are patched.
    (add-after 'configure 'backup-configure-files backup-new-files)

    ;; Restore the backed up source, removing the patched shebangs.
    (add-after 'build 'restore-source restore-source)

    ;; (replace 'build restore-source)
    ;; (add-after 'build 'kill-it (lambda _ (exit 1)))

    ;; Ensure the dist is made only after the shebangs are replaced.
    ;; This ensures there are no store paths in the tarball.
    (add-after 'restore-source 'build-dist build-dist)

    (replace 'install install-dist)
    (delete 'install-license-files)))            ;don't create 'OUT/share/doc'

;;; gnu-dist.scm ends here
