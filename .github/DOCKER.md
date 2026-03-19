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
- `openssh-service-type` – SSH server for interactive debugging.

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
.github/bin/build-guix-docker.sh guix-dev:latest
```

The script will:
1. Call `guix system docker-image .github/guix-dev-docker.scm` to produce a
   compressed tarball in the Guix store.
2. Load the tarball with `docker load`.
3. Tag the resulting image as specified (default: `guix-dev:latest`).

You can also customize behaviour with environment variables:

```bash
REGISTRY=ghcr.io/my-org \
IMAGE_TAG=guix-dev:custom \
GUIX_SYSTEM_CONFIG=/path/to/my-config.scm \
EXTRA_GUIX_FLAGS="--no-offload" \
  .github/bin/build-guix-docker.sh
```

---

## Pushing to GitHub Container Registry (GHCR) – manual steps

The automated GitHub Actions workflow (`.github/workflows/docker-image.yml`)
requires a **self-hosted runner** with Guix installed because the GitHub-hosted
runners do not have Guix available.  Until such a runner is configured you can
push images manually:

```bash
# 1. Log in to GHCR
echo "$GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 2. Build and tag
.github/bin/build-guix-docker.sh ghcr.io/YOUR_ORG/guix-dev:latest

# 3. Push
docker push ghcr.io/YOUR_ORG/guix-dev:latest
```

### Setting up the self-hosted runner

1. In your GitHub repository go to **Settings → Actions → Runners** and add a
   new self-hosted runner.
2. Follow the on-screen instructions to install and register the runner agent
   on a machine that has GNU Guix and Docker installed.
3. Give the runner the **`guix`** label (used in
   `.github/workflows/docker-image.yml` as `runs-on: [self-hosted, guix]`).
4. Make sure the runner user has permission to talk to the Docker daemon
   (i.e. is in the `docker` group or uses `sudo docker`).

### Making the image public (optional)

By default GHCR packages inherit the repository visibility.  To make the image
publicly available (so agents can pull it without credentials):

1. Go to your GitHub profile → **Packages**.
2. Find the `guix-dev` package and open its settings.
3. Change visibility to **Public**.

---

## Using the image

### Interactive shell

```bash
docker run --rm -it ghcr.io/YOUR_ORG/guix-dev:latest \
  /run/current-system/profile/bin/bash
```

### Running Guix commands inside the container

```bash
# Build a package
docker run --rm ghcr.io/YOUR_ORG/guix-dev:latest \
  /run/current-system/profile/bin/guix build hello

# Open a development shell for a package
docker run --rm -it ghcr.io/YOUR_ORG/guix-dev:latest \
  /run/current-system/profile/bin/guix shell hello
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

Edit `.github/guix-dev-docker.scm` to add or remove packages, then either:
- Push to `master` – the Actions workflow will rebuild and push automatically
  (once a self-hosted runner is configured), or
- Run `.github/bin/build-guix-docker.sh` locally and push manually.
