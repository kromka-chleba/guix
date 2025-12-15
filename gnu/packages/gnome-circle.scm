;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Noé Lopez <noelopez@free.fr>
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

(define-module (gnu packages gnome-circle)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages rust)
  #:use-module (guix build-system cargo)
  #:use-module (guix build-system meson)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages))

(define-public resources
  ;; In-between commit with libadwaita 1.7. The 1.9.0 release has libadwaita 1.8
  ;; and the 1.8.0 release has libadwaita 1.6.
  (let ((commit "5c52cf627a7e2137fef2eea003b50ccd6d3a565")
        (revision "0"))
    (package
      (name "resources")
      (version (git-version "1.8.0" revision commit))
      (source (origin
                (method git-fetch)
                (uri (git-reference
                       (url "https://github.com/nokyan/resources")
                       (commit commit)))
                (file-name (git-file-name name version))
                (sha256
                 (base32
                  "0m5s07lwr9lpl2d09p2zp1fiy0xblllahpraazpq0m1x0cjyfbjs"))))
      (build-system meson-build-system)
      (arguments
       (list
        #:glib-or-gtk? #t
        #:imported-modules `(,@%meson-build-system-modules
                             ,@%cargo-build-system-modules)
        #:modules `(((guix build cargo-build-system) #:prefix cargo:)
                    (guix build meson-build-system)
                    (guix build utils))
        #:configure-flags #~(list "-Dprofile=default")
        #:phases
        (with-extensions (list (cargo-guile-json))
          #~(modify-phases %standard-phases
              (add-after 'unpack 'prepare-for-build
                (lambda _
                  (substitute* "meson.build"
                    (("gtk_update_icon_cache: true")
                     "gtk_update_icon_cache: false")
                    (("update_desktop_database: true")
                     "update_desktop_database: false")
                    (("glib_compile_schemas: true")
                     "glib_compile_schemas: false"))
                  (delete-file "Cargo.lock")
                  (delete-file "lib/process_data/Cargo.lock")))
              ;; This tests suites uses a different set of dependencies.
              ;; (add-after 'unpack 'disable-incompatible-tests
              ;;   (lambda _
              (add-after 'configure 'prepare-cargo-build-system
                (lambda args
                  (for-each
                   (lambda (phase)
                     (format #t "Running cargo phase: ~a~%" phase)
                     (apply (assoc-ref cargo:%standard-phases phase)
                            #:vendor-dir "vendor"
                            #:cargo-target #$(cargo-triplet)
                            args))
                   '(unpack-rust-crates
                     configure
                     check-for-pregenerated-files
                     patch-cargo-checksums))))))))
      (native-inputs
       (list gettext-minimal
             `(,glib "bin")
             pkg-config
             rust
             `(,rust "cargo")))
      (inputs
       (cons* gtk
              libadwaita
              (cargo-inputs 'resources)))
      (home-page "https://apps.gnome.org/Resources/")
      (synopsis "System resource and process monitor")
      (description "Resources is a simple yet powerful monitor for system
resources and processes, written in Rust and using GTK 4 and libadwaita for its
GUI.  It’s capable of displaying usage and details of your CPU, memory, GPUs,
NPUs, network interfaces and block devices.  It’s also capable of listing and
terminating running graphical applications as well as processes.")
      (license license:gpl3+))))
