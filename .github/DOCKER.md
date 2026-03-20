# Guix Development Docker Image

This document explains how to build, publish, and use the Docker image that
provides a complete Guix build/development environment.  The image is intended
to be used by coding agents (e.g. GitHub Copilot Coding Agent) so they can
compile and test new Guix packages and services without relying on the host
machine's environment.

---

## Contents of the image

The image is produced from `.github/guix-dev-docker.scm`, a
[Guix System](https://guix.gnu.org/manual/en/html_node/System-Configuration.html)
configuration that includes:

| Category | Packages / services |
|----------|---------------------|
| Core toolchain | `gcc-toolchain`, `gnu-make`, `autoconf`, `automake`, `libtool`, `pkg-config` |
| Guile / Guix | `guix`, `guile`, `guile-json`, `guile-gcrypt`, `guile-git` |
| Version control | `git`, `nss-certs` |
| Compression | `gzip`, `bzip2`, `xz`, `zstd` |
| Cryptography | `gnupg` |
| Documentation | `texinfo`, `imagemagick` |
| Scripting | `perl`, `python`, `bash` |
| **Container tooling** | **`docker`, `containerd`** (daemon started via Shepherd) |
| Installer tests | `guile-newt`, `guile-parted`, `guile-webutils` |

**Services (started by Shepherd on container boot):**
- `guix-service-type` – Guix build daemon (so agents can run `guix build` etc.)
- `docker-service-type` – Docker daemon (dockerd + containerd), so the
  container can itself build and push Docker images without an external daemon.

No SSH server is included.  Use `docker exec` (or the devcontainer mechanism)
to get an interactive shell; this avoids the SSH host-key entropy wait that
slows down container startup.

---

## Automated CI build (GitHub Actions)

The image is built and pushed automatically by
`.github/workflows/docker-image.yml` on every push to `master` that touches:

- `.github/guix-dev-docker.scm`
- `.github/bin/build-guix-docker.scm`
- `.github/workflows/docker-image.yml`

A manual build can be triggered at any time via the
**Actions → Build & Publish Guix Dev Docker Image → Run workflow** button.

### How the automated build works

The workflow runs on a standard **GitHub-hosted `ubuntu-latest` runner** – no
self-hosted runner or pre-existing Guix installation is needed.  The build
uses the **official `guix/guix` image from Docker Hub** as a reproducible
bootstrap environment:

```
ubuntu-latest runner  (has Docker)
│
└─► docker run --privileged --rm \
      --volume workspace:/workspace:ro \
      --volume output:/guix-output \
      guix/guix                           ← official Guix bootstrap image
        │
        ├─► start guix-daemon (build users already configured)
        │
        └─► guix system image \
              --image-type=docker \
              .github/guix-dev-docker.scm
                │
                └─► /gnu/store/…-docker-image.tar.gz
                      │
                      └─ cp → /guix-output/guix-dev-image.tar.gz
                                    │   (host-visible via volume mount)
                                    │
                                    ├─ docker load
                                    ├─ docker tag  :latest  :SHORT_SHA
                                    └─ docker push ghcr.io/…/guix-dev
```

Key properties:

* **No circular dependency.** The `guix/guix` bootstrap image is entirely
  independent of the image being built here.  Even if `ghcr.io/…/guix-dev`
  does not yet exist, the workflow succeeds.
* **Reproducible.** `guix system image` produces bit-for-bit reproducible
  output (given the same channel state).  Package versions are pinned by the
  Guix channel in `guix-dev-docker.scm`.
* **Substitutes.** Guix downloads pre-built binaries from
  `bordeaux.guix.gnu.org`, so only packages absent from the substitutes cache
  need to be compiled – builds typically finish in under 30 minutes.
* **Privileged container.** Guix uses Linux user namespaces for isolated
  builds, which requires `--privileged`.  GitHub-hosted runners allow this.

### Self-sufficient image (Docker-in-Docker capable)

The resulting `guix-dev` image includes both the Guix daemon **and** the
Docker daemon (`docker-service-type`).  Running it with `--privileged` starts
both daemons via Shepherd, which means:

* CI workflows that use `guix-dev` as their build environment can run
  `docker build`, `docker load`, and `docker push` without mounting an
  external socket.
* The coding agent can build and test packages *and* produce new Docker images
  entirely inside a single `guix-dev` container.

---

## Building the image locally

### Prerequisites

1. **GNU Guix** must be installed on the build host.  Follow the
   [official installation guide](https://guix.gnu.org/en/download/).
2. **Docker** (or Podman) must be installed and the daemon must be running.

### Steps

```bash
# From the repository root:
guix system image --image-type=docker .github/guix-dev-docker.scm \
  | xargs -I{} docker load -i {}
docker tag $(docker images -q | head -1) guix-dev:latest
```

Or use the helper build script (handles the tag/push steps):

```bash
.github/bin/build-guix-docker.scm --image-tag=guix-dev:latest
```

---

## Using the image

### Interactive shell

Guix System Docker images run Shepherd as PID 1.  Using
`docker run --rm -it … bash` does NOT work because Shepherd blocks the
container before a shell can start.  Use `docker exec` instead:

```bash
# 1. Start the container
CONTAINER=$(docker run -d --privileged ghcr.io/YOUR_ORG/guix-dev:latest)

# 2. Attach an interactive login shell
docker exec -ti $CONTAINER /run/current-system/profile/bin/bash --login

# 3. Stop when done
docker stop $CONTAINER
```

### Running Guix and Docker commands inside the container

```bash
CONTAINER=$(docker run -d --privileged ghcr.io/YOUR_ORG/guix-dev:latest)

# Wait for Shepherd to finish booting
docker exec $CONTAINER \
  /run/current-system/profile/bin/herd status

# Build a Guix package
docker exec $CONTAINER \
  /run/current-system/profile/bin/guix build hello

# Check Docker daemon is running
docker exec $CONTAINER docker info

# Build a Docker image (no socket mount needed – daemon is inside)
docker exec $CONTAINER \
  docker build -t my-image /path/to/context

docker stop $CONTAINER
```

### In GitHub Copilot Coding Agent

Reference the image in your Copilot agent configuration or devcontainer setup:

```json
{
  "image": "ghcr.io/YOUR_ORG/guix-dev:latest",
  "runArgs": ["--privileged"],
  "postStartCommand": "herd status"
}
```

---

## Making the image public (optional)

By default GHCR packages inherit the repository visibility.  To make the image
publicly available (so agents can pull it without credentials):

1. Go to your GitHub profile → **Packages**.
2. Find the `guix-dev` package and open its settings.
3. Change visibility to **Public**.

---

## Updating the image

Edit `.github/guix-dev-docker.scm` to add or remove packages or services, then
push to `master`.  The Actions workflow automatically rebuilds and pushes the
updated image to `ghcr.io/kromka-chleba/guix-dev:latest`.
