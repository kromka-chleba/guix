;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2017 Nikita <nikita@n0.is>
;;; Copyright © 2018 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2019 Efraim Flashner <efraim@flashner.co.il>
;;; Copyright © 2022 florhizome <florhizome@posteo.net>
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

(define-module (gnu packages cinnamon)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module (guix build utils)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system meson)
  #:use-module (guix build-system python)
  #:use-module (gnu packages)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages bootstrap)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages cups)
  #:use-module (gnu packages docbook)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages ghostscript)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gnuzilla)
  #:use-module (gnu packages ibus)
  #:use-module (gnu packages iso-codes)
  #:use-module (gnu packages kerberos)
  #:use-module (gnu packages libcanberra)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages nss)
  #:use-module (gnu packages password-utils)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages photo)
  #:use-module (gnu packages polkit)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages readline)
  #:use-module (gnu packages samba)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages web)
  #:use-module (gnu packages wm)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages xorg))

(define-public libadapta
  (package
    (name "libadapta")
    (version "1.5.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/xapp-project/libadapta")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "07zl1wswvqqxana1x59dxhpbm2biqn06jr5z0qvg03hdyh7isp2d"))))
    (build-system meson-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (add-before 'check 'pre-check
           (lambda* (#:key inputs #:allow-other-keys)
             ;; Tests require a running X server.
             (system "Xvfb :1 &")
             (setenv "DISPLAY" ":1"))))))
    (native-inputs
     (list gettext-minimal
           `(,glib "bin")
           gobject-introspection
           gtk-doc/stable
           pkg-config
           sassc
           vala
           xorg-server-for-tests))
    (propagated-inputs
     (list appstream gtk))
    (home-page "https://github.com/xapp-project/libadapta")
    (synopsis "Building blocks for GTK-based applications")
    (description
     "@code{libadapta} is a soft fork of @code{libadwaita}, providing support
for theming and features used in desktop environments outside of GNOME.")
    (license license:lgpl2.1+)))

(define-public libxapp
  (package
    (name "libxapp")
    (version "2.8.13")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/linuxmint/xapp/")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0i7pyib8s4hjf5k01gaw8nmckxi6haji4ngpj41y1ymq7y9k1cq9"))))
    (build-system meson-build-system)
    (arguments
     (list
      #:modules
      `((guix build meson-build-system)
        (guix build utils)
        ((guix build python-build-system) #:prefix python:))
      #:imported-modules
      `(,@%meson-build-system-modules
        (guix build python-build-system))
      #:configure-flags
      #~(list (string-append
               "-Dpy-overrides-dir="
               (python:site-packages %build-inputs %outputs) "/gi/overrides"))
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'configure 'set-gtk-module-path
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (substitute* "libxapp/meson.build"
                (("gtk3_dep\\.get_variable[(]pkgconfig: 'libdir'[)]")
                 (string-append "'" (assoc-ref outputs "out") "/lib'")))

              (substitute* "scripts/pastebin"
                (("'nc'")
                 (string-append "'"
                                (search-input-file inputs "/bin/nc")
                                "'")))

              (substitute* "scripts/upload-system-info"
                (("'inxi'")
                 (string-append "'"
                                (search-input-file inputs "/bin/inxi")
                                "'"))
                (("'/usr/bin/pastebin'")
                 (string-append "'"
                                (assoc-ref outputs "out")
                                "/bin/pastebin'"))
                (("'xdg-open'")
                 (string-append "'"
                                (search-input-file inputs "/bin/xdg-open")
                                "'"))))))))
    (inputs
     (list dbus
           glib                         ; for gio
           gtk+
           inxi-minimal                 ; used by upload-system-info
           libdbusmenu
           libgnomekbd
           netcat                       ; used by pastebin
           xdg-utils))                  ; used by upload-system-info
    (native-inputs
     (list gettext-minimal
           `(,glib "bin")               ; for glib-mkenums
           gobject-introspection
           pkg-config
           python
           python-pygobject
           vala))
    (home-page "https://github.com/linuxmint/xapp")
    (synopsis "Library for traditional GTK applications")
    (description
     "The libxapp package contains the components which are common to multiple
GTK desktop environments (Cinnamon, MATE and Xfce) and required to implement
cross-DE solutions.")
    (license license:lgpl3+)))

(define-public python-xapp
  (package
    (name "python-xapp")
    (version "2.4.2")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/linuxmint/python3-xapp")
             (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "06v84bvhhhx7lf7bsl2wdxh7vlkpb2fczjh6717b9jjr7xhvif8r"))))
    (build-system meson-build-system)
    (arguments
     (list
      #:tests? #f ; no tests provided
      #:imported-modules `((guix build python-build-system)
                           ,@%meson-build-system-modules)
      #:modules '((guix build utils)
                  (guix build meson-build-system)
                  ((guix build python-build-system)
                   #:prefix python:))))
    (native-inputs
     (list gobject-introspection
           intltool
           python-wrapper))
    (inputs
     (list libxapp))
    (propagated-inputs
     (list python-configobj
           python-distutils-extra
           python-pycairo
           python-pygobject
           python-pyinotify
           python-pyxdg
           python-setproctitle
           python-setuptools
           python-unidecode
           python-xdg
           python-xlib))
    (home-page "https://github.com/linuxmint/python3-xapp")
    (synopsis "Python 3 XApp library")
    (description
     "Provides Python 3 bindings for libxapp, including a toolkit to build and
persist XApp settings windows using GSettings.")
    (license license:lgpl2.0+)))

(define-public cjs
  (package
    (name "cjs")
    (version "6.4.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                     (url "https://github.com/linuxmint/cjs")
                     (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0gll1pdf9fk9as3ir8klnrbg6008pcygvjyzpdqpi8qfp9d0hnfs"))
              (modules '((guix build utils)))
              (snippet
               '(begin
                  (substitute* "installed-tests/scripts/testCommandLine.sh"
                    (("Valentín") "")
                    (("☭") ""))))))
    (build-system meson-build-system)
    (arguments
     '(#:configure-flags '("-Dinstalled_tests=false")
       #:phases
       (modify-phases %standard-phases
         (add-before 'check 'pre-check
           (lambda _
             ;; The test suite requires a running X server.
             (system "Xvfb :1 &")
             (setenv "DISPLAY" ":1")

             ;; For the missing /etc/machine-id.
             (setenv "DBUS_FATAL_WARNINGS" "0")))
         (add-after 'install 'wrap-gi
           (lambda* (#:key inputs outputs #:allow-other-keys)
             (wrap-program (string-append (assoc-ref outputs "out")
                                          "/bin/cjs")
               `("GI_TYPELIB_PATH" suffix
                 (,(dirname
                    (search-input-file
                     inputs
                     "lib/girepository-1.0/GObject-2.0.typelib"))
                  ,(dirname
                    (search-input-file
                     inputs
                     "lib/girepository-1.0/GIRepository-2.0.typelib"))))))))))
    (native-inputs
     (list `(,glib "bin")               ;for glib-compile-resources
           pkg-config
           libxml2
           ;; For testing
           dbus
           dconf                        ;required to properly store settings
           util-linux
           xorg-server-for-tests))
    (propagated-inputs
     ;; These are all in the Requires.private field of gjs-1.0.pc.
     ;; Check the version of mozjs required in meson.build.
     (list cairo gobject-introspection mozjs-115))
    (inputs
     (list gtk+ readline))
    (synopsis "Javascript bindings for Cinnamon")
    (home-page "https://github.com/linuxmint/cjs/")
    (description
     "CJS is a javascript binding for Cinnamon, forked from GJS.")
    (license license:gpl2+)))

(define-public cinnamon-control-center
  (package
    (name "cinnamon-control-center")
    (version "6.4.2")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/linuxmint/cinnamon-control-center")
              (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "1za37ynf8kckkmjc5n500fckynirw6ggg3s5wdlygpxkp2qz83lz"))))
    (build-system meson-build-system)
    (arguments
     (list
      #:glib-or-gtk? #t
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'configure 'patch-paths
            (lambda* (#:key inputs #:allow-other-keys)
              (substitute* '("panels/network/net-device-mobile.c"
                             "panels/network/connection-editor/net-connection-editor.c")
                (("\"nm-connection-editor")
                 (string-append "\"" (search-input-file
                                      inputs "bin/nm-connection-editor"))))))
          (add-after 'unpack 'skip-gtk-update-icon-cache
            ;; Don't create 'icon-theme.cache'.
            (lambda _
              (substitute* "meson.build"
                (("gtk_update_icon_cache: true")
                 "gtk_update_icon_cache: false"))))
          (replace 'check
            (lambda* (#:key parallel-tests? tests? #:allow-other-keys)
              (when tests?
                ;; Tests require a running X server.
                (system "Xvfb :1 &")
                (setenv "DISPLAY" ":1")
                ;; For the missing /var/lib/dbus/machine-id
                (setenv "DBUS_FATAL_WARNINGS" "0")
                (setenv "NO_AT_BRIDGE" "1")
                (setenv "HOME" "/tmp")
                (setenv "XDG_RUNTIME_DIR" (string-append (getcwd) "/runtime-dir"))
                (mkdir (getenv "XDG_RUNTIME_DIR"))
                (chmod (getenv "XDG_RUNTIME_DIR") #o700)
                (setenv "MESON_TESTTHREADS"
                        (if parallel-tests?
                            (number->string (parallel-job-count))
                            "1"))
                (invoke "dbus-run-session" "--"
                        "meson" "test" "-t" "0")))))))
    (native-inputs
     (list docbook-xsl
           gettext-minimal
           `(,glib "bin")               ;for glib-mkenums, etc.
           libxslt
           pkg-config
           python
           python-dbusmock
           xorg-server-for-tests
           setxkbmap))
    (inputs
     (list accountsservice
           cinnamon-desktop
           cinnamon-menus
           cinnamon-settings-daemon
           colord-gtk
           cups
           dconf
           gcr
           gnome-bluetooth
           gnome-online-accounts
           gnome-session
           gnutls
           grilo
           gsound
           ibus
           iso-codes
           json-glib
           libadwaita
           libgnomekbd
           libgudev
           libgtop
           libnma
           libnotify
           libpwquality
           (librsvg-for-system)             ;for loading SVG files
           libsecret
           libsoup
           libxml2
           libwacom
           mesa
           mit-krb5
           modem-manager
           network-manager-applet
           polkit
           pulseaudio
           samba
           tecla
           tzdata
           udisks
           upower))
    (synopsis "Utilities to configure the GNOME desktop")
    (home-page "https://www.gnome.org/")
    (description
     "This package contains configuration applets for the GNOME desktop,
allowing to set accessibility configuration, desktop fonts, keyboard and mouse
properties, sound setup, desktop theme and background, user interface
properties, screen resolution, and other GNOME parameters.")
    (license license:gpl2+)))

(define-public cinnamon-desktop
  (package
    (name "cinnamon-desktop")
    (version "6.4.2")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                     (url "https://github.com/linuxmint/cinnamon-desktop")
                     (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "15yq710rphidq35nk5d7dmd0cq0yiamp70ic9pwdqhj2zds5bp4h"))))
    (build-system meson-build-system)
    (arguments
     (list
      #:glib-or-gtk? #true
      #:configure-flags #~(list "-Dalsa=true")))
    (inputs
     (list accountsservice
           alsa-lib
           eudev
           glib
           gnome-common
           gtk+
           iso-codes
           libxrandr
           libxext
           pulseaudio
           xkeyboard-config))
    (propagated-inputs (list libxkbfile))
    (native-inputs
     (list gettext-minimal
           `(,glib "bin")               ;glib-gettextize
           gobject-introspection
           pkg-config))
    (home-page "https://github.com/linuxmint/cinnamon-desktop/")
    (synopsis "Library for the Cinnamon Desktop")
    (description
     "The cinnamon-desktop package contains the libcinnamon-desktop library,
as well as some desktop-wide documents.")
    (license (list license:gpl2+ license:lgpl2.0+
                   license:expat)))) ;display-name.c , edid-parse.c

(define-public cinnamon-menus
  (package
    (name "cinnamon-menus")
    (version "6.2.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/linuxmint/cinnamon-menus")
              (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "01k48gds0m2jkd0lchha5kcj0h68dkwir4lzn39a6xbx8mwsks0w"))))
    (build-system meson-build-system)
    (inputs (list glib))
    (native-inputs
     (list gettext-minimal gobject-introspection pkg-config))
    (synopsis "Menu support for Cinnamon desktop")
    (description "Cinnamon Menus contains the libcinnamon-menu library,
the layout configuration files for the Cinnamon menu, as well as a simple
menu editor.")
    (home-page "https://github.com/linuxmint/cinnamon-menus")
    (license license:lgpl2.0+)))

(define-public cinnamon-screensaver
  (package
    (name "cinnamon-screensaver")
    (version "6.4.1")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                     (url "https://github.com/linuxmint/cinnamon-screensaver")
                     (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32 "1fcxzvr34j4rpzpwbvz7lbgnjx9p1laizg2pyc4d4z0sj8zidbh8"))))
    (build-system meson-build-system)
    (inputs (list gtk+
                  linux-pam
                  xdotool))
    (native-inputs
     (list gettext-minimal `(,glib "bin") gobject-introspection pkg-config))
    (home-page "https://github.com/linuxmint/cinnamon-screensaver")
    (synopsis "Cinnamon Screensaver")
    (description "This package provides the Cinnamon screen locker and
screensaver program.")
    (license license:gpl2+)))

(define-public cinnamon-session
  (package
    (name "cinnamon-session")
    (version "6.4.2")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                     (url "https://github.com/linuxmint/cinnamon-session")
                     (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32 "19q6adhylppjxhrqj7v46hay9mdd4qxqcy17df0hy1nrqba5gzff"))))
    (build-system meson-build-system)
    (inputs (list cinnamon-desktop
                  glib
                  gtk+
                  libcanberra
                  libgnomekbd
                  libsm
                  libxapp
                  libxkbfile
                  xtrans))
    (native-inputs
     (list gettext-minimal `(,glib "bin") gobject-introspection pkg-config))
    (home-page "https://github.com/linuxmint/cinnamon-session")
    (synopsis "Cinnamon session manager")
    (description "his package contains the Cinnamon session manager,
as well as a configuration program to choose applications starting on login.")
    (license license:gpl2+)))

(define-public cinnamon-settings-daemon
  (package
    (name "cinnamon-settings-daemon")
    (version "6.4.3")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/linuxmint/cinnamon-settings-daemon")
              (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "12lf0lprdqcm1rlk13cnf7nq08dnphayjfmwlrfq18cq561qxgrg"))))
    (build-system meson-build-system)
    (arguments
     (list
      #:glib-or-gtk? #t
      #:configure-flags
      #~(list ;; Otherwise, the RUNPATH will lack the final path component.
              (string-append "-Dc_link_args=-Wl,-rpath=" #$output
                             "/lib/cinnamon-settings-daemon-3.0:"
                             ;; Also add NSS because for some reason Meson
                             ;; > 0.60 does not add it automatically (XXX).
                             (search-input-directory %build-inputs "lib/nss")))
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'configure 'set-baobab-file-name
            (lambda* (#:key inputs #:allow-other-keys)
              ;; Hard-code the file name of Baobab instead of looking
              ;; it up in $PATH.  This ensures users get the "Examine"
              ;; button in the low disk space notification of CDM even
              ;; if they don't have Cinnamon in their main profile.
              (substitute* "plugins/housekeeping/csd-disk-space.c"
                (("g_find_program_in_path \\(DISK_SPACE_ANALYZER\\)")
                 (format #f "g_strdup (~s)"
                         (search-input-file inputs "bin/baobab"))))))
          (add-after 'unpack 'skip-update-icon-cache
            (lambda _
              (substitute* "install-scripts/meson_update_icon_cache.py"
                (("gtk-update-icon-cache") "true")))))))
    (native-inputs
     (list docbook-xml-4.2
           docbook-xsl
           gettext-minimal
           `(,glib "bin")               ;for glib-mkenums
           libxslt
           perl
           pkg-config))
    (inputs
     (list alsa-lib
           baobab
           cinnamon-desktop
           colord
           cups
           gcr
           geoclue
           geocode-glib
           gsettings-desktop-schemas
           lcms
           libcanberra
           libgnomekbd
           libgudev
           libgweather
           libnotify
           (librsvg-for-system)
           libwacom
           libx11
           libxtst
           modem-manager
           network-manager
           nss
           polkit
           pulseaudio
           upower
           wayland
           xf86-input-wacom))
    (home-page "https://github.com/linuxmint/cinnamon-settings-daemon")
    (synopsis "Cinnamon settings daemon")
    (description
     "This package contains the daemon responsible for setting the various
parameters of a Cinnamon session and the applications that run under it.  It
handles settings such keyboard layout, shortcuts, and accessibility, clipboard
settings, themes, mouse settings, and startup of other daemons.")
    (license license:gpl2+)))

(define-public muffin
  (package
    (name "muffin")
    (version "6.4.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                     (url "https://github.com/linuxmint/muffin")
                     (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "1ndyx4dk9nq2dysrzw45np609k782hhdcqiz3w091njchvj8xa3s"))))
    (build-system meson-build-system)
    (arguments
     (list
      #:modules '((guix build meson-build-system)
                  (guix build utils)
                  (ice-9 match))
      #:glib-or-gtk? #t
      #:configure-flags
      #~(list
         ;; Otherwise, the RUNPATH will lack the final path component.
         (string-append "-Dc_link_args=-Wl,-rpath="
                        #$output "/lib,-rpath="
                        #$output "/lib/muffin")
         ;; Don't install tests.
         "-Dinstalled_tests=false"
         ;; The following flags are needed for the bundled clutter
         (string-append "-Dxwayland_path="
                        (search-input-file %build-inputs "bin/Xwayland"))
         ;; the remaining flags are needed for the bundled cogl
         (string-append "-Dopengl_libname="
                        (search-input-file %build-inputs "lib/libGL.so"))
         (string-append "-Dgles2_libname="
                        (search-input-file %build-inputs "lib/libGLESv2.so"))
         "-Degl_device=true"            ;false by default
         "-Dwayland_eglstream=true"     ;false by default
         )
      #:test-options #~(list "--verbose")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'set-SOURCE_DIR
            (lambda _
              ;; Just to make our life easier later.
              (setenv "SOURCE_DIR" (getcwd))))
          (add-after 'unpack 'use-RUNPATH-instead-of-RPATH
            (lambda _
              ;; The build system disables RUNPATH in favor of RPATH to work
              ;; around a peculiarity of their CI system.  Ignore that.
              (substitute* "meson.build"
                (("disable-new-dtags")
                 "enable-new-dtags"))))
          (add-after 'unpack 'patch-dlopen-calls
            (lambda* (#:key inputs #:allow-other-keys)
              (substitute* "src/wayland/meta-wayland-egl-stream.c"
                (("libnvidia-egl-wayland.so.1")
                 (search-input-file inputs "lib/libnvidia-egl-wayland.so.1")))))
          (add-before 'configure 'set-udev-dir
            (lambda _
              (setenv "PKG_CONFIG_UDEV_UDEVDIR"
                      (string-append #$output "/lib/udev"))))
          (add-after 'unpack 'disable-problematic-tests
            (lambda _
              (with-directory-excursion "src/tests"
                (substitute* "meson.build"
                  ;; The 'sync' variant of the X11 test fails for unknown reason
                  ;; (see: https://gitlab.gnome.org/GNOME/mutter/-/issues/3910).
                  (("foreach mode: \\['', 'sync'\\]")
                   "foreach mode: []")
                  ;; Many (all?) stacking tests are susceptible to fail
                  ;; non-deterministically under high load (see:
                  ;; https://gitlab.gnome.org/GNOME/mutter/-/issues/4035).
                  (("foreach stacking_test: stacking_tests")
                   "foreach stacking_test: []"))
                (substitute* "clutter/conform/meson.build"
                  ;; TODO: Re-instate the gesture test in a 47+ release.
                  ;; The conform/gesture test fails non-deterministically on
                  ;; some machines (see:
                  ;; https://gitlab.gnome.org/GNOME/mutter/-/issues/3521#note_2385427).
                  ((".*'gesture',.*") "")

                  ;; The 'event-delivery' test fails non-deterministically
                  ;; (see:
                  ;; https://gitlab.gnome.org/GNOME/mutter/-/issues/4035#note_2402672).
                  ((".*'event-delivery',.*") "")))))
          (replace 'check
            (lambda* (#:key tests? test-options parallel-tests?
                      #:allow-other-keys)
              (when tests?
                ;; Setup (refer to the 'test-mutter' and its dependents targets
                ;; in the '.gitlab-ci.yml' file.
                (setenv "HOME" "/tmp")
                (setenv "XDG_RUNTIME_DIR" (string-append (getcwd)
                                                         "/runtime-dir"))
                (mkdir (getenv "XDG_RUNTIME_DIR"))
                (chmod (getenv "XDG_RUNTIME_DIR") #o700)

                (setenv "GSETTINGS_SCHEMA_DIR" "data")
                (setenv "MUFFIN_DEBUG_DUMMY_MODE_SPECS" "800x600@10.0")
                (setenv "PIPEWIRE_DEBUG" "2")
                (setenv "PIPEWIRE_LOG" "meson-logs/pipewire.log")
                (setenv "XVFB_SERVER_ARGS" "+iglx -noreset")
                (setenv "G_SLICE" "always-malloc")
                (setenv "MALLOC_CHECK" "3")
                (setenv "NO_AT_BRIDGE" "1")

                (invoke "glib-compile-schemas" (getenv "GSETTINGS_SCHEMA_DIR"))
                (invoke "pipewire" "--version") ;check for pipewire

                (setenv "MESON_TESTTHREADS"
                        (if parallel-tests?
                            (number->string (parallel-job-count))
                            "1"))

                (apply invoke "xvfb-run" "-a" "-s" (getenv "XVFB_SERVER_ARGS")
                       "meson" "test" "-t" "0"
                       "--setup=plain"
                       "--no-suite=mutter/kvm"
                       "--no-rebuild"
                       "--print-errorlogs"
                       test-options)))))))
    (native-inputs
     (list desktop-file-utils           ;for update-desktop-database
           `(,glib "bin")               ;for glib-compile-schemas, etc.
           gettext-minimal
           gobject-introspection
           pkg-config
           xvfb-run
           wayland-protocols
           ;; For tests.
           ;; Warnings are configured to be fatal during the tests; add an icon
           ;; theme to please libxcursor.
           adwaita-icon-theme
           libei
           libxcursor                   ;for XCURSOR_PATH
           pipewire
           python
           python-dbus
           python-dbusmock
           wireplumber-minimal))
    (propagated-inputs
     (list gsettings-desktop-schemas
           at-spi2-core
           cairo
           eudev
           gdk-pixbuf
           glib
           gtk+
           graphene
           json-glib
           libinput
           libx11
           libxcomposite
           libxcvt
           libxdamage
           libxext
           libxfixes
           libxkbcommon
           libxml2
           libxrandr
           mesa
           pango
           xinput))
    (inputs
     (list colord
           egl-wayland                  ;for wayland-eglstream-protocols
           elogind
           cinnamon-desktop
           libcanberra
           libdisplay-info
           libgudev
           libice
           libsm
           libwacom
           libxkbfile
           libxrandr
           libxtst
           pipewire
           startup-notification
           sysprof
           upower
           xkeyboard-config
           xorg-server-xwayland))
    (home-page "https://github.com/linuxmint/muffin")
    (synopsis "Window and compositing manager")
    (description
     "Muffin is a  fork of Mutter, specifically adapted to work as the
window manager for the Cinnamon desktop environment.")
    (license license:gpl2+)))

(define-public nemo
  (package
    (name "nemo")
    (version "6.4.5")
    (source
     (origin
       (method git-fetch)
       (uri
        (git-reference
         (url "https://github.com/linuxmint/nemo")
         (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0bqii4cxh57knnsl7f76524y88yp37wcrjjyfhdg93aq5q2c55zl"))))
    (build-system meson-build-system)
    (arguments
     (list
      #:glib-or-gtk? #true
      #:tests? #false                   ;tests stall
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'patch-source-shebangs 'adjust-prefix
            (lambda _
              (substitute* "meson.build"
                (("'data_dir")
                 (string-append "'" #$output "/share")))))
          (add-before 'check 'pre-check
            (lambda _
              (system "Xvfb :1 &")
              (setenv "DISPLAY" ":1")
              (setenv "HOME" "/tmp")    ;some tests require a writable HOME
              (setenv "XDG_DATA_DIRS"
                      (string-append (getenv "XDG_DATA_DIRS")
                                     ":" #$output "/share")))))))
    (native-inputs
     (list gettext-minimal
           (list glib "bin")
           gobject-introspection
           (list gtk+ "bin")
           intltool
           pkg-config
           xorg-server-for-tests))
    (inputs
     (list atk
           cinnamon-desktop
           exempi
           gsettings-desktop-schemas
           gtk+
           json-glib
           libexif
           libgnomekbd
           libgsf
           libnotify
           libx11
           libxapp
           libxkbfile
           libxml2
           xkeyboard-config))
    (home-page "https://github.com/linuxmint/nemo")
    (synopsis "File browser for Cinnamon")
    (description
     "Nemo is the file manager for the Cinnamon desktop environment.")
    (properties '((lint-hidden-cpe-vendors . ("nvidia"))))
    (license license:expat)))
