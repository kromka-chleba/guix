;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 Danny Milosavljevic <dannym@friendly-machines.com>
;;; Copyright © 2025 Matej Košík <matej@kosik.sk>
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

(define-module (gnu packages playwright)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix build-system node)
  #:use-module (guix build-system pyproject)
  #:use-module (guix utils)
  #:use-module (gnu packages)
  #:use-module (gnu packages chromium)
  #:use-module (gnu packages node)
  #:use-module (gnu packages node-xyz)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages web))

;; Playwright is a browser automation framework.  Upstream provides patched
;; versions of Firefox and WebKit browsers, but those require building
;; custom browser forks.  This package only supports Chromium-based browsers
;; (using the system ungoogled-chromium) since Chromium's DevTools Protocol
;; is sufficient for automation without patches.
;;
;; Firefox support would require Playwright's "Juggler" protocol patches.
;; WebKit support would require Playwright's WebKit automation patches.
;; Both are invasive changes to browser source code.
;;
;; In the future, WebDriver BiDi (a W3C standard) may allow Playwright to
;; work with unpatched browsers.

(define-public node-playwright-core
  (package
    (name "node-playwright-core")
    (version "1.50.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/microsoft/playwright")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0xymivpn2c4srbaqdix3qx2zcr6cx5zgs2a20drvi4dmkspn4jz6"))
       (modules '((guix build utils)))
       (snippet
        '(delete-file-recursively "packages/playwright-core/bundles"))))
    (build-system node-build-system)
    (arguments
     (list
      #:tests? #f  ; Tests require browser binaries.
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'break-monorepo-structure
            (lambda _
              ;; This is a monorepo with npm workspaces. Delete root package.json
              ;; and lock files to prevent npm from reading workspace config.
              (delete-file "package.json")
              (for-each delete-file
                        (find-files "." "package-lock\\.json$"))))
          (add-after 'break-monorepo-structure 'change-to-package-directory
            (lambda _
              (chdir "packages/playwright-core")))
          (add-after 'unpack 'skip-browser-download
            (lambda _
              (setenv "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD" "1")))
          (add-after 'unpack 'unbundle-dependencies
            (lambda _
              (substitute* "packages/playwright-core/src/zipBundle.ts"
                (("require\\('./zipBundleImpl'\\)\\.yazl")
                 "require('yazl')")
                (("require\\('./zipBundleImpl'\\)\\.yauzl")
                 "require('yauzl')")
                (("require\\('./zipBundleImpl'\\)\\.extract")
                 "require('extract-zip')"))
              (substitute* "packages/playwright-core/src/utilsBundle.ts"
                (("require\\('./utilsBundleImpl'\\)\\.colors")
                 "require('colors/safe')")
                (("require\\('./utilsBundleImpl'\\)\\.debug")
                 "require('debug')")
                (("require\\('./utilsBundleImpl'\\)\\.diff")
                 "require('diff')")
                (("require\\('./utilsBundleImpl'\\)\\.dotenv")
                 "require('dotenv')")
                (("require\\('./utilsBundleImpl'\\)\\.getProxyForUrl")
                 "require('proxy-from-env').getProxyForUrl")
                (("require\\('./utilsBundleImpl'\\)\\.HttpsProxyAgent")
                 "require('https-proxy-agent').HttpsProxyAgent")
                (("require\\('./utilsBundleImpl'\\)\\.jpegjs")
                 "require('jpeg-js')")
                (("require\\('./utilsBundleImpl'\\)\\.lockfile")
                 "require('proper-lockfile')")
                (("require\\('./utilsBundleImpl'\\)\\.mime")
                 "require('mime')")
                (("require\\('./utilsBundleImpl'\\)\\.minimatch")
                 "require('minimatch')")
                (("require\\('./utilsBundleImpl'\\)\\.open")
                 "require('open')")
                (("require\\('./utilsBundleImpl'\\)\\.PNG")
                 "require('pngjs').PNG")
                (("require\\('./utilsBundleImpl'\\)\\.program")
                 "require('commander').program")
                (("require\\('./utilsBundleImpl'\\)\\.progress")
                 "require('progress')")
                (("require\\('./utilsBundleImpl'\\)\\.SocksProxyAgent")
                 "require('socks-proxy-agent').SocksProxyAgent")
                (("require\\('./utilsBundleImpl'\\)\\.yaml")
                 "require('yaml')")
                (("require\\('./utilsBundleImpl'\\)\\.wsServer")
                 "require('ws').WebSocketServer")
                (("require\\('./utilsBundleImpl'\\)\\.wsReceiver")
                 "require('ws').Receiver")
                (("require\\('./utilsBundleImpl'\\)\\.wsSender")
                 "require('ws').Sender")
                (("require\\('./utilsBundleImpl'\\)\\.ws\\b")
                 "require('ws')")
                (("require\\('./utilsBundleImpl'\\)\\.StackUtils")
                 "require('stack-utils')"))))
          (add-after 'unbundle-dependencies 'add-unbundled-dependencies
            (lambda _
              ;; Add dependencies that were unbundled from utilsBundle/zipBundle.
              ;; Must run before patch-dependencies which minifies package.json.
              (modify-json
               #:file "packages/playwright-core/package.json"
               (lambda (pkg)
                 (acons "dependencies"
                        '(("colors" . "*")
                          ("commander" . "*")
                          ("debug" . "*")
                          ("diff" . "*")
                          ("dotenv" . "*")
                          ("extract-zip" . "*")
                          ("https-proxy-agent" . "*")
                          ("jpeg-js" . "*")
                          ("mime" . "*")
                          ("minimatch" . "*")
                          ("open" . "*")
                          ("pngjs" . "*")
                          ("progress" . "*")
                          ("proper-lockfile" . "*")
                          ("proxy-from-env" . "*")
                          ("socks-proxy-agent" . "*")
                          ("stack-utils" . "*")
                          ("ws" . "*")
                          ("yaml" . "*")
                          ("yazl" . "*")
                          ("yauzl" . "*"))
                        pkg)))))
          (add-before 'build 'generate-injected-scripts
            (lambda _
              ;; Run generate_injected.js to create src/generated/*.ts files.
              (invoke "node" "../../utils/generate_injected.js")))
          (add-after 'generate-injected-scripts 'add-build-script
            (lambda _
              ;; Upstream uses Babel, but Babel isn't packaged. Use esbuild.
              ;; Compile TypeScript and copy non-TS files (JS, JSON, PNG).
              (modify-json
               (lambda (pkg)
                 (acons "scripts"
                        '(("build" . "find src -name '*.ts' | xargs esbuild --outdir=lib --format=cjs --platform=node && cp -r src/third_party lib/ && find src \\( -name '*.json' -o -name '*.png' \\) -exec sh -c 'mkdir -p lib/$(dirname ${0#src/}) && cp $0 lib/${0#src/}' {} \\;"))
                        pkg)))))
          (add-before 'install 'set-cc
            (lambda _
              (setenv "CC" #$(cc-for-target))))
          (add-after 'install 'wrap-playwright-cli
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (cli (string-append out "/lib/node_modules/playwright-core/cli.js")))
                (wrap-program cli
                  ;; Avoid vite dependency.
                  `("PW_CODEGEN_NO_INSPECTOR" = ("1"))
                  `("PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD" = ("1")))))))))
    (inputs
     (list node-esbuild
           ;; Dependencies (unbundled from utilsBundle).
           node-colors
           node-commander
           node-debug
           node-diff
           node-dotenv
           node-graceful-fs
           node-https-proxy-agent
           node-jpeg-js
           node-mime
           node-minimatch-3
           node-ms
           node-open
           node-pngjs
           node-progress
           node-proper-lockfile
           node-proxy-from-env
           node-retry
           node-signal-exit
           node-socks-proxy-agent
           node-stack-utils
           node-ws
           node-yaml
           ;; Dependencies (unbundled from zipBundle).
           node-yazl
           node-yauzl
           node-extract-zip))
    (native-inputs
     (list esbuild python))
    (native-search-paths
     (list
      (search-path-specification
       (variable "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH")
       (file-type 'regular)
       (separator #f)              ;single entry
       (files '("bin/chromium")))
      (search-path-specification
       (variable "PWTEST_CLI_EXECUTABLE_PATH")
       (file-type 'regular)
       (separator #f)              ;single entry
       (files '("bin/chromium")))))
    (home-page "https://playwright.dev/")
    (synopsis "Browser automation library (Chromium-only)")
    (description
     "Playwright is a framework for browser automation and end-to-end testing.
This package provides @code{playwright-core}, the library without bundled
browsers.

@strong{Important}: This package only supports Chromium-based browsers.
Firefox and WebKit are not supported because Playwright requires custom-patched
versions of those browsers that are not packaged for Guix.

To use Playwright with the system Chromium, either:
@enumerate
@item
Set the environment variable @env{PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH} to the
Chromium binary path, or
@item
Use the @code{executablePath} option in your Playwright code:
@example
const browser = await chromium.launch(@{
  executablePath: '/run/current-system/profile/bin/chromium'
@});
@end example

For the command line variant $code{playwright-core}, set the environment
variable $env{PWTEST_CLI_EXECUTABLE_PATH} to the Chromium binary path.
@end enumerate")
    (license license:asl2.0)))

(define-public python-playwright
  (package
    (name "python-playwright")
    (version "1.58.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/microsoft/playwright-python")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1dmf1kr9wvnw11zamnwq9jarjlf2cf56z7xgj2zkqk3w62k7vbc0"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      #:tests? #f                       ;tests require browser binaries
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'build 'set-version
            (lambda _
              ;; setuptools-scm requires a git checkout to determine the
              ;; version; provide it explicitly instead.
              (setenv "SETUPTOOLS_SCM_PRETEND_VERSION" #$version)))
          (add-before 'build 'patch-build-files
            (lambda _
              ;; Relax exact build-dependency versions imposed by upstream.
              (substitute* "pyproject.toml"
                (("\"setuptools==[0-9.]+\", \"setuptools-scm==[0-9.]+\", \
\"wheel==[0-9.]+\", \"auditwheel==[0-9.]+\"")
                 "\"setuptools\", \"setuptools-scm\", \"wheel\""))
              ;; Remove the custom bdist_wheel command that tries to
              ;; download the Playwright driver bundle from the internet.
              (substitute* "setup.py"
                (("    cmdclass=\\{\"bdist_wheel\".*") ""))))
          (add-after 'install 'install-driver
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((node (assoc-ref inputs "node"))
                     (playwright-core (assoc-ref inputs "node-playwright-core"))
                     (driver-dir
                      (string-append (site-packages inputs outputs)
                                     "/playwright/driver")))
                (mkdir-p driver-dir)
                ;; Point to the system Node.js binary.
                (symlink (string-append node "/bin/node")
                         (string-append driver-dir "/node"))
                ;; Point to the playwright-core JavaScript package.
                (symlink
                 (string-append playwright-core
                                "/lib/node_modules/playwright-core")
                 (string-append driver-dir "/package")))))
          (add-after 'install-driver 'patch-driver
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (substitute*
                  (string-append (site-packages inputs outputs)
                                 "/playwright/_impl/_driver.py")
                ;; node-playwright-core uses wrap-program on cli.js, turning
                ;; it into a shell script (with "export VAR=..." lines) and
                ;; saving the original JavaScript as .cli.js-real.  When the
                ;; Python playwright driver calls "node cli.js", Node.js
                ;; fails to parse the shell wrapper.  Use the original JS.
                (("cli_path = str\\(driver_path / \"package\" / \"cli\\.js\"\\)")
                 (string-append
                  "_cli_real = driver_path / \"package\" / \".cli.js-real\"\n"
                  "    cli_path = str(_cli_real if _cli_real.exists()"
                  " else driver_path / \"package\" / \"cli.js\")"))
                ;; Add the environment variables that node-playwright-core's
                ;; cli.js shell wrapper was setting.
                (("    env\\[\"PW_CLI_DISPLAY_VERSION\"\\] = version\n")
                 (string-append
                  "    env[\"PW_CLI_DISPLAY_VERSION\"] = version\n"
                  "    env[\"PW_CODEGEN_NO_INSPECTOR\"] = \"1\"\n"
                  "    env[\"PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD\"] = \"1\"\n"))))))))
    (inputs
     (list node-lts
           node-playwright-core))
    (propagated-inputs
     (list python-greenlet
           python-pyee))
    (native-inputs
     (list python-setuptools
           python-setuptools-scm
           python-wheel))
    (native-search-paths
     ;; When ungoogled-chromium is in the profile, Guix automatically sets
     ;; PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH to its binary, telling playwright
     ;; to use the system browser instead of downloading one.
     (list
      (search-path-specification
       (variable "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH")
       (file-type 'regular)
       (separator #f)              ;single entry
       (files '("bin/chromium")))))
    (home-page "https://playwright.dev/python/")
    (synopsis "Browser automation library for Python")
    (description
     "Playwright is a Python library to automate Chromium, Firefox, and
WebKit browsers with a single API.

@strong{Important}: This package only supports Chromium-based browsers
using the system @code{ungoogled-chromium}, because Playwright requires
custom-patched versions of Firefox and WebKit that are not packaged for
Guix.

To use Playwright with the system Chromium, set the environment variable
@env{PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH} to the Chromium binary path.")
    (license license:asl2.0)))
