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
             (gnu packages guile)
             (gnu packages version-control)
             (gnu packages wget)
             (gnu packages compression)
             (srfi srfi-1)
             (guix packages)    ; package-native-inputs, package-inputs
             (ice-9 match))     ; match-lambda

(use-service-modules base)

;; Collect all direct development inputs of the 'guix' package (native-inputs
;; and regular inputs).  Pre-installing these in the system image means that
;; 'guix shell -D guix' inside the container finds them already in the store
;; and does not need to fetch or build them during dev-env setup.
;;
;; IMPORTANT: The 'guix' package object used here must define the same input
;; versions as the guix binary that will run inside the container.  We
;; therefore configure the guix service with (current-guix), which builds the
;; binary from this very checkout.  That binary's module files define
;; 'guile-3.0-latest' and friends identically to the definitions below, so
;; 'guix shell -D guix' will find every input in the pre-populated store
;; without downloading anything.
(define %guix-dev-packages
  (filter-map
   (match-lambda
     ((_ (? package? p) . _) p)
     (_ #f))
   (append (package-native-inputs guix)
           (package-inputs guix))))

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
  ;; guile is also pre-installed.
  ;; %guix-dev-packages pre-populates the store with all direct inputs of
  ;; the 'guix' package so that 'guix shell -D guix' needs no network access
  ;; and no graft builds on first use.
  (packages (append
             %guix-dev-packages
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
  ;;
  ;; Use (current-guix) so the installed binary is built from this checkout.
  ;; Its module files then define the same package versions as %guix-dev-packages,
  ;; ensuring 'guix shell -D guix' finds all inputs in the store without
  ;; downloading anything.
  (services
   (list (service guix-service-type
                  (guix-configuration
                   (guix (current-guix))
                   ;; This container does not serve substitutes, so there is no
                   ;; need to generate a signing key pair.  Skipping it avoids
                   ;; blocking on entropy during system activation — the
                   ;; 'guix archive --generate-key' call in the activation
                   ;; script reads from /dev/random via gcrypt and can block
                   ;; indefinitely in an entropy-starved Docker environment.
                   ;; rngd-service-type cannot help here because rngd is a
                   ;; Shepherd-managed service that starts *after* activation.
                   (generate-substitute-key? #f)
                   ;; Allow builds without network by default; override at
                   ;; runtime with --substitute-urls.
                   (substitute-urls '("https://bordeaux.guix.gnu.org"
                                      "https://ci.guix.gnu.org"))))
         ;; Minimal logging.
         (service syslog-service-type)

         ;; Provide /bin/sh and /usr/bin/env symlinks that many build scripts
         ;; and shebangs rely on.  We add this service directly rather than
         ;; using extra-special-file, because extra-special-file extends
         ;; special-files-service-type which is not present when %base-services
         ;; is not used.
         (service special-files-service-type
                  `(("/bin/sh" ,(file-append bash "/bin/sh"))
                    ("/usr/bin/env" ,(file-append coreutils "/bin/env")))))))
