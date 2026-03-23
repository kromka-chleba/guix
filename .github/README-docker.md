# Guix Dev Docker Environment

> **⚠ Unofficial / Personal tooling**
>
> This Docker image and all related tooling in `.github/docker/` are
> **not** part of the official [GNU Guix](https://guix.gnu.org/) project.
> They are maintained for a **personal development branch/workflow** to
> speed up package and service work on the
> [kromka-chleba/guix](https://github.com/kromka-chleba/guix) fork.
>
> The repository is public so that random users can also benefit from the
> workflow, but please do not confuse it with upstream Guix infrastructure.

---

## Table of Contents

1. [Purpose](#purpose)
2. [Repository layout](#repository-layout)
3. [Quick start — local development](#quick-start--local-development)
4. [Preparing the dev environment](#preparing-the-dev-environment)
5. [pre-inst-env requirement](#pre-inst-env-requirement)
6. [How the Docker image is built (image-from-scratch)](#how-the-docker-image-is-built-image-from-scratch)
7. [Container runtime behaviour](#container-runtime-behaviour)
8. [Helper scripts](#helper-scripts)
9. [CI pipeline](#ci-pipeline)
10. [Bootstrap and recovery](#bootstrap-and-recovery)
11. [Caveats](#caveats)

---

## Purpose

The container is intended to:

- Test and validate Guix package/service changes in a stable, reproducible
  environment.
- Run Guix development commands consistently across machines and CI.
- Act as a **bootstrap environment** for building and publishing updated
  versions of itself (see [Bootstrap and recovery](#bootstrap-and-recovery)).

---

## Repository layout

All Docker-environment assets live under `.github/` and are isolated from
the core Guix source tree:

```
.github/
├── docker/
│   ├── guix-dev-system.scm          # Guix OS configuration for the dev image
│   ├── docker-lib.scm               # Shared helpers loaded by all scripts below
│   ├── build-image.scm              # Guile script: bootstrap image from native Guix
│   ├── build-image-in-docker.scm   # Guile script: build image inside a Docker container
│   ├── test-image.scm               # Guile script: smoke-test a container
│   ├── start-container.scm          # Guile script: start a dev container
│   ├── stop-container.scm           # Guile script: stop and remove a container
│   ├── push-image.scm               # Guile script: push image to GHCR
│   └── list-source-urls.scm         # Guile script: list package source URLs
├── workflows/
│   └── docker-image.yml             # GitHub Actions CI workflow
└── README-docker.md                 # ← you are here
.devcontainer/
└── devcontainer.json                # VS Code / GitHub Codespaces config
```

`gnu/` and `guix/` are **not** touched by any of this tooling.

---

## Quick start — local development

### Prerequisites

- A working Guix installation (or the bootstrap container itself).
- Docker installed and running.
- This repository checked out locally.

### 1 — Pull the published image

```bash
docker pull ghcr.io/kromka-chleba/guix-dev:latest
```

### 2 — Create and start a container

```bash
guile .github/docker/start-container.scm \
    --image ghcr.io/kromka-chleba/guix-dev:latest
```

Or manually:

```bash
container_id="$(docker create --privileged \
    -v "$PWD:/workspace" -w /workspace \
    ghcr.io/kromka-chleba/guix-dev:latest)"
docker start "$container_id"
```

> **Note:** `--privileged` is required so that `guix-daemon` can set up build
> sandboxes inside the container.  Without it, the daemon will not start and
> `guix build` will fail.

### 3 — Open an interactive shell

```bash
docker exec -ti "$container_id" /run/current-system/profile/bin/bash --login
```

### 4 — Prepare the dev environment (inside the container)

Before `./pre-inst-env` can be used, the build system must be generated and
compiled.  This **must be done inside the Docker container** so that the
correct Guix store and build dependencies are used:

```bash
docker exec "$container_id" \
    sh -c 'cd /workspace && guix shell -D guix -- sh -c "./bootstrap && ./configure --localstatedir=/var && make"'
```

`guix shell -D guix` makes all of Guix's build dependencies (GNU Autoconf,
Automake, Gettext, Guile, …) available, then runs the three commands that
generate `configure`, configure the build tree, and compile the Guile modules.

> **Note for Guix System users:** If you are already running Guix System (or
> have Guix installed natively), you can run the same command directly in your
> checkout without Docker:
>
> ```bash
> cd /path/to/guix-checkout
> guix shell -D guix -- sh -c './bootstrap && ./configure --localstatedir=/var && make'
> ```
>
> The Docker container is only required when you need a fully isolated,
> reproducible build environment (e.g. for CI or cross-machine consistency).

### 5 — Run Guix development commands

Inside the container, navigate to the mounted repository checkout and use
`./pre-inst-env` (see [pre-inst-env requirement](#pre-inst-env-requirement)).
The dev environment preparation step above must have been run first.

```bash
cd /workspace
./pre-inst-env guix build hello
./pre-inst-env guix lint my-package
# Build a new Docker image (from the host, no manual prepare step needed;
# build-image-in-docker.scm handles preparation automatically):
guile .github/docker/build-image-in-docker.scm \
    --bootstrap-image ghcr.io/kromka-chleba/guix-dev:latest \
    --output guix-system-docker-image.tar.gz
```

---

## Preparing the dev environment

Before `./pre-inst-env` can be used, the build system must be generated and
compiled from the source checkout.  This **must be done inside the Docker
container** — running it on the host or in a different environment will
produce artefacts that reference wrong store paths and will not work:

```bash
guix shell -D guix -- sh -c './bootstrap && ./configure --localstatedir=/var && make'
```

`guix shell -D guix` installs all of Guix's build dependencies (GNU Autoconf,
Automake, Gettext, Guile, …) into the current environment without modifying the
system, then runs the given command inside that environment.

The three sub-commands do the following:

| Command | Purpose |
|---------|---------|
| `./bootstrap` | Runs Autoconf/Automake to generate `configure` and `Makefile.in` files. |
| `./configure --localstatedir=/var` | Configures the build tree; `--localstatedir=/var` matches the value used by an installed Guix. |
| `make` | Compiles the Guile modules, making `./pre-inst-env` operational. |

In CI this is handled automatically by the **"Prepare dev environment"**
workflow step (see [CI pipeline](#ci-pipeline)).

---

## pre-inst-env requirement

> **See also:** _"22.4 Running Guix Before It Is Installed"_ in the
> [Guix manual](https://guix.gnu.org/manual/en/html_node/Running-Guix-Before-It-Is-Installed.html).

When working from a source checkout of this repository (rather than an
installed copy of Guix), all `guix` commands **must** be prefixed with
`./pre-inst-env` so that the in-tree modules take precedence over any
system-installed Guix:

```bash
# Correct — uses in-tree Guix:
./pre-inst-env guix build hello

# Also correct — the helper scripts call ./pre-inst-env internally:
./pre-inst-env guile .github/docker/build-image.scm
./pre-inst-env guile .github/docker/list-source-urls.scm hello gcc
```

This applies to:

- Local development commands.
- CI steps that run `guix system image …` or other `guix` sub-commands.
- Helper scripts in `.github/docker/` (they call `./pre-inst-env guix …`
  internally).

---

## How the Docker image is built (image-from-scratch)

The image is generated with:

```bash
./pre-inst-env guix system image \
    --image-type=docker \
    --system=x86_64-linux \
    .github/docker/guix-dev-system.scm \
    > guix-system-docker-image.tar.gz
```

### Key points

- Guix produces a Docker image **from scratch**, not from a pre-existing
  Docker base image (no `FROM ubuntu`, no Alpine, etc.).
- The image contains **exactly** what is declared in
  `.github/docker/guix-dev-system.scm` — nothing more, nothing less.
- The result is a deterministic, reproducible `.tar.gz` tarball that can
  be loaded with `docker load`.

### Loading the image

```bash
image_id="$(docker load < guix-system-docker-image.tar.gz | awk '{print $NF}')"
container_id="$(docker create --privileged \
    -v "$PWD:/workspace" -w /workspace "$image_id")"
docker start "$container_id"
```

### Interactive shell

```bash
docker exec -ti "$container_id" /run/current-system/profile/bin/bash --login
```

---

## Container runtime behaviour

When the container starts, the Guix system boots normally:

1. **Shepherd** (the Guix init system) is PID 1 and starts configured
   services.
2. The **Guix daemon** (`guix-daemon`) starts, enabling `guix build`,
   `guix install`, etc. from within the container.
3. The system profile is at `/run/current-system/profile/`.

Because this is a minimal dev image, many services that would be present
on a full desktop system (NetworkManager, display manager, etc.) are
intentionally absent.

---

## Helper scripts

All scripts are written in **Guile/Scheme** and share common helpers from
`docker-lib.scm`.  Scripts that call `guix` sub-commands require
`./pre-inst-env` (see [pre-inst-env requirement](#pre-inst-env-requirement));
the container lifecycle scripts (`start`, `stop`, `push`) only need Docker
and a working Guile installation.

### `start-container.scm` — Start a dev container

```bash
# Start container from default local image (name: guix-dev)
guile .github/docker/start-container.scm

# Start container from GHCR image with a custom name
guile .github/docker/start-container.scm \
    --image ghcr.io/kromka-chleba/guix-dev:latest \
    --name my-dev
```

Creates and starts a container with `--privileged` and the repository
mounted at `/workspace`.  Prints the `docker exec` command to connect.

### `stop-container.scm` — Stop and remove a dev container

```bash
# Stop the default container (guix-dev)
guile .github/docker/stop-container.scm

# Stop a named container
guile .github/docker/stop-container.scm --name my-dev
```

### `push-image.scm` — Push the image to GHCR

```bash
# Push the default local image (guix-dev:latest) to GHCR
guile .github/docker/push-image.scm

# Also tag and push as a specific git SHA
guile .github/docker/push-image.scm --sha "$(git rev-parse HEAD)"

# Push a custom local image / remote tag
guile .github/docker/push-image.scm \
    --image my-local-image:tag \
    --tag ghcr.io/kromka-chleba/guix-dev:latest
```

Docker credentials are read from `~/.docker/config.json` as managed by
`docker login`.  Run `docker login ghcr.io` once if you have not
authenticated already.

### `build-image.scm` — Bootstrap the image from a native Guix system

```bash
./pre-inst-env guile .github/docker/build-image.scm \
    --system-config .github/docker/guix-dev-system.scm \
    --output guix-system-docker-image.tar.gz \
    --tag ghcr.io/kromka-chleba/guix-dev:latest
```

Use this script **only for bootstrapping** (first-time setup or recovery) when
no Docker bootstrap image is available yet.  It calls `guix system image`
directly on the host, so `./pre-inst-env` and a working Guix installation are
required.

Pass `--no-load` to only produce the tarball without loading it into Docker.

### `build-image-in-docker.scm` — Build the image inside a bootstrap container

```bash
guile .github/docker/build-image-in-docker.scm \
    --bootstrap-image ghcr.io/kromka-chleba/guix-dev:latest \
    --system-config .github/docker/guix-dev-system.scm \
    --output guix-system-docker-image.tar.gz \
    --tag guix-dev:latest
```

This is the **normal steady-state build path**.  It launches a temporary
container from an existing Guix Docker image, runs `build-image.scm` inside it
via `docker exec`, and optionally loads and tags the resulting tarball.  No
native Guix installation is required on the host.

Pass `--no-load` to only produce the tarball (useful in CI where tagging with
multiple names is handled by a subsequent step).

### `test-image.scm` — Smoke-test a container

```bash
guile .github/docker/test-image.scm \
    --image ghcr.io/kromka-chleba/guix-dev:latest
```

The container runs with `--privileged` by default so that `guix-daemon` starts
and the `guix build hello` test can succeed.  Pass `--no-privileged` to skip
that flag (the build test will then fail as expected).

### `list-source-urls.scm` — List package source URLs

Prints the source URLs for a package and all its transitive dependencies.
Useful for building network allowlists in restricted build environments:

```bash
./pre-inst-env guile .github/docker/list-source-urls.scm hello gcc glibc
```

---

## CI pipeline

The workflow at `.github/workflows/docker-image.yml`:

| Trigger | Behaviour |
|---------|-----------|
| Push to `master` (paths: `.github/docker/**`) | Build, test, publish |
| Pull request (paths: `.github/docker/**`) | Build and test only (no publish) |
| `workflow_dispatch` | Manual run; supports `force_rebuild` input |

### Cache behaviour

The workflow hashes `guix-dev-system.scm`.  If the hash is unchanged
(and `force_rebuild` is not set), the cached tarball from a previous run
is reused, skipping the expensive `guix system image` step.

### Image tags published

- `ghcr.io/kromka-chleba/guix-dev:latest` — always updated on master.
- `ghcr.io/kromka-chleba/guix-dev:<git-sha>` — immutable per commit.

### Build environment

CI uses the previously published `latest` image as the **bootstrap
container**.  `build-image-in-docker.scm` handles the full pipeline inside
that container within a single `guix shell -D guix` environment: preparing
the dev environment (bootstrap/configure/make) and running `guix system image`
to produce the new tarball.  Running everything inside `guix shell -D guix`
ensures `./pre-inst-env` is never invoked outside of it.  See the next
section for what to do when no bootstrap image exists yet.

---

## Bootstrap and recovery

### First-time bootstrap

If no image has been published to GHCR yet, CI cannot pull a bootstrap
image and will fail with an informative error.  To bootstrap:

1. On a machine with Guix installed, build the image using `build-image.scm`:

   ```bash
   ./pre-inst-env guile .github/docker/build-image.scm \
       --output guix-system-docker-image.tar.gz
   ```

2. Load and tag it:

   ```bash
   image_id="$(docker load < guix-system-docker-image.tar.gz | awk '{print $NF}')"
   docker tag "$image_id" ghcr.io/kromka-chleba/guix-dev:latest
   ```

3. Log in to GHCR (if not already) and push:

   ```bash
   docker login ghcr.io   # one-time; credentials saved to ~/.docker/config.json
   guile .github/docker/push-image.scm
   ```

4. Re-trigger the CI workflow; it will now succeed.

### Steady state

CI uses the published `latest` as the bootstrap input to build the next
image.  Each successful master build publishes a new `latest`, keeping
the cycle self-sustaining.

### Recovery (bootstrap image is broken or incompatible)

If the bootstrap image becomes so outdated that it can no longer build a
new image (e.g., Guix API breakage):

1. Follow the [First-time bootstrap](#first-time-bootstrap) steps on any
   machine that has a working Guix installation.
2. Push the freshly built image as `latest` to restore CI.

---

## Caveats

### Privileged mode for builds

`guix-daemon` requires certain Linux capabilities (chroot, device nodes, …) to
set up build sandboxes.  In Docker, this means the container must be started
with `--privileged`.

The helper scripts and `test-image.scm` **use `--privileged` by default**.
If you manage containers manually, always include the flag:

```bash
docker create --privileged "$image_id"
```

Without `--privileged`, Shepherd starts but `guix-daemon` stays stopped, and
`guix build` will fail with a connection error.

### Networking

The `--network` option to `guix system image` (or `guix system
docker-image`) controls how the image is built with respect to the host
network.  An image built with `--network` will share the host network
namespace at runtime, and typically omits services like `nscd` or
`NetworkManager` that manage networking independently.  The default
(without `--network`) creates an isolated network namespace.

The dev image in this repository is built **without** `--network` so that
it behaves predictably across different host environments.

### This is not upstream Guix

The image, scripts, and CI workflow here are maintained solely for
personal development of the
[kromka-chleba/guix](https://github.com/kromka-chleba/guix) fork.
They are not reviewed or endorsed by the GNU Guix maintainers.  For
official Guix containers and infrastructure, see the upstream project at
<https://guix.gnu.org/>.
