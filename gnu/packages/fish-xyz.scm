;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Luis Guilherme Coelho <lgcoelho@disroot.org>
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

(define-module (gnu packages fish-xyz)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages terminals)
  #:use-module (gnu packages rust-apps)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix utils))

(define-public fish-foreign-env
  (package
    (name "fish-foreign-env")
    (version "0.20230823")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/oh-my-fish/plugin-foreign-env")
             (commit "7f0cf099ae1e1e4ab38f46350ed6757d54471de7")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0d16mdgjdwln41zk44qa5vcilmlia4w15r8z2rc3p49i5ankksg3"))))
    (build-system trivial-build-system)
    (arguments
     '(#:modules ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils))
         (let* ((source (assoc-ref %build-inputs "source"))
                (out (assoc-ref %outputs "out"))
                (func-path (string-append out "/share/fish/functions")))
           (mkdir-p func-path)
           (copy-recursively (string-append source "/functions")
                             func-path)

           ;; Embed absolute paths.
           (substitute* `(,(string-append func-path "/fenv.fish")
                          ,(string-append func-path "/fenv.main.fish"))
             (("bash")
              (search-input-file %build-inputs "/bin/bash"))
             (("sed")
              (search-input-file %build-inputs "/bin/sed"))
             ((" tr ")
              (string-append " "
                             (search-input-file %build-inputs "/bin/tr")
                             " ")))))))
    (inputs
     (list bash coreutils sed))
    (home-page "https://github.com/oh-my-fish/plugin-foreign-env")
    (synopsis "Foreign environment interface for fish shell")
    (description "@code{fish-foreign-env} wraps bash script execution in a way
that environment variables that are exported or modified get imported back
into fish.")
    (license license:expat)))

(define-public fish-fzf
  (package
    (name "fish-fzf")
    (version "10.3")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/PatrickF1/fzf.fish")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1hqqppna8iwjnm8135qdjbd093583qd2kbq8pj507zpb1wn9ihjg"))))
    (build-system copy-build-system)
    (arguments
     (list #:install-plan
           #~'(("completions" "share/fish/")
               ("conf.d" "share/fish/")
               ("functions" "share/fish/"))
           #:phases
           #~(modify-phases %standard-phases
               (add-after 'unpack 'patch-scripts
                 (lambda* (#:key inputs #:allow-other-keys)
                   (let ((bat (search-input-file inputs "bin/bat"))
                         (fd  (search-input-file inputs "bin/fd"))
                         (fzf (search-input-file inputs "bin/fzf")))
                     (substitute* "functions/_fzf_wrapper.fish"
                       (("fzf \\$argv") (string-append fzf " $argv")))
                     (substitute* "functions/_fzf_search_directory.fish"
                       (("set -f fd_cmd .*")
                        (string-append "set -f fd_cmd " fd "\n")))
                     (substitute* "functions/_fzf_preview_file.fish"
                       (("bat") bat))))))))
    (inputs
     (list bat fd fzf))
    (home-page "https://github.com/PatrickF1/fzf.fish")
    (synopsis "Mnemonic key bindings for using fzf within the Fish shell")
    (description "This package aims to augment your Fish shell with mnemonic
key bindings to efficiently find what you need using fzf.")
    (license license:expat)))
