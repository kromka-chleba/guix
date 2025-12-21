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
;;; GraalVM build tool and components
;;;

;; The Universal Permissive License (UPL) 1.0 is an FSF-approved,
;; GPL-compatible, permissive free software license.
;; See: <https://www.fsf.org/blogs/licensing/universal-permissive-license-added-to-license-list>
(define upl1.0
  (license:non-copyleft "https://opensource.org/licenses/UPL"
                        "Universal Permissive License 1.0"))

;;; Shared version and source definitions

(define %graalvm-version "25.0.1")

;; Main graal repository source (used by sdk, truffle)
(define %graal-source
  (origin
    (method git-fetch)
    (uri (git-reference
          (url "https://github.com/oracle/graal")
          (commit (string-append "vm-" %graalvm-version))))
    (file-name (git-file-name "graal" %graalvm-version))
    (sha256
     (base32 "06m8nbjrjawn5falr7fzgsqqav23zapzhc5f774320cdjbj90zvx"))
    (modules '((guix build utils)))
    (snippet
     #~(begin
         (use-modules (guix build utils))
         ;; Use GCC toolchain instead of clang
         (substitute* '("sdk/mx.sdk/mx_sdk_vm_impl.py"
                        "sdk/mx.sdk/mx_sdk_vm_ng.py")
           (("sdk:LLVM_NINJA_TOOLCHAIN") "mx:DEFAULT_NINJA_TOOLCHAIN"))
         (substitute* '("sdk/mx.sdk/suite.py"
                        "truffle/mx.truffle/suite.py")
           (("\"toolchain\"\\s*:\\s*\"sdk:LLVM_NINJA_TOOLCHAIN\"")
            "\"toolchain\": \"mx:DEFAULT_NINJA_TOOLCHAIN\""))
         ;; Remove clang-specific flags that GCC doesn't understand.
         (substitute* '("sdk/mx.sdk/suite.py"
                        "sdk/mx.sdk/mx_sdk_vm_impl.py"
                        "sdk/mx.sdk/mx_sdk_vm_ng.py")
           (("-stdlib=libc\\+\\+") "")
           (("-static-libstdc\\+\\+") "")
           (("-l:libc\\+\\+abi\\.a") ""))
         ;; Fix missing #include <memory> for GCC.
         (substitute* "sdk/src/org.graalvm.launcher.native/src/launcher.cc"
           (("#include <sys/stat.h>")
            "#include <sys/stat.h>
#include <memory>"))
         ;; Patch the libffi bootstrap Makefile patch to use bash explicitly.
         (substitute* "truffle/src/libffi/patches/others/0001-Add-mx-bootstrap-Makefile.patch"
           (("\\.\\./(\\$\\(SOURCES\\))/configure" all sources)
            (string-append "$(SHELL) ../" sources "/configure")))))))

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

;; Build install phase that uses `mx paths` to find distribution JARs.
;; dists: list of distribution names (e.g., '("GRAAL_SDK" "WORD"))
;; subdir: output subdirectory under lib/ (default "graal")
(define* (make-mx-install-phase dists #:optional (subdir "graal"))
  #~(lambda* (#:key outputs #:allow-other-keys)
      (use-modules (ice-9 popen) (ice-9 rdelim))
      (define (mx-paths dist)
        (let* ((port (open-pipe* OPEN_READ "mx" "--user-home" (getcwd) "paths" dist))
               (path (read-line port)))
          (close-pipe port)
          path))
      (let* ((out (assoc-ref outputs "out"))
             (lib (string-append out "/lib/" #$subdir)))
        (mkdir-p lib)
        (for-each (lambda (dist)
                    (let ((jar (mx-paths dist)))
                      (format #t "Installing ~a -> ~a~%" dist jar)
                      (install-file jar lib)))
                  '#$dists))))

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

(define %mx-rewrites-substratevm
  (append %mx-rewrites-truffle
          %mx-rewrites-capnproto))

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

;; GraalVM SDK - standalone foundation with no suite imports.
;; Provides: POLYGLOT, COLLECTIONS, NATIVEIMAGE, WORD, LAUNCHER_COMMON.
(define-public graal-sdk
  (package
    (name "graal-sdk")
    (version %graalvm-version)
    (source %graal-source)
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'chdir-to-sdk
            (lambda _ (chdir "sdk")))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (setenv "JAVA_HOME" (assoc-ref inputs "openjdk"))
              (setenv "MX_PYTHON" (which "python3"))
              ;; Redirect mx's build output and cache to writable locations.
              (setenv "MX_ALT_OUTPUT_ROOT" (string-append (getcwd) "/mxbuild-output"))
              (setenv "MX_CACHE_DIR" (string-append (getcwd) "/mx-cache"))
              ;; Build the core SDK distributions (without LAUNCHER_COMMON which needs JLINE).
              (invoke "mx" "--user-home" (getcwd)
                      "build" "--dependencies" "GRAAL_SDK,WORD,COLLECTIONS,NATIVEIMAGE,POLYGLOT")))
          (replace 'install
            #$(make-mx-install-phase '("GRAAL_SDK" "WORD" "COLLECTIONS" "NATIVEIMAGE" "POLYGLOT"))))))
    (native-inputs (list graalvm-mx (list openjdk "jdk")))
    (inputs (list python-3))
    (home-page "https://www.graalvm.org/")
    (synopsis "GraalVM SDK and Polyglot API")
    (description "Foundation libraries for GraalVM including the Polyglot API
for language interoperability, collections, and native image support.")
    (license upl1.0)))

;; Truffle - Language implementation framework
;; Imports: sdk (as subdir)
;; Provides: TRUFFLE_API, TRUFFLE_NFI, TRUFFLE_DSL_PROCESSOR
(define-public graal-truffle
  (package
    (name "graal-truffle")
    (version %graalvm-version)
    (source %graal-source)
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'chdir-to-truffle
            (lambda _
              (chdir "truffle")))
          (add-before 'build 'setup-mx-urlrewrites
            #$(make-mx-urlrewrites-phase %mx-rewrites-truffle))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (setenv "JAVA_HOME" (assoc-ref inputs "openjdk"))
              (setenv "MX_PYTHON" (which "python3"))
              ;; Redirect mx's build output and cache to writable locations.
              (setenv "MX_ALT_OUTPUT_ROOT" (string-append (getcwd) "/mxbuild-output"))
              (setenv "MX_CACHE_DIR" (string-append (getcwd) "/mx-cache"))
              ;; Build only the pure-Java Truffle distributions.
              ;; Distributions that require native tooling (LLVM) or JLINE are excluded.
              ;; GraalPy needs these core distributions:
              ;;   TRUFFLE_API, TRUFFLE_DSL_PROCESSOR, TRUFFLE_ICU4J, TRUFFLE_NFI,
              ;;   TRUFFLE_NFI_PANAMA, TRUFFLE_RUNTIME, TRUFFLE_TCK, TRUFFLE_XZ
              ;; Excluded (need LLVM/JLINE):
              ;;   TRUFFLE_NFI_LIBFFI - needs LIBFFI_SOURCES + native compilation
              ;;   TRUFFLE_NFI_NATIVE_GRAALVM_SUPPORT - needs sdk:LLVM_NINJA_TOOLCHAIN
              ;;   TRUFFLE_ATTACH_GRAALVM_SUPPORT - may need JLINE for launcher
              (invoke "mx" "--user-home" (getcwd) "build"
                      "--dependencies" (string-join
                                        '("TRUFFLE_API"
                                          "TRUFFLE_DSL_PROCESSOR"
                                          "TRUFFLE_ICU4J"
                                          "TRUFFLE_NFI"
                                          "TRUFFLE_NFI_PANAMA"
                                          "TRUFFLE_RUNTIME"
                                          "TRUFFLE_XZ")
                                        ","))))
          (replace 'install
            #$(make-mx-install-phase '("TRUFFLE_API" "TRUFFLE_DSL_PROCESSOR" "TRUFFLE_ICU4J" "TRUFFLE_NFI" "TRUFFLE_NFI_PANAMA" "TRUFFLE_RUNTIME" "TRUFFLE_XZ"))))))
    (native-inputs
     (list (list "mx" graalvm-mx)
           (list "openjdk" openjdk "jdk")
           (list "java-asm" java-asm-for-graal-truffle)
           (list "java-asm-tree" java-asm-tree-for-graal-truffle)
           (list "java-asm-analysis" java-asm-analysis-for-graal-truffle)
           (list "java-asm-util" java-asm-util-for-graal-truffle)
           (list "java-asm-commons" java-asm-commons-for-graal-truffle)
           (list "java-antlr4-runtime" java-antlr4-runtime-for-graal-truffle)
           (list "java-hamcrest-core" java-hamcrest-core-for-graal-truffle)
           (list "java-icu4j" java-icu4j-for-graal-truffle)
           (list "java-icu4j-charset" java-icu4j-charset-for-graal-truffle)
           (list "java-xz" java-xz-for-graal-truffle)
           (list "java-jline-terminal" java-jline-terminal-for-graal-truffle)
           (list "java-jline-reader" java-jline-reader-for-graal-truffle)
           (list "java-jline-builtins" java-jline-builtins-for-graal-truffle)
           (list "java-jline-terminal-ffm" java-jline-terminal-ffm-for-graal-truffle)
           (list "ninja" ninja-for-graal-truffle)
           (list "libffi-3.4.8.tar.gz" (package-source libffi-for-graal-truffle))))
    (inputs (list python-3))
    (home-page "https://www.graalvm.org/")
    (synopsis "Truffle language implementation framework")
    (description "Truffle is a framework for implementing programming languages
as self-modifying Abstract Syntax Tree (AST) interpreters.  Languages built on
Truffle can achieve high performance through the Graal JIT compiler.")
    (license upl1.0)))

;; Graal Tools - debugging and profiling utilities.
;; This builds the tools suite which imports truffle, so it needs the same
;; URL rewrites and dependencies as graal-truffle.
(define-public graal-tools
  (package
    (name "graal-tools")
    (version %graalvm-version)
    (source %graal-source)
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'chdir-to-tools
            (lambda _ (chdir "tools")))
          (add-before 'build 'setup-mx-urlrewrites
            #$(make-mx-urlrewrites-phase %mx-rewrites-tools))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (setenv "JAVA_HOME" (assoc-ref inputs "openjdk"))
              (setenv "MX_PYTHON" (which "python3"))
              (setenv "MX_ALT_OUTPUT_ROOT" (string-append (getcwd) "/mxbuild-output"))
              (setenv "MX_CACHE_DIR" (string-append (getcwd) "/mx-cache"))
              ;; Only build TRUFFLE_PROFILER - this is what graalpy needs.
              ;; The full tools suite needs many more dependencies (GUAVA, JIMFS, JSON, etc.)
              (invoke "mx" "--user-home" (getcwd) "build"
                      "--dependencies" "TRUFFLE_PROFILER")))
          (replace 'install
            #$(make-mx-install-phase '("TRUFFLE_PROFILER"))))))
    (native-inputs
     (list (list "mx" graalvm-mx)
           (list "openjdk" openjdk "jdk")
           (list "java-asm" java-asm-for-graal-truffle)
           (list "java-asm-tree" java-asm-tree-for-graal-truffle)
           (list "java-asm-analysis" java-asm-analysis-for-graal-truffle)
           (list "java-asm-util" java-asm-util-for-graal-truffle)
           (list "java-asm-commons" java-asm-commons-for-graal-truffle)
           (list "java-antlr4-runtime" java-antlr4-runtime-for-graal-truffle)
           (list "java-hamcrest-core" java-hamcrest-core-for-graal-truffle)
           (list "java-icu4j" java-icu4j-for-graal-truffle)
           (list "java-icu4j-charset" java-icu4j-charset-for-graal-truffle)
           (list "java-xz" java-xz-for-graal-truffle)
           (list "java-jline-terminal" java-jline-terminal-for-graal-truffle)
           (list "java-jline-reader" java-jline-reader-for-graal-truffle)
           (list "java-jline-builtins" java-jline-builtins-for-graal-truffle)
           (list "java-jline-terminal-ffm" java-jline-terminal-ffm-for-graal-truffle)
           (list "java-json" java-json-for-graal-truffle)
           (list "ninja" ninja-for-graal-truffle)
           (list "libffi-3.4.8.tar.gz" (package-source libffi-for-graal-truffle))))
    (inputs (list python-3))
    (home-page "https://www.graalvm.org/")
    (synopsis "GraalVM debugging and profiling tools")
    (description "Development tools for GraalVM languages including debugger,
profiler, and other development utilities.")
    (license upl1.0)))

;; Graal Regex - TRegex regular expression engine
;; This builds the regex suite which imports truffle, so it needs the same
;; URL rewrites and dependencies as graal-truffle.
(define-public graal-regex
  (package
    (name "graal-regex")
    (version %graalvm-version)
    (source %graal-source)
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'chdir-to-regex
            (lambda _ (chdir "regex")))
          (add-before 'build 'setup-mx-urlrewrites
            #$(make-mx-urlrewrites-phase %mx-rewrites-regex))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (setenv "JAVA_HOME" (assoc-ref inputs "openjdk"))
              (setenv "MX_PYTHON" (which "python3"))
              (setenv "MX_ALT_OUTPUT_ROOT" (string-append (getcwd) "/mxbuild-output"))
              (setenv "MX_CACHE_DIR" (string-append (getcwd) "/mx-cache"))
              (invoke "mx" "--user-home" (getcwd) "build"
                      "--dependencies" "TREGEX")))
          (replace 'install
            #$(make-mx-install-phase '("TREGEX"))))))
    (native-inputs (list graalvm-mx
                         (list openjdk "jdk")
                         ninja-for-graal-truffle
                         java-asm-for-graal-truffle
                         java-asm-tree-for-graal-truffle
                         java-asm-analysis-for-graal-truffle
                         java-asm-util-for-graal-truffle
                         java-asm-commons-for-graal-truffle
                         java-antlr4-runtime-for-graal-truffle
                         java-icu4j-for-graal-truffle
                         java-icu4j-charset-for-graal-truffle
                         java-xz-for-graal-truffle))
    (inputs (list python-3))
    (home-page "https://www.graalvm.org/")
    (synopsis "TRegex regular expression engine for GraalVM")
    (description "TRegex is a high-performance regular expression engine
used by GraalVM languages for pattern matching operations.")
    (license upl1.0)))

;; Graal Compiler - the JIT compiler for GraalVM
;; This builds the compiler suite which imports truffle, regex, and sdk.
(define-public graal-compiler
  (package
    (name "graal-compiler")
    (version %graalvm-version)
    (source %graal-source)
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'chdir-to-compiler
            (lambda _ (chdir "compiler")))
          (add-before 'build 'setup-mx-urlrewrites
            #$(make-mx-urlrewrites-phase %mx-rewrites-truffle))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (setenv "JAVA_HOME" (assoc-ref inputs "openjdk"))
              (setenv "MX_PYTHON" (which "python3"))
              (setenv "MX_ALT_OUTPUT_ROOT" (string-append (getcwd) "/mxbuild-output"))
              (setenv "MX_CACHE_DIR" (string-append (getcwd) "/mx-cache"))
              ;; Build the core compiler distributions.
              ;; GRAAL is the main compiler JAR for use with --upgrade-module-path.
              ;; GRAAL_MANAGEMENT provides JMX management beans.
              (invoke "mx" "--user-home" (getcwd) "build"
                      "--dependencies" "GRAAL,GRAAL_MANAGEMENT")))
          (replace 'install
            #$(make-mx-install-phase '("GRAAL" "GRAAL_MANAGEMENT"))))))
    (native-inputs
     (list (list "mx" graalvm-mx)
           (list "openjdk" openjdk-for-graal "jdk")
           (list "java-asm" java-asm-for-graal-truffle)
           (list "java-asm-tree" java-asm-tree-for-graal-truffle)
           (list "java-asm-analysis" java-asm-analysis-for-graal-truffle)
           (list "java-asm-util" java-asm-util-for-graal-truffle)
           (list "java-asm-commons" java-asm-commons-for-graal-truffle)
           (list "java-antlr4-runtime" java-antlr4-runtime-for-graal-truffle)
           (list "java-hamcrest-core" java-hamcrest-core-for-graal-truffle)
           (list "java-icu4j" java-icu4j-for-graal-truffle)
           (list "java-icu4j-charset" java-icu4j-charset-for-graal-truffle)
           (list "java-xz" java-xz-for-graal-truffle)
           (list "java-jline-terminal" java-jline-terminal-for-graal-truffle)
           (list "java-jline-reader" java-jline-reader-for-graal-truffle)
           (list "java-jline-builtins" java-jline-builtins-for-graal-truffle)
           (list "java-jline-terminal-ffm" java-jline-terminal-ffm-for-graal-truffle)
           (list "ninja" ninja-for-graal-truffle)
           (list "libffi-3.4.8.tar.gz" (package-source libffi-for-graal-truffle))))
    (inputs (list python-3))
    (home-page "https://www.graalvm.org/")
    (synopsis "Graal JIT compiler for the JVM")
    (description "The Graal compiler is a high-performance JIT compiler for
the JVM that can be used as a replacement for the C2 compiler.  It provides
optimizations specifically tuned for dynamic languages and can be used with
any JVM that supports JVMCI.  Use with @code{-XX:+EnableJVMCI} and add the
compiler JARs to @code{--upgrade-module-path}.")
    (license (list license:gpl2+  ; with Classpath exception
                   upl1.0))))

;; SubstrateVM - Ahead-of-time compilation for Java (native-image)
;; This builds the substratevm suite which imports compiler and espresso-shared.
(define-public graal-substratevm
  (package
    (name "graal-substratevm")
    (version %graalvm-version)
    (source %graal-source)
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'chdir-to-substratevm
            (lambda _ (chdir "substratevm")))
          (add-before 'build 'setup-mx-urlrewrites
            #$(make-mx-urlrewrites-phase %mx-rewrites-substratevm))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (setenv "JAVA_HOME" (assoc-ref inputs "openjdk"))
              (setenv "MX_PYTHON" (which "python3"))
              (setenv "MX_ALT_OUTPUT_ROOT" (string-append (getcwd) "/mxbuild-output"))
              (setenv "MX_CACHE_DIR" (string-append (getcwd) "/mx-cache"))
              ;; Build the native-image driver and its dependencies.
              ;; SVM_DRIVER is the native-image building tool.
              ;; SVM is the main SubstrateVM image builder.
              (invoke "mx" "--user-home" (getcwd) "build"
                      "--dependencies" "SVM_DRIVER,SVM")))
          (replace 'install
            #$(make-mx-install-phase '("SVM_DRIVER" "SVM") "svm")))))
    (native-inputs
     (list (list "mx" graalvm-mx)
           (list "openjdk" openjdk-for-graal "jdk")
           (list "java-asm" java-asm-for-graal-truffle)
           (list "java-asm-tree" java-asm-tree-for-graal-truffle)
           (list "java-asm-analysis" java-asm-analysis-for-graal-truffle)
           (list "java-asm-util" java-asm-util-for-graal-truffle)
           (list "java-asm-commons" java-asm-commons-for-graal-truffle)
           (list "java-antlr4-runtime" java-antlr4-runtime-for-graal-truffle)
           (list "java-hamcrest-core" java-hamcrest-core-for-graal-truffle)
           (list "java-icu4j" java-icu4j-for-graal-truffle)
           (list "java-icu4j-charset" java-icu4j-charset-for-graal-truffle)
           (list "java-xz" java-xz-for-graal-truffle)
           (list "java-jline-terminal" java-jline-terminal-for-graal-truffle)
           (list "java-jline-reader" java-jline-reader-for-graal-truffle)
           (list "java-jline-builtins" java-jline-builtins-for-graal-truffle)
           (list "java-jline-terminal-ffm" java-jline-terminal-ffm-for-graal-truffle)
           (list "ninja" ninja-for-graal-truffle)
           (list "libffi-3.4.8.tar.gz" (package-source libffi-for-graal-truffle))
           (list "java-capnproto-runtime" java-capnproto-runtime-for-graal-truffle)))
    (inputs (list python-3))
    (home-page "https://www.graalvm.org/")
    (synopsis "Ahead-of-time compilation for Java applications")
    (description "SubstrateVM provides ahead-of-time (AOT) compilation for Java
applications using the @command{native-image} tool.  It compiles Java bytecode
into standalone native executables that start instantly and use less memory
than traditional JVM-based applications.  The resulting binaries include the
application code, required libraries, and a minimal runtime called Substrate VM.")
    (license (list license:gpl2+  ; with Classpath exception
                   upl1.0))))
;; GraalPy - Python 3.12 implementation on GraalVM
(define-public graalpy-community
  (package
    (name "graalpy-community")
    (version %graalvm-version)
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/oracle/graalpython")
                    (commit (string-append "graal-" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32 "19w22gw1ixkgy2c79m9xfhw9xvxl5vc68vddal7vq6dbsyh3g2lh"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'fix-cmake-minimum-version
            (lambda _
              ;; pegparser.generator uses cmake 3.0 which is rejected by newer cmake.
              (substitute* "graalpython/com.oracle.graal.python.pegparser.generator/CMakeLists.txt"
                (("cmake_minimum_required\\(VERSION 3\\.0\\)")
                 "cmake_minimum_required(VERSION 3.5)"))))
          (add-after 'unpack 'setup-graal-sources
            (lambda* (#:key inputs #:allow-other-keys)
              ;; mx expects to find the graal repository as a sibling directory.
              ;; The graalpython suite.py imports sdk, truffle, tools, regex from graal.
              ;;
              ;; We MUST use copy-recursively here, NOT symlink, because mx needs
              ;; to write to various directories during the build:
              ;;
              ;; 1. ShadedLibraryProject (mx_sdk_shaded.py): These projects generate
              ;;    shaded/relocated Java bytecode at build time. mx creates output
              ;;    directories like truffle/src/com.oracle.truffle.api.impl.asm/
              ;;    to store the generated .class files. There are ~10 such projects
              ;;    across espresso, sdk, substratevm, and truffle suites.
              ;;
              ;; 2. DefaultNativeProject (mx_native.py): These projects create
              ;;    'include' subdirectories for header files and write build
              ;;    artifacts to various locations within native project directories.
              ;;
              ;; 3. Build outputs: mx writes various build artifacts, caches, and
              ;;    intermediate files throughout the source tree during compilation.
              (let ((graal-src (assoc-ref inputs "graal-25.0.1-checkout")))
                (copy-recursively graal-src "../graal")
                (when (not (file-exists? "../graal/sdk/mx.sdk/suite.py"))
                  (error "graal source not set up correctly")))))
          (add-before 'build 'setup-mx-urlrewrites
            #$(make-mx-urlrewrites-phase %mx-rewrites-graalpy))
          (add-after 'setup-graal-sources 'setup-environment
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((jdk (assoc-ref inputs "openjdk")))
                (setenv "JAVA_HOME" jdk))
              ;; Do NOT set STANDALONE_JAVA_HOME - we want mx to build a full
              ;; jimage with libgraal (libjvmcicompiler.so) baked in.
              (setenv "MX_PYTHON" (which "python3"))
              (setenv "MX_ALT_OUTPUT_ROOT" (string-append (getcwd) "/mxbuild-output"))
              (setenv "MX_CACHE_DIR" (string-append (getcwd) "/mx-cache"))
              ;; CONFIG_SHELL is needed so autoconf-based builds (like libffi)
              ;; use the correct shell instead of /bin/sh which doesn't exist
              (setenv "CONFIG_SHELL" (which "bash"))
              (setenv "SHELL" (which "bash"))
              ;; OpenJDK JVMCI: 25.0.1, GraalVM expects: 25.0.1+8-jvmci-b01
              (setenv "JVMCI_VERSION_CHECK" "ignore")))
          (add-before 'build 'patch-libgraal-env
            (lambda _
              ;; Add svm,ni so native-image is available to build libjvmcicompiler.so.
              (substitute* "mx.graalpython/jvm-ce-libgraal"
                (("COMPONENTS=LibGraal")
                 "COMPONENTS=LibGraal,svm,ni"))
              ;; Remove musl from extra_native_targets to avoid needing musl toolchain.
              (substitute* "../graal/substratevm/mx.substratevm/mx_substratevm.py"
                (("'linux-default-glibc', 'linux-default-musl'")
                 "'linux-default-glibc'"))
              ;; Fix launcher_template.sh shebang - /usr/bin/env doesn't exist in Guix.
              ;; The native-image bash launcher uses this template.
              (let ((bash (which "bash")))
                (substitute* "../graal/sdk/mx.sdk/vm/launcher_template.sh"
                  (("#!/usr/bin/env bash")
                   (string-append "#!" bash))))
              ;; Propagate gcc environment variables through native-image's env sanitization.
              ;; native-image's sanitizeJVMEnvironment (NativeImage.java) strips all env vars
              ;; except a whitelist (PATH, HOME, etc). The -E<varname> flag passes vars through.
              ;; mx already does this for JVMCI_VERSION_CHECK; we add gcc include/library paths.
              (substitute* "../graal/sdk/mx.sdk/mx_sdk_vm_impl.py"
                (("'-EJVMCI_VERSION_CHECK',")
                 (string-append "'-EJVMCI_VERSION_CHECK',\n"
                                "            '-EC_INCLUDE_PATH',\n"
                                "            '-ECPLUS_INCLUDE_PATH',\n"
                                "            '-ELIBRARY_PATH',\n"
                                "            '-ECPATH',  # C include path\n")))))
          (replace 'build
            (lambda _
              ;; Build Python for JVM with Graal JIT compiler using jvm-ce-libgraal env.
              (invoke "mx" "--user-home" (getcwd)
                      "--env" "jvm-ce-libgraal"
                      "build"
                      "--target" "GRAALPY_JVM_STANDALONE")))
          (replace 'install
            (lambda* (#:key outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (standalone-dir (car (find-files
                                           (string-append (getcwd) "/mxbuild-output/graalpython")
                                           "^GRAALPY_JVM_STANDALONE$"
                                           #:directories? #t))))
                (copy-recursively standalone-dir out)))))))
    (native-inputs
     (list (list "mx" graalvm-mx)
           ;; Use openjdk-for-graal which provides static JDK libraries
           ;; required for SubstrateVM's JvmFuncsFallbacks build task.
           (list "openjdk" openjdk-for-graal "jdk")
           (list "python" python-3)
           (list "graal-25.0.1-checkout" %graal-source)
           (list "java-asm" java-asm-for-graal-truffle)
           (list "java-asm-tree" java-asm-tree-for-graal-truffle)
           (list "java-asm-analysis" java-asm-analysis-for-graal-truffle)
           (list "java-asm-util" java-asm-util-for-graal-truffle)
           (list "java-asm-commons" java-asm-commons-for-graal-truffle)
           (list "java-antlr4-runtime" java-antlr4-runtime-for-graal-truffle)
           (list "java-hamcrest-core" java-hamcrest-core-for-graal-truffle)
           (list "java-icu4j" java-icu4j-for-graal-truffle)
           (list "java-icu4j-charset" java-icu4j-charset-for-graal-truffle)
           (list "java-xz" java-xz-for-graal-truffle)
           (list "java-jline-terminal" java-jline-terminal-for-graal-truffle)
           (list "java-jline-reader" java-jline-reader-for-graal-truffle)
           (list "java-jline-builtins" java-jline-builtins-for-graal-truffle)
           (list "java-jline-terminal-ffm" java-jline-terminal-ffm-for-graal-truffle)
           (list "java-json" java-json-for-graal-truffle)
           (list "java-capnproto-runtime" java-capnproto-runtime-for-graal-truffle)
           (list "java-bcprov" java-bcprov-for-graalpy)
           (list "java-bcutil" java-bcutil-for-graalpy)
           (list "java-bcpkix" java-bcpkix-for-graalpy)
           (list "java-trufflejws" java-trufflejws-for-graal)
           (list "ninja" ninja-for-graal-truffle)
           (list "cmake" cmake)
           (list "git" git-minimal)
           (list "libffi-3.4.8.tar.gz" (package-source libffi-for-graal-truffle))
           (list "bzip2-1.0.8.tar.gz" (package-source bzip2))
           (list "xz-5.6.2.tar.gz" (package-source xz-for-graal-truffle))))
    (inputs (list zlib
                  bzip2
                  xz))
    (home-page "https://www.graalvm.org/python/")
    (synopsis "Python 3.12 implementation on GraalVM")
    (description "GraalPy is a high-performance Python 3.12 implementation
built on the Truffle framework.  It provides Java interoperability and can
use the system toolchain for building C extensions.")
    (license upl1.0)))
