;; -*- mode: scheme; -*-
;; This is the Guix operating system configuration for the personal development
;; Docker image used with the kromka-chleba/guix repository.
;;
;; NOT official Guix project infrastructure.  This image is maintained for
;; personal development/testing of package and service changes.
;;
;; Build with (from a guix checkout, using pre-inst-env):
;;   ./pre-inst-env guix system image --image-type=docker \
;;       .github/docker/guix-dev-system.scm

(use-modules (gnu)
             (gnu services)
             (gnu services base)
             (gnu services guix)
             (gnu packages base)
             (gnu packages bash)
             (gnu packages package-management)
             (gnu packages version-control)
             (gnu packages wget)
             (gnu packages compression))

(use-service-modules base networking)

(operating-system
  (host-name "guix-dev")
  (timezone "UTC")
  (locale "en_US.utf8")

  ;; User accounts.
  (users (cons* (user-account
                 (name "dev")
                 (comment "Guix developer")
                 (group "users")
                 (home-directory "/home/dev")
                 (supplementary-groups '("wheel")))
                %base-user-accounts))

  ;; Packages available system-wide inside the container.
  ;; nss-certs is already included in %base-packages; no need to list it here.
  (packages (append
             (list bash
                   git
                   wget
                   gzip
                   tar)
             %base-packages))

  ;; Bootloader/file-systems are ignored for Docker images, but Guix requires
  ;; them to be present in the configuration.
  (bootloader (bootloader-configuration
               (bootloader grub-bootloader)
               (targets '("does-not-matter"))))
  (file-systems (list (file-system
                        (device "does-not-matter")
                        (mount-point "/")
                        (type "does-not-matter"))))

  ;; Services: keep it minimal — Guix daemon is the key service.
  ;; nscd is omitted intentionally (Docker provides name resolution via the
  ;; --network option).
  (services
   (list (service guix-service-type
                  (guix-configuration
                   (guix guix)
                   ;; Allow builds without network by default; override at
                   ;; runtime with --substitute-urls.
                   (substitute-urls '("https://bordeaux.guix.gnu.org"
                                      "https://ci.guix.gnu.org"))))
         ;; Minimal logging.
         (service syslog-service-type))))
