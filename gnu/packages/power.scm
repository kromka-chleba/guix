;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Tomas Volf <~@wolfsden.cz>
;;; Copyright © 2023 Raven Hallsby <karl@hallsby.com>
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
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system gnu)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages avahi)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages documentation)
  #:use-module (gnu packages docbook)
  #:use-module (gnu packages engineering)
  #:use-module (gnu packages freeipmi)
  #:use-module (gnu packages gd)
  #:use-module (gnu packages libusb)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages man)
  #:use-module (gnu packages networking)
  #:use-module (gnu packages nss)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages version-control))

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

(define-public nut
  (package
    (name "nut")
    (version "2.8.4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/networkupstools/nut")
              (commit (string-append "v" version))))
       (sha256
        (base32 "1b64v0bxjn4s6ch3bb1nxycf3qch38jixwnamyhx8rp4bqd70p1r"))
       (file-name (git-file-name name version))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:configure-flags
      #~(list ;; "--with-docs" ;; TODO: Enable docs
              "--with-python3"
              ;; Build & install development headers
              "--with-dev"
              ;; Add SSL & NSS support
              "--with-ssl"
              ;; "--with-nss"
              "--with-openssl"
              ;; Build all the drivers we can support
              "--with-all"
              "--with-impi" "--with-freeimpi"
              "--with-cgi"
              "--with-powerman=no" ; Powerman library not available
              ;; FIXME: Turn PyNUT on.
              ;; Attempts to install to "system-wide" Python, which is RO for us
              "--with-pynut=no"
              ;; State directories.
              "--with-statepath=/run"
              "--with-pidpath=/run"
              ;; FIXME: Set udev & devd dirs
              ;; "--with-udev-dir=blah"
              ;; "--with-devd-dir=blah"
              ;; Guix does not use systemd, disable those featuers
              "--with-libsystemd=no")
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'bootstrap 'fix-autogen
            (lambda _
              ;; Make bootstrap scripts use Guix-encoded values
              (substitute* "autogen.sh"
                ;; Use the version string we have in Guix
                (("^(NUT_VERSION_QUERY=).*$" _ version-var)
                 (string-append version-var #$version "\n")))
              (substitute* "configure.ac"
                ;; Use Guix's version. Remember to add the trailing comma!
                (("m4_esyscmd_s\\(\\[NUT_VERSION_QUERY=VER50.*")
                 (string-append #$version ","))
                ;; Use Guix's URL to the home-page. Remember to add end paren!
                (("m4_esyscmd_s\\(\\[NUT_VERSION_QUERY=URL.*")
                 (string-append #$(package-home-page this-package) ")")))
              ;; Forcibly set CONFIG_SHELL so autogen.sh trusts us that this is
              ;; the shell to use.
              (setenv "CONFIG_SHELL" #$(file-append bash-minimal "/bin/bash")))))))
    (native-inputs
     (list autoconf automake libtool pkg-config
           bash-minimal
           ;; Generate documentation
           ;; mandoc asciidoc dblatex
           ;; Perl & Python used in setup scripts.
           perl python))
    (inputs
     (list avahi
           freeipmi
           gd
           i2c-tools
           libgpiod
           libmodbus
           libltdl
           libusb libusb-compat
           neon
           net-snmp
           ;; nss-certs
           openssl
           zlib))
    (home-page "https://networkupstools.org/")
    (synopsis "Provides support for power devices")
    (description "Network UPS Tools (NUT) provides support for Power
Devices, such as Uninterruptible Power Supplies, Power Distribution Units,
Automatic Transfer Switches, Power Supply Units and Solar Controllers. NUT
provides a common protocol and set of tools to monitor and manage such devices,
and to consistently name equivalent features and data points, across a vast
range of vendor-specific protocols and connection media types.")
    (license (list
              ;; Perl module
              license:gpl1+
              ;; Donated Scripts/Installer and Source
              license:gpl2+
              ;; Python scripts
              license:gpl3+))))
