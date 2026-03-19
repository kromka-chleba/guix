;; -*- mode: scheme; -*-
;; Guix system configuration for a Docker image providing the full
;; build/development environment for Guix development.
;;
;; This image is intended to be used by coding agents (e.g. GitHub Copilot)
;; to test newly-created packages, services, and other changes to Guix.
;;
;; Build with:
;;   guix system image --image-type=docker .github/guix-dev-docker.scm
;; or using the build script:
;;   .github/bin/build-guix-docker.sh

(use-modules (gnu)
             (guix packages))
(use-service-modules guix ssh)
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
          "nss-certs"

          ;; Compression / archive tools
          "gzip"
          "bzip2"
          "xz"
          "zstd"

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

  ;; Services: run a Guix daemon so agents can build packages inside the
  ;; container, and an SSH server for interactive debugging if needed.
  (services
   (list
    ;; Guix daemon – required to run any 'guix build' / 'guix package' commands.
    (service guix-service-type)

    ;; OpenSSH for interactive access / debugging.
    (service openssh-service-type
             (openssh-configuration
              (openssh openssh-sans-x)
              ;; Permit root login for convenience inside the container.
              (permit-root-login 'yes)
              ;; No host-key checking required inside the container.
              (password-authentication? #t))))))
