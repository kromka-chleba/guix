;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 Wilko Meyer <w@wmeyer.eu>
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

(define-module (gnu system images mnt-reform)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader u-boot)
  #:use-module (gnu image)
  #:use-module (gnu packages linux)
  #:use-module (guix platforms arm)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services networking)
  #:use-module (gnu services dbus)
  #:use-module (gnu services desktop)
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system keyboard)
  #:use-module (gnu system shadow)
  #:use-module (gnu system image)
  #:use-module (srfi srfi-26)
  #:export (mnt-reform-barebones-os mnt-reform-image-type
                                    mnt-reform-barebones-raw-image))

(define mnt-reform-initrd
  (list "rfkill"
        "dm_mod"
        "rk805_pwrkey"
        "hantro_vpu"
        "snd_soc_wm8960"
        "v4l2_vp9"
        "rockchip_saradc"
        "v4l2_h264"
        "v4l2_jpeg"
        "industrialio_triggered_buffer"
        "v4l2_mem2mem"
        "rockchip_thermal"
        "kfifo_buf"
        "snd_soc_rockchip_i2s_tdm"
        "videobuf2_dma_contig"
        "videobuf2_memops"
        "videobuf2_v4l2"
        "panthor"
        "videodev"
        "drm_gpuvm"
        "videobuf2_common"
        "drm_exec"
        "snd_soc_audio_graph_card"
        "mc"
        "drm_shmem_helper"
        "gpu_sched"
        "snd_soc_simple_card_utils"
        "pci_endpoint_test"
        "fuse"
        "x_tables"
        "ipv6"
        "onboard_usb_dev"
        "dwmac_rk"
        "stmmac_platform"
        "stmmac"
        "phy_rockchip_naneng_combphy"
        "phy_rockchip_usbdp"
        "typec"
        "rtc_pcf8523"
        "phy_rockchip_samsung_hdptx"
        "pcs_xpcs"
        "nvme"
        "nvme_core"
        "rockchipdrm"
        "analogix_dp"
        "dw_hdmi_qp"
        "dw_mipi_dsi"
        "ahci"
        "dm-crypt"
        "xts"))

(define mnt-reform-kernel-args
  (list "no_console_suspend"
        "cryptomgr.notests"
        "loglevel=3"
        "clk_ignore_unused"
        "cma=256M"
        "swiotlb=65535"
        "console=ttyS2,1500000"
        "fbcon=rotate:3"
        "fbcon=font:TER16x32"
        "console=tty1"))

(define mnt-reform-barebones-os
  (operating-system
    (host-name "reform")
    (timezone "Europe/Paris")
    (locale "en_US.utf8")
    (keyboard-layout (keyboard-layout "us" "altgr-intl"))
    ;; this creates a generic extlinux.conf that can be read by a probably
    ;; already present stock u-boot on MNT laptops. We can't include any
    ;; device-specific u-boot packages as they all require non-free blobs.
    (bootloader (bootloader-configuration
                  (bootloader u-boot-bootloader)))
    (file-systems (cons (file-system
                          (device (file-system-label "my-root"))
                          (mount-point "/")
                          (type "ext4")) %base-file-systems))
    (kernel linux-libre-arm64-mnt-reform)
    ;; the reform2-lpc module is needed for battery status and shutting down
    ;; the system properly from userspace.
    (kernel-loadable-modules (list reform2-lpc-module))
    (kernel-arguments mnt-reform-kernel-args)
    (initrd-modules mnt-reform-initrd)
    (users (cons* (user-account
                    (name "guest")
                    (group "users")
                    (supplementary-groups '("wheel" "netdev" "audio" "video")))
                  %base-user-accounts))
    (services
     (cons* (service elogind-service-type)
            (service wpa-supplicant-service-type)
            (service network-manager-service-type)
            (service dbus-root-service-type) %base-services))))

(define mnt-reform-image-type
  (image-type (name 'mnt-reform-raw)
              (constructor (lambda (os)
                             (image (inherit (raw-with-offset-disk-image (* 16
                                                                            (expt
                                                                             2
                                                                             20))))
                                    (operating-system
                                      os)
                                    (platform aarch64-linux))))))

(define mnt-reform-barebones-raw-image
  (image (inherit (os+platform->image mnt-reform-barebones-os aarch64-linux
                                      #:type mnt-reform-image-type))
         (name 'mnt-reform-barebones-raw-image)))

mnt-reform-barebones-raw-image
