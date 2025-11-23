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
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:export (foot-configuration
            foot-font-configuration
            foot-colors-configuration
	    foot-key-bindings-configuration
	    foot-search-bindings-configuration
	    foot-url-bindings-configuration
	    foot-mouse-bindings-configuration
            foot-configuration->file
            home-foot-service-type))

(define (choice-sanitizer list)
  "Create a procedure that checks if a value is member of LIST."
  (lambda (value)
    (cond
     ((equal? value '%unset-marker%) '%unset-marker%)
     ((member value list) value)
     (else (error (format #f "value '~a' is not one of ~a" value list))))))

(define (verify-pair type?)
  (lambda (pair)
    (match pair
      ((key . value) (and (type? key) (type? value)))
      (_ #f))))

(define (extra-content? lines)
  (and (list? lines)
       (every string? lines)))

(define (color? value)
  (integer? value))

(define (color-pair? value)
  ((verify-pair color?) value))

(define (colors-N? N colors)
  (and (list? colors)
       (<= (length colors) N)
       (every (verify-pair color?) colors)))

(define (colors-8? colors)
  (colors-N? 8 colors))

(define (colors-16? colors)
  (colors-N? 16 colors))

(define (colors-256? colors)
  (colors-N? 256 colors))

(define (colors-256/no-field-name? colors)
  (colors-256? colors))

(define (string-pair? s)
  ((verify-pair string?) s))

(define (list-of-string-pairs? s)
  (every string-pair? s))

(define (fontconfig-integer? s)
  (integer? s))

(define (fontconfig-string? s)
  (string? s))

(define (fontconfig-name? s)
  (string? s))

(define (list-of-fontconfig-string-pairs? s)
  (list-of-string-pairs? s))

;;TODO: foot-font-configuration?

(define (list-of-foot-font-configuration? configs)
  (every foot-font-configuration? configs))

(define-maybe color)
(define-maybe colors-8)
(define-maybe colors-16)
(define-maybe colors-256)
(define-maybe colors-256/no-field-name)
(define-maybe color-pair)
(define-maybe string)
(define-maybe boolean)
(define-maybe number)
(define-maybe alpha-mode)
(define-maybe dim-blend-towards)
(define-maybe integer)
(define-maybe list-of-string-pairs)
(define-maybe fontconfig-string)
(define-maybe fontconfig-integer)
(define-maybe list-of-fontconfig-string-pairs)
(define-maybe list-of-foot-font-configuration)

(define (serialize-key-value field-name value)
  (format #f "~a=~a~%" field-name value))

(define* (pair->string value #:key (transform identity))
  (match-let (((first . second) value))
    (format #f
            "~a ~a"
            (transform first)
            (transform second))))

(define (color->hex-string value)
  (format #f "~6,'0x" value))

(define (serialize-color field-name value)
  (format #f "~a=~a~%" field-name (color->hex-string value)))

(define (serialize-extra-content field-name value)
  (string-join value "\n"))

(define (serialize-list-section field-name list)
  (string-concatenate
   (cons (format #f "~%[~a]~%" field-name)
         (map (match-lambda ((key . value) (serialize-key-value key value)))
              list))))

(define (serialize-color-pair field-name value)
  (serialize-key-value
   field-name
   (pair->string value #:transform color->hex-string)))

(define (serialize-colorsN field-name value)
  (let ((prefix-name (match field-name
                       ('_ "")
                       (name (symbol->string name)))))
    (fold-right string-append ""
          (map (match-lambda
                 ((id . color)
                  (serialize-color
                   (string-append prefix-name
                                  (number->string id))
                   color)))
               value))))

(define (serialize-colors-8 field-name value)
  (serialize-colorsN field-name value))

(define (serialize-colors-16 field-name value)
  (serialize-colorsN field-name value))

(define (serialize-colors-256 field-name value)
  (serialize-colorsN field-name value))

(define (serialize-colors-256/no-field-name _ value)
  (serialize-colorsN '_ value))

(define (serialize-number field-name value)
  (serialize-key-value field-name value))

(define (serialize-string field-name value)
  (serialize-key-value field-name value))

(define (serialize-list-of-pairs field-name value serializer)
  (string-concatenate
   (map (match-lambda
          ((k . v) (serializer k v)))
        value)))

(define (serialize-list-of-string-pairs field-name value)
  (serialize-list-of-pairs field-name value serialize-key-value))

(define (serialize-boolean field-name value)
  (format #f "~a=~a~%" field-name (if value "yes" "no")))

(define (serialize-foot-section-configuration fields)
  (lambda (section config)
    #~(string-append #$(format #f "~%[~a]~%" section)
                     #$(serialize-configuration config fields))))

(define (serialize-fontconfig field-name value)
  (format #f ":~a=~a" field-name value))

(define (serialize-fontconfig-name field-name value)
  (format #f "~a" value))

(define (serialize-fontconfig-string field-name value)
  (serialize-fontconfig field-name value))

(define (serialize-fontconfig-integer field-name value)
  (serialize-fontconfig field-name (number->string value)))

(define (serialize-list-of-fontconfig-string-pairs field-name value)
  (serialize-list-of-pairs field-name value serialize-fontconfig))

(define (serialize-list-of-foot-font-configuration font-option configs)
  #~(format #f "~a=~a~%"
            #$(symbol->string font-option)
            (string-join
             (list #$@(map (lambda (config)
                             (serialize-configuration config foot-font-configuration-fields))
                           configs))
             ", ")))

(define (description-colors from to)
  (format #f "Defined as a list of cons cells: @code{(INDEX . COLOR)}.  Where @code{INDEX} \
is an integer from ~a to ~a, and @code{COLOR} is the given color for that \
index." from to))

(define (description-translucency)
  "A value in the range [0.0, 1.0], where 0.0 means completely transparent, and 1.0 is opaque.")

(define (description-extra-content section)
  (format #f "Lines to add to the end of the ~a section of the configuration, see \
foot.ini(5) man page for available options." section))

(define-configuration foot-font-configuration
  (name
   (fontconfig-name)
   "Name of the font.")
  (size
   (maybe-fontconfig-integer)
   "Font size in points, as defined by fontconfig.

Note that this is affected by the @code{dpi-aware} option.")
  (pixersize
   (maybe-fontconfig-integer)
   "Font size in pixels.

Note that this is unaffected by the @code{dpi-aware} \
option, but affected by desktop scaling.")
  (weight
   (maybe-fontconfig-string)
   "Specify the weight (boldness) for the font.  E.g. @code{(weight \"bold\")} for \
bold font.")
  (slant
   (maybe-fontconfig-string)
   "Specify the slant for the font.  E.g. @code{(slant \"italic\")} for \
italic font.")
  (fontconfig-options
   (maybe-list-of-fontconfig-string-pairs)
   "Additional fontconfig options.
@lisp
(foot-font-configuration
 (name \"Iosevka\")
 (fontconfig-options
  '((\"fontfeatures\" . \"cv01=1\")
    (\"fontfeatures\" . \"cv06=1\"))))
@end lisp"))

(define-configuration foot-colors-configuration
  (cursor
   (maybe-color-pair)
   "A pair of @code{RRGGBB} values in hexadecimal in a cons cell: @code{(CURSOR . TEXT)}.

Example: @code{(cursor (cons #xff0000 #x00ff00))} for green cursor and red text.")
  (foreground
   (maybe-color)
   "Default foreground color in hexadecimal.  This is the color used when no ANSI \
color is being used.")
  (background
   (maybe-color)
   "Default background color in hexadecimal.  This is the color used when no ANSI \
color is being used.")
  (regular
   (maybe-colors-8)
   (string-append "The eight basic ANSI colors (Black, Red, Green, Yellow, Blue, Magenta, Cyan, \
White).  "(description-colors 0 7)"

E.g @code{(regular '((0 . #x242424) (7 . #xe6e6e6)))} to set the Black (@code{regular0}) and White (@code{regular7}) \

%/>
fields @code{242424} and @code{e6e6e6} respectively"))
  (bright
   (maybe-colors-8)
   (string-append "The eight bright ANSI colors (Black, Red, Green, Yellow, Blue, Magenta, Cyan, \
White).  "(description-colors 0 7)"

E.g @code{(bright '((1 . #xff4d51) (2 . #x35d450)))} to set the Red (@code{bright1}) and Green (@code{bright2}) \
fields @code{242424} and @code{e6e6e6} respectively"))
  (dim
   (maybe-colors-8)
   (string-append "Eight custom colors to use with dimmed colors.  "(description-colors 0 7)"

See foot.ini(5) man page for details."))
  (256-color-palette
   (maybe-colors-256/no-field-name)
   (string-append "Arbitrary colors in the 256-color palette.  "(description-colors 0 255)"

See foot.ini(5) man page for details."))
  (sixel
   (maybe-colors-16)
   (string-append "The default sixel color palette of 16 colors.  "(description-colors 0 15)"

See foot.ini(5) man page for details."))
  (alpha
   (maybe-number)
   (string-append "Background translucency.  "(description-translucency)))
  (alpha-mode
   (maybe-alpha-mode)
   "Specifies when alpha is applied.  One of the symbols @code{'default}, @code{'matching} or \
@code{'all}.

See foot.ini(5) man page for details."
   (serializer serialize-key-value)
   (sanitizer (choice-sanitizer '(default matching all))))
  (dim-blend-towards
   (maybe-dim-blend-towards)
   "Which color to blend towards when \"auto\" dimming a color (see foot.ini(5)
man page for details).  Takes one of the symbols @code{'black} or @code{'white.}  Blending
towards black makes the text darker, while blending towards white makes it
whiter (but still dimmer than normal text)."
   (serializer serialize-key-value)
   (sanitizer (choice-sanitizer '(black white))))
  (selection-foreground
   (maybe-color)
   "Selection foreground color in hexadecimal.")
  (selection-background
   (maybe-color)
   "Selection background color in hexadecimal.")
  (jump-labels
   (maybe-color-pair)
   "A pair of color values in a cons cell @code{(FOREGROUND . BACKGROUND)}, specifying \
the foreground (text) and background colors to use when rendering jump labels \
in URL mode.")
  (scrollback-indicator
   (maybe-color-pair)
   "A pair of color values in a cons cell @code{(FOREGROUND . BACKGROUND)}, specifying \
the foreground (text) and background (indicator itself) colors for the \
scrollback indicator.")
  (search-box-no-match
   (maybe-color-pair)
   "A pair of color values in a cons cell @code{(FOREGROUND . BACKGROUND)}, specifying \
the foreground (text) and background colors for the scrollback search box, \
when there are no matches.")
  (urls
   (maybe-color)
   "Color to use for the underline used to highlight URLs in URL mode.")
  (flash
   (maybe-color)
   "Color to use for the terminal window flash.")
  (flash-alpha
   (maybe-color)
   (string-append "Flash translucency.  "(description-translucency)))
  (extra-content
   (extra-content '())
   (description-extra-content "colors/colors2")))

(define-maybe foot-colors-configuration)

(define-configuration foot-key-bindings-configuration
  (noop
   (maybe-string)
   "All key combinations listed here will not be sent to the application.")
  (scrollback-up-page
   (string "Shift+Page_Up Shift+KP_Page_Up")
   "Scrolls up/back one page in history.")
  (scrollback-up-half-page
   (maybe-string)
   "Scrolls up/back half of a page in history.")
  (scrollback-up-line
   (maybe-string)
   "Scrolls up/back a single line in history.")
  (scrollback-down-page
   (string "Shift+Page_Down Shift+KP_Page_Down")
   "Scroll down/forward one page in history.")
  (scrollback-down-half-page
   (maybe-string)
   "Scroll down/forward half of a page in history.")
  (scrollback-down-line
   (maybe-string)
   "Scroll down/forward a single line in history.")
  (scrollback-home
   (maybe-string)
   "Scroll to the beginning of the scrollback.")
  (scrollback-end
   (maybe-string)
   "Scroll to the end (bottom) of the scrollback.")
  (clipboard-copy
   (string "Control+Shift+c XF86Copy")
   "Copies the current selection into the clipboard.")
  (clipboard-paste
   (string "Control+Shift+v XF86Paste")
   "Pastes from the clipboard.")
  (primary-paste
   (string "Shift+Insert")
   "Pastes from the primary selection.")
  (search-start
   (string "Control+Shift+r")
   "Starts a scrollback/history search.")
  (font-increase
   (string "Control+plus Control+equal Control+KP_Add")
   "Increases the font size by 0.5pt.")
  (font-decrease
   (string "Control+minus Control+KP_Subtract")
   "Decreases the font size by 0.5pt.")
  (font-reset
   (string "Control+0 Control+KP_0")
   "Resets the font size to the default.")
  (spawn-terminal
   (string "Control+Shift+n")
   "Spawns a new terminal. If the shell has been configured to emit the OSC 7 escape sequence, the new terminal will start in the current working directory.")
  (minimize
   (maybe-string)
   "Minimizes the window.")
  (maximize
   (maybe-string)
   "Toggle the maximized state.")
  (fullscreen
   (maybe-string)
   "Toggles the fullscreen state.")
  (pipe-visible
   (maybe-string)
   "Pipes the currently visible text to an external tool.")
  (pipe-scrollback
   (maybe-string)
   "Pipes the entire scrollback to an external tool.")
  (pipe-selected
   (maybe-string)
   "Pipes the currently selected text to an external tool.")
  (pipe-command-output
   (maybe-string)
   "Pipes the last command's output to an external tool.")
  (show-urls-launch
   (string "Control+Shift+o")
   "Enter URL mode, where all currently visible URLs are tagged with a jump label with a key sequence that will open the URL (and exit URL mode).")
  (show-urls-persistent
   (maybe-string)
   "Similar to @code{show-urls-launch}, but does not automatically exit URL mode after activating an URL.")
  (show-urls-copy
   (maybe-string)
   "Enter URL mode, where all currently visible URLs are tagged with a jump label with a key sequence that will place the URL in the clipboard. If the hint is completed with an uppercase character, the match will also be pasted.")
  (regex-launch
   (maybe-string)
   "Enter regex mode. This works exactly the same as URL mode; all regex matches are tagged with a jump label with a key sequence that will \"launch\" to match (and exit regex mode).")
  (regex-copy
   (maybe-string)
   "Same as @code{regex-launch}, but the match is placed in the clipboard, instead of \"launched\", upon activation. If the hint is completed with an uppercase character, the match will also be pasted.")
  (prompt-prev
   (string "Control+Shift+z")
   "Jump to the previous, currently not visible, prompt (requires shell integration, see foot(1)).")
  (prompt-next
   (string "Control+Shift+x")
   "Jump the next prompt (requires shell integration, see foot(1)).")
  (unicode-input
   (string "Control+Shift+u")
   "Input a Unicode character by typing its codepoint in hexadecimal, followed by @code{Enter} or @code{Space.}")
  (color-theme-switch-1
   (maybe-string)
   "applies the primary color theme regardless of which color theme is currently active.")
  (color-theme-switch-2
   (maybe-string)
   "applies the alternative color theme regardless of which color theme is currently active.")
  (color-theme-toggle
   (maybe-string)
   "toggles between the primary and alternative color themes.")
  (quit
   (maybe-string)
   "Quit foot.")
  (extra-content
   (extra-content '())
   (description-extra-content "key-bindings")))

(define-maybe foot-key-bindings-configuration)

(define-configuration foot-search-bindings-configuration
  (cancel
   (string "Control+g Control+c Escape")
   "Aborts the search. The viewport is restored and the primary selection is not updated.")
  (commit
   (string "Return KP_Enter")
   "Exit search mode and copy current selection into the primary selection.  Viewport is not restored. To copy the selection to the regular clipboard, use @code{Control+Shift+c}.")
  (find-prev
   (string "Control+r")
   "Search backwards in the scrollback history for the next match.")
  (find-next
   (string "Control+s")
   "Searches forwards in the scrollback history for the next match.")
  (cursor-left
   (string "Left Control+b")
   "Moves the cursor in the search box one character to the left.")
  (cursor-left-word
   (string "Control+Left Mod1+b")
   "Moves the cursor in the search box one word to the left.")
  (cursor-right
   (string "Right Control+f")
   "Moves the cursor in the search box one character to the right.")
  (cursor-right-word
   (string "Control+Right Mod1+f")
   "Moves the cursor in the search box one word to the right.")
  (cursor-home
   (string "Home Control+a")
   "Moves the cursor in the search box to the beginning of the input.")
  (cursor-end
   (string "End Control+e")
   "Moves the cursor in the search box to the end of the input.")
  (delete-prev
   (string "BackSpace")
   "Deletes the character before the cursor.")
  (delete-prev-word
   (string "Mod1+BackSpace Control+BackSpace")
   "Deletes the word before the cursor.")
  (delete-next
   (string "Delete")
   "Deletes the character after the cursor.")
  (delete-next-word
   (string "Mod1+d Control+Delete")
   "Deletes the word after the cursor.")
  (delete-to-start
   (string "Ctrl+u")
   "Deletes search input before the cursor.")
  (delete-to-end
   (string "Ctrl+k")
   "Deletes search input after the cursor.")
  (extend-char
   (string "Shift+Right")
   "Extend current selection to the right, by one character.")
  (extend-to-word-boundary
   (string "Control+w Control+Shift+Right")
   "Extend current selection to the right, to the next word boundary.")
  (extend-to-next-whitespace
   (string "Control+Shift+w")
   "Extend the current selection to the right, to the next whitespace.")
  (extend-line-down
   (string "Shift+Down")
   "Extend current selection down one line.")
  (extend-backward-char
   (string "Shift+Left")
   "Extend current selection to the left, by one character.")
  (extend-backward-to-word-boundary
   (string "Control+Shift+Left")
   "Extend current selection to the left, to the next word boundary.")
  (extend-backward-to-next-whitespace
   (maybe-string)
   "Extend the current selection to the left, to the next whitespace.")
  (extend-line-up
   (string "Shift+Up")
   "Extend current selection up one line.")
  (clipboard-paste
   (string "Control+v Control+y Control+Shift+v XF86Paste")
   "Paste from the clipboard into the search buffer.")
  (primary-paste
   (string "Shift+Insert")
   "Paste from the primary selection into the search buffer.")
  (unicode-input
   (maybe-string)
   "Unicode input mode. See @file{key-bindings.unicode-input} for details.")
  (scrollback-up-page
   (string "Shift+Page_Up Shift+KP_Page_Up")
   "Scrolls up/back one page in history.")
  (scrollback-up-half-page
   (maybe-string)
   "Scrolls up/back half of a page in history.")
  (scrollback-up-line
   (maybe-string)
   "Scrolls up/back a single line in history.")
  (scrollback-down-page
   (string "Shift+Page_Down Shift+KP_Page_Down")
   "Scroll down/forward one page in history.")
  (scrollback-down-half-page
   (maybe-string)
   "Scroll down/forward half of a page in history.")
  (scrollback-down-line
   (maybe-string)
   "Scroll down/forward a single line in history.")
  (scrollback-home
   (maybe-string)
   "Scroll to the beginning of the scrollback.")
  (scrollback-end
   (maybe-string)
   "Scroll to the end (bottom) of the scrollback.")
  (extra-content
   (extra-content '())
   (description-extra-content "search-bindings")))

(define-maybe foot-search-bindings-configuration)

(define-configuration foot-url-bindings-configuration
  (cancel
   (string "Control+g Control+c Control+d Escape")
   "Exits URL mode without opening a URL.")
  (toggle-url-visible
   (string "t")
   "This action toggles between showing and hiding the URL on the jump label.")
  (extra-content
   (extra-content '())
   (description-extra-content "url-bindings")))

(define-maybe foot-url-bindings-configuration)

(define-configuration foot-mouse-bindings-configuration
  (selection-override-modifiers
   (string "Shift")
   "The modifiers set in this set (which may be set to any combination of modifiers, e.g. @code{mod1+mod2+mod3}, as well as none) are used to enable selecting text with the mouse irrespective of whether a client application currently has the mouse grabbed. These modifiers cannot be used as modifiers in mouse bindings. Because the order of bindings is significant, it is best to set this prior to any other mouse bindings that might use modifiers in the default set.")
  (scrollback-up-mouse
   (string "BTN_WHEEL_BACK")
   "Normal screen: scrolls up the contents.  Alt screen: send fake @code{KeyUP} events to the client application, if alternate scroll mode is enabled.")
  (scrollback-down-mouse
   (string "BTN_WHEEL_FORWARD")
   "Normal screen: scrolls down the contents.  Alt screen: send fake @code{KeyDOWN} events to the client application, if alternate scroll mode is enabled.")
  (select-begin
   (string "BTN_LEFT")
   "Begin an interactive selection. The selection is finalized, and copied to the primary selection, when the button is released.")
  (select-begin-block
   (string "Control+BTN_LEFT")
   "Begin an interactive block selection. The selection is finalized, and copied to the primary selection, when the button is released.")
  (select-word
   (string "BTN_LEFT-2")
   "Begin an interactive word-wise selection, where words are separated by whitespace and all characters defined by the word-delimiters option. The selection is finalized, and copied to the primary selection, when the button is released.")
  (select-word-whitespace
   (string "Control+BTN_LEFT-2")
   "Same as select-word, but the characters in the word-delimiters option are ignored. I.e only whitespace characters act as delimiters. The selection is finalized, and copied to the primary selection, when the button is released.")
  (select-quote
   (string "BTN_LEFT-3")
   "Begin an interactive \"quote\" selection. This is similar to select-word, except an entire quote is selected. Recognized quote characters are: \" and '.")
  (select-row
   (string "BTN_LEFT-4")
   "Begin an interactive row-wise selection. The selection is finalized, and copied to the primary selection, when the button is released.")
  (select-extend
   (string "BTN_RIGHT")
   "Interactively extend an existing selection, using the original selection mode (normal, block, word-wise or row-wise). The selection is finalized, and copied to the primary selection, when the button is released.")
  (select-extend-character-wise
   (string "Control+BTN_RIGHT")
   "Same as select-extend, but forces the selection mode to normal (i.e.  character wise). Note that this causes subsequent select-extend operations to be character wise. This action is ignored for block selections.")
  (primary-paste
   (string "BTN_MIDDLE")
   "Pastes from the primary selection.")
  (font-increase
   (string "Control+BTN_WHEEL_BACK")
   "Increases the font size by 0.5pt.")
  (font-decrease
   (string "Control+BTN_WHEEL_FORWARD")
   "Decreases the font size by 0.5pt.")
  (extra-content
   (extra-content '())
   (description-extra-content "mouse-bindings")))

(define-maybe foot-mouse-bindings-configuration)

(define (description-font font)
  (format #f "List of @code{foot-font-configuration} for the ~a fonts to use.  See foot.ini(5)
man page for details." font))

(define-configuration foot-configuration
  (shell
    (maybe-string)
    "Executable to launch. Typically a shell. You can also pass arguments. For example /bin/bash --norc.")
  (login-shell
   (maybe-boolean)
   "If enabled, the shell will be launched as a login shell, by prepending a '-'
to argv[0].")
  (term
   (maybe-string)
   "@anchor{home-foot-configuration-term}Value to set the environment variable TERM to.")
  (font
   (maybe-list-of-foot-font-configuration)
   (description-font "normal"))
  (font-bold
   (maybe-list-of-foot-font-configuration)
   (description-font "bold"))
  (font-italic
   (maybe-list-of-foot-font-configuration)
   (description-font "italic"))
  (font-bold-italic
   (maybe-list-of-foot-font-configuration)
   (description-font "bold italic"))
  (box-drawings-uses-font-glyphs
    (maybe-boolean)
    "Boolean. When disabled, foot generates box/line drawing characters itself.")
  (dpi-aware
   (maybe-boolean)
   "Fonts are sized using the monitor's DPI when true.")
  (gamma-correct-blending
    (maybe-boolean)
    "Boolean. When enabled, foot will do gamma-correct blending in linear color space. This is how font glyphs are supposed to be rendered, but since nearly no applications or toolkits are doing it on Linux, the result may not look like you are used to.")
  ;; Spacing, offsets, underline and strikethrough
  ;; TODO: these are measured in points by default. The "px" suffix can be used to measure in pixels instead. Supporting that will need a new serializer, I think.
  (line-height
    (maybe-integer)
    "An absolute value, in points, that override line height from the font metrics.")
  (letter-spacing
    (maybe-integer)
    "Spacing between letters, in points. A positive value will increase the cell size, and a negative value shrinks it.")
  (horizontal-letter-offset
    (maybe-integer)
    "Horizontal offset used when positioning glyphs within cells, in points, relative to the top left corner.")
  (vertical-letter-offset
    (maybe-integer)
    "Vertical offset used when positioning glyphs within cells, in points, relative to the top left corner.")
  (underline-offset
    (maybe-integer)
    "Custom offset for underlines, in points and relative to the font's baseline. Positive values position in under the baseline, negative values position it over the baseline.")
  (underline-thickness
    (maybe-integer)
    "Use a custom thickness (height) for underlines, in points.")
  (strikeout-thickness
    (maybe-integer)
    "Use a custom thickness (height) for strikeouts, in points.")
  (uppercase-regex-insert
    (maybe-boolean)
    "Boolean. When enabled, inputting an uppercase hint character in show- urls-copy or regex-copy mode will insert the selected text into the prompt in addition to copying it to the clipboard.")
  (include
    (maybe-string)
    "Absolute path to configuration file to import.")
  (extra-content
   (extra-content '())
   (description-extra-content "main"))
  (environment
   (maybe-list-of-string-pairs)
   "Section to define environment variables that will be set in the client \
application, in addition to the variables inherited from the terminal process \
itself.

Format is a list of @code{(KEY . VALUE)} pairs, where @code{KEY} is a string \
matching the environment variable name to set, and @code{VALUE} a string \
representing the environment variable's value.

If you want to set environment variables for your home configuration, use
@code{home-environment-variables-service-type} instead.  @xref{Essential Home \
Services} for details.

Note: do not set @code{TERM} here, instead \
@xref{home-foot-configuration-term,,term}."
   (serializer serialize-list-section))
  (colors
   (maybe-foot-colors-configuration)
   "Color section of the configuration.
The color format is a 6 digit hex value in the form RRGGBB.  You can use \
@code{#xRRGGBB} to set these in guix.  For example setting the foreground and \
background color:
@lisp
(foot-color-configuration
 (foreground #x839496)
 (background #x002b36))
@end lisp"
   (serializer (serialize-foot-section-configuration
                foot-colors-configuration-fields)))
  (colors2
   (maybe-foot-colors-configuration)
   "Alternative color theme section of the configuration.  See foot.ini(5) man \
page for details."
   (serializer (serialize-foot-section-configuration
                foot-colors-configuration-fields)))
  (key-bindings
   (maybe-foot-key-bindings-configuration)
   "Key bindings section of the configuration."
   (serializer (serialize-foot-section-configuration
                foot-key-bindings-configuration-fields)))
  (search-bindings
   (maybe-foot-search-bindings-configuration)
   "Search bindings section of the configuration."
   (serializer (serialize-foot-section-configuration
                foot-search-bindings-configuration-fields)))
  (url-bindings
   (maybe-foot-url-bindings-configuration)
   "Url bindings section of the configuration."
   (serializer (serialize-foot-section-configuration
                foot-url-bindings-configuration-fields)))
  (text-bindings
    (maybe-list-of-string-pairs)
    "Text bindings section of the configuration."
    (serializer serialize-list-section))
  (mouse-bindings
   (maybe-foot-mouse-bindings-configuration)
   "Mouse-bindings section of the configuration."
   (serializer (serialize-foot-section-configuration
                foot-mouse-bindings-configuration-fields))))

(define (foot-configuration->file config)
  (mixed-text-file
   "foot.ini"
   (serialize-configuration config foot-configuration-fields)))

(define (foot-generate-documentation node documentation documentation-name)
  (format #f "@node ~a~%~a" node
	  (regexp-substitute/global
	    #f (make-regexp "@(end )?lisp")
	    (generate-documentation documentation
				    documentation-name)
	    'pre
	    (lambda (m)
	      (format #f "~%~a~%" (match:substring m)))
	    'post)))

(define (foot-configuration-documentation->file)
  (mixed-text-file "foot-configuration.texi"
                   (foot-generate-documentation
		     "Top"
		     `((foot-configuration ,foot-configuration-fields))
		     'foot-configuration)
                   (foot-generate-documentation
		     "Font"
		     `((foot-font-configuration ,foot-font-configuration-fields))
		     'foot-font-configuration)
                   (foot-generate-documentation
		     "Colors"
		     `((foot-colors-configuration ,foot-colors-configuration-fields))
		     'foot-colors-configuration)
                   (foot-generate-documentation
		     "Key Bindings"
		     `((foot-key-bindings-configuration ,foot-key-bindings-configuration-fields))
		     'foot-key-bindings-configuration)
                   (foot-generate-documentation
		     "Mouse Bindings"
		     `((foot-mouse-bindings-configuration ,foot-mouse-bindings-configuration-fields))
		     'foot-mouse-bindings-configuration)
                   (foot-generate-documentation
		     "Search Bindings"
		     `((foot-search-bindings-configuration ,foot-search-bindings-configuration-fields))
		     'foot-search-bindings-configuration)
                   (foot-generate-documentation
		     "URL Bindings"
		     `((foot-url-bindings-configuration ,foot-url-bindings-configuration-fields))
		     'foot-url-bindings-configuration)))

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
