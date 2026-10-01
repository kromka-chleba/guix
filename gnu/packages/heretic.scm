;;; Standalone package definitions for Heretic and missing dependencies.
;;;
;;; This file is intended for use in an external channel setup where
;;; python-accelerate, python-datasets, python-optuna, and python-questionary
;;; come from guix-science.

(define-module (gnu packages heretic)
  #:use-module (gnu packages)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system pyproject)
  #:use-module ((guix licenses) #:prefix license:))

(define (lookup spec)
  (specification->package spec))

(define-public python-bitsandbytes
  (package
    (name "python-bitsandbytes")
    (version "0.49.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/bitsandbytes-foundation/bitsandbytes/archive/refs/tags/"
             version ".tar.gz"))
       (file-name (string-append name "-" version ".tar.gz"))
       (sha256
        (base32 "0vad7pvmmy76yq9hh6sl4l76893g2a6jl1w899ais36n78k3i0bk"))))
    (build-system pyproject-build-system)
    (arguments
     (list #:tests? #f))
    (propagated-inputs
     (map lookup
          (list "python-numpy"
                "python-packaging"
                "python-pytorch")))
    (native-inputs
     (map lookup
          (list "cmake"
                "ninja"
                "python-scikit-build-core"
                "python-setuptools")))
    (home-page "https://github.com/bitsandbytes-foundation/bitsandbytes")
    (synopsis "k-bit optimizers and matrix multiplication routines")
    (description
     "BitsAndBytes provides k-bit optimizers and quantization-focused matrix
operations for large language model workloads.")
    (license license:expat)))

(define-public python-peft
  (package
    (name "python-peft")
    (version "0.19.1")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "peft" version))
       (sha256
        (base32 "03cpahpyjvfdm8hd7f0w0vr6z64633s1d9rm8jmj7hv1ik5nfjj0"))))
    (build-system pyproject-build-system)
    (arguments
     (list #:tests? #f))
    (propagated-inputs
     (map lookup
          (list "python-accelerate"
                "python-huggingface-hub"
                "python-numpy"
                "python-packaging"
                "python-psutil"
                "python-pytorch"
                "python-pyyaml"
                "python-safetensors"
                "python-tqdm"
                "python-transformers")))
    (home-page "https://github.com/huggingface/peft")
    (synopsis "Parameter-efficient fine-tuning for transformers")
    (description
     "PEFT provides methods for parameter-efficient fine-tuning of large
transformer models.")
    (license license:asl2.0)))

(define-public python-lm-eval
  (package
    (name "python-lm-eval")
    (version "0.4.9.1")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "lm_eval" version))
       (sha256
        (base32 "1s3ylklv6zpnzlqc8pq8hpxb9pzdrqk6024s9s6s1ch3q3jvjdcp"))))
    (build-system pyproject-build-system)
    (arguments
     (list #:tests? #f))
    (propagated-inputs
     (map lookup
          (list "python-accelerate"
                "python-datasets"
                "python-dill"
                "python-immutabledict"
                "python-jinja2"
                "python-langdetect"
                "python-more-itertools"
                "python-numpy"
                "python-peft"
                "python-requests"
                "python-sacrebleu"
                "python-scikit-learn"
                "python-sqlitedict"
                "python-tqdm"
                "python-typing-extensions"
                "python-transformers"
                "python-pytorch")))
    (home-page "https://github.com/EleutherAI/lm-evaluation-harness")
    (synopsis "Language model evaluation harness")
    (description
     "LM Evaluation Harness provides benchmark and evaluation tooling for
language models across many tasks.")
    (license license:expat)))

(define-public python-heretic-llm
  (package
    (name "python-heretic-llm")
    (version "2.0.0.dev0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/p-e-w/heretic/archive/"
             "662e4ba27ecaf8878b0938c184a78f75a9116f82"
             ".tar.gz"))
       (file-name (string-append name "-" version ".tar.gz"))
       (sha256
        (base32 "18v7sixnq72mh6sll5r20497x5k0bnz3qcqby6q3iw9awnkglwfh"))))
    (build-system pyproject-build-system)
    (arguments
     (list #:tests? #f))
    (propagated-inputs
     (map lookup
          (list "python-accelerate"
                "python-bitsandbytes"
                "python-datasets"
                "python-huggingface-hub"
                "python-immutabledict"
                "python-langdetect"
                "python-lm-eval"
                "python-numpy"
                "python-optuna"
                "python-peft"
                "python-psutil"
                "python-py-cpuinfo"
                "python-pydantic-settings"
                "python-questionary"
                "python-rich"
                "python-tomli-w"
                "python-pytorch"
                "python-torchvision"
                "python-tqdm"
                "python-transformers")))
    (home-page "https://github.com/p-e-w/heretic")
    (synopsis "Automatic censorship removal for language models")
    (description
     "Heretic applies directional ablation techniques to transformer-based
language models, with parameter search for balancing refusal suppression and
behavior preservation.")
    (license license:agpl3+)))
