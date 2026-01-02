;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Tomas Volf <~@wolfsden.cz>
;;; Copyright © 2023 Raven Hallsby <karl@hallsby.com>
;;; Copyright © 2026 Giacomo Leidi <therewasa@fishinthecalculator.me>
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

;;;; Commentary:

;;; Power-related packages.

;;;; Code:

(define-module (gnu packages power)
  #:use-module (gnu packages)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages disk)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages instrumentation)
  #:use-module (gnu packages libusb)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages man)
  #:use-module (gnu packages networking)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages ruby-xyz)
  #:use-module (gnu packages virtualization)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system pyproject)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages))

(define-public apcupsd
  (package
    (name "apcupsd")
    (version "3.14.14")
    (source (origin
              (method url-fetch)
              (uri
               (string-append
                "mirror://sourceforge/" name "/" name " - Stable/" version
                "/" name "-" version ".tar.gz"))
              (sha256
               (base32
                "0rwqiyzlg9p0szf3x6q1ppvrw6f6dbpn2rc5z623fk3bkdalhxyv"))))
    (outputs '("out" "doc"))
    (build-system gnu-build-system)
    (arguments
     (list
      #:configure-flags
      #~(list
         ;; The configure script ignores --prefix for most of the file names.
         (string-append "--exec-prefix=" #$output)
         (string-append "--mandir=" #$output "/share/man")
         (string-append "--sbindir=" #$output "/sbin")
         (string-append "--sysconfdir=" #$output "/etc/apcupsd")
         (string-append "--with-halpolicydir=" #$output "/share/halpolicy")

         ;; Put us into the version string.
         "--with-distname=GNU Guix"
         "--disable-install-distdir"

         ;; State directories.
         "--localstatedir=/var"
         "--with-log-dir=/var/log"
         "--with-pid-dir=/run"
         "--with-lock-dir=/run/apcupsd/lock"
         "--with-nologin=/run/apcupsd"
         "--with-pwrfail-dir=/run/apcupsd"

         ;; Configure requires these, but we do not use the genenerated
         ;; apcupsd.conf, so in order to reduce dependencies of the package,
         ;; provide fake values.
         (string-append "ac_cv_path_SHUTDOWN=/nope")
         (string-append "ac_cv_path_APCUPSD_MAIL=/nope")
         ;; While `wall' is not expanded anywhere, it still is searched for.
         ;; See https://sourceforge.net/p/apcupsd/mailman/message/59128628/ .
         (string-append "ac_cv_path_WALL=/nope")

         ;; Enable additional drivers.
         "--enable-usb"
         "--enable-modbus-usb")
      #:tests? #f                       ; There are no tests.
      #:modules (cons '(ice-9 ftw) %default-gnu-modules)
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'configure 'remove-time-from-manual
            (lambda _
              ;; Do not bake the date and time of the build into the manual.
              (substitute* "doc/manual/manual.rst"
                (("\\| \\|date\\| \\|time\\|") ""))
              (substitute* "autoconf/variables.mak.in"
                (("^(RST2HTMLOPTS = .*) --time (.*)" all pref suff)
                 (string-append pref " " suff)))))
          (add-after 'build 'build-manual
            (lambda _
              (invoke "make" "-C" "doc/manual" "manual.html")))
          (add-after 'install-license-files 'move-doc
            (lambda _
              (let ((target (string-append #$output:doc
                                           "/share/doc/"
                                           (strip-store-file-name #$output))))
                (mkdir-p target)
                (for-each (lambda (f)
                            (copy-file (string-append "doc/manual/" f)
                                       (string-append target "/" f)))
                          (scandir "doc/manual"
                                   (lambda (f)
                                     (or (string-suffix? ".png" f)
                                         (string-suffix? ".html" f))))))))
          ;; If sending mails is required, use proper mail program.
          (add-after 'install 'remove-smtp
            (lambda _
              (delete-file (string-append #$output "/sbin/smtp"))))
          ;; The configuration files and scripts are not really suitable for
          ;; Guix, and our service provides its own version anyway.  So delete
          ;; these to make sure `apcupsd' and `apctest' executed without any
          ;; arguments fail.  `apctest' actually segfaults, but only after
          ;; printing an error.
          (add-after 'install 'remove-etc-apcupsd
            (lambda _
              (delete-file-recursively
               (string-append #$output "/etc/apcupsd")))))))
    (native-inputs (list mandoc pkg-config python-docutils-0.19 util-linux))
    (inputs (list libusb libusb-compat))
    (home-page "http://www.apcupsd.org")
    (synopsis "Daemon for controlling APC UPSes")
    (description "@command{apcupsd} can be used for power management and
controlling most of @acronym{APC, American Power Conversion}’s @acronym{UPS,
Uninterruptible Power Supply} models.  @command{apcupsd} works with most of
APC’s Smart-UPS models as well as most simple signalling models such a
Back-UPS, and BackUPS-Office.")
    (license license:gpl2)))

(define-public tuned-minimal
  (package
    (name "tuned-minimal")
    (version "2.26.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                     (url "https://github.com/redhat-performance/tuned")
                     (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0r4a42s2hk9hcrp835164yzddmvr8n4b17bhhpwxx16iiaizramn"))
              (patches (search-patches "tuned-minimal-remove-tty-tests.patch"))))
    (build-system pyproject-build-system)
    (arguments
       (list
        #:imported-modules `((guix build glib-or-gtk-build-system)
                             ,@%pyproject-build-system-modules)
        #:modules '((guix build pyproject-build-system)
                    ((guix build glib-or-gtk-build-system) #:prefix glib-or-gtk:)
                    (guix build utils))
        #:phases
        #~(let ((make-flags
                 (lambda (tuned-python)
                   (list
                    (string-append "PYTHON=" tuned-python)
                    (string-append "PREFIX=" #$output)
                    (string-append "PYTHON_SITELIB=" #$output "/lib/python"
                                   (python-version tuned-python)
                                   "/site-packages")
                    (string-append "SYSCONFDIR=" #$output "/etc")
                    (string-append "TMPFILESDIR=" #$output "/run/tuned")))))
            (modify-phases %standard-phases
              (add-after 'unpack 'patch-paths
                (lambda _
                  (substitute* "Makefile"
                    ;; These directories do not make sense on Guix.
                    (("mkdir -p \\$\\(DESTDIR\\)/var/lib/tuned") "")
                    (("mkdir -p \\$\\(DESTDIR\\)/var/log/tuned") "")
                    (("mkdir -p \\$\\(DESTDIR\\)/run/tuned") "")
                    (((string-append "install -Dpm 0644 tuned\\.service "
                                     "\\$\\(DESTDIR\\)\\$\\(UNITDIR\\)/tuned"
                                     "\\.service"))
                     "")
                    (((string-append "install -Dpm 0644 tuned/ppd/"
                                     "tuned-ppd\\.service \\$\\(DESTDIR\\)"
                                     "\\$\\(UNITDIR\\)/tuned-ppd\\.service"))
                     ""))
                  ;; Substitute FHS paths with Guix ones.
                  (substitute* "experiments/powertop2tuned.py"
                    (("/usr/sbin/powertop")
                     (which "powertop"))
                    (("/usr/lib/tuned/functions")
                     (string-append #$output "/lib/tuned/functions")))
                  (substitute* "tuned-gui.desktop"
                    (("Exec=/usr/sbin/tuned-gui")
                     (string-append "Exec=" #$output "/sbin/tuned-gui")))
                  (for-each
                   (lambda (source)
                     (substitute* source
                       (("/usr/sbin/tuned-gui")
                        (string-append #$output "/sbin/tuned-gui"))
                       (("/usr/share/tuned/ui/tuned-gui.glade")
                        (string-append #$output
                                       "/share/tuned/ui/tuned-gui.glade"))))
                   (list "tuned-gui.py" "tuned/gtk/tuned_dialog.py"))
                  (for-each
                   (lambda (source)
                     (substitute* source
                       ;; TuneD really wants to write to
                       ;; /etc/modprobe.d/tuned.conf . Guix manages this file
                       ;; declaratively, so the default location for TuneD is
                       ;; is changed to a file where it can actually write.
                       (("/etc/modprobe\\.d/tuned\\.conf")
                        "/etc/tuned/modprobe.d/tuned.conf")
                       (("/usr/lib")
                        (string-append #$output "/lib"))
                       (("/usr/share")
                        (string-append #$output "/share"))))
                   (append '("tuned-adm.bash" "tuned/consts.py")
                           (find-files "profiles"
                                       (lambda (name stat)
                                         (and (string-suffix? ".sh" name)
                                              (eq? 'regular (stat:type stat))
                                              (access? name X_OK))))))))
              ;; There is nothing to build except documentation.
              ;; https://github.com/redhat-performance/tuned/blob/v2.26.0/INSTALL#L4 and
              ;; https://github.com/redhat-performance/tuned/blob/v2.26.0/tuned.spec
              (replace 'build
                (lambda _
                  (apply invoke
                         `("make" "html" ,@(make-flags (which "python"))))))
              (replace 'install
                (lambda _
                  ;; Install TuneD.
                  (apply invoke
                         `("make" "install" ,@(make-flags (which "python"))))
                  ;; Install power-profiles-daemon compatibility layer.
                  (apply invoke
                         `("make" "install-ppd" ,@(make-flags (which "python"))))
                  ;; Install HTML documentation.
                  (apply invoke
                         `("make" "install-html" ,@(make-flags (which "python"))))
                  ;; tuned-gui depends on systemctl being available.  Drop it
                  ;; until it'll be compatible with other init systems.
                  (delete-file (string-append #$output "/sbin/tuned-gui"))
                  (delete-file
                   (string-append
                    #$output "/share/applications/tuned-gui.desktop"))))
              (add-after 'wrap 'wrap-binaries
                (lambda _
                  (let ((gui (string-append #$output
                                            "/sbin/tuned-gui"))
                        (python-sitelib
                         (string-append "lib/python"
                                        (python-version (which "python"))
                                        "/site-packages"))
                        (bin (string-append #$output "/bin"))
                        (sbin (string-append #$output "/sbin")))
                    (for-each
                     (lambda (bindir)
                       (for-each
                        (lambda (binary)
                          (use-modules (srfi srfi-1))
                          (define this-package-inputs
                            (map second '#$(package-inputs this-package)))
                          (wrap-program binary
                            `("GI_TYPELIB_PATH" ":" prefix
                              ,(search-path-as-list
                                '("lib/girepository-1.0")
                                this-package-inputs))
                            `("GUIX_PYTHONPATH" ":" prefix
                              ,(search-path-as-list
                                 (list python-sitelib)
                                 this-package-inputs))
                            `("PATH" ":" prefix
                              ,(search-path-as-list
                                '("bin" "sbin" "libexec")
                                this-package-inputs))))
                        (find-files bindir
                                    (lambda (name stat)
                                      (not
                                       (string-prefix? "." (basename name)))))))
                     (list bin sbin)))))
              (add-after 'wrap-binaries 'glib-or-gtk-wrap
                (assoc-ref glib-or-gtk:%standard-phases 'glib-or-gtk-wrap))
              (replace 'check
                (lambda _
                  (apply invoke
                         `("make" "test" ,@(make-flags (which "python"))))))))))
    (native-inputs (list desktop-file-utils
                         gnu-make
                         pkg-config
                         ruby-asciidoctor))
    (inputs
     (list bash-minimal
           ethtool
           gawk
           glib
           hdparm
           kmod
           iproute
           powertop
           python-dbus
           python-pyinotify
           python-linux-procfs
           python-pygobject
           python-pyudev
           systemtap
           util-linux
           virt-what))
    (synopsis
     "Dynamic adaptive system tuning daemon")
    (description
     "The TuneD package contains a daemon that tunes system settings
dynamically.  It does so by monitoring the usage of several system components
periodically.  Based on that information components will then be put into lower
or higher power saving modes to adapt to the current usage.")
    (home-page "https://tuned-project.org")
    (license (list license:gpl2+ license:cc-by-sa3.0))))

(define-public tuned
  (package
    (inherit tuned-minimal)
    (name "tuned")
    (inputs
     (modify-inputs (package-inputs tuned-minimal)
       (prepend dmidecode perf wireless-tools)))))
