;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Igorj Gorjaĉev <igor@goryachev.org>
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

(define-module (gnu packages beam-packages)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system mix)
  #:use-module (guix build-system rebar)
  #:use-module (gnu packages beam-sources)
  #:export (;; TODO: lookup-mix-inputs
            lookup-rebar-inputs))

;;;
;;; This file is managed by ‘guix import’.  Do NOT add definitions manually.
;;;
;;; BEAM libraries fetched from hex.pm.
;;;

(define aaaa-separator 'begin-of-beam-packages)

(define beam-base64url-1.0.1
  (hexpm-source "base64url" "base64url" "1.0.1"
                "0p4zf53v86zfpnk3flinjnk6cx9yndsv960386qaj0hsfgaavczr"))

(define beam-cache-tab-1.0.33
  (hexpm-source "cache_tab" "cache_tab" "1.0.33"
                "002rqgikbdnzfkzw4n2wi6k03155pcqf4j68w2mjmcjhn2g00n22"))

(define beam-eimp-1.0.26
  (hexpm-source "eimp" "eimp" "1.0.26"
                "0k04abnna5vqd0r248car4xkfjc83p5z0iqy4w7w9pxrfa2lwvfr"))

(define beam-epam-1.0.14
  (hexpm-source "epam" "epam" "1.0.14"
                "12frsirp8m0ajdb19xi1g86zghhgvld5cgw459n2m9w553kljd1g"))

(define beam-eredis-1.7.1
  (hexpm-source "eredis" "eredis" "1.7.1"
                "1h9wihjqs4fmgr5ihqpisf7k99h006dsf71lygp5zmgycv2m8avw"))

(define beam-esip-1.0.59
  (hexpm-source "esip" "esip" "1.0.59"
                "1rpvsfm5y932wfra1mvkqhdabikmwqlh65bky52b3h4x6hy2xpqb"))

(define beam-ezlib-1.0.15
  (hexpm-source "ezlib" "ezlib" "1.0.15"
                "1arfjvipmfvz52szlsy6gn4s1x25spip6gljwv7za6jj29nbl56x"))

(define beam-fast-tls-1.1.25
  (hexpm-source "fast_tls" "fast_tls" "1.1.25"
                "08d894ckv6flwagngk5zwmgrwxz7nmrycsxap010wrqffjsq7qar"))

(define beam-fast-xml-1.1.57
  (hexpm-source "fast_xml" "fast_xml" "1.1.57"
                "0fcwj8yifwhr5m5maqa0ifwp7vad05d67ayxsmky9bxcmn84xhzf"))

(define beam-fast-yaml-1.0.39
  (hexpm-source "fast_yaml" "fast_yaml" "1.0.39"
                "13d7n1zjgvnkrxjk7riignqssrh952hs5x259vb6k4ibksmvkir4"))

(define beam-idna-6.1.1
  (hexpm-source "idna" "idna" "6.1.1"
                "1sjcjibl34sprpf1dgdmzfww24xlyy34lpj7mhcys4j4i6vnwdwj"))

(define beam-jiffy-1.1.2
  (hexpm-source "jiffy" "jiffy" "1.1.2"
                "10gkbi48in96bzkv7f2cqw9119krpd40whcsn0yd7fr0lx1bqqdv"))

(define beam-jose-1.11.10
  (hexpm-source "jose" "jose" "1.11.10"
                "0576jdjygby37qmzrs8cm5l6n622b0mi3z28j6r4s5xsz1px6v0d"))

(define beam-luerl-1.2.3
  (hexpm-source "luerl" "luerl" "1.2.3"
                "1v9svw2ki9dsaqazkgv23dj158pmx5g6lykqsb8q1lnpll69sjqv"))

(define beam-mqtree-1.0.19
  (hexpm-source "mqtree" "mqtree" "1.0.19"
                "0g6fz25j942ryc6m6c6iyb9hvs22v3i5l2pq28l8i8a9biqna468"))

(define beam-p1-acme-1.0.28
  (hexpm-source "p1_acme" "p1_acme" "1.0.28"
                "08v4shjng4gdq6nffsvckhs9lcj5rcipbs5ghp95z79zvs36js6f"))

(define beam-p1-mysql-1.0.26
  (hexpm-source "p1_mysql" "p1_mysql" "1.0.26"
                "1v7xz81wqx2c6ndl9rd3kq0v125209cbz7alrywijiy5ya1q04za"))

(define beam-p1-oauth2-0.6.14
  (hexpm-source "p1_oauth2" "p1_oauth2" "0.6.14"
                "13xfk4flaqb3nsxirf3vmy3yv67n6s6xzil7bafjswj39r3srlqz"))

(define beam-p1-pgsql-1.1.35
  (hexpm-source "p1_pgsql" "p1_pgsql" "1.1.35"
                "1hjmw82f6k2dpchgdn2i0j0bvi7m6qihcnvrjq36c721di2995g9"))

(define beam-p1-utils-1.0.28
  (hexpm-source "p1_utils" "p1_utils" "1.0.28"
                "0cq0gwd4vy51j1qq2c6p1i6nv98agvfjdy0sd6bdj2m4qi5x96y4"))

(define beam-pkix-1.0.10
  (hexpm-source "pkix" "pkix" "1.0.10"
                "03jxmjirg98r1zq7b1f3mnwm8pb1iac2iaxi85615jwl63w688g0"))

(define beam-sqlite3-1.1.15
  (hexpm-source "sqlite3" "sqlite3" "1.1.15"
                "0mr8kpv8hf4yknx8vbmyakgasrhk64ldsbafvr4svhi26ghs82rw"))

(define beam-stringprep-1.0.33
  (hexpm-source "stringprep" "stringprep" "1.0.33"
                "1h4qvajlsfqfg61c9f0rjf3rmha8sahvqiivnc2zd1q8ql5v7y4n"))

(define beam-stun-1.2.21
  (hexpm-source "stun" "stun" "1.2.21"
                "1n8j3vf8g2aq7i271lcm5202vzvvif5vz9m9d8528nyhp7pyhzrx"))

(define beam-unicode-util-compat-0.7.1
  (hexpm-source "unicode_util_compat" "unicode_util_compat" "0.7.1"
                "0hinn81kwkr3fvxb4vvp6qqnf19f23hd2jkl34v27bp39j2igadk"))

(define beam-xmpp-1.11.1
  (hexpm-source "xmpp" "xmpp" "1.11.1"
                "05ipgf53dnz5d7hfz0bvmv1lxs0c85737ni5ak0wxcsaj3gk7jd5"))

(define beam-yconf-1.0.21
  (hexpm-source "yconf" "yconf" "1.0.21"
                "0v093p002l0zw8v8g4f3l769fkr0ihv2xk39nj2mv1w6zpqsa965"))

(define cccc-separator 'end-of-beam-packages)


;;;
;;; Mix inputs.
;;;

;; TODO: (define-mix-inputs lookup-mix-inputs)


;;;
;;; Rebar inputs.
;;;

(define-rebar-inputs lookup-rebar-inputs
                     (ejabberd =>
                               (list beam-yconf-1.0.21
                                     beam-xmpp-1.11.1
                                     beam-unicode-util-compat-0.7.1
                                     beam-stun-1.2.21
                                     beam-stringprep-1.0.33
                                     beam-sqlite3-1.1.15
                                     beam-pkix-1.0.10
                                     beam-p1-utils-1.0.28
                                     beam-p1-pgsql-1.1.35
                                     beam-p1-oauth2-0.6.14
                                     beam-p1-mysql-1.0.26
                                     beam-p1-acme-1.0.28
                                     beam-mqtree-1.0.19
                                     beam-luerl-1.2.3
                                     beam-jose-1.11.10
                                     beam-jiffy-1.1.2
                                     beam-idna-6.1.1
                                     beam-fast-yaml-1.0.39
                                     beam-fast-xml-1.1.57
                                     beam-fast-tls-1.1.25
                                     beam-ezlib-1.0.15
                                     beam-esip-1.0.59
                                     beam-eredis-1.7.1
                                     beam-epam-1.0.14
                                     beam-eimp-1.0.26
                                     beam-cache-tab-1.0.33
                                     beam-base64url-1.0.1)))
