;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Danny Milosavljevic <dannym@friendly-machines.com>
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

(define-module (gnu packages graal)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system ant)
  #:use-module (gnu packages)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages java)
  #:use-module (gnu packages python)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages icu4c)
  #:use-module (gnu packages java-compression)
  #:use-module (gnu packages libffi)
  #:use-module (gnu packages ninja)
  #:use-module (gnu packages cmake)
  #:use-module (gnu packages version-control))

;;;
;;; MX URL Rewrite Helpers
;;;
;;; The mx build tool downloads dependencies from Maven and other URLs.
;;; MX_URLREWRITES redirects these to Guix-built JARs with computed SHA512 digests.

;; Build MX_URLREWRITES JSON from a list of rewrite specifications.
;; Each spec is: (maven-url path-pattern)
;;   maven-url: the URL mx tries to fetch
;;   path-pattern: pattern for search-input-file, or input key for assoc-ref if no "/"
(define (make-mx-urlrewrites-phase specs)
  #~(lambda* (#:key inputs #:allow-other-keys)
      (use-modules (ice-9 popen) (ice-9 rdelim))
      (define (file-sha512 path)
        (let* ((port (open-pipe* OPEN_READ "sha512sum" "--" path))
               (line (read-line port))
               (hash (car (string-split line #\space))))
          (close-pipe port)
          hash))
      (define (resolve-path path-pattern)
        (if (string-index path-pattern #\/)
            (search-input-file inputs path-pattern)
            (assoc-ref inputs path-pattern)))
      (define (make-rewrite spec)
        (let* ((maven-url (car spec))
               (path-pattern (cadr spec))
               (local-path (resolve-path path-pattern))
               (sha512 (file-sha512 local-path)))
          (format #f "{\"~a\":{\"replacement\":\"file://~a\",\"digest\":\"sha512:~a\"}}"
                  maven-url local-path sha512)))
      (let ((rewrites (string-append "[" (string-join (map make-rewrite '#$specs) ",") "]")))
        (format #t "Setting MX_URLREWRITES:~%~a~%" rewrites)
        (setenv "MX_URLREWRITES" rewrites))))

;; ASM bytecode manipulation library (version 9.7.1)
(define %mx-rewrites-asm
  '(("https://repo1.maven.org/maven2/org/ow2/asm/asm/9.7.1/asm-9.7.1.jar"
     "share/java/asm9.jar")
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm/9.7.1/asm-9.7.1-sources.jar"
     "share/java/asm9-sources.jar")
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-tree/9.7.1/asm-tree-9.7.1.jar"
     "share/java/asm-tree.jar")
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-tree/9.7.1/asm-tree-9.7.1-sources.jar"
     "share/java/asm-tree-sources.jar")
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-analysis/9.7.1/asm-analysis-9.7.1.jar"
     "share/java/asm-analysis.jar")
    ;; asm-analysis sources -> binary (no sources JAR available)
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-analysis/9.7.1/asm-analysis-9.7.1-sources.jar"
     "share/java/asm-analysis.jar")
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-util/9.7.1/asm-util-9.7.1.jar"
     "share/java/asm-util8.jar")
    ;; asm-util sources -> binary
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-util/9.7.1/asm-util-9.7.1-sources.jar"
     "share/java/asm-util8.jar")
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-commons/9.7.1/asm-commons-9.7.1.jar"
     "share/java/asm-commons8.jar")
    ("https://repo1.maven.org/maven2/org/ow2/asm/asm-commons/9.7.1/asm-commons-9.7.1-sources.jar"
     "share/java/asm-commons-sources.jar")))

;; ANTLR4 parser runtime (version 4.13.2)
(define %mx-rewrites-antlr
  '(("https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/4.13.2/antlr4-runtime-4.13.2.jar"
     "share/java/java-antlr4-runtime.jar")
    ;; sources -> binary
    ("https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/4.13.2/antlr4-runtime-4.13.2-sources.jar"
     "share/java/java-antlr4-runtime.jar")))

;; ICU4J unicode library (mx wants 76.1, we provide 73.2)
(define %mx-rewrites-icu
  '(("https://repo1.maven.org/maven2/com/ibm/icu/icu4j/76.1/icu4j-76.1.jar"
     "share/java/icu4j.jar")
    ("https://search.maven.org/remotecontent?filepath=com/ibm/icu/icu4j/76.1/icu4j-76.1.jar"
     "share/java/icu4j.jar")
    ("https://repo1.maven.org/maven2/com/ibm/icu/icu4j/76.1/icu4j-76.1-sources.jar"
     "share/java/icu4j-sources.jar")
    ("https://repo1.maven.org/maven2/com/ibm/icu/icu4j-charset/76.1/icu4j-charset-76.1.jar"
     "share/java/icu4j-charset.jar")
    ("https://search.maven.org/remotecontent?filepath=com/ibm/icu/icu4j-charset/76.1/icu4j-charset-76.1.jar"
     "share/java/icu4j-charset.jar")
    ("https://repo1.maven.org/maven2/com/ibm/icu/icu4j-charset/76.1/icu4j-charset-76.1-sources.jar"
     "share/java/icu4j-charset-sources.jar")))

;; XZ compression library (version 1.10)
(define %mx-rewrites-xz
  '(("https://repo1.maven.org/maven2/org/tukaani/xz/1.10/xz-1.10.jar"
     "share/java/xz.jar")
    ("https://search.maven.org/remotecontent?filepath=org/tukaani/xz/1.10/xz-1.10.jar"
     "share/java/xz.jar")
    ("https://repo1.maven.org/maven2/org/tukaani/xz/1.10/xz-1.10-sources.jar"
     "share/java/xz-sources.jar")))

;; Ninja build tool
(define %mx-rewrites-ninja
  '(("https://lafo.ssw.uni-linz.ac.at/pub/graal-external-deps/ninja-1.10.2-linux-amd64.zip"
     "share/ninja/ninja.zip")))

;; Hamcrest test matchers
(define %mx-rewrites-hamcrest
  '(("https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar"
     "lib/m2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar")
    ("https://search.maven.org/remotecontent?filepath=org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar"
     "lib/m2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar")
    ;; sources -> binary
    ("https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3-sources.jar"
     "lib/m2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar")
    ("https://search.maven.org/remotecontent?filepath=org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3-sources.jar"
     "lib/m2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar")))

;; libffi source tarball
(define %mx-rewrites-libffi
  '(("https://github.com/libffi/libffi/releases/download/v3.4.8/libffi-3.4.8.tar.gz"
     "libffi-3.4.8.tar.gz")
    ("https://lafo.ssw.uni-linz.ac.at/pub/graal-external-deps/libffi-3.4.8.tar.gz"
     "libffi-3.4.8.tar.gz")))

;; JLine terminal library (version 3.28.0)
(define %mx-rewrites-jline
  '(("https://repo1.maven.org/maven2/org/jline/jline-terminal/3.28.0/jline-terminal-3.28.0.jar"
     "share/java/jline-terminal.jar")
    ("https://repo1.maven.org/maven2/org/jline/jline-terminal/3.28.0/jline-terminal-3.28.0-sources.jar"
     "share/java/jline-terminal-sources.jar")
    ("https://repo1.maven.org/maven2/org/jline/jline-reader/3.28.0/jline-reader-3.28.0.jar"
     "share/java/jline-reader.jar")
    ("https://repo1.maven.org/maven2/org/jline/jline-reader/3.28.0/jline-reader-3.28.0-sources.jar"
     "share/java/jline-reader-sources.jar")
    ("https://repo1.maven.org/maven2/org/jline/jline-builtins/3.28.0/jline-builtins-3.28.0.jar"
     "share/java/jline-builtins.jar")
    ("https://repo1.maven.org/maven2/org/jline/jline-builtins/3.28.0/jline-builtins-3.28.0-sources.jar"
     "share/java/jline-builtins-sources.jar")
    ("https://repo1.maven.org/maven2/org/jline/jline-terminal-ffm/3.28.0/jline-terminal-ffm-3.28.0.jar"
     "share/java/jline-terminal-ffm.jar")
    ("https://repo1.maven.org/maven2/org/jline/jline-terminal-ffm/3.28.0/jline-terminal-ffm-3.28.0-sources.jar"
     "share/java/jline-terminal-ffm-sources.jar")))

;; JSON library (version 20250517)
(define %mx-rewrites-json
  '(("https://repo1.maven.org/maven2/org/json/json/20250517/json-20250517.jar"
     "share/java/json.jar")
    ("https://repo1.maven.org/maven2/org/json/json/20250517/json-20250517-sources.jar"
     "share/java/json-sources.jar")))

;; BouncyCastle crypto library (version 1.78.1)
(define %mx-rewrites-bouncycastle
  '(("https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/1.78.1/bcprov-jdk18on-1.78.1.jar"
     "share/java/bcprov-jdk18on.jar")
    ("https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/1.78.1/bcprov-jdk18on-1.78.1-sources.jar"
     "share/java/bcprov-jdk18on-sources.jar")
    ("https://repo1.maven.org/maven2/org/bouncycastle/bcutil-jdk18on/1.78.1/bcutil-jdk18on-1.78.1.jar"
     "share/java/bcutil-jdk18on.jar")
    ("https://repo1.maven.org/maven2/org/bouncycastle/bcutil-jdk18on/1.78.1/bcutil-jdk18on-1.78.1-sources.jar"
     "share/java/bcutil-jdk18on-sources.jar")
    ("https://repo1.maven.org/maven2/org/bouncycastle/bcpkix-jdk18on/1.78.1/bcpkix-jdk18on-1.78.1.jar"
     "share/java/bcpkix-jdk18on.jar")
    ("https://repo1.maven.org/maven2/org/bouncycastle/bcpkix-jdk18on/1.78.1/bcpkix-jdk18on-1.78.1-sources.jar"
     "share/java/bcpkix-jdk18on-sources.jar")))

;; Cap'n Proto runtime (version 0.1.16)
(define %mx-rewrites-capnproto
  '(("https://repo1.maven.org/maven2/org/capnproto/runtime/0.1.16/runtime-0.1.16.jar"
     "share/java/capnproto-runtime.jar")
    ("https://repo1.maven.org/maven2/org/capnproto/runtime/0.1.16/runtime-0.1.16-sources.jar"
     "share/java/capnproto-runtime-sources.jar")))

;; TruffleJWS WebSocket library
(define %mx-rewrites-trufflejws
  '(("https://lafo.ssw.uni-linz.ac.at/pub/graal-external-deps/trufflejws-1.5.7.jar"
     "share/java/trufflejws.jar")
    ("https://lafo.ssw.uni-linz.ac.at/pub/graal-external-deps/trufflejws-1.5.7-src.jar"
     "share/java/trufflejws-sources.jar")))

;; Native source tarballs for graalpy
(define %mx-rewrites-native-sources
  '(("https://lafo.ssw.uni-linz.ac.at/pub/graal-external-deps/graalpython/bzip2-1.0.8.tar.gz"
     "bzip2-1.0.8.tar.gz")
    ("https://lafo.ssw.uni-linz.ac.at/pub/graal-external-deps/xz-5.6.2.tar.gz"
     "xz-5.6.2.tar.gz")))

;; Composed rewrite lists for each package tier
(define %mx-rewrites-regex
  (append %mx-rewrites-asm
          %mx-rewrites-antlr
          %mx-rewrites-icu
          %mx-rewrites-xz
          %mx-rewrites-ninja))

(define %mx-rewrites-truffle
  (append %mx-rewrites-regex
          %mx-rewrites-hamcrest
          %mx-rewrites-libffi
          %mx-rewrites-jline))

(define %mx-rewrites-tools
  (append %mx-rewrites-truffle
          %mx-rewrites-json))

(define %mx-rewrites-graalpy
  (append %mx-rewrites-truffle
          %mx-rewrites-json
          %mx-rewrites-bouncycastle
          %mx-rewrites-capnproto
          %mx-rewrites-trufflejws
          %mx-rewrites-native-sources))

;;;
;;; Packages
;;;

;; The mx build tool is used to build all GraalVM projects.
;; It has no external Python dependencies (stdlib only).
(define-public graalvm-mx
  (package
    (name "graalvm-mx")
    (version "7.68.2")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/graalvm/mx")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0y7qqc8374vq6sg9icfm0jlfx8fb447p9blpm18ji95qrm9ywzx0"))
              (patches (search-patches "graalvm-mx-check-failed-after-join.patch"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("." "lib/mx/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'create-missing-directories
            ;; mx's suite.py defines native projects that expect certain
            ;; directories to exist.  Create them so mx doesn't fail when
            ;; initializing.
            (lambda* (#:key outputs #:allow-other-keys)
              (let ((lib (string-append (assoc-ref outputs "out") "/lib/mx")))
                (mkdir-p (string-append lib "/java/com.oracle.jvmtiasmagent/include")))))
          (add-after 'create-missing-directories 'install-ninja-syntax
            ;; mx needs ninja_syntax Python module for native projects.
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let ((ninja-syntax (search-input-file inputs "misc/ninja_syntax.py"))
                    (lib (string-append (assoc-ref outputs "out") "/lib/mx")))
                (copy-file ninja-syntax (string-append lib "/ninja_syntax.py")))))
          (add-after 'install-ninja-syntax 'create-wrapper
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (bin (string-append out "/bin"))
                     (lib (string-append out "/lib/mx"))
                     (python (search-input-file inputs "/bin/python3")))
                (mkdir-p bin)
                (call-with-output-file (string-append bin "/mx")
                  (lambda (port)
                    (format port "#!~a~%exec ~a ~a/mx.py \"$@\"~%"
                            (search-input-file inputs "/bin/bash")
                            python
                            lib)))
                (chmod (string-append bin "/mx")
                       #o755)))))))
    (native-inputs (list (package-source ninja)))
    (inputs (list bash-minimal python-3))
    (home-page "https://github.com/graalvm/mx")
    (synopsis "Build tool for GraalVM projects")
    (description "mx is a command-line tool used for the development of
GraalVM projects.  It provides commands for building, testing, and packaging
polyglot language implementations built on the Truffle framework.")
    (license license:gpl2)))

;; TruffleJWS - WebSocket implementation used by GraalVM tools (chromeinspector)
;; Built from source jar distributed by Oracle at lafo.ssw.uni-linz.ac.at
(define-public java-trufflejws-for-graal
  (package
    (name "java-trufflejws-for-graal")
    (version "1.5.7")
    (source (origin
              (method url-fetch)
              (uri "https://lafo.ssw.uni-linz.ac.at/pub/graal-external-deps/trufflejws-1.5.7-src.jar")
              (sha256
               (base32 "0c6ccyl9s07mimdnscc4g56zkhc31qd6qvhy16vidrj12h8cxgfn"))))
    (build-system ant-build-system)
    (arguments
     (list
      #:jar-name "trufflejws.jar"
      #:source-dir "."
      #:tests? #f  ; no tests in source jar
      #:phases
      #~(modify-phases %standard-phases
          (replace 'unpack
            (lambda* (#:key source #:allow-other-keys)
              ;; Source is a jar file containing .java files.
              (invoke "unzip" "-q" source)))
          (add-after 'install 'install-sources
            (lambda* (#:key outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (share (string-append out "/share/java")))
                ;; Copy source jar as sources jar for mx.
                (copy-file #$source
                           (string-append share "/trufflejws-sources.jar"))))))))
    (native-inputs (list unzip))
    (home-page "https://www.graalvm.org")
    (synopsis "WebSocket implementation for GraalVM tools")
    (description "TruffleJWS is a WebSocket library used by GraalVM's
Chrome Inspector and other debugging tools.  It provides WebSocket client
and server implementations for the Truffle framework.")
    (license upl1.0)))

