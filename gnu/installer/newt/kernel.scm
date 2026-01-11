;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2024 Janneke Nieuwenhuizen <janneke@gnu.org>
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

(define-module (gnu installer newt kernel)
  #:use-module (gnu installer newt page)
  #:use-module (guix i18n)
  #:use-module (guix utils)
  #:export (run-kernel-page))

(define (run-kernel-page)
  (let* ((hurd-label
          ;; TRANSLATORS: "Hurd" is a proper noun and must not be translated.
          (G_ "Hurd (experimental)"))
         (kernels `("Linux Libre"
                    ,@(if (target-x86?)
                          (list hurd-label)
                          '())))
         (result
          (run-listbox-selection-page
           #:title (G_ "Kernel")
           #:info-text
           (G_ "Please select a kernel.  When in doubt, choose \"Linux Libre\".

The Hurd is offered as a technology preview and development aid; many packages \
are not yet available in Guix, such as a desktop environment or even a windowing \
system (X, Wayland).")
           #:listbox-items kernels
           #:listbox-item->text identity
           #:listbox-default-item "Linux Libre"
           #:sort-listbox-items? #f               ;keep Linux first
           #:button-text (G_ "Back")
           #:button-callback-procedure
           (lambda _
             (abort-to-prompt 'installer-step 'abort)))))
    (if (equal? result hurd-label)
        (begin
          (%current-target-system "i586-pc-gnu")
          "Hurd")
        result)))
