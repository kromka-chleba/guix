;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2017 Dave Love <fx@gnu.org>
;;; Copyright © 2018, 2019, 2020 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2022 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2023, 2025 dan <i@dan.games>
;;; Copyright © 2025 Luca Cirrottola <luca.cirro@gmail.com>
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

(define-module (gnu packages profiling)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:) ; avoid zlib, expat clashes
  #:use-module (guix download)
  #:use-module (guix utils)
  #:use-module (guix build-system cmake)
  #:use-module (guix build-system gnu)
  #:use-module (gnu packages)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages base)      ;for "which"
  #:use-module (gnu packages bash)      ;for "which"
  #:use-module (gnu packages bison)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages cpp)
  #:use-module (gnu packages documentation)
  #:use-module (gnu packages engineering)
  #:use-module (gnu packages fabric-management)
  #:use-module (gnu packages flex)
  #:use-module (gnu packages fontutils)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages libunwind)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages mpi)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages xdisorg))

;; Fixme: Separate out lib and fix resulting cycle errors; separate libpfm
;; output(?); build libmsr and add that component.
(define-public papi
  (package
    (name "papi")
    (version "6.0.0.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://icl.utk.edu/projects/papi/downloads/papi-"
                           version ".tar.gz"))
       (sha256
        (base32 "0zr83v51lp4ijgk997dz9fpph48prlsbml26dvb223avqr8fvmrw"))
       (modules '((guix build utils)))
       (snippet
        '(begin
           ;; Remove bundled software.
           (for-each delete-file-recursively
                     '("src/libpfm-3.y" "src/libpfm4"
                       "src/perfctr-2.6.x"
                       "src/perfctr-2.7.x"))

           ;; Adjust include directives.
           (substitute* "src/components/lmsensors/linux-lmsensors.c"
             (("<sensors.h>")
              "<sensors/sensors.h>"))))))
    (build-system gnu-build-system)
    (inputs
     (list ncurses
           rdma-core
           libpfm4
           `(,lm-sensors "lib")
           `(,infiniband-diags "lib")
           net-tools))
    (native-inputs
     (list gcc-13
           gfortran-13))
    (arguments
     (list #:tests? #f                            ;no check target
           #:configure-flags
           ;; These are roughly per Fedora, but elide mx (assumed to be dead, even
           ;; Open-MX) and add and powercap -- I don't know the pros/cons of
           ;; infiniband and infiniband_mad, but you can't use them together, and
           ;; the umad version needs at least one patch.
           ;; Implicit enabled components: perf_event perf_event_uncore
           #~`("--with-perf-events" "--with-shared-lib=yes" "--with-shlib"
               "--with-static-lib=no" "--with-shlib-tools"
               "--with-components=appio coretemp example lustre micpower net rapl \
stealtime lmsensors infiniband powercap"
               ;; So utils get rpath set correctly:
               ,(string-append "LDFLAGS=-Xlinker -rpath -Xlinker "
                               #$output "/lib")
               ,(string-append "--with-pfm-prefix="
                               #$(this-package-input "libpfm4")))

           #:phases
           #~(modify-phases %standard-phases
               (add-after 'unpack 'change-directory
                 (lambda _
                   (chdir "src")

                   ;; Work around a mistake whereby 'configure' would always error
                   ;; out when passing '--with-static-lib=no'.
                   (substitute* "configure"
                     (("test \"\\$static_lib\" = \"no\"")
                      "false"))))
               (add-after 'install 'extra-doc
                 (lambda* (#:key outputs #:allow-other-keys)
                   (let ((doc (string-append (assoc-ref outputs "out")
                                             "/share/doc/"
                                             #$name "-" #$version)))
                     (chdir "..")                   ; we went into src above
                     (for-each (lambda (file)
                                 (install-file file doc))
                               '("README.md" "RELEASENOTES.txt"))))))))
    (home-page "https://icl.utk.edu/papi/")
    (synopsis "Performance Application Programming Interface")
    (description
     "PAPI provides the tool designer and application engineer with a consistent
interface and methodology for use of the performance counter hardware found in
most major microprocessors.  PAPI enables software engineers to see, in near
real time, the relation between software performance and processor events.

In addition, PAPI provides access to a collection of components that expose
performance measurement opportunities across the hardware and software stack.")
    (properties
     '((release-monitoring-url
        . "http://icl.cs.utk.edu/papi/software/")))
    ;; See Debian papi copyright file.
    (license (list license:bsd-3
                   license:lgpl2.1+        ;src/components/infiniband/pscanf.h
                   ;; not used in output
                   license:gpl2+ ;src/components/appio/tests/iozone/gengnuplot.sh
                   ))))

;; NB. there's a potential name clash with libotf.
(define-public otf2
  (package
    (name "otf2")
    (version "3.1.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/tags/otf2-"
                           version "/otf2-" version ".tar.gz"))
       (sha256 (base32 "0vhai3xsb1kbqy2fqcvzv9pk886p1iq5pi9mzsadfkmca4x02kjs"))))
    (native-inputs (list python))
    (outputs '("doc"                              ; 21MB
               "lib"
               "out"))
    (build-system gnu-build-system)
    (arguments
     `(#:configure-flags '("--enable-shared" "--disable-static")
       #:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'normalize-pkgconfig-files-location
           (lambda _
             ;; Prevent lib/pkgconfig/otf2-backend.pc from referencing the
             ;; prefix of output "out" from the "lib" store location.
             (substitute* "otf2-build.pc.in"
               (("^prefix=.*") "")
               (("^exec_prefix=.*") ""))))
         (add-after 'install 'licence
           (lambda* (#:key outputs #:allow-other-keys)
             (for-each (lambda (output)
                         (let ((doc (string-append (assoc-ref outputs output)
                                                   "/share/doc/otf2")))
                           (install-file "COPYING" doc)))
                       '("lib" "doc"))
             #t)))))
    (home-page "https://www.vi-hps.org/projects/score-p/")
    (synopsis "Open Trace Format 2 library")
    (description "The Open Trace Format 2 (@dfn{OTF2}) is a scalable,
memory-efficient event trace data format plus support library.")
    (license license:bsd-3)))

(define-public opari2
  (package
    (name "opari2")
    (version "2.0.9")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://perftools.pages.jsc.fz-juelich.de/cicd/opari2/tags/opari2-"
                           version "/opari2-" version ".tar.gz"))
       (sha256
        (base32 "0yfpzxy70wp6mwi6pvvc9a6bkaal14yysiddmvx6lrn5azvkjwfm"))))
    (build-system gnu-build-system)
    (inputs (list gfortran))
    (native-inputs (list gawk ; for tests
                         which))
    (home-page "https://www.vi-hps.org/projects/score-p")
    (synopsis "OpenMP runtime performance measurement instrumenter")
    (description "OPARI2 is a source-to-source instrumentation tool for OpenMP
and hybrid codes.  It surrounds OpenMP directives and runtime library calls
with calls to the POMP2 measurement interface.")
    (license license:bsd-3)))

;; Since version 4.4, CUBE has been split in three different packages: CubeW,
;; CubeLib, CubeGUI. They are still released together, so we conventionally
;; define cubew as the parent package for cubelib and cubegui to factorize
;; common data.
(define-public cubew
  (package
    (name "cubew")
    (version "4.9")
    (source
     (origin
       (method url-fetch)
       (uri
        (string-append "https://apps.fz-juelich.de/scalasca/releases/cube/"
                       version "/dist/cubew-"
                       version ".tar.gz"))
       (sha256
        (base32 "1pdcs8688y4nwcxshgs9773xmdajxahsbjsrfh8m7gv9qn0lxxsf"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:configure-flags
      #~(list "--enable-shared" "--disable-static" "--disable-silent-rules"
              (string-append "--with-frontend-zlib="
                             #$(this-package-input "zlib") "/lib")
              (string-append "--with-backend-zlib="
                             #$(this-package-input "zlib") "/lib"))))
    (inputs
     (list zlib))
    (home-page "https://www.scalasca.org/software/cube-4.x/download.html")
    (synopsis "CUBE high performance C writer library")
    (description
     "CUBE (CUBE Uniform Behavioral Encoding) is a tool to display a variety
of performance metrics for parallel programs including MPI and OpenMP
applications.  CubeW is the high performance C writer library of the CUBE
project.")
    (license license:bsd-3)))

(define-public cubelib
  (package/inherit cubew
    (name "cubelib")
    (source
     (origin
       (method url-fetch)
       (uri
        (string-append "https://apps.fz-juelich.de/scalasca/releases/cube/"
                       (package-version cubew) "/dist/cubelib-"
                       (package-version cubew) ".tar.gz"))
       (sha256
        (base32 "0hwl0aihn6fgpl0qhqckxc3sslb78wq6xav5ykfgfjzpyddqyrd0"))))
    (arguments
     (substitute-keyword-arguments (package-arguments cubew)
       ((#:configure-flags flags)
        #~(append #$flags
                  (list "--with-compression=full")))
       ((#:parallel-tests? _ #f) #f)))
    (inputs
     (list zlib))
    (synopsis "CUBE C++ profile library")
    (description
     "CUBE (CUBE Uniform Behavioral Encoding) is a tool to display a variety
of performance metrics for parallel programs including MPI and OpenMP
applications.  CubeLib is the general purpose C++ library and tool of the CUBE
project.")))

(define-public cubegui
  (package/inherit cubew
    (name "cubegui")
    (source
     (origin
       (method url-fetch)
       (uri
        (string-append "https://apps.fz-juelich.de/scalasca/releases/cube/"
                       (package-version cubew) "/dist/cubegui-"
                       (package-version cubew) ".tar.gz"))
       (sha256
        (base32 "04byhf00xnn1ppca914ag4hq2kjv37lhwyh8dl369ps47mp6viqh"))))
    (arguments
     (list
      #:configure-flags
      #~(list "--enable-shared" "--disable-static" "--disable-silent-rules"
              (string-append "CXXFLAGS=-I" #$(this-package-input "dbus")
                             "/include/dbus-1.0")
              (string-append "LDFLAGS=-L" #$(this-package-input "dbus")
                             "/lib"))))
    (native-inputs
     (list qtbase))
    (inputs
     (list cubelib
           dbus
           perl))
    (synopsis "CUBE profile explorer GUI")
    (description
     "CUBE (CUBE Uniform Behavioral Encoding) is a tool to display a variety
of performance metrics for parallel programs including MPI and OpenMP
applications.  CubeGUI is the graphical explorer of the CUBE project.")))

;; deprecated on 2025-09-22
(define-public cube
  (deprecated-package "cube" cubegui))

(define imgui-for-tracy
  (origin
    (method git-fetch)
    (uri (git-reference
           (url "https://github.com/ocornut/imgui")
           (commit "v1.91.9b-docking")))
    (file-name (git-file-name "imgui" "1.91.9b-docking"))
    (sha256
     (base32
      "1d0wa48k4wdwwgz6xb8bai3phyqav8ndfyh6lrlbbywd63m8j0wr"))
    (modules '((guix build utils)))
    (snippet
     ;; Remove bundled fonts.
     '(delete-file-recursively "misc/fonts"))))

(define ppqsort-for-tracy
  (origin
    (method git-fetch)
    (uri (git-reference
           (url "https://github.com/GabTux/PPQSort")
           (commit "v1.0.5")))
    (file-name (git-file-name "ppqsort" "1.0.5"))
    (sha256
     (base32
      "1ycr8fsp8k1225scrbjkj6bjm6iidvbavzvyxgwhbkxjzcimbihh"))))

(define package-project-cmake-for-tracy
  (origin
    (method git-fetch)
    (uri (git-reference
           (url "https://github.com/TheLartians/PackageProject.cmake")
           (commit (string-append "v" "1.13.0"))))
    (file-name (git-file-name "package-project-cmake" "1.13.0"))
    (sha256
     (base32
      "1nivxmjjhc3bi5v7qwwvllq8ykdh3mijz1d7sil502xy370b5fj5"))))

(define-public tracy-wayland
  (package
    (name "tracy-wayland")
    (version "0.12.2")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/wolfpld/tracy")
             (commit (string-append "v" version))))
       (sha256
        (base32
         "0rrnv77yh0fzlqpmn237jwpb93r8ds3jsy7xg46bb7hkq6bym0dy"))
       (file-name (git-file-name "tracy" version))
       (patches (search-patches "tracy-cpm-workarounds.patch"))))
    (build-system cmake-build-system)
    (arguments
     (list
      #:tests? #f                       ;no test for the profiler
      #:configure-flags
      #~(list "-DDOWNLOAD_CAPSTONE=OFF"
              "-DCPM_LOCAL_PACKAGES_ONLY=ON"
              "-DCPM_ImGui_SOURCE=../lib/imgui"
              "-DCPM_PPQSort_SOURCE=../lib/ppqsort"
              ;; Somehow find_package() fails to locate nfd, feeding source to
              ;; CPM instead.
              (string-append "-DCPM_nfd_SOURCE="
                             #$(package-source (this-package-input "nativefiledialog-extended")))
              (string-append "-Dwayland-protocols_SOURCE_DIR="
                             #$wayland-protocols "/share/wayland-protocols")
              ;; PPQSort depends on PackageProject.cmake.
              (string-append "-DCPM_PackageProject.cmake_SOURCE="
                             #$package-project-cmake-for-tracy))
      #:phases
      #~(modify-phases %standard-phases
          ;; Both imgui and ppqsort need to be patched, thus we need to copy
          ;; them otherwise files are read-only.
          (add-after 'unpack 'copy-libs
            (lambda _
              (mkdir-p "lib/ppqsort")
              (copy-recursively #$ppqsort-for-tracy "./lib/ppqsort/")
              (delete-file "./lib/ppqsort/cmake/CPM.cmake")
              (copy-file "cmake/CPM.cmake" "./lib/ppqsort/cmake/CPM.cmake")
              (mkdir-p "lib/imgui")
              (copy-recursively #$imgui-for-tracy "./lib/imgui/")))
          ;; We only have capstone 5 in Guix.  Remove this phase when we
          ;; upgrade to capstone 6.
          (add-after 'unpack 'patch-capstone-arch
            (lambda _
              (substitute* '("server/TracyWorker.cpp"
                             "profiler/src/profiler/TracySourceView.cpp")
                (("AARCH64") "ARM64")
                (("aarch64") "arm64"))))
          (add-after 'unpack 'patch-zstd-link-target
            (lambda _
              (substitute* "cmake/server.cmake"
                (("libzstd") "zstd"))))
          (add-before 'configure 'chdir
            (lambda _
              (chdir "profiler"))))))
    (inputs (list capstone
                  dbus
                  freetype
                  libxkbcommon
                  mesa
                  nativefiledialog-extended
                  wayland
                  `(,zstd "lib")))
    (native-inputs (list pkg-config))
    (home-page "https://github.com/wolfpld/tracy")
    (synopsis "Frame profiler")
    (description
     "A real time, nanosecond resolution, remote telemetry, hybrid frame and
sampling profiler for games and other applications.")
    (license license:bsd-3)))

(define-public tracy
  (package;xb
    (inherit tracy-wayland)
    (name "tracy")
    (arguments
     (substitute-keyword-arguments (package-arguments tracy-wayland)
       ((#:configure-flags flags #~'())
        #~(append #$flags
                  ;; The LEGACY flag indicate we want to build tracy with glfw.
                  (list "-DLEGACY=ON")))))
    (inputs (modify-inputs (package-inputs tracy-wayland)
              (delete "libxkbcommon" "wayland")
              (prepend glfw)))
    (synopsis "Frame profiler (X11 version)")))

(define-public scalasca
  (package
    (name "scalasca")
    (version "2.6.2")
    (source
      (origin
        (method url-fetch)
        (uri (string-append
               "https://apps.fz-juelich.de/scalasca/releases/scalasca/2.6/"
               "dist/scalasca-" version ".tar.gz"))
        (sha256
          (base32
            "18022bzdlzdgngcc5zlmsakvsk9dfg14kvg4ancqfhxy13cjzrqp"))
        ;; Remove bundled dependencies that can be replaced by inputs
        (snippet
          #~(begin
              (use-modules (guix build utils))
              (delete-file-recursively "vendor/cubew/")
              (delete-file-recursively "vendor/otf2/")))))
    (build-system gnu-build-system)
    (arguments
      (list
        #:configure-flags
        #~(list "--enable-shared" "--disable-static")
        #:phases
        #~(modify-phases %standard-phases
          (add-after 'install 'wrap-scripts
            ;; Use wrap-program on some outputs to resolve runtime dependency
            ;; on coreutils, sed... without propagating these inputs.
            (lambda* (#:key outputs #:allow-other-keys)
              (with-directory-excursion
                (string-append #$output "/bin")
                (for-each
                  (lambda (file)
                    (wrap-program file
                      `("PATH" ":" prefix ,(search-path-as-string->list
                        (getenv "PATH")))))
                  (list "scalasca" "skin" "square"))))))))
    (inputs
      (list openmpi
            cubew
            otf2
            zlib
            libiberty
            which ; configure and runtime dependency
            findutils ; runtime dependency
            gawk ; runtime dependency
            scorep-openmpi ; runtime dependency
            cubelib ; otherwise "ERROR: cube_dump is not available!"
            cubegui ; needed at runtime
            bash-minimal)) ; needed for using "wrap-program" in the recipe
    (home-page "https://scalasca.org")
    (synopsis "Performance analysis of parallel programs through runtime
measurements")
    (description
     "Scalasca targets mainly scientific and engineering applications based on
the programming interfaces MPI and OpenMP, including hybrid applications based
on a combination of the two.  Unlike Scalasca 1.x, the Scalasca 2.x release
series is based on the community instrumentation and measurement infrastructure
Score-P.  This significantly improves interoperability with other performance
analysis tool suites such as Vampir and TAU due to the usage of the two common
data formats CUBE4 for profiles and the Open Trace Format 2 (OTF2) for event
trace data.")
    (license license:bsd-3)))
