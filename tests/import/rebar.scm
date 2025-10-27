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

(define-module (test-rebar)
  #:use-module (guix import rebar)
  #:use-module (guix base32)
  #:use-module (guix build-system rebar)
  #:use-module (gcrypt hash)
  #:use-module (guix read-print)
  #:use-module (guix tests)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-64)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 match))

(define test-rebar-lock-file
  "\
{\"1.2.0\",
[{<<\"xmpp\">>,{pkg,<<\"xmpp\">>,<<\"1.11.1\">>},1},
 {<<\"erlydtl\">>,
   {git,\"https://github.com/manuel-rubio/erlydtl.git\",
        {ref,\"dffa1a73ee2bfba14195b8b3964c39f007ff1284\"}},
   0},
 {<<\"yconf\">>,{pkg,<<\"yconf\">>,<<\"1.0.21\">>},0}]}.
[
{pkg_hash,[
 {<<\"xmpp\">>, <<\"60181E7D3E8E48AA3B23B2792075CDA37E2E507EC152490B866E61E5320CB1DA\">>},
 {<<\"yconf\">>, <<\"DBAE1589381E044529E112B7E0097C89D88DF89E446EAD53BD33E8D27E2BCC83\">>}]},
{pkg_hash_ext,[
 {<<\"xmpp\">>, <<\"A5C933DF904AB3CEC15425DA334E410CE84EC3AE7B81EFE069E5DB368A7B3716\">>},
 {<<\"yconf\">>, <<\"C524A5F1FD86875D85B469CC2E368C204F97CCA1C3918736E21F5001C01D096C\">>}]}
].")

(define temp-file
  (string-append "t-rebar-" (number->string (getpid))))

(test-begin "rebar")

(test-assert "rebar-lock-file-import"
  (begin
    (call-with-output-file temp-file
      (lambda (port)
        (display test-rebar-lock-file port)))
    (mock
     ((guix scripts download) guix-download
      (lambda _
        (format #t "~a~%~a~%"
                "/gnu/store/m43vixiijc26ni5p9zvbvjrs311h4fsm-erlydtl-dffa1a7"
                "1jhcfh0idadlh9999kjzx1riqjw0k05wm6ii08xkjvirhjg0vawh")))
     (let-values
         (((source-expressions beam-inputs-entry)
           (rebar-lock->expressions temp-file "test")))
       (and
        (match source-expressions
          ('((define beam-yconf-1.0.21
               (hexpm-source
                "yconf" "yconf" "1.0.21"
                "0v093p002l0zw8v8g4f3l769fkr0ihv2xk39nj2mv1w6zpqsa965"))
             (define beam-erlydtl-snapshot.dffa1a7
               (origin
                 (method git-fetch)
                 (uri
                  (git-reference
                    (url "https://github.com/manuel-rubio/erlydtl.git")
                    (commit "dffa1a73ee2bfba14195b8b3964c39f007ff1284")))
                 (file-name (git-file-name "beam-erlydtl" "snapshot.dffa1a7"))
                 (sha256
                  (base32
                   "1jhcfh0idadlh9999kjzx1riqjw0k05wm6ii08xkjvirhjg0vawh"))))
             (define beam-xmpp-1.11.1
               (hexpm-source
                "xmpp" "xmpp" "1.11.1"
                "05ipgf53dnz5d7hfz0bvmv1lxs0c85737ni5ak0wxcsaj3gk7jd5")))
           #t)
          (x
           (pk 'fail (pretty-print-with-comments (current-output-port) x) #f)))
        (match beam-inputs-entry
          (`(test => (list beam-yconf-1.0.21
                           beam-erlydtl-snapshot.dffa1a7
                           beam-xmpp-1.11.1))
           #t)
          (x
           (pk 'fail x #f))))))))

(test-end "rebar")

(false-if-exception (delete-file temp-file))
