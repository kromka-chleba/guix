;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Igorj Gorjaĉev <igor@goryachev.org>
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

(define-module (guix import rebar rebar-lock)
  #:use-module (ice-9 match)
  #:use-module (ice-9 peg)
  #:export (rebar-lock-string->scm))

;;;
;;; PEG parser for ‘rebar.lock’.
;;;

(define (rebar-lock-string->scm str)
  (consult->scm
   (peg:tree
    (search-for-pattern consult str))))

;; Auxiliar peg patterns
(define-peg-pattern numeric-char body
  (range #\0 #\9))

(define-peg-pattern lowercase-char body
  (range #\a #\z))

(define-peg-pattern uppercase-char body
  (range #\A #\Z))

(define-peg-pattern alphabetic-char body
  (or lowercase-char uppercase-char))

(define-peg-pattern alphanumeric-char body
  (or alphabetic-char numeric-char))

(define-peg-pattern space-char body
  (+ (or " " "\t" "\n" "\r")))

;; integer: 42
(define-peg-pattern integer all
  (+ numeric-char))

;; string: "string"
(define-peg-pattern string-char body
  (or alphanumeric-char
      space-char
      "_" "." "~" "=" "<" ">" "/" ":" "-"))

;; treat list-based and binary-based strings equally
(define-peg-pattern string all
  (and (ignore (? "<<"))
       (ignore "\"")
       (* string-char)
       (ignore "\"")
       (ignore (? ">>"))))

;; atom: atom
(define-peg-pattern atom-char body
  (or alphanumeric-char "_" "@" "?" "!"))

(define-peg-pattern atom all
  (+ atom-char))

;; list: [ ... ]
(define-peg-pattern list all
  (and (ignore (* space-char))
       (ignore "[")
       (ignore (* space-char))
       (* (and
           value
           (ignore (? ","))))
       (ignore (* space-char))
       (ignore "]")
       (ignore (* space-char))))

;; tuple: { ... }
(define-peg-pattern tuple all
  (and (ignore (* space-char))
       (ignore "{")
       (ignore (* space-char))
       (* (and
           value
           (ignore (? ","))))
       (ignore (* space-char))
       (ignore "}")
       (ignore (* space-char))))

;; value may be string, atom, tuple, list
(define-peg-pattern value body
  (and (ignore (* space-char))
       (or integer string atom tuple list)
       (ignore (* space-char))))

(define-peg-pattern consult all
  (* (and value
          (ignore "."))))

(define (consult->scm consult)
  "Convert raw CONSULT format to SCM."
  (define (hashes->alist hashes)
    (let loop ((hashes hashes)
               (acc '()))
      (match hashes
        ((('tuple
           ('atom "pkg_hash") . _) . tail)
         (loop tail acc))
        ((('tuple
           ('atom "pkg_hash_ext") . (('list . hashes))) . _)
         (loop hashes acc))
        ((('tuple
           ('string name)
           ('string hash)) . tail)
         (loop tail (cons* `(,name . ,hash) acc)))
        (()
         acc)
        (_
         #f))))
  (let loop ((consult consult)
             (acc '())
             (hashes '()))
    (match consult
      (('consult . tail)
       (loop tail acc hashes))
      ((('tuple
         ('string "1.2.0")
         ('list . deps)) . (('list . hashes)))
       (loop deps acc (hashes->alist hashes)))
      ((('tuple
         ('string entry-name)
         ('tuple
          ('atom "pkg")
          ('string hexpm-name)
          ('string hexpm-version))
         ('integer _)) . deps)
       (let* ((hexpm-checksum (string-downcase
                               (cdr (assoc hexpm-name hashes))))
              (entry `(rebar-lock-entry
                       (entry-name ,entry-name)
                       (entry-hexpm
                        (hexpm-name ,hexpm-name)
                        (hexpm-version ,hexpm-version)
                        (hexpm-checksum ,hexpm-checksum)))))
         (loop deps (cons entry acc) hashes)))
      ((('tuple
         ('string entry-name)
         ('tuple
          ('atom "git")
          ('string git-url)
          ('tuple
           ('atom "ref")
           ('string git-commit)))
         ('integer _)) . deps)
       (let* ((entry `(rebar-lock-entry
                       (entry-name ,entry-name)
                       (entry-git
                        (git-url ,git-url)
                        (git-commit ,git-commit)))))
         (loop deps (cons entry acc) hashes)))
      (()
       (cons 'rebar-lock acc))
      (_
       #f))))
