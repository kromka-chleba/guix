

(package
 (name "ocaml-longleaf")
 (version "1.0.3")
 (build-system dune-build-system)
 (home-page "https://github.com/hesterjeng/longleaf")
 (source
     (github-tag-origin
      name home-page version "1sy188ibw4n38kfsy8zq808wy77gd8s56fsx0jraflnkwadrqi7m"
      "v"))
 (native-inputs
  (list ocaml-alcotest))
 (propagated-inputs
  (list ocaml-ppx-deriving
        ocaml-ppx-yojson-conv
        ocaml-ppx-variants-conv
        ocaml-ppx-fields-conv
        ocaml-ppx-hash
        ocaml-tyxml
        ocaml-tacaml
        ocaml-ptime
        ocaml-eio-main
        ;; ocaml-ptime
        ;; ocaml-ppx-yojson-conv-lib
        ;; ocaml-ppx-deriving
        ;; ocaml-ppx-variants-conv
        ;; ocaml-ppx-fields-conv
        ;; ocaml-cmdliner
        ;; ocaml-graph
        ;; ocaml-eio-main
        ;; ocaml-tacaml
        ;; ocaml-fileutils
        ;; ocaml-yojson
        ;; ocaml-uuidm
        ;; ocaml-tyxml
        ;; ocaml-alcotest
        ;; longleaf-frontend-dev
        ;; longleaf-quantstats-dev
        ))
 (synopsis "Algorithmic trading platform written in OCaml")
 (description
  "Longleaf is an algorithmic trading platform that supports live trading,
paper trading, and backtesting with multiple brokerages and market data sources.
The platform uses a functional, modular architecture with strategies implemented
as functors for maximum code reuse and type safety.

The platform includes tacaml for TA-Lib technical analysis bindings.")
 (license license:gpl3+)
    ))

(define-public ocaml-tacaml
  (package
    (name "ocaml-tacaml")
    (version "1.0.0")
    (home-page "https://github.com/hesterjeng/tacaml")
    (source
     (github-tag-origin
      name home-page version
      "0d45rjr2rc39i53fdsczd7pxw5rb5i2a2vcjd0k08vrjxac5ys0s"
      "v"
      ))
    (build-system dune-build-system)
    (propagated-inputs (list ocaml-ctypes ocaml-ppx-deriving ocaml-containers))
    (native-inputs (list ta-lib))
    ;; (propagated-inputs (list ocaml-eio ocaml-ssl))
    ;; (propagated-inputs (list ocaml-eio ocaml-ipaddr ocaml-ke ocaml-uri ocaml-ssl))
    (synopsis " ta-lib bindings for OCaml ")
    (description "tacaml provides OCaml bindings to the TA-Lib (Technical Analysis Library). This project offers both raw C bindings and higher-level, type-safe wrappers for over 160 technical analysis functions commonly used in financial markets.")
    (license license:lgpl2.0)))
