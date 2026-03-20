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
- `guix-service-type` – Guix build daemon
- `docker-service-type` – Docker daemon (dockerd + containerd)

No SSH server is included.  Use `docker exec` to get an interactive shell.

---

## Automated CI build (GitHub Actions)

The workflow (`.github/workflows/docker-image.yml`) fires automatically only
on **`master`** pushes that touch one of these files:

- `.github/guix-dev-docker.scm`
- `.github/bin/build-guix-docker.scm`
- `.github/workflows/docker-image.yml`

Restricting the trigger to `master` avoids generating large amounts of cached
data for every feature branch.

**For feature-branch work:** use
**Actions → Build & Publish Guix Dev Docker Image → Run workflow**
to build and test the image manually on your branch before merging.

### Branch behaviour

| Trigger | Branch | Pushes to registry? |
|---------|--------|---------------------|
| `push` (automatic) | `master` only | Always yes |
| `workflow_dispatch` (manual) | Any branch | Controlled by `push_image` input (default: `true`) |

Set `push_image = false` in the manual trigger for a dry-run that builds the
image and validates it without publishing anything.

### Build caching — skip rebuilds when nothing has changed

`guix system image` is deterministic: the same `.scm` file and the same
bootstrap image always produce the identical tarball.  The workflow exploits
this by caching the tarball in the GitHub Actions cache, keyed on:

```
sha256(.github/guix-dev-docker.scm)[0:16] + bootstrap-image-digest[0:16]
```

On a cache **hit** the `guix system image` build is skipped entirely and the
cached tarball is loaded directly into Docker.  This turns a multi-hour cold
build into a sub-minute warm run.

The cache is automatically invalidated whenever:
- `guix-dev-docker.scm` changes (new packages, services, …), or
- `ghcr.io/kromka-chleba/guix-dev:latest` is updated (new Guix version)

To bypass the cache and force a full rebuild, use
**Run workflow → force_rebuild = true**.

### How the automated build works

```
ubuntu-latest runner
│
├─► docker pull ghcr.io/kromka-chleba/guix-dev:latest
├─► compute cache key  (sha256(guix-dev-docker.scm) + image digest)
│
├─ Cache HIT ──► restore tarball from Actions cache  (skip build)
│
└─ Cache MISS ──► docker run -d --privileged  (bootstrap container)
                    │
                    ├─► Shepherd boots (PID 1)
                    ├─► herd start guix-daemon
                    │
                    └─► guix system image \
                          --image-type=docker \
                          /workspace/.github/guix-dev-docker.scm
                            │
                            └─► /gnu/store/…-docker-image.tar.gz
                                  │
                                  └─► docker cp → guix-dev-image.tar.gz
                                      └─► save to Actions cache

(both paths continue here)
docker load  →  docker tag :latest :SHORT_SHA
  │
  └─► (master only) docker push ghcr.io/kromka-chleba/guix-dev
```

The workflow uses the **previously published** `guix-dev:latest` as the
bootstrap environment.  This is intentional: once the image exists in the
registry, every subsequent CI run uses it to build the next version.
The resulting image always has Docker included (via `docker-service-type`),
so the bootstrap container can also run Docker builds itself.

### First-time bootstrap (when no image exists in the registry yet)

Because the CI workflow depends on `ghcr.io/kromka-chleba/guix-dev:latest`
already being present, the very first image must be built manually on a
machine running **Guix System** (or with Guix installed):

```bash
# 1. Build the Docker image tarball with Guix
guix system image --image-type=docker .github/guix-dev-docker.scm

# 2. Load it into Docker (the command above prints the store path)
docker load -i /gnu/store/…-docker-image.tar.gz

# 3. Tag it
docker tag $(docker images -q | head -1) ghcr.io/kromka-chleba/guix-dev:latest

# 4. Log in to GHCR and push
echo "$GITHUB_TOKEN" | docker login ghcr.io -u YOUR_USERNAME --password-stdin
docker push ghcr.io/kromka-chleba/guix-dev:latest
```

After that first push, the CI workflow takes over automatically for all
future updates.

---

## Building the image locally (with Guix installed)

You can also use the helper build script, which wraps the steps above:

```bash
# From the repository root:
.github/bin/build-guix-docker.scm --image-tag=ghcr.io/kromka-chleba/guix-dev:latest
```

The script will:
1. Run `guix system image --image-type=docker .github/guix-dev-docker.scm`.
2. Load the resulting tarball with `docker load`.
3. Tag the image as specified.

Additional options:

```bash
.github/bin/build-guix-docker.scm \
  --guix-flag=--no-offload \
  --guix-flag=--keep-failed \
  --guix-flag=--cores=4
```

---

## Making the image public (optional)

By default GHCR packages inherit the repository visibility.  To make the
image publicly accessible without credentials:

1. Go to your GitHub profile → **Packages**.
2. Find the `guix-dev` package and open its settings.
3. Change visibility to **Public**.

---

## Using the image

### Interactive shell

Guix System Docker images run Shepherd as PID 1.  **Do not** use
`docker run --rm -it … bash` — Shepherd will block before a shell starts.
Use `docker exec` instead:

```bash
# 1. Start the container
CONTAINER=$(docker run -d --privileged ghcr.io/kromka-chleba/guix-dev:latest)

# 2. Wait for Shepherd to finish booting, then attach a shell
docker exec -ti $CONTAINER /run/current-system/profile/bin/bash --login

# 3. Stop when done
docker stop $CONTAINER
```

### Running Guix commands inside the container

```bash
CONTAINER=$(docker run -d --privileged ghcr.io/kromka-chleba/guix-dev:latest)

# Start the Guix daemon (stopped by default at boot)
docker exec $CONTAINER /run/current-system/profile/bin/herd start guix-daemon

# Build a package
docker exec $CONTAINER /run/current-system/profile/bin/guix build hello
```

### Running Docker commands inside the container

The image includes the Docker daemon (`docker-service-type`).  Running with
`--privileged` starts it via Shepherd, so `docker` commands work without
mounting an external socket:

```bash
CONTAINER=$(docker run -d --privileged ghcr.io/kromka-chleba/guix-dev:latest)

# Confirm the Docker daemon is running
docker exec $CONTAINER docker info

# Build a Docker image from inside the container
docker exec $CONTAINER docker build -t my-image /path/to/context
```

### In GitHub Copilot Coding Agent

```json
{
  "image": "ghcr.io/kromka-chleba/guix-dev:latest",
  "runArgs": ["--privileged"],
  "postStartCommand": "herd status"
}
```

---

## Updating the image

Edit `.github/guix-dev-docker.scm` to add or remove packages or services,
then push to `master`.  The Actions workflow automatically rebuilds and pushes
the updated image to `ghcr.io/kromka-chleba/guix-dev:latest`.
