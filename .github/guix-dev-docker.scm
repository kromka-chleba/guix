;; -*- mode: scheme; -*-
;; Guix system configuration for a Docker image providing the full
;; build/development environment for Guix development.
;;
;; This image is intended to be used by coding agents (e.g. GitHub Copilot)
;; to test newly-created packages, services, and other changes to Guix.
;;
;; Build with:
;;   guix system image --image-type=docker -L . .github/guix-dev-docker.scm
;; or using the build script:
;;   .github/bin/build-guix-docker.sh

(use-modules (gnu)
             (guix packages))
(use-service-modules base networking ssh)
(use-package-modules ssh)

(operating-system
  (host-name "guix-dev")
  (timezone "UTC")
  (locale "en_US.utf8")

  ;; No real user accounts needed; root access is fine for CI/agent use.
  (users %base-user-accounts)

  ;; Packages needed for Guix development and testing.
  ;; Resolved by name so no extra use-package-modules imports are required.
  (packages
   (append
    (map specification->package
         (list
          ;; Guix itself (for running 'guix build', 'guix package', etc.)
          "guix"

          ;; Core build toolchain
          "gcc-toolchain"
          "make"
          "autoconf"
          "automake"
          "libtool"
          "pkg-config"

          ;; Guile (the language Guix is written in)
          "guile"
          "guile-json"
          "guile-gcrypt"
          "guile-git"

          ;; Version control and patch submission
          "git"

          ;; Compression / archive tools
          "gzip"
          "bzip2"
          "xz"
          ;; Note: zstd is already included via %base-packages (%base-packages-utils)
          ;; and must not be listed here again: doing so would trigger a profile
          ;; conflict because specification->package resolves "zstd" to zstd-1.5.7
          ;; while %base-packages-utils binds the zstd variable to zstd-1.5.6.

          ;; Cryptography (signing, verification)
          "gnupg"

          ;; Documentation tools
          "texinfo"

          ;; Needed for 'make dist' / 'make distcheck'
          "imagemagick"
          "perl"

          ;; Network / download utilities
          "curl"
          "wget"

          ;; Scripting / text processing
          "python"
          "bash"

          ;; For installer tests
          "guile-newt"
          "guile-parted"
          "guile-webutils"))
    %base-packages))

  ;; Because the system runs in a Docker container, bootloader and file-system
  ;; entries are placeholders that Docker ignores.
  (bootloader (bootloader-configuration
               (bootloader grub-bootloader)
               (targets '("does-not-matter"))))
  (file-systems (list (file-system
                        (device "does-not-matter")
                        (mount-point "/")
                        (type "does-not-matter"))))

  ;; Services: extend %base-services (which already includes the Guix daemon
  ;; and syslogd) with an SSH server for interactive debugging if needed.
  (services
   (append
    (list
     ;; Provide the 'networking' shepherd provision so that openssh-service-type
     ;; (which requires it) starts correctly.  In Docker the network is
     ;; configured by the daemon externally, so dhcpcd acts as a lightweight
     ;; placeholder that satisfies the dependency.
     (service dhcpcd-service-type)

     ;; haveged for entropy generation in containers/VMs.
     ;; This speeds up SSH host key generation significantly.
     (service haveged-service-type)

     ;; OpenSSH for interactive access / debugging.
     (service openssh-service-type
              (openssh-configuration
               (openssh openssh-sans-x)
               ;; Permit root login for convenience inside the container.
               (permit-root-login #t)
               ;; No host-key checking required inside the container.
               (password-authentication? #t))))
    %base-services)))
