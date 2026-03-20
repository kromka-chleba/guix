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

| Category | Packages |
|----------|----------|
| Core toolchain | `gcc-toolchain`, `gnu-make`, `autoconf`, `automake`, `libtool`, `pkg-config` |
| Guile / Guix | `guix`, `guile`, `guile-json`, `guile-gcrypt`, `guile-git` |
| Version control | `git`, `nss-certs` |
| Compression | `gzip`, `bzip2`, `xz`, `zstd` |
| Cryptography | `gnupg` |
| Documentation | `texinfo`, `imagemagick` |
| Scripting | `perl`, `python`, `bash` |
| Networking | `curl`, `wget` |
| Installer tests | `guile-newt`, `guile-parted`, `guile-webutils` |

**Services:**
- `guix-service-type` – a Guix build daemon so that agents can run
  `guix build` / `guix package` inside the container.

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

A manual build can be triggered at any time via the **Actions → Build &
Publish Guix Dev Docker Image → Run workflow** button.

### How the automated build works

The workflow runs on a standard **GitHub-hosted `ubuntu-latest` runner** – no
self-hosted runner is needed.  The build is performed *inside* the existing
`ghcr.io/kromka-chleba/guix-dev:latest` container, which already has Guix
installed:

```
ubuntu-latest runner  (has Docker)
│
└─► docker run --privileged ghcr.io/kromka-chleba/guix-dev:latest
      │
      ├─► herd start guix-daemon
      │
      └─► guix system image --image-type=docker .github/guix-dev-docker.scm
            │
            └─► /gnu/store/…-system-docker-image.tar.gz
                 │
                 └─ docker cp  →  guix-dev-image.tar.gz (on runner)
                                      │
                                      ├─ docker load
                                      ├─ docker tag  :latest  :SHORT_SHA
                                      └─ docker push  ghcr.io/…/guix-dev
```

Key points:

* **Privileged container**: Guix uses Linux user namespaces for isolated
  builds, which requires `--privileged`.  GitHub-hosted runners allow this.
* **Pre-built substitutes**: Guix downloads pre-built binaries from
  `bordeaux.guix.gnu.org`, so only packages that are not already in the
  container's store need to be fetched.
* **Self-contained**: The entire build pipeline lives in this repository; no
  external Guix server or self-hosted runner is required.

### Bootstrap procedure (first-time / recovery)

The automated workflow uses the *existing* `ghcr.io/kromka-chleba/guix-dev:latest`
to build the *next* image.  If the image does not exist yet (e.g. initial
setup or after accidental deletion), you must bootstrap it manually:

```bash
# Prerequisites: GNU Guix and Docker installed on your machine.

# 1. Log in to GHCR
echo "$GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 2. Build and push
.github/bin/build-guix-docker.scm \
  --registry=ghcr.io/YOUR_ORG \
  --image-tag=guix-dev:latest
docker push ghcr.io/YOUR_ORG/guix-dev:latest
```

After that first push the CI workflow takes over automatically.

---

## Building the image locally

### Prerequisites

1. **GNU Guix** must be installed on the build host.  Follow the
   [official installation guide](https://guix.gnu.org/en/download/).
2. **Docker** (or Podman) must be installed and the daemon must be running.
3. The build host needs several gigabytes of free disk space.

### Steps

```bash
# From the repository root:
.github/bin/build-guix-docker.scm --image-tag=guix-dev:latest
```

The script will:
1. Call `guix system image --image-type=docker .github/guix-dev-docker.scm` to produce a
   compressed tarball in the Guix store.
2. Load the tarball with `docker load`.
3. Tag the resulting image as specified (default: `guix-dev:latest`).

You can pass additional options as flags:

```bash
.github/bin/build-guix-docker.scm \
  --registry=ghcr.io/my-org \
  --image-tag=guix-dev:custom \
  --config=/path/to/my-config.scm \
  --guix-flag=--no-offload
```

The `--guix-flag` option can be repeated to pass multiple flags to
`guix system image`:

```bash
.github/bin/build-guix-docker.scm \
  --guix-flag=--no-offload \
  --guix-flag=--keep-failed \
  --guix-flag=--cores=4
```

---

## Making the image public (optional)

By default GHCR packages inherit the repository visibility.  To make the image
publicly available (so agents can pull it without credentials):

1. Go to your GitHub profile → **Packages**.
2. Find the `guix-dev` package and open its settings.
3. Change visibility to **Public**.

---

## Using the image

### Interactive shell

Guix system Docker images run Shepherd as PID 1.  Using
`docker run --rm -it … bash` does not work because Shepherd blocks the
container before the shell can start.  Use `docker exec` instead:

```bash
# 1. Start the container (Shepherd boots the system in the background)
CONTAINER=$(docker run -d --privileged ghcr.io/YOUR_ORG/guix-dev:latest)

# 2. Attach an interactive login shell
docker exec -ti $CONTAINER /run/current-system/profile/bin/bash --login

# 3. Stop the container when done
docker stop $CONTAINER
```

### Running Guix commands inside the container

```bash
# Start the container once
CONTAINER=$(docker run -d --privileged ghcr.io/YOUR_ORG/guix-dev:latest)

# Run individual commands via docker exec
docker exec $CONTAINER /run/current-system/profile/bin/guix build hello

# Open an interactive development shell for a package
docker exec -ti $CONTAINER /run/current-system/profile/bin/guix shell hello

# Stop when done
docker stop $CONTAINER
```

### In GitHub Copilot Coding Agent

Reference the image in your Copilot agent configuration or devcontainer setup:

```json
{
  "image": "ghcr.io/YOUR_ORG/guix-dev:latest"
}
```

The coding agent can then run `guix build`, `guix package`, and any other Guix
commands directly inside the container to test newly written package/service
definitions before submitting a patch.

---

## Updating the image

Edit `.github/guix-dev-docker.scm` to add or remove packages or services, then
push to `master`.  The Actions workflow will automatically rebuild and push the
updated image to `ghcr.io/kromka-chleba/guix-dev:latest`.
