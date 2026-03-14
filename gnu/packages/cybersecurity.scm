;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2020 Jakub Kądziołka <kuba@kadziolka.net>
;;; Copyright © 2020, 2021 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2021 c4droid <c4droid@foxmail.com>
;;; Copyright © 2021 Raghav Gururajan <rg@raghavgururajan.name>
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>
;;; Copyright © 2025 Sharlatan Hellseher <sharlatanus@gmail.com>
;;; Copyright © 2025 Artyom V. Poptsov <poptsov.artyom@gmail.com>
;;; Copyright © 2026 Cayetano Santos <csantosb@inventati.org>
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

(define-module (gnu packages cybersecurity)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix build-system cmake)
  #:use-module (guix build-system pyproject)
  #:use-module (guix build-system python)
  #:use-module (guix build-system trivial)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages check)
  #:use-module (gnu packages cpp)
  #:use-module (gnu packages engineering)
  #:use-module (gnu packages java)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-compression)
  #:use-module (gnu packages python-crypto)
  #:use-module (gnu packages python-web)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages serialization)
  #:use-module (gnu packages time)
  #:use-module (gnu packages emulators)
  #:use-module (gnu packages gcc))

(define-public blacksmith
  (package
    (name "blacksmith")
    (version "0.0.2")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/comsec-group/blacksmith")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "15ib0lal2sdjb4j2a4r3645w5axbd1a6j8w9f0pxr8v3ra9cjp5m"))
              (modules '((guix build utils)))
              (snippet `(begin
                          (delete-file-recursively "external")
                          (substitute* "CMakeLists.txt"
                            (("add_subdirectory\\(external\\)") "")
                            (("[ \t]*FetchContent_MakeAvailable\\(asmjit\\)")
                             (string-append
                              "find_package(asmjit)\n"
                              "find_package(nlohmann_json)")))))))
    (build-system cmake-build-system)
    (arguments
     `(#:tests? #f                      ;no test-suite
       #:imported-modules
       ((guix build copy-build-system)
        ,@%cmake-build-system-modules)
       #:modules
       (((guix build copy-build-system) #:prefix copy:)
        (guix build cmake-build-system)
        (guix build utils))
       #:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'fix-build
           (lambda _
             (substitute* "CMakeLists.txt"
               ;; Use default C++ standard instead.
               (("cxx_std_17") "")
               ;; This project tries to link argagg library, which doesn't
               ;; exist, as argagg project is a single header file.
               (("argagg") ""))))
         (replace 'install
           (lambda args
             (apply (assoc-ref copy:%standard-phases 'install)
                    #:install-plan
                    '(("." "bin" #:include ("blacksmith"))
                      ("." "lib" #:include-regexp ("\\.a$")))
                    args))))))
    (native-inputs
     (list pkg-config))
    (inputs
     (list argagg asmjit nlohmann-json))
    (home-page "https://comsec.ethz.ch/research/dram/blacksmith")
    (synopsis "Rowhammer fuzzer with non-uniform and frequency-based patterns")
    (description
     "Blacksmith is an implementation of Rowhammer fuzzer that crafts novel
non-uniform Rowhammer access patterns based on the concepts of frequency,
phase, and amplitude.  It is able to bypass recent @acronym{TRR, Target Row
Refresh}in-DRAM mitigations effectively and as such can trigger bit flips.")
    (license license:expat)))

(define-public gallia
  (package
    (name "gallia")
    (version "2.0.2")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/Fraunhofer-AISEC/gallia")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1yvjpwpqq6r6glfm4qzb8j91d2gsfy4lvygd9z9pg2j6jvcq6f6s"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      #:build-backend "poetry.core.masonry.api" ;XXX: python-uv-build is required
      ;; NOTE: Test steps are sourced from GitHub Actions attached to the
      ;; project. This is a minimal test suite, more precise tests require
      ;; setting up local service with Bats (Bash Automated Testing System)
      ;; <https://bats-core.readthedocs.io/en/stable/>. bs
      #:test-flags #~(list "tests/pytest")))
    (native-inputs
     (list python-poetry-core
           python-pygit2
           python-pytest
           python-pytest-asyncio))
    (inputs
     (list python-aiofiles
           python-aiosqlite
           python-argcomplete
           python-boltons
           python-can
           python-construct
           python-exitcode
           python-httpx
           python-more-itertools
           python-msgspec
           python-platformdirs
           python-psutil
           python-pydantic
           python-pygit2
           python-tabulate
           python-zstandard))
    (home-page "https://github.com/Fraunhofer-AISEC/gallia")
    (synopsis "Extendable Pentesting Framework")
    (description
     "Gallia is an extendable pentesting framework with the focus on the
automotive domain.  The scope of the toolchain is conducting penetration tests
from a single ECU up to whole cars.")
    (license license:apsl2)))

;;; Helper to create a url-fetch origin for a single Maven JAR.
(define (maven-jar group artifact version hash)
  (let* ((group-path (string-join (string-split group #\.) "/"))
         (jar-name   (string-append artifact "-" version ".jar"))
         (url        (string-append "https://repo1.maven.org/maven2/"
                                    group-path "/" artifact "/" version
                                    "/" jar-name)))
    (origin
      (method url-fetch)
      (uri url)
      (sha256 (base32 hash)))))

;;; Individual Maven JARs required by the Ghidra build.
(define %ghidra-maven-jars
  ;; (name . origin) pairs used to populate the flatRepo.
  `(("antlr-runtime-3.5.2.jar"
     . ,(maven-jar "org.antlr" "antlr-runtime" "3.5.2"
                   "1kizr3nb23rrx6iwvp5v5kim1lkjv76ks2qy33kgwwy3p4w9r1rl"))
    ("antlr-3.5.2.jar"
     . ,(maven-jar "org.antlr" "antlr" "3.5.2"
                   "0nn3dhmczc50yg9pvbz21ddmf3r68gid006693a4a0y2ff5ychyz"))
    ("ST4-4.0.8.jar"
     . ,(maven-jar "org.antlr" "ST4" "4.0.8"
                   "0n6amg20r7vln2srjgyqd3hgcjjhq1sr1576l98smbxdk3nzqyiv"))
    ("asm-9.7.1.jar"
     . ,(maven-jar "org.ow2.asm" "asm" "9.7.1"
                   "135dshxcbsvd17g0bypcr8wbj5x082xr2ff7xpmlrj0wfh5p2cl1"))
    ("asm-analysis-9.7.1.jar"
     . ,(maven-jar "org.ow2.asm" "asm-analysis" "9.7.1"
                   "11djjdqqhjx33fvnxpr268y2q971fb1jcyk72lpblg8wrhp087pj"))
    ("asm-commons-9.7.1.jar"
     . ,(maven-jar "org.ow2.asm" "asm-commons" "9.7.1"
                   "16jpkdad54mdkghp3m1i7za77733an9c5ddc792rpg8h976xxim0"))
    ("asm-tree-9.7.1.jar"
     . ,(maven-jar "org.ow2.asm" "asm-tree" "9.7.1"
                   "1699i0gmksvbhh78dma5f33pnnfff8fi0kkdzmx415w9j71d7d0z"))
    ("asm-util-9.7.1.jar"
     . ,(maven-jar "org.ow2.asm" "asm-util" "9.7.1"
                   "1y45prqvbj85avsz3b8w9y97dclvjq2pqjbx8rk6zr6xpv1wnhy6"))
    ("baksmali-2.5.2.jar"
     . ,(maven-jar "org.smali" "baksmali" "2.5.2"
                   "07nj6qk6szf4j1xavq5ik8sgfzpsq99l5diwib755rbr0fcl3cw9"))
    ("bcpkix-jdk18on-1.80.jar"
     . ,(maven-jar "org.bouncycastle" "bcpkix-jdk18on" "1.80"
                   "0ksblsljc5za37f1hgqglpdljbpf89pxvqm0lbbcjivpzz8syr0k"))
    ("bcprov-jdk18on-1.80.jar"
     . ,(maven-jar "org.bouncycastle" "bcprov-jdk18on" "1.80"
                   "1s5d42gqqn6jj6iprabm1sg9zb30b5lmdjc3wjfxha13h7fqncj9"))
    ("bcutil-jdk18on-1.80.jar"
     . ,(maven-jar "org.bouncycastle" "bcutil-jdk18on" "1.80"
                   "08pcls3zg5al27s5dbrkwvm8ws7wfg6q1jwb6am5yylb30kxgikq"))
    ("biz.aQute.bnd.util-7.0.0.jar"
     . ,(maven-jar "biz.aQute.bnd" "biz.aQute.bnd.util" "7.0.0"
                   "0fapblah4jcn5af6sincwzk75rvpr2l642hx5li0qzrc19wrwxi3"))
    ("biz.aQute.bndlib-7.0.0.jar"
     . ,(maven-jar "biz.aQute.bnd" "biz.aQute.bndlib" "7.0.0"
                   "1055d780dwrfj9ffwk78my96nzkgvamanp6bzmgy9jfdzyf4vlnz"))
    ("commonmark-0.23.0.jar"
     . ,(maven-jar "org.commonmark" "commonmark" "0.23.0"
                   "1clm0q8q7760q33f4p087qx6n8lmxg1jg0rfq1rkwzcvpjaffkmk"))
    ("commonmark-ext-footnotes-0.23.0.jar"
     . ,(maven-jar "org.commonmark" "commonmark-ext-footnotes" "0.23.0"
                   "0qq2i9ymx5gfr3i6xq229ca1z1z9vaawf62g59d4kfs3vyym7c84"))
    ("commonmark-ext-gfm-tables-0.23.0.jar"
     . ,(maven-jar "org.commonmark" "commonmark-ext-gfm-tables" "0.23.0"
                   "0ngknqddhwn230xq5v50a9yph6na8m712xyp3669g5djfiyif2vv"))
    ("commonmark-ext-heading-anchor-0.23.0.jar"
     . ,(maven-jar "org.commonmark" "commonmark-ext-heading-anchor" "0.23.0"
                   "1v7dpcxminvj1ihkaz0vw6x16ajw3rwwrsz03w6kv6inwm94435x"))
    ("commons-codec-1.18.0.jar"
     . ,(maven-jar "commons-codec" "commons-codec" "1.18.0"
                   "1fh0bwq4rvwjlggdw953ibasr6wazk7hv3vmhffnq4rqcd6ggxp4"))
    ("commons-collections4-4.1.jar"
     . ,(maven-jar "org.apache.commons" "commons-collections4" "4.1"
                   "1cgyidcnidbxhijl4lspxlnrvilma12iignjvxdmcp2birlc3j55"))
    ("commons-compress-1.27.1.jar"
     . ,(maven-jar "org.apache.commons" "commons-compress" "1.27.1"
                   "0a9xh3slnlvbfh4mvkbylg7hladvzhs04lcjh4rj95gl886kf38n"))
    ("commons-dbcp2-2.9.0.jar"
     . ,(maven-jar "org.apache.commons" "commons-dbcp2" "2.9.0"
                   "123p428jqp5vrpznw3i1sl1ljdsmby7zqnbkh7pziykpycyfdmjf"))
    ("commons-io-2.19.0.jar"
     . ,(maven-jar "commons-io" "commons-io" "2.19.0"
                   "10j2d28rnjv2z7s0y2658f0xwnckn1wgb1k7wcrd2ws8mq0rswmr"))
    ("commons-lang3-3.20.0.jar"
     . ,(maven-jar "org.apache.commons" "commons-lang3" "3.20.0"
                   "0sg5r7x3bnksa6jzs84rvzjnlbcd6b7j6gigdmvhwyb18r204qzl"))
    ("commons-logging-1.2.jar"
     . ,(maven-jar "commons-logging" "commons-logging" "1.2"
                   "1nnxx8ga1ghgasbqmcq0df5cja1lmzpgpndpwkk32vyaazghz9in"))
    ("commons-pool2-2.11.1.jar"
     . ,(maven-jar "org.apache.commons" "commons-pool2" "2.11.1"
                   "1sh50pp7a5g5icdc1rl6wk8sbngpv04f4ld63g1p3ah5jnwrcgw3"))
    ("commons-text-1.10.0.jar"
     . ,(maven-jar "org.apache.commons" "commons-text" "1.10.0"
                   "0xqcv41zlyv09lgpxxxs2zw42236faab5d3qps7d3brvzysaw00q"))
    ("dex-ir-2.4.24.jar"
     . ,(maven-jar "com.googlecode.d2j" "dex-ir" "2.4.24"
                   "1rq0fl5pj1jqzaqdbiw2ys51zgf5hzpqlagqncn82szr4p998n80"))
    ("dex-reader-2.4.24.jar"
     . ,(maven-jar "com.googlecode.d2j" "dex-reader" "2.4.24"
                   "0jhz1c8rxs2kznxjp7jprh8772n90v8i3a5nn0ilv9wg93ffn6mj"))
    ("dex-reader-api-2.4.24.jar"
     . ,(maven-jar "com.googlecode.d2j" "dex-reader-api" "2.4.24"
                   "104vrlcxrb6nk6x090n2fk9j1dlx5qa722c7bf65axr9mbjr7i5c"))
    ("dex-translator-2.4.24.jar"
     . ,(maven-jar "com.googlecode.d2j" "dex-translator" "2.4.24"
                   "1maby6asw16yzm56ri01pxc68k9lrqlwf05rafjz03vz3mxh7njm"))
    ("dexlib2-2.5.2.jar"
     . ,(maven-jar "org.smali" "dexlib2" "2.5.2"
                   "0njwi61digbxdqxv383i614y7iwbf6gc6ar0ysv1k22wxhqa1pb1"))
    ("failureaccess-1.0.1.jar"
     . ,(maven-jar "com.google.guava" "failureaccess" "1.0.1"
                   "18bixr676kfjva1pwjqnpsfz8rhszavjlhddmwqyp16zvbwkdji6"))
    ("flatlaf-3.5.4.jar"
     . ,(maven-jar "com.formdev" "flatlaf" "3.5.4"
                   "0g1lnspb5wbhm5ac8dc68zml7dlb8ix2qd8zyc8hfbviayjx9qpy"))
    ("gson-2.9.0.jar"
     . ,(maven-jar "com.google.code.gson" "gson" "2.9.0"
                   "1jbdc1ai6cd1jvdcajvlbak45k87ivw9nvr6f53bf1gjqb5yy19d"))
    ("guava-32.1.3-jre.jar"
     . ,(maven-jar "com.google.guava" "guava" "32.1.3-jre"
                   "0vaf5dd132mbcbkfbqlx31d0497fv0n8bi0aqg9krw2a4w63nds4"))
    ("h2-2.2.220.jar"
     . ,(maven-jar "com.h2database" "h2" "2.2.220"
                   "15wap1ih339zjrg3i205f71n54zaic8ah231jharqkax42shy2jp"))
    ("hamcrest-2.2.jar"
     . ,(maven-jar "org.hamcrest" "hamcrest" "2.2"
                   "0pk2him8kw2wsy6dkhd5agrl1l028n1q1hr08mfx3y7wajbsi8f1"))
    ("isorelax-20050913.jar"
     . ,(maven-jar "msv" "isorelax" "20050913"
                   "0d172lj33kvzjrzr5rlybjn1c53wbn7v9d75m2kjyllig27grzwc"))
    ("javahelp-2.0.05.jar"
     . ,(maven-jar "javax.help" "javahelp" "2.0.05"
                   "1z7lj8nkizw5317is8r865xvc216w56sjj5bsq3fwgaviim71pmx"))
    ("jdom-legacy-1.1.3.jar"
     . ,(maven-jar "org.jdom" "jdom-legacy" "1.1.3"
                   "00mxc6kjbs5gkc0pdd1vyac1dl6792wap58khnyi4yz3fj4k4nha"))
    ("jgrapht-core-1.5.1.jar"
     . ,(maven-jar "org.jgrapht" "jgrapht-core" "1.5.1"
                   "196q235n7q57g9sks53hjkzakpa2x0ngqmxa52grz192kwk08fxl"))
    ("jgrapht-io-1.5.1.jar"
     . ,(maven-jar "org.jgrapht" "jgrapht-io" "1.5.1"
                   "11n7zikcq687pz16ndkd9p995k8dla3bvqgx12513h6rfafnvk2w"))
    ("jheaps-0.13.jar"
     . ,(maven-jar "org.jheaps" "jheaps" "0.13"
                   "0qs18a8c6jbzib0g20i0j83hi3gc8vylfiz0ymm2dilk13l5qr0m"))
    ("jna-5.14.0.jar"
     . ,(maven-jar "net.java.dev.jna" "jna" "5.14.0"
                   "0d7d3qgjgyl9dg551ny4x6fg6wr9cz7c71x7l3ay6j3c15kkzs66"))
    ("jna-platform-5.14.0.jar"
     . ,(maven-jar "net.java.dev.jna" "jna-platform" "5.14.0"
                   "1bjcmkmkhh3k1hjkgydpzdas06xbln02hss14aai925wxraqq929"))
    ("joda-time-2.14.0.jar"
     . ,(maven-jar "joda-time" "joda-time" "2.14.0"
                   "07idlvwynrgj18jxk8qqd0qysarzn57plj71xy10c4sywn6b2hyk"))
    ("jung-algorithms-2.1.1.jar"
     . ,(maven-jar "net.sf.jung" "jung-algorithms" "2.1.1"
                   "1v8kiqpnnarg2fpn389z2y4brrpivs45ii1fww57shg650wkg8qa"))
    ("jung-api-2.1.1.jar"
     . ,(maven-jar "net.sf.jung" "jung-api" "2.1.1"
                   "0v5p6nb3qdnm2mfhvrgik81lhnws4vk7al71c2rxv280k9pm2saf"))
    ("jung-graph-impl-2.1.1.jar"
     . ,(maven-jar "net.sf.jung" "jung-graph-impl" "2.1.1"
                   "0j8iv82dfysggfs6b9jswg63l00cmr6m5dc7j4g3q2sc9dj394y1"))
    ("jung-visualization-2.1.1.jar"
     . ,(maven-jar "net.sf.jung" "jung-visualization" "2.1.1"
                   "14rvl9n26263px2ndhw2i5wvd2np88kj8mqp2bjsy3g8fsyzz8mf"))
    ("jungrapht-layout-1.4.jar"
     . ,(maven-jar "com.github.tomnelson" "jungrapht-layout" "1.4"
                   "18q404lxqfgd4ckb6v51biil88pfayd4c5w6d3wr8hp3icz60w4r"))
    ("jungrapht-visualization-1.4.jar"
     . ,(maven-jar "com.github.tomnelson" "jungrapht-visualization" "1.4"
                   "15q578fx5kdb4qzvaq8z3g42p1ib62czjlg3rl2n9qz27lckykfq"))
    ("junit-4.13.2.jar"
     . ,(maven-jar "junit" "junit" "4.13.2"
                   "13j9bdil8sfn9ywaryiljnh6bjxcr2hgzxaww7ii01xy9hbdqmyk"))
    ("jython-standalone-2.7.4.jar"
     . ,(maven-jar "org.python" "jython-standalone" "2.7.4"
                   "07xs2xlyzz68n6gmw423dg42fjhmiklqhmcz4mwjghjcffxi6zrw"))
    ("lisa-analyses-0.1.jar"
     . ,(maven-jar "io.github.lisa-analyzer" "lisa-analyses" "0.1"
                   "04z263n8i93xkz8lz4jg165rg0w8g3phvnzg6rh5qs9w4wsanpxq"))
    ("lisa-program-0.1.jar"
     . ,(maven-jar "io.github.lisa-analyzer" "lisa-program" "0.1"
                   "0p9dmggp3gnnv0a6ddjz3y8jvs1kqpvc7as6a2jg6za7hxyq6l56"))
    ("lisa-sdk-0.1.jar"
     . ,(maven-jar "io.github.lisa-analyzer" "lisa-sdk" "0.1"
                   "1vjvss97fi2li3w3rw2hly7ai2hyp9dkrwa4zn6as8rpfs2jw6n4"))
    ("log4j-api-2.25.3.jar"
     . ,(maven-jar "org.apache.logging.log4j" "log4j-api" "2.25.3"
                   "1s46d0lj1yhgp7bfnqwmvjsdw2448gw68v49qpjq8vhniqr7yh3g"))
    ("log4j-core-2.25.3.jar"
     . ,(maven-jar "org.apache.logging.log4j" "log4j-core" "2.25.3"
                   "0dibgz5nbdrslinc9g2kmgsfn8bg8i587dfil0vwnvyzzw5fkw7r"))
    ("log4j-slf4j-impl-2.17.1.jar"
     . ,(maven-jar "org.apache.logging.log4j" "log4j-slf4j-impl" "2.17.1"
                   "1sd06whfbm87c04w4lq66pd9s228bqla1c7c41q8vbf53bxpir0y"))
    ("msv-20050913.jar"
     . ,(maven-jar "msv" "msv" "20050913"
                   "055y79ahwl446fsgw43pbma0x7mmiczg0knp8mmwgiyjhp4hr1x2"))
    ("olcut-config-protobuf-5.2.0.jar"
     . ,(maven-jar "com.oracle.labs.olcut" "olcut-config-protobuf" "5.2.0"
                   "1ikahvj69zc25xqwxvl9p4jkg5y3vkyzcmn4vcmzjvd4f7mrgcya"))
    ("olcut-core-5.2.0.jar"
     . ,(maven-jar "com.oracle.labs.olcut" "olcut-core" "5.2.0"
                   "1r9yiq4hmm16iliallz0d0mvpsmir0g2ra242gx46q1a85izdghr"))
    ("org.apache.felix.framework-7.0.5.jar"
     . ,(maven-jar "org.apache.felix" "org.apache.felix.framework" "7.0.5"
                   "1ax754rcbzz55ldfkyvkahalfjy861gx0kq51s2iyflgczd1hd7x"))
    ("org.osgi.util.promise-1.3.0.jar"
     . ,(maven-jar "org.osgi" "org.osgi.util.promise" "1.3.0"
                   "0w2kqmz7szc8zv3bj2brlfpi4phx5fw4f9la6a52y7nnbb8a9hc5"))
    ("phidias-0.3.7.jar"
     . ,(maven-jar "com.github.rotty3000" "phidias" "0.3.7"
                   "1j6hfq6f7c7d2i9x8ddwvlqy6kqbwfn0j0jfgqd9if53rszllsxm"))
    ("postgresql-42.7.9.jar"
     . ,(maven-jar "org.postgresql" "postgresql" "42.7.9"
                   "127izhwr5s0fqfq4ixwq0c79l0aaliw3qh5gnmnkwyl7xq5dy5kg"))
    ("protobuf-java-4.31.0.jar"
     . ,(maven-jar "com.google.protobuf" "protobuf-java" "4.31.0"
                   "0s3p7p6ddk2q6npplx47b77cypm21zq864vf713zpsa5fawf1vba"))
    ("protobuf-java-util-4.31.0.jar"
     . ,(maven-jar "com.google.protobuf" "protobuf-java-util" "4.31.0"
                   "1x0x1pvg21z5fgj2kdajhrvv6lc4r7a4m2w8skviyxmk39d1ihx9"))
    ("relaxngDatatype-20050913.jar"
     . ,(maven-jar "msv" "relaxngDatatype" "20050913"
                   "0ka5m4zbbkf34qqrcrkkr5abhgy9nq50d0dvvp7glb29fv84rpgj"))
    ("sevenzipjbinding-16.02-2.01.jar"
     . ,(maven-jar "net.sf.sevenzipjbinding" "sevenzipjbinding" "16.02-2.01"
                   "04rwlgv9r33kbn4rgh4lfx84yj59ybk1x9xp0jrp2jlhcsqyzf4f"))
    ("sevenzipjbinding-all-platforms-16.02-2.01.jar"
     . ,(maven-jar "net.sf.sevenzipjbinding" "sevenzipjbinding-all-platforms"
                   "16.02-2.01"
                   "0wpsnlx9scg1dmjkzqgl000is0m7ysy6m4g8cd5mrynmrqax8rxv"))
    ("slf4j-api-1.7.25.jar"
     . ,(maven-jar "org.slf4j" "slf4j-api" "1.7.25"
                   "0664l04msp0xlsw1fn9ffrxv4g99vlpmc2np9pvmzwwn3nyy4nvr"))
    ("slf4j-nop-1.7.25.jar"
     . ,(maven-jar "org.slf4j" "slf4j-nop" "1.7.25"
                   "0v5i4w9qyhdmm1lzkv6x0qdd2xwrl3izwwh4c03rf5afn11jxsqj"))
    ("timingframework-1.0.jar"
     . ,(maven-jar "net.java.dev.timingframework" "timingframework" "1.0"
                   "0x31x4j6qfq534b4b9zr9h84d06c6635pd6r2842mh1gyxqj1ksb"))
    ("tribuo-classification-core-4.2.0.jar"
     . ,(maven-jar "org.tribuo" "tribuo-classification-core" "4.2.0"
                   "1ypvz4x74awsnm1fx1wsbx7na5wnwk5fl6v7k06maqpyipcdpag6"))
    ("tribuo-classification-tree-4.2.0.jar"
     . ,(maven-jar "org.tribuo" "tribuo-classification-tree" "4.2.0"
                   "1fas6cnr4j7d2aaq65v49ka3swp6vn5dw2i4z754wlns0yysqqx7"))
    ("tribuo-common-tree-4.2.0.jar"
     . ,(maven-jar "org.tribuo" "tribuo-common-tree" "4.2.0"
                   "1pw8m8hn9zjzml44rciijyrf18fnq4z4xl3fwp11jxmfn3draz79"))
    ("tribuo-core-4.2.0.jar"
     . ,(maven-jar "org.tribuo" "tribuo-core" "4.2.0"
                   "0d2w6dyw51wfqx82961amc374wcvffg733kksyib5vz8nvax02dz"))
    ("tribuo-math-4.2.0.jar"
     . ,(maven-jar "org.tribuo" "tribuo-math" "4.2.0"
                   "1v6nbn28zxj8h0bh9fds1xqacinl0c10rggd4qgxfda8393rcm8j"))
    ("tribuo-util-onnx-4.2.0.jar"
     . ,(maven-jar "org.tribuo" "tribuo-util-onnx" "4.2.0"
                   "18hp02mqkjq7bz74zi940dczj768z2vz4hl95mjv0gx8fnnjrpav"))
    ("util-2.5.2.jar"
     . ,(maven-jar "org.smali" "util" "2.5.2"
                   "0ksq1afgygmvhg5kzlhbxj4f6zjg30vrdjk54wr9j9hic8185npa"))
    ("xsdlib-20050913.jar"
     . ,(maven-jar "msv" "xsdlib" "20050913"
                   "0swfz8cgymqc14bdlw1c8s86p7la2fg1q1fvy7jdiggbl92c3cmk"))
    ("xz-1.9.jar"
     . ,(maven-jar "org.tukaani" "xz" "1.9"
                   "088v61ngqi7qz5nz7853vnppbflcaa4yxmvxc3bjz24vp1azadg5"))))

;;; Non-Maven third-party JARs bundled with Ghidra.
(define %ghidra-extra-jars
  `(("AXMLPrinter2.jar"
     . ,(origin
          (method url-fetch)
          (uri "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/android4me/AXMLPrinter2.jar")
          (sha256
           (base32
            "007d0f7bdaxgdpgcilh2lgnpm0dm452qyk6lb6a825fgs0pzb7bd"))))
    ("java-sarif-2.1-modified.jar"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/flatRepo/java-sarif-2.1-modified.jar")
          (sha256
           (base32
            "0zvkcmk4jisns9qslpjb3bvci7f51l3lmcf66x54gpw249j24sq1"))))))

;;; FunctionID database files (pre-built Windows library signature databases).
(define %ghidra-fidb-files
  `(("vs2012_x64.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2012_x64.fidb")
          (sha256
           (base32
            "1m79iarzg45q65wk46231fx0v2r4lpxz9nk5n30zza6b1kxyn36w"))))
    ("vs2012_x86.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2012_x86.fidb")
          (sha256
           (base32
            "194hxmz2xlhyb1s5kzmfmkkh6svyvr6fhkkjw46zv32p8d56j65n"))))
    ("vs2015_x64.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2015_x64.fidb")
          (sha256
           (base32
            "1q2fkr0gkv5n0745ykc4xndzcss56qxy3lg85hb2wk4r0awcnl4g"))))
    ("vs2015_x86.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2015_x86.fidb")
          (sha256
           (base32
            "1dkfwsb6agifsdjr37gamvw8a41i433r5qifg6pp1l90kmz1v1j4"))))
    ("vs2017_x64.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2017_x64.fidb")
          (sha256
           (base32
            "1mgsbxlp560p9yjks93x6ncyd898hih5mlc1qywm9qiq1v0z1gc9"))))
    ("vs2017_x86.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2017_x86.fidb")
          (sha256
           (base32
            "1lw9rf6pdzsab753by4ip191qwmdbw6zjvi575rs5lhshqaa9k41"))))
    ("vs2019_x64.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2019_x64.fidb")
          (sha256
           (base32
            "05800xwnzhva81lnc2nn4i4smnmg7p8inf34lppj3rwq674wx48q"))))
    ("vs2019_x86.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vs2019_x86.fidb")
          (sha256
           (base32
            "1sv318vgm9c6ldqynwsdq2xxil9wrbpnjzrxnn3jb5imiwyx4hra"))))
    ("vsOlder_x64.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vsOlder_x64.fidb")
          (sha256
           (base32
            "131va7s6c36jgqd0sq8akwzjspxwhcx6db4ywhwkxqpj90g8an36"))))
    ("vsOlder_x86.fidb"
     . ,(origin
          (method url-fetch)
          (uri "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_12.0.4/FunctionID/vsOlder_x86.fidb")
          (sha256
           (base32
            "1630bimnp4hlm52xhi743j2qc3alcjd4bg57hwzgd68w1s9p41w7"))))))

;;; Binary Gradle distribution used to bootstrap the build.
(define gradle-8.13-bin
  (origin
    (method url-fetch)
    (uri "https://services.gradle.org/distributions/gradle-8.13-bin.zip")
    (sha256
     (base32
      "087in4bn4dr599pw416q8d0rdyhilk7v71snflcwc5anx1qhmvbq"))))

;;; yajsw (Yet Another Java Service Wrapper) for GhidraServer.
(define yajsw-stable-13.18
  (origin
    (method url-fetch)
    (uri "https://sourceforge.net/projects/yajsw/files/yajsw/yajsw-stable-13.18/yajsw-stable-13.18.zip")
    (sha256
     (base32
      "0l5k9sc1giab55qgll8zyic4yranq5wzd61kma5rn7zn91dn2s2g"))))

(define-public ghidra
  (package
    (name "ghidra")
    (version "12.0.4")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/NationalSecurityAgency/ghidra/archive/refs/tags/"
             "Ghidra_" version "_build.tar.gz"))
       (sha256
        (base32
         "09jhnp2z4qaqhgdk8wapz26ibxphdk8lw8iiav6nnq1l4r083xdl"))
       (patches
        (search-patches "ghidra-offline-build.patch"))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let* ((out        #$output)
                 (lib        (string-append out "/lib/ghidra"))
                 (bin        (string-append out "/bin"))
                 (build-dir  "/tmp/ghidra-build")
                 (deps-dir   (string-append build-dir "/dependencies"))
                 (flat-repo  (string-append deps-dir "/flatRepo"))
                 (fidb-dir   (string-append deps-dir "/fidb"))
                 (server-dir (string-append deps-dir "/GhidraServer"))
                 (gradle-dir (string-append build-dir "/gradle-8.13"))
                 (gradle     (string-append gradle-dir "/bin/gradle"))
                 (bash       #$(file-append bash-minimal "/bin/bash"))
                 (unzip      #$(file-append unzip "/bin/unzip"))
                 (java-home  #$(file-append openjdk21 "")))

            ;; Unpack Gradle.
            (mkdir-p build-dir)
            (with-directory-excursion build-dir
              (invoke unzip "-q" #$gradle-8.13-bin)
              (rename-file "gradle-8.13" "gradle-8.13-orig")
              (copy-recursively "gradle-8.13-orig" "gradle-8.13"))
            (chmod gradle #o755)

            ;; Unpack Ghidra source.
            (invoke unzip "-q"
                    (string-append #$source) "-d" "/tmp/ghidra-src")
            ;; Actually it's a tar.gz
            (invoke #$(file-append (@ (gnu packages base) tar) "/bin/tar")
                    "-xf" #$source "-C" "/tmp/ghidra-src")
            (let ((src-dir (string-append
                            "/tmp/ghidra-src/ghidra-Ghidra_"
                            #$version "_build")))
              (copy-recursively src-dir build-dir))

            ;; Populate flatRepo with Maven JARs.
            (mkdir-p flat-repo)
            #$@(map (lambda (entry)
                      #~(begin
                          (copy-file
                           #$(cdr entry)
                           (string-append flat-repo "/" #$(car entry)))))
                    (append %ghidra-maven-jars
                            %ghidra-extra-jars))

            ;; Populate FunctionID database directory.
            (mkdir-p fidb-dir)
            #$@(map (lambda (entry)
                      #~(copy-file
                         #$(cdr entry)
                         (string-append fidb-dir "/" #$(car entry))))
                    %ghidra-fidb-files)

            ;; Populate GhidraServer dependency directory (yajsw).
            (mkdir-p server-dir)
            (copy-file #$yajsw-stable-13.18
                       (string-append server-dir "/yajsw-stable-13.18.zip"))

            ;; Remove extensions that require native binaries not available
            ;; for offline source builds.
            (for-each
             (lambda (d)
               (let ((p (string-append build-dir "/" d)))
                 (when (file-exists? p)
                   (delete-file-recursively p))))
             '("Ghidra/Extensions/SymbolicSummaryZ3"
               "Ghidra/Debug/Debugger-agent-dbgeng"))

            ;; Write a gradle.properties file with the protobuf version.
            (call-with-output-file (string-append build-dir
                                                  "/gradle.properties")
              (lambda (port)
                (format port "ghidra.protobuf.java.version=4.31.0~%")))

            ;; Run the Ghidra build.
            (with-directory-excursion build-dir
              (setenv "JAVA_HOME" java-home)
              (setenv "PATH"
                      (string-append java-home "/bin:"
                                     (getenv "PATH")))
              (setenv "GRADLE_USER_HOME" "/tmp/gradle-home")
              (invoke gradle
                      "buildGhidra"
                      "--offline"
                      "--no-daemon"
                      "-x" "test"
                      "--stacktrace"))

            ;; Install: extract the produced distribution zip.
            (let* ((dist-dir (string-append build-dir "/build/dist"))
                   (zips     (find-files dist-dir "\\.zip$"))
                   (dist-zip (car zips)))
              (mkdir-p lib)
              (with-directory-excursion lib
                (invoke unzip "-q" dist-zip)
                ;; Move contents up one level (zip has a top-level dir).
                (let ((top (car (scandir "." (lambda (e)
                                              (not (member e '("." ".."))))))))
                  (for-each
                   (lambda (entry)
                     (rename-file (string-append top "/" entry) entry))
                   (scandir top (lambda (e) (not (member e '("." "..")))))))))

            (mkdir-p bin)

            ;; Create ghidra wrapper script.
            (call-with-output-file (string-append bin "/ghidra")
              (lambda (port)
                (format port "#!~a~%" bash)
                (format port "export JAVA_HOME=\"~a\"~%" java-home)
                (format port "export PATH=\"~a/bin:$PATH\"~%" java-home)
                (format port "exec \"~a/ghidraRun\" \"$@\"~%" lib)))
            (chmod (string-append bin "/ghidra") #o755)

            ;; Create analyzeHeadless wrapper script.
            (call-with-output-file (string-append bin
                                                  "/ghidra-analyzeHeadless")
              (lambda (port)
                (format port "#!~a~%" bash)
                (format port "export JAVA_HOME=\"~a\"~%" java-home)
                (format port "export PATH=\"~a/bin:$PATH\"~%" java-home)
                (format port "exec \"~a/support/analyzeHeadless\" \"$@\"~%"
                        lib)))
            (chmod (string-append bin "/ghidra-analyzeHeadless") #o755)))))
    (inputs
     (list bash-minimal openjdk21))
    (native-inputs
     (list unzip
           (@ (gnu packages base) tar)
           (@ (gnu packages gcc) gcc "lib")))
    (home-page "https://ghidra-sre.org/")
    (synopsis "Software reverse engineering framework")
    (description
     "Ghidra is a software reverse engineering (SRE) framework developed by
the National Security Agency (NSA).  It helps analyze malicious code and
malware, and can be used for a range of software reverse engineering tasks.
Ghidra includes a suite of full-featured, high-end software analysis tools
that enable users to analyze compiled code on a variety of platforms,
including Windows, Mac OS, and Linux.  Capabilities include disassembly,
assembly, decompilation, graphing, and scripting, along with hundreds of
other features.")
    (license license:asl2.0)))

(define-public ropgadget
  (package
    (name "ropgadget")
    (version "7.7")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/JonathanSalwan/ROPgadget/")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0g87qz8hfiajl1v5z5rxama4531hi9gabzbgkhrbavjj7v3xgavw"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      ;; TODO PyPI lack test data, Git provides a collection of binaries for
      ;; the tests.
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (replace 'check
            (lambda* (#:key tests? #:allow-other-keys)
              (when tests?
                (with-directory-excursion "test-suite-binaries"
                  (invoke  "./test.sh"))))))))
    (native-inputs
     (list python-setuptools))
    (propagated-inputs
     (list python-capstone))
    (home-page "https://shell-storm.org/project/ROPgadget/")
    (synopsis "Semiautomatic return oriented programming")
    (description
     "This tool lets you search for @acronym{ROP, Return Oriented Programming}
gadgets in binaries.  Some facilities are included for automatically generating
chains of gadgets to execute system calls.")
    (license license:bsd-3)))

(define-public pwntools
  (package
    (name "pwntools")
    (version "4.15.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/Gallopsled/pwntools")
              (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0phi7gks9w9rim9rzs8cgwznc3xximdpxyj5vrafivziill51qnl"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      #:tests? #f  ;XXX: needs a specific version of unicorn
      #:phases
      '(modify-phases %standard-phases
          (add-after 'unpack 'relax-dependencies
            (lambda _
              (substitute* "pyproject.toml"
                (("^ *\"pip.*\",.*")
                 "")))))))
    (propagated-inputs
     (list capstone
           python-colored-traceback
           python-dateutil
           python-intervaltree
           python-mako
           python-packaging
           python-paramiko
           python-psutil
           python-pyelftools
           python-pygments
           python-pyserial
           python-pysocks
           python-requests
           ropgadget
           python-rpyc
           python-six
           python-sortedcontainers
           python-unix-ar
           python-zstandard
           unicorn))
    (native-inputs
     (list python-setuptools python-toml))
    (home-page "https://github.com/Gallopsled/pwntools")
    (synopsis
     "Capture-the-flag (CTF) framework and exploit development library")
    (description
     "Pwntools is a capture-the-flag (CTF) framework and exploit development library.
Written in Python, it is designed for rapid prototyping and development, and
intended to make exploit writing as simple as possible.")
    (license license:expat)))
