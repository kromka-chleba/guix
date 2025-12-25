;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2015, 2016 Roel Janssen <roel@gnu.org>
;;; Copyright © 2015, 2018 Pjotr Prins <pjotr.guix@thebird.nl>
;;; Copyright © 2017 Frederick Muriithi <fredmanglis@gmail.com>
;;; Copyright © 2017 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2017, 2019, 2022 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2020 Guy Fleury Iteriteka <gfleury@disroot.org>
;;; Copyright © 2021-2024 Efraim Flashner <efraim@flashner.co.il>
;;; Copyright © 2021, 2024 Maxim Cournoyer <maxim@guixotic.coop>
;;; Copyright © 2022 ( <paren@disroot.org>
;;; Copyright © 2022 Esther Flashner <esther@flashner.co.il>
;;; Copyright © 2025-2026 Jonas Meeuws <jonas.meeuws@gmail.com>
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

(define-module (gnu packages dlang)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module ((guix build utils) #:hide (delete which))
  #:use-module (guix build-system)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system cmake)
  #:use-module (guix build-system copy)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages check)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages gdb)
  #:use-module (gnu packages libedit)
  #:use-module (gnu packages llvm)
  #:use-module (gnu packages ninja)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages textutils)
  #:use-module (gnu packages xorg)
  #:use-module (srfi srfi-1))


;; Compilers and tooling for the D programming language.
;; Note: The GNU D compiler is defined in (gnu packages gcc) instead.

(define (force* arg)
  (if (promise? arg)
      (force arg)
      arg))

(define (gexp-list? l)
  (and (gexp? l)
       (list? (gexp->approximate-sexp l))))

(define* (gexp-if cond t #:optional (f #~()))
  (unless (every gexp-list? (list t f))
    (error "gexp-if: Not a GEXP list."))
  (if cond t f))

(define-public d-tools
  (package
    (name "d-tools")
    (version "2.105.3")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/dlang/tools")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0hvz786k0pi8697x1vk9x5bx52jiy7pvi13wmfkx15ddvv0x5j33"))))
    (build-system gnu-build-system)
    (arguments
     (list #:phases
           #~(modify-phases %standard-phases
               (delete 'configure)
               (replace 'build
                 (lambda _
                   (mkdir-p "bin")
                   (setenv "CC" #$(cc-for-target))
                   (setenv "LD" #$(ld-for-target))
                   (invoke "ldc2" "rdmd.d" "--of" "bin/rdmd")
                   (apply invoke "ldc2" "--of=bin/dustmite"
                          (find-files "DustMite" ".*\\.d"))))
               (replace 'check
                 (lambda* (#:key tests? #:allow-other-keys)
                   (when tests?
                     (invoke "bin/rdmd" "rdmd_test.d" "bin/rdmd"
                             "--rdmd-default-compiler" "ldmd2"))))
               (replace 'install
                 (lambda* (#:key outputs #:allow-other-keys)
                   (let* ((out (assoc-ref outputs "out"))
                          (bin (string-append out "/bin"))
                          (man (string-append out "/man")))
                     (for-each delete-file (find-files "bin" "\\.o$"))
                     (copy-recursively "bin" bin)
                     (copy-recursively "man" man)))))))
    (native-inputs
     (list ldc
           (module-ref (resolve-interface
                        '(gnu packages commencement))
                       'ld-gold-wrapper)))
    (home-page "https://github.com/dlang/tools")
    (synopsis "Useful D-related tools")
    (description
     "@code{d-tools} provides two useful tools for the D language: @code{rdmd},
which runs D source files as scripts, and @code{dustmite}, which reduces D code
to a minimal test case.")
    (license license:boost1.0)))

;; LLVM-based D compiler

;; FIXME/TODO: Use seperate output for libdruntime-ldc-shared and
;; libphobos-ldc-shared, to remove runtime dependency on ldc, llvm,
;; clang-runtime and clang for D applications. Add debug output.
(define* (make-ldc version hash
                   #:key
                   (name "ldc")
                   (frontend-version #f)

                   (bootstrap-dmd (delay gdmd-11))
                   (llvm (delay llvm))
                   (clang-runtime (delay clang-runtime))
                   (clang (delay clang)))
  (define (since-version? since) (version>=? version since))
  (define (until-version? until) (version>? until version))
  (define (dmd-test-path subpath)
    (string-append
     (if (until-version? "1.31")
         "tests/d2/dmd-testsuite"
         "tests/dmd")
     subpath))
  (define* (make-ldc-stage stage prev-stage)
    (package
      (name name)
      (version version)
      (source
       (origin
         (method git-fetch)
         (uri (git-reference
                (url "https://github.com/ldc-developers/ldc")
                (commit (string-append "v" version))
                (recursive? #t)))
         (file-name (git-file-name name version))
         (sha256 (base32 hash))))
      (inputs
       (list (force* llvm)
             (force* clang-runtime)
             libconfig
             zlib
             (force* clang) ; Used as a linker wrapper.
             tzdata         ; std.datetime.timezone
             curl           ; std.net.curl
             bash-minimal)) ; std.process
      (native-inputs
       (list (force* (cond ((= stage 1) bootstrap-dmd)
                           ((= stage 2) prev-stage)))
             (force* clang)
             lld-as-ld-wrapper
             ;; For testing
             (@* (gnu packages commencement) ld-gold-wrapper)
             gdb-16
             python-wrapper
             python-lit))
      (build-system cmake-build-system)
      (arguments
       (list
        ;; Note: In stage 1, allow references to the bootstrap compiler for
        ;; dynamic linking. In stage 2 those should not remain. Stage 2 might
        ;; still have internal error messages referencing stage 1 paths, which
        ;; is fine.
        #:disallowed-references
        (cond ((= stage 1) (list))
              ((= stage 2) (list (force* bootstrap-dmd))))
        #:generator "Ninja"
        #:configure-flags
        (if (target-riscv64?)
            #~'("-DCMAKE_EXE_LINKER_FLAGS=-latomic")
            #~'())
        #:build-type
        (cond ((= stage 1) "Debug")
              ((= stage 2) "RelWithDebInfo"))
        #:tests?
        (cond ((= stage 1) #f)
              ((= stage 2) #t))
        #:phases
        (let* ((target-file
                (lambda (pkg path)
                  (file-append (this-package-input pkg) path)))
               (native-file
                (lambda (pkg path)
                  (file-append (this-package-native-input pkg) path)))
               (target-bin-sh (target-file "bash-minimal" "/bin/sh"))
               (target-bin-clang (target-file "clang" "/bin/clang"))
               (target-clang-runtime (target-file "clang-runtime" ""))
               (target-lib-curl (target-file "curl" "/lib/libcurl.so"))
               (target-zoneinfo (target-file "tzdata" "/share/zoneinfo/"))
               (native-bin-clang (native-file "clang" "/bin/clang"))
               (native-bin-clang++ (native-file "clang" "/bin/clang++")))
          #~(modify-phases %standard-phases
              #$@(gexp-if
                  ;; LDC needs a C compiler as a linker wrapper.
                  ;; Change the default fallback "cc" to clang.
                  ;; Discovery implemented in ldc v1.19.0.
                  (since-version? "1.19.0")
                  (let ((file-to-patch (if (until-version? "1.33.0")
                                           "driver/tool.cpp"
                                           "driver/tool.h")))
                    #~((add-after 'patch-usr-bin-file 'patch-default-cc
                         (lambda _
                           (substitute* #$file-to-patch
                             (("\"cc\"")
                              (format #f "~s" #$target-bin-clang))))))))
              (add-after 'unpack 'patch-compiler-rt-library-discovery
                (lambda _
                  (let* ((system #$(or (%current-target-system)
                                       (%current-system)))
                         (arch (car (string-split system #\-)))
                         (clang-arch (cond
                                      ((string-suffix? "86" arch) "i386")
                                      (#t arch))))
                    ;; Coax LLVM into agreeing with Clang about system target
                    ;; naming.
                    (substitute* "driver/linker-gcc.cpp"
                      (("triple.getArchName\\(\\)")
                       (format #f "~s" clang-arch)))
                    ;; Augment the configuration of the ldc2 binaries so they
                    ;; can find the compiler-rt libraries they need to be
                    ;; linked with for the tests.
                    (substitute* (find-files "." "^ldc2.*\\.conf\\.in$")
                      ((".*LIB_SUFFIX.*" all)
                       (string-append all
                                      "        \""
                                      #$target-clang-runtime
                                      "/lib/linux\",\n"))))))
              #$@(gexp-if
                  ;; Using ImportC will always emit warnings when using gcc 14+
                  ;; as its preprocessor, causing tests that read stderr to
                  ;; fail.
                  ;; Introduced in ldc v1.29.0.
                  ;; Fixed (like this) in ldc v1.40.0.
                  (and (since-version? "1.29.0")
                       (until-version? "1.40.0"))
                  #~((add-after 'unpack 'patch-importc-system-header
                       (lambda _
                         (substitute* "runtime/druntime/src/importc.h"
                           (("^#define __IMPORTC__ 1.*$" all)
                            (string-append
                             all
                             "\n"
                             "#ifdef __GNUC__\n"
                             "#pragma GCC system_header\n"
                             "#endif\n")))))))
              ;; Using ImportC with clang as preprocessor will cause
              ;; ImportC to fail on glibc float headers.
              ;; Introduced in ldc v1.33.0.
              #$@(gexp-if
                  (since-version? "1.33.0")
                  (if (until-version? "1.41.0")
                      #~((add-after 'unpack 'patch-importc-float128
                           (lambda _
                             (substitute* "runtime/druntime/src/importc.h"
                               (("^#ifndef __aarch64__.*$")
                                (string-append
                                 "#if !defined(__aarch64__) && defined(__clang__)\n"
                                 "#define __float128 long double\n"
                                 "#elif !defined(__aarch64__)\n"))))))
                      #~((add-after 'unpack 'patch-importc-float128
                           (lambda _
                             (substitute* "runtime/druntime/src/importc.h"
                               (("^#ifndef __clang__.*$")
                                (string-append
                                 "#ifdef __clang__\n"
                                 "#define __float128 long double\n"
                                 "#else\n"))))))))
              #$@(gexp-if
                  ;; The ldc-profgen tool is broken in ldc v1.36.0.
                  (and (since-version? "1.36.0")
                       (until-version? "1.37.0"))
                  #~((add-after 'unpack 'disable-ldc-profgen
                       (lambda _
                         (delete-file-recursively "tools/ldc-profgen")))))
              (add-after 'unpack 'patch-paths-in-phobos
                (lambda _
                  (with-directory-excursion "runtime/phobos"
                    (substitute* "std/datetime/timezone.d"
                      (("\"/usr/share/zoneinfo/\"")
                       (format #f "~s" #$target-zoneinfo)))
                    (substitute* "std/net/curl.d"
                      (("\"libcurl\\.so\"")
                       (format #f "~s" #$target-lib-curl)))
                    (substitute* "std/process.d"
                      (("return \"/bin/sh\";")
                       (format #f "return ~s;" #$target-bin-sh))
                      (("#!/bin/sh")
                       (string-append "#!" #$target-bin-sh))))))
              (add-after 'unpack 'patch-getInstalledTZNames-infinite-symlink
                (lambda _
                  ;; Disable following directory symlinks when iterating tzdata.
                  (substitute* "runtime/phobos/std/datetime/timezone.d"
                    (("SpanMode\\.depth\\)") "SpanMode.depth, false)"))))
              (add-after 'unpack 'patch-tests
                (lambda _
                  ;; Patch a shell path in the dmd tests Makefile.
                  ;; The file was fully replaced with run.d in ldc v1.37.0.
                  #$@(gexp-if
                      (until-version? "1.37.0")
                      #~((substitute* #$(dmd-test-path "/Makefile")
                           (("SHELL=/bin/bash")
                            (string-append "SHELL=" #$target-bin-sh)))))

                  ;; Fails often. Relies on guessing the test binary size,
                  ;; sleeps, and file timestamps.
                  ;; Introduced in ldc v1.1.0.
                  #$@(gexp-if
                      (since-version? "1.1.0")
                      #~((delete-file "tests/linking/ir2obj_cache_pruning2.d")))

                  ;; Very unreliable.
                  ;; Introduced in ldc v1.4.0.
                  #$@(gexp-if
                      (since-version? "1.4.0")
                      #~((delete-file "tests/sanitizers/fuzz_asan.d")))

                  ;; These 2 tests try to build a Makefile on their own.
                  ;; Introduced in ldc v1.8.0.
                  #$@(gexp-if
                      (since-version? "1.8.0")
                      #~((delete-file-recursively "tests/plugins")))

                  ;; This test doesn't expect the linker to demangle D symbols.
                  ;; Introduced in ldc v1.8.1.
                  #$@(gexp-if
                      (since-version? "1.8.1")
                      #~((substitute*
                             #$(dmd-test-path "/fail_compilation/needspkgmod.d")
                           (("_D7imports9pkgmod3133mod3barFZv")
                            "imports.pkgmod313.mod.bar()"))))

                  ;; Our gdb is more clever than expected.
                  ;; Introduced in ldc v1.13.0. Fixed (like this) in v1.40.0.
                  #$@(gexp-if
                      (and (since-version? "1.13.1")
                           (until-version? "1.40.0"))
                      #~((substitute* "tests/debuginfo/print_gdb.d"
                           (("GDB: p b_Glob")
                            "GDB: p inputs.import_b.b_Glob"))))

                  ;; These CTFE tests fail on riscv64-linux.
                  ;; Test for signbit introduced in ldc v1.19.0.
                  ;; Test for getNaNPayload introduced in vldc 1.25.0.
                  ;; std.math was split into modules in vldc 1.27.0.
                  #$@(gexp-if
                      (target-riscv64?)
                      (let ((comment (lambda (line) (string-append "// " line)))
                            (nan-rgx "static assert\\(getNaNPayload\\(a\\)")
                            (signbit-rgx "static assert\\(signbit\\(-.*\\.nan"))
                        (cond
                         ((and (since-version? "1.19.0")
                               (until-version? "1.27.0"))
                          #~((substitute* "runtime/phobos/std/math.d"
                               ((nan-rgx line) (comment line))
                               ((signbit-rgx line) (comment line)))))
                         ((since-version? "1.27.0")
                          #~((substitute* "runtime/phobos/std/math/operations.d"
                               ((nan-rgx line) (comment line)))
                             (substitute* "runtime/phobos/std/math/traits.d"
                               ((signbit-rgx line) (comment line))))))))

                  ;; This test creates a shell script and runs it.
                  ;; Introduced in ldc v1.22.0.
                  #$@(gexp-if
                      (since-version? "1.22.0")
                      #~((substitute* #$(dmd-test-path "/dshell/test6952.d")
                           (("/usr/bin/env bash") #$target-bin-sh))))

                  ;; Fails to detect the race condition for some reason.
                  ;; Introduced in ldc v1.23.0.
                  #$@(gexp-if
                      (since-version? "1.23.0")
                      #~((for-each delete-file
                                   '("tests/sanitizers/tsan_tiny_race.d"
                                     "tests/sanitizers/tsan_tiny_race_TLS.d"))))

                  ;; Ditto.
                  ;; Introduced in ldc v1.27.0.
                  #$@(gexp-if
                      (since-version? "1.27.0")
                      #~((for-each delete-file
                                   '("tests/sanitizers/msan_noerror.d"
                                     "tests/sanitizers/msan_uninitialized.d"))))

                  ;; Ditto.
                  ;; Introduced in ldc v1.30.0.
                  #$@(gexp-if
                      (since-version? "1.30.0")
                      #~((for-each delete-file
                                   '("tests/sanitizers/lsan_memleak.d"))))

                  ;; Doesn't compile due to implicit int error.
                  ;; Introduced in ldc v1.31.0.
                  ;; Fixed in ldc v1.38.0.
                  #$@(gexp-if
                      (and (since-version? "1.31.0")
                           (until-version? "1.38.0"))
                      #~((substitute* "runtime/druntime/test/shared/src/host.c"
                           (("const fullpathsize")
                            "const size_t fullpathsize"))))

                  ;; Also related to ImportC with clang breaking on floats.
                  ;; Introduced in ldc v1.36.0
                  ;; Fixed (like this) in ldc v1.41.0.
                  #$@(gexp-if
                      (and (since-version? "1.36.0")
                           (until-version? "1.41.0"))
                      #~((delete-file
                          #$(dmd-test-path "/compilable/fix24187.c"))))

                  ;; Patch a shell path in the druntime profile test Makefile.
                  ;; Introduced in ldc v1.34.0.
                  #$@(gexp-if
                      (since-version? "1.34.0")
                      #~((substitute* "runtime/druntime/test/profile/Makefile"
                           (("SHELL=/bin/bash")
                            (string-append "SHELL=" #$target-bin-sh)))))

                  ;; Since the implementation of SOURCE_DATE_EPOCH support in
                  ;; Ddoc, this test fails, as it expects Ddoc timestamps to
                  ;; match the output of the `date` command.
                  ;; Introduced in ldc v1.36.0.
                  #$@(gexp-if
                      (since-version? "1.36.0")
                      #~((substitute* #$(dmd-test-path
                                         (string-append
                                          "/compilable/extra-files"
                                          "/ddocYear-postscript.sh"))
                           (("^YEAR=.*$") "YEAR=1970\n"))))

                  ;; This tests how the CC env var is handled by the compiler,
                  ;; by setting it to cc, which we don't have.
                  ;; Introduced in ldc v1.37.0.
                  #$@(gexp-if
                      (since-version? "1.37.0")
                      #~((delete-file "tests/driver/cli_CC_envvar.d")))

                  ;; One of these tests hangs when a modern llvm opt is applied.
                  ;; Fix by only running debug builds.
                  ;; Introduced in ldc v1.41.0.
                  #$@(gexp-if
                      (since-version? "1.41.0")
                      #~((substitute*
                             "runtime/druntime/test/exceptions/Makefile"
                           (("TESTS\\+=memoryerror.*$" all)
                            (string-append
                             "ifeq ($(BUILD),debug)\n" all "endif\n")))))

                  ;; The following tests fail on some systems, not all of
                  ;; which are tested upstream.
                  (for-each
                   (lambda (path) (false-if-file-not-found (delete-file path)))
                   (list
                    #$@(gexp-if
                        (or (target-x86-32?)
                            (target-arm32?))
                        #~(#$(dmd-test-path "/runnable_cxx/cppa.d")
                           "tests/codegen/mangling.d"
                           "tests/instrument/xray_check_pipeline.d"
                           "tests/instrument/xray_link.d"
                           "tests/instrument/xray_simple_execution.d"
                           "tests/PGO/profile_rt_calls.d"
                           "tests/sanitizers/msan_noerror.d"
                           "tests/sanitizers/msan_uninitialized.d"))
                    #$@(gexp-if
                        (target-riscv64?)
                        #~(#$(dmd-test-path "/codegen/simd_alignment.d")
                           #$(dmd-test-path "/compilable/test23705.d")
                           #$(dmd-test-path "/fail_compilation/diag7420.d")
                           #$(dmd-test-path "/runnable/argufilem.d")
                           #$(dmd-test-path "/runnable_cxx/cppa.d")))))))
              ;; The tests require to be built with Clang; build everything
              ;; with it, for simplicity.
              (add-before 'configure 'set-cc
                (lambda _
                  (setenv "CC" #$native-bin-clang)
                  (setenv "CXX" #$native-bin-clang++)))
              ;; The test targets are tested separately to provide
              ;; finer-grained diagnostics (see the `.github/actions/4*`
              ;; files in the source).
              (replace 'check
                (lambda* (#:key tests? parallel-tests? #:allow-other-keys)
                  (define* (run-tests name includes excludes
                                      #:key
                                      (job-count (if parallel-tests?
                                                     (parallel-job-count)
                                                     1)))
                    (define (regex-flags prefix patterns)
                      (if (> (length patterns) 0)
                          (list prefix
                                (format #f "(~a)" (string-join patterns "|")))
                          '()))
                    (format #t "running the ~a...\n" name)
                    (apply invoke
                           `("ctest"
                             "--output-on-failure"
                             "-j" ,(number->string job-count)
                             ,@(regex-flags "-R" includes)
                             ,@(regex-flags "-E" excludes))))
                  (when tests?
                    (run-tests "ldc2 unit tests"
                               (list "ldc2-unittest")
                               (list))
                    (run-tests "lit test suite"
                               (list "lit-tests")
                               (list))
                    ;; This test has a race condition so run it with 1 core.
                    (run-tests "dmd test suite"
                               (list "dmd-testsuite")
                               (list)
                               #:job-count 1)
                    (run-tests "druntime unit tests"
                               (list "druntime-test-runner"
                                     "^core\\."
                                     "^etc\\.linux" "etc\\.valgrind"
                                     "^ldc\\."
                                     "^object"
                                     "^rt\\.")
                               (list #$@(gexp-if
                                         (target-riscv64?)
                                         ;; These hang forever
                                         #~("core.thread.fiber-.*shared"
                                            "core.thread.osthread-.*shared"))))
                    (run-tests "druntime integration tests"
                               (list "druntime-test")
                               (list "druntime-test-runner"
                                     #$@(gexp-if
                                         (target-aarch64?)
                                         #~("druntime-test-exceptions-debug"))))
                    ;; Building these tests is very resource intensive, so
                    ;; limit the job count.
                    (run-tests
                     "phobos unit tests"
                     (list "phobos"
                           "etc\\.c\\."
                           "^std")
                     (list #$@(gexp-if
                               (target-aarch64?)
                               #~("std.internal.math.gammafunction-.*shared"
                                  "std.math.exponential-shared"))
                           #$@(gexp-if
                               (target-riscv64?)
                               #~("std.internal.math.errorfunction-.*shared"
                                  "std.internal.math.gammafunction-.*shared"
                                  "std.math.exponential-.*shared"
                                  "std.math.operations-debug-shared"
                                  "std.math.traits-debug-shared"
                                  "std.math.trigonometry-.*shared"
                                  "std.mathspecial-.*shared"
                                  "std.socket-debug-shared"
                                  "std.socket-shared")))
                     #:job-count 1))))))))
      (properties
       ;; Some of the tests take a very long time on ARMv7.  See
       ;; https://lists.gnu.org/archive/html/guix-devel/2018-02/msg00312.html.
       (if (target-arm32?)
           `((max-silent-time . ,(* 3600 3)))
           '()))
      (home-page "http://wiki.dlang.org/LDC")
      (synopsis "LLVM-based compiler for the D programming language")
      (description
       (string-append
        "The LDC project provides a portable D programming language compiler
with modern optimization and code generation capabilities.  The compiler uses
the official DMD frontend to support the latest version of D2, and relies on the
LLVM Core libraries for code generation."
        (if frontend-version
            (format
             #f "~%~%This compiler is based on the DMD frontend version ~a."
             frontend-version)
            "")))
      ;; Most of the code is released under BSD-3, except for code originally
      ;; written for GDC, which is released under GPLv2+, and the DMD frontend
      ;; and druntime library which are released under the
      ;; "Boost Software License version 1.0".
      (license (list license:bsd-3
                     license:gpl2+
                     license:boost1.0))))
  (let* ((stage1 (make-ldc-stage 1 #f))
         (stage2 (make-ldc-stage 2 stage1)))
    stage2))

(define-public ldc-1.25
  (make-ldc "1.25.1" "0h30gzl8fl6c5gjf3xrrjj4i6m5r1mzn6y5g8vkir3y0z0mgpd31"
            #:frontend-version "2.095.1"
            #:llvm (delay llvm-12)
            #:clang-runtime (delay clang-runtime-12)))
(define-public ldc-1.26
  (make-ldc "1.26.0" "045y488ccdkbgldhwkaiiwmvbfi4nh1d7nk0ixwbldm5mcxlklbr"
            #:frontend-version "2.096.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-12)
            #:clang-runtime (delay clang-runtime-12)))
(define-public ldc-1.27
  (make-ldc "1.27.1" "1ry3zflnnd6lwyca7qr5cah948didmlv52xrhlw0z6pfb1ym8lq9"
            #:frontend-version "2.097.2"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-12)
            #:clang-runtime (delay clang-runtime-12)))
(define-public ldc-1.28
  (make-ldc "1.28.1" "0gjvx98nv7vx7ddsv2cwzhwk9z9qsy70572whh0g65pxp5nsdiaa"
            #:frontend-version "2.098.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-12)
            #:clang-runtime (delay clang-runtime-12)))
(define-public ldc-1.29
  (make-ldc "1.29.0" "0q8lhap4j13z0g6mhc404mcr12dqkiwc1hl13iw70zls5bdfy78j"
            #:frontend-version "2.099.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-14)
            #:clang-runtime (delay clang-runtime-14)))
(define-public ldc-1.30
  (make-ldc "1.30.0" "1x7hhvs2qcyzmpf8wjzhhxximpxc37hwxs5qycil5f8bjps1agi3"
            #:frontend-version "2.100.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-14)
            #:clang-runtime (delay clang-runtime-14)))
(define-public ldc-1.31
  (make-ldc "1.31.0" "1zv321jw5y0vvggfky8chrr4m9cm2xs71w0qik4sizp4286msjy7"
            #:frontend-version "2.101.2"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-14)
            #:clang-runtime (delay clang-runtime-14)))
(define-public ldc-1.32
  (make-ldc "1.32.2" "0h5h960ydcx2i786i8z8wyw5i8mwvwmnr0j6q8fy8cmpmi8hw3rd"
            #:frontend-version "2.102.2"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-15)
            #:clang-runtime (delay clang-runtime-15)))
(define-public ldc-1.33
  (make-ldc "1.33.0" "0yjgpn08y91bx8ffcl3aabgbwvvf85xl8ddpa0ji89zfvcbfn1in"
            #:frontend-version "2.103.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-15)
            #:clang-runtime (delay clang-runtime-15)))
(define-public ldc-1.34
  (make-ldc "1.34.0" "1hg0053dm06ndf4mapiihv0vz1p3l1q2ywc3zbxh9x0xz8axi9v3"
            #:frontend-version "2.104.2"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-16)
            #:clang-runtime (delay clang-runtime-16)))
(define-public ldc-1.35
  (make-ldc "1.35.0" "19i554n02sxvpy8mmq1sk0as9qaz2wl7zgw6jaffyids92y9barw"
            #:frontend-version "2.105.2"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-16)
            #:clang-runtime (delay clang-runtime-16)))
(define-public ldc-1.36
  (make-ldc "1.36.0" "1z22zhy10j1gy77zrszk0rp48wf86mvrz12jpvass8mx02z3wmxl"
            #:frontend-version "2.106.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-17)
            #:clang-runtime (delay clang-runtime-17)))
(define-public ldc-1.37
  (make-ldc "1.37.0" "0lk0b35ng8hna1m8srriys7aiiyj5c1rvwyflnfw963dc9x7li2k"
            #:frontend-version "2.107.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-17)
            #:clang-runtime (delay clang-runtime-17)))
(define-public ldc-1.38
  (make-ldc "1.38.0" "068gqv368mhi9jywk9dcx9xssywcix5ypixxs9hi87cz3w913xbp"
            #:frontend-version "2.108.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-18)
            #:clang-runtime (delay clang-runtime-18)))
(define-public ldc-1.39
  (make-ldc "1.39.0" "0spa8170sm4lskjq2qja1ciymyz16j7dvb3vv8p0ps0q7c0v88b6"
            #:frontend-version "2.109.1"
            #:bootstrap-dmd ldc-1.25
            #:llvm (delay llvm-18)
            #:clang-runtime (delay clang-runtime-18)))
(define-public ldc ldc-1.38)

;;; Bootstrap version of phobos that is built with GDC, using GDC's standard
;;; library.
(define dmd-bootstrap
  (package
    ;; This package is purposefully named just "dmd" and not "dmd-bootstrap",
    ;; as the final dmd package rewrites references from this one to itself,
    ;; and their names must have the same length to avoid corrupting the
    ;; binary.
    (name "dmd")
    (version "2.106.1")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/dlang/dmd")
                    (commit (string-append "v" version))))
              (file-name (git-file-name "dmd" version))
              (sha256
               (base32
                "1bq4jws1vns2jjzfz7biyngrx9y5pvvgklymhrvb5kvbzky1ldmy"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:disallowed-references (list (gexp-input (canonical-package gcc)
                                                "lib"))
      ;; Disable tests, as gdmd cannot cope with some arguments used such as
      ;; '-conf'.
      #:tests? #f
      #:test-target "test"
      #:make-flags
      #~(list (string-append "CC=" #$(cc-for-target))
              ;; XXX: Proceed despite conflicts from symbols provided by both
              ;; the source built and GDC.
              "DFLAGS=-L--allow-multiple-definition"
              "ENABLE_RELEASE=1"
              (string-append "HOST_CXX=" #$(cxx-for-target))
              "HOST_DMD=gdmd"
              (string-append "INSTALL_DIR=" #$output)
              ;; Do not build the shared libphobos2.so library, to avoid
              ;; retaining a reference to gcc:lib.
              "SHARED=0"
              (string-append "SYSCONFDIR=" #$output "/etc")
              "VERBOSE=1"
              "-f" "posix.mak")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'copy-phobos-source-and-chdir
            ;; Start with building phobos, which in turns will automatically
            ;; build druntime and dmd.  A minimal dmd command is still
            ;; required to do so, which is why we need dmd-bootstrap-0.
            (lambda _
              (symlink "." "dmd")  ;to please the build system expected layout
              (copy-recursively
               #$(this-package-native-input (git-file-name "phobos" version))
               "phobos")
              (chdir "phobos")))
          (add-after 'copy-phobos-source-and-chdir 'adjust-phobos-install-dirs
            (lambda _
              (substitute* "posix.mak"
                ;; Install to lib directory, not to e.g. 'linux/lib64'.
                (("\\$\\(INSTALL_DIR)/\\$\\(OS)/\\$\\(lib_dir)")
                 (string-append #$output "/lib"))
                ;; Do not install license file, already done by the gnu build
                ;; system.
                ((".*\\$\\(INSTALL_DIR)/phobos-LICENSE.txt.*") ""))))
          (delete 'configure)
          (add-after 'install 'install-druntime
            (lambda args
              (chdir "../druntime")
              (apply (assoc-ref %standard-phases 'install) args)
              (chdir "..")))
          (add-after 'install-druntime 'install-includes
            (lambda _
              ;; Normalize the include files prefix to include/dmd.
              (let ((include-dir (string-append #$output "/include/dmd")))
                (mkdir-p include-dir)
                (rename-file (string-append #$output "/src/phobos")
                             (string-append include-dir))
                (copy-recursively "druntime/import" include-dir))
              (delete-file-recursively (string-append #$output "/src"))))
          (add-after 'install-druntime 'install-dmd
            (assoc-ref %standard-phases 'install))
          (add-after 'install-license-files 'refine-install-layout
            (lambda _
              (let* ((docdir (string-append #$output "/share/doc/"
                                            (strip-store-file-name #$output)))
                     ;; The dmd binary gets installed to
                     ;; e.g. /linux/bin64/dmd.
                     (dmd (car (find-files #$output "^dmd$")))
                     (dmd.conf (car (find-files #$output "^dmd.conf$")))
                     (os-dir (dirname (dirname dmd))))
                ;; Move samples from root to the doc directory.
                (rename-file (string-append #$output "/samples")
                             (string-append docdir "/samples"))
                ;; Remove duplicate license file.
                (delete-file (string-append #$output
                                            "/dmd-boostlicense.txt"))
                ;; Move dmd binary and dmd.conf.
                (install-file dmd (string-append #$output "/bin"))
                (install-file dmd.conf (string-append #$output "/etc"))
                (delete-file-recursively os-dir))))
          (add-after 'refine-install-layout 'patch-dmd.conf
            (lambda* (#:key outputs #:allow-other-keys)
              (substitute* (search-input-file outputs "etc/dmd.conf")
                (("lib(32|64)")
                 "lib")
                (("\\.\\./src/(phobos|druntime/import)")
                 "include/dmd")))))))
    (native-inputs (list gdmd which
                         (origin
                           (method git-fetch)
                           (uri (git-reference
                                 (url "https://github.com/dlang/phobos")
                                 (commit (string-append "v" version))))
                           (file-name (git-file-name "phobos" version))
                           (sha256
                            (base32
                             "1yw7nb5d78cx9m7sfibv7rfc7wj3w0dw9mfk3d269qpfpnwzs4n9")))))
    (home-page "https://github.com/dlang/dmd")
    (synopsis "Reference D Programming Language compiler")
    (description "@acronym{DMD, Digital Mars D compiler} is the reference
compiler for the D programming language.")
    ;; As reported by upstream:
    ;; https://wiki.dlang.org/Compilers#Comparison
    (supported-systems '("i686-linux" "x86_64-linux"))
    (license license:boost1.0)))

;;; Second bootstrap of DMD, built using dmd-bootstrap, with its shared
;;; libraries preserved.
(define-public dmd
  (package
    (inherit dmd-bootstrap)
    (arguments
     (substitute-keyword-arguments
         (strip-keyword-arguments
          '(#:tests?)                   ;reinstate tests
          (package-arguments dmd-bootstrap))
       ((#:disallowed-references  _ ''())
        (list dmd-bootstrap))
       ((#:modules _ ''())
        '((guix build gnu-build-system)
          (guix build utils)
          (srfi srfi-1)))               ;for fold
       ((#:make-flags flags ''())
        #~(fold delete #$flags '("DFLAGS=-L--allow-multiple-definition"
                                 "HOST_DMD=gdmd"
                                 "SHARED=0")))
       ((#:phases phases '%standard-phases)
        #~(modify-phases #$phases
            (add-after 'patch-dmd.conf 'rewrite-references-to-bootstrap
              ;; DMD keeps references to include files used to build a
              ;; binary.  Rewrite those of dmd-bootstrap to itself, to reduce
              ;; its closure size.
              (lambda* (#:key native-inputs inputs outputs
                        #:allow-other-keys)
                (let ((dmd (search-input-file outputs "bin/dmd"))
                      (dmd-bootstrap (dirname
                                      (dirname
                                       (search-input-file
                                        (or native-inputs inputs)
                                        "bin/dmd")))))
                  ;; XXX: Use sed, as replace-store-references wouldn't
                  ;; replace the references, while substitute* throws an
                  ;; error.
                  (invoke "sed" "-i"
                          (format #f "s,~a,~a,g" dmd-bootstrap #$output)
                          dmd))))))))
    (native-inputs (modify-inputs (package-native-inputs dmd-bootstrap)
                     (replace "gdmd" dmd-bootstrap)))))

(define-public dub
  (package
    (name "dub")
    (version "1.33.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/dlang/dub")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "09p3rvsv11f8lgqgxgz2zj0szsw5lzrsc7y7471hswksc7nmmj70"))))
    (build-system gnu-build-system)
    (arguments
     (list #:tests? #f                  ; tests try to install packages
           #:phases
           #~(modify-phases %standard-phases
               (delete 'configure)      ; no configure script
               (replace 'build
                 (lambda _
                   (setenv "CC" #$(cc-for-target))
                   (setenv "LD" #$(ld-for-target))
                   (invoke "./build.d")))
               (replace 'install
                 (lambda* (#:key outputs #:allow-other-keys)
                   (let* ((out (assoc-ref outputs "out"))
                          (bin (string-append out "/bin")))
                     (install-file "bin/dub" bin)))))))
    (inputs
     (list curl))
    (native-inputs
     (list d-tools
           ldc
           (module-ref (resolve-interface
                        '(gnu packages commencement))
                       'ld-gold-wrapper)))
    (home-page "https://code.dlang.org/getting_started")
    (synopsis "Package and build manager for D projects")
    (description
     "DUB is a package and build manager for applications and
libraries written in the D programming language.  It can
automatically retrieve a project's dependencies and integrate
them in the build process.

The design emphasis is on maximum simplicity for simple projects,
while providing the opportunity to customize things when
needed.")
    (license license:expat)))

(define-public gtkd
  (package
    (name "gtkd")
    (version "3.10.0")
    (source
     (origin
      (method url-fetch/zipbomb)
      (uri (string-append "https://gtkd.org/Downloads/sources/GtkD-"
                          version ".zip"))
      (sha256
       (base32 "0vc5ssb3ar02mg2pngmdi1xg4qjaya8332a9mk0sv97x6b4ddy3g"))))
    (build-system gnu-build-system)
    (native-inputs
     (list unzip
           ldc
           pkg-config
           xorg-server-for-tests))
    (arguments
     `(#:test-target "test"
       #:make-flags
       `("DC=ldc2"
         ,(string-append "prefix=" (assoc-ref %outputs "out"))
         ,(string-append "libdir=" (assoc-ref %outputs "out") "/lib")
         "pkgconfigdir=lib/pkgconfig")
       #:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (add-before 'build 'patch-makefile
           (lambda* (#:key outputs #:allow-other-keys)
             (substitute* "GNUmakefile"
               ;; We do the tests ourselves.
               (("default-goal: libs test") "default-goal: libs")
               (("all: libs shared-libs test") "all: libs shared-libs")
               ;; Work around upstream bug.
               (("\\$\\(prefix\\)\\/\\$\\(libdir\\)") "$(libdir)"))))
         (add-before 'check 'pre-check
           (lambda _
             (system "Xvfb :1 &")
             (setenv "DISPLAY" ":1")
             (setenv "CC" ,(cc-for-target)))))))
    (home-page "https://gtkd.org/")
    (synopsis "D binding and OO wrapper of GTK+")
    (description "This package provides bindings to GTK+ for D.")
    (license license:lgpl2.1)))

(define-public d-demangler
  (package
    (name "d-demangler")
    (version "0.0.2")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/lievenhey/d_demangler")
                    (commit (string-append "version-" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "13lbbxlaa1mffjs57xchl1g6kyr5lxi0z5x7snyvym0knslxwx2g"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f                       ;no test suite
      #:make-flags #~(list (string-append "CC=" #$(cc-for-target))
                           "d_demangle")
      #:phases #~(modify-phases %standard-phases
                   (delete 'configure)
                   (replace 'install
                     (lambda _
                       (install-file "libd_demangle.so"
                                     (string-append #$output "/lib")))))))
    (native-inputs (list dmd))
    (home-page "https://github.com/lievenhey/d_demangler")
    (synopsis "Utility to demangle D symbols")
    (description "@command{d_demangle} is a small utility that can be used to
demangle D symbols.  A shared library is also provided.")
    (license license:gpl3+)))
