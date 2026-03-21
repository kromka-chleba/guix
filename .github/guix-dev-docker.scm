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
;;   .github/bin/build-guix-docker.scm

(use-modules (gnu)
             (guix packages))
(use-service-modules base dbus desktop docker networking)

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

          ;; Container tooling – Docker daemon + CLI so the image can build
          ;; and push Docker images without an external Docker installation.
          ;; docker-service-type (below) starts the daemon via Shepherd.
          "docker"
          "containerd"

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

  ;; Services: %base-services already includes the Guix daemon and syslogd.
  ;; No SSH server is needed—use 'docker exec' to get a shell inside the
  ;; container, which avoids the SSH host-key entropy wait entirely.
  ;; Disable substitute key generation: generating an RSA key pair requires
  ;; entropy which is scarce in containers and causes a long hang at startup.
  ;; This Docker image is only used for building/testing, not for serving
  ;; substitutes, so the key is not needed.
  ;; The container is run with --cap-add=SYS_ADMIN (not --privileged), which
  ;; gives Docker a private cgroup namespace.  Shepherd therefore mounts
  ;; cgroup2 at /sys/fs/cgroup without an EBUSY conflict, and the full
  ;; dependency chain (file-systems → user-processes → guix-daemon) completes
  ;; normally with plain elogind-service-type.
  ;; dbus-root-service-type is required by docker-service-type.
  ;; containerd-service-type and docker-service-type together start the Docker
  ;; daemon (containerd + dockerd) managed by Shepherd.  containerd must be
  ;; listed explicitly because docker-service-type no longer bundles it.
  ;; docker-service-type requires a 'networking' shepherd service.
  ;; dhcpcd-service-type provides 'networking' and configures the container's
  ;; Ethernet interface via DHCP, which is exactly what Docker's virtual
  ;; network expects.
  (services
   (cons* (service dbus-root-service-type)
          (service elogind-service-type)
          (service containerd-service-type)
          (service docker-service-type)
          (service dhcpcd-service-type)
          (modify-services %base-services
            (guix-service-type
             config => (guix-configuration
                        (inherit config)
                        (generate-substitute-key? #f)))))))
