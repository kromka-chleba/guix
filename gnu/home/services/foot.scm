;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Fredrik Salomonsson <plattfot@posteo.net>
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

(define-module (gnu home services foot)
  #:use-module (gnu home services)
  #:use-module (gnu services configuration)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (foot-configuration
            foot-color-configuration
            foot-configuration->file
            home-foot-service-type))

(define (alpha-mode? value)
  (member value '(default matching all)))

(define (dim-blend-towards? value)
  (member value '(black white)))

(define (extra-content? lines)
  (and (list? lines)
       (fold (lambda (line prev)
               (and
                (string? line)
                prev))
             #t
             lines)))

(define (integer-pair? value)
  (match value
    ((one . two) (and (integer? one) (integer? two)))
    (_ #f)))

(define (integers-N? N ints)
  (and (list? ints)
       (<= (length ints) N)
       (fold (lambda (pair prev)
               (and
                (match pair
                  ((id . color) (and (integer? id) (integer? color)))
                  (_ #f))
                prev))
             #t
             ints)))

(define (integers-8? ints)
  (integers-N? 8 ints))

(define (integers-16? ints)
  (integers-N? 16 ints))

(define (integers-256? ints)
  (integers-N? 256 ints))

(define (integers-256/no-field-name? ints)
  (integers-256? ints))

(define-maybe string)
(define-maybe boolean)
(define-maybe number)
(define-maybe alpha-mode)
(define-maybe dim-blend-towards)
(define-maybe integer)
(define-maybe integers-8)
(define-maybe integers-16)
(define-maybe integers-256)
(define-maybe integers-256/no-field-name)
(define-maybe integer-pair)

(define (serialize-key-value field-name value)
  (format #f "~a=~a~%" field-name value))

(define (integer->hex-string value)
  (format #f "~6,'0x" value))

(define (serialize-integer field-name value)
  (format #f "~a=~a~%" field-name (integer->hex-string value)))

(define (serialize-extra-content field-name value)
  (fold-right string-append "" value))

(define (serialize-integer-pair field-name value)
  (match value
    ((cursor . text)
     (format #f
             "~a=~a ~a~%"
             field-name
             (integer->hex-string cursor)
             (integer->hex-string text)))))

(define (serialize-integersN field-name value)
  (let ((prefix-name (match field-name
                       ('_ "")
                       (name (symbol->string name)))))
    (fold-right string-append ""
          (map (lambda (pair)
                 (match pair
                   ((id . color)
                    (serialize-integer
                     (string-append prefix-name
                                    (number->string id))
                     color))))
               value))))

(define (serialize-integers-8 field-name value)
  (serialize-integersN field-name value))

(define (serialize-integers-16 field-name value)
  (serialize-integersN field-name value))

(define (serialize-integers-256 field-name value)
  (serialize-integersN field-name value))

(define (serialize-integers-256/no-field-name _ value)
  (serialize-integersN '_ value))

;; TODO: investigate why (serializer serialize-key-value) doesn't work in
;; define-configuration for alpha-mode and dim-blend-towards
(define (serialize-alpha-mode field-name value)
  (serialize-key-value field-name value))

(define (serialize-dim-blend-towards field-name value)
  (serialize-key-value field-name value))

(define (serialize-number field-name value)
  (serialize-key-value field-name value))

(define (serialize-string field-name value)
  (serialize-key-value field-name value))

(define (serialize-boolean field-name value)
  (format #f "~a=~a~%" field-name (if value "yes" "no")))

(define (serialize-foot-color-configuration field-name config)
   #~(string-append "\n[colors]\n"
                    #$(serialize-configuration
                       config foot-color-configuration-fields)))

(define (serialize-font-name field-name value)
  (format #f "font=~a" value))

(define (serialize-font-size field-name value)
  (format #f ":size=~a~%" value))

(define (description-integers from to)
  (format #f "Defined as a list of cons cells: @code{(INDEX . COLOR)}.  Where @code{INDEX} \
is an integer from ~a to ~a, and @code{COLOR} is the given color for that \
index." from to))

(define (description-translucency)
  "A value in the range [0.0, 1.0], where 0.0 means completely transparent, and 1.0 is opaque.")

(define-configuration foot-color-configuration
  (cursor
   (maybe-integer-pair)
   "A pair of @code{RRGGBB} values in hexadecimal in a cons cell: @code{(CURSOR . TEXT)}.

Example: @code{(cursor (cons #xff0000 #x00ff00))} for green cursor and red text.")
  (foreground
   (maybe-integer)
   "Default foreground color in hexadecimal.  This is the color used when no ANSI \
color is being used.")
  (background
   (maybe-integer)
   "Default background color in hexadecimal.  This is the color used when no ANSI \
color is being used.")
  (regular
   (maybe-integers-8)
   (string-append "The eight basic ANSI colors (Black, Red, Green, Yellow, Blue, Magenta, Cyan, \
White).  "(description-integers 0 7)"

E.g @code{(regular '((0 . #x242424) (7 . #xe6e6e6)))} to set the Black (@code{regular0}) and White (@code{regular7}) \

%/>
fields @code{242424} and @code{e6e6e6} respectively"))
  (bright
   (maybe-integers-8)
   (string-append "The eight bright ANSI colors (Black, Red, Green, Yellow, Blue, Magenta, Cyan, \
White).  "(description-integers 0 7)"

E.g @code{(bright '((1 . #xff4d51) (2 . #x35d450)))} to set the Red (@code{bright1}) and Green (@code{bright2}) \
fields @code{242424} and @code{e6e6e6} respectively"))
  (dim
   (maybe-integers-8)
   (string-append "Eight custom colors to use with dimmed colors.  "(description-integers 0 7)"

See foot.ini(5) man page for details."))
  (256-color-palette
   (maybe-integers-256/no-field-name)
   (string-append "Arbitrary colors in the 256-color palette.  "(description-integers 0 255)"

See foot.ini(5) man page for details."))
  (sixel
   (maybe-integers-16)
   (string-append "The default sixel color palette of 16 colors.  "(description-integers 0 15)"

See foot.ini(5) man page for details."))
  (alpha
   (maybe-number)
   (string-append "Background translucency.  "(description-translucency)))
  (alpha-mode
   (maybe-alpha-mode)
   "Specifies when alpha is applied.  One of the symbols @code{'default}, @code{'matching} or \
@code{'all}.

See foot.ini(5) man page for details.")
  (dim-blend-towards
   (maybe-dim-blend-towards)
   "Which color to blend towards when \"auto\" dimming a color (see foot.ini(5)
man page for details).  Takes one of the symbols @code{'black} or @code{'white.}  Blending
towards black makes the text darker, while blending towards white makes it
whiter (but still dimmer than normal text).")
  (selection-foreground
   (maybe-integer)
   "Selection foreground color in hexadecimal.")
  (selection-background
   (maybe-integer)
   "Selection background color in hexadecimal.")
  (jump-labels
   (maybe-integer-pair)
   "A pair of color values in a cons cell @code{(FOREGROUND . BACKGROUND)}, specifying \
the foreground (text) and background colors to use when rendering jump labels \
in URL mode.")
  (scrollback-indicator
   (maybe-integer-pair)
   "A pair of color values in a cons cell @code{(FOREGROUND . BACKGROUND)}, specifying \
the foreground (text) and background (indicator itself) colors for the \
scrollback indicator.")
  (search-box-no-match
   (maybe-integer-pair)
   "A pair of color values in a cons cell @code{(FOREGROUND . BACKGROUND)}, specifying \
the foreground (text) and background colors for the scrollback search box, \
when there are no matches.")
  (urls
   (maybe-integer)
   "Color to use for the underline used to highlight URLs in URL mode.")
  (flash
   (maybe-integer)
   "Color to use for the terminal window flash.")
  (flash-alpha
   (maybe-integer)
   (string-append "Flash translucency.  "(description-translucency)))
  (extra-content
   (extra-content '())
   "Lines to add to the end of the color section of the configuration, see
foot.ini(5) man page."))

(define-maybe foot-color-configuration)

(define-configuration foot-configuration
  ;; shell
  (login-shell
   (maybe-boolean)
   "If enabled, the shell will be launched as a login shell, by prepending a '-'
to argv[0].")
  (term
   (maybe-string)
   "Value to set the environment variable TERM to.")
  ;; TODO: replace font-name and font-size with a custom define-configuration
  ;; for fonts
  (font-name
   (maybe-string)
   "Font name."
   (serializer serialize-font-name))
  (font-size
   (maybe-integer)
   "Font size."
   (serializer serialize-font-size))
  (dpi-aware
   (maybe-boolean)
   "Fonts are sized using the monitor's DPI when true.")
  (raw-fields
   (maybe-string)
   "Additional fields to the main section of the configuration, see
foot.ini(5) man page.")
  (colors
   (maybe-foot-color-configuration)
   "Color section of the configuration."))

(define (foot-configuration->file config)
  (mixed-text-file
   "foot.ini"
   (serialize-configuration config foot-configuration-fields)))

(define (home-foot-config config)
  `(("foot/foot.ini" ,(foot-configuration->file config))))

(define home-foot-service-type
  (service-type
   (name 'home-foot-config)
   (extensions
    (list (service-extension home-xdg-configuration-files-service-type
                             home-foot-config)))
   ;; TODO: compose and extend?
   (default-value (foot-configuration))
   (description "Install and configure foot.")))
