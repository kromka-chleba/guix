# GitHub Copilot Coding Agent – Instructions for Guix Development

## Development environment

**Always use the pre-built Docker image for all build, test, and package-verification tasks.**

The image is published at:

```
ghcr.io/kromka-chleba/guix-dev:latest
```

It contains the complete Guix development toolchain: `guix`, `gcc-toolchain`,
`gnu-make`, `autoconf`, `automake`, `libtool`, `pkg-config`, `guile` + key
extensions, `git`, `gnupg`, `texinfo`, and all other dependencies listed in
`.github/guix-dev-docker.scm`.  A Guix daemon is running inside the container
so you can call `guix build`, `guix package`, `guix shell`, etc. directly.

### Configuring your devcontainer

Add or update `.devcontainer/devcontainer.json` in the repository root:

```json
{
  "image": "ghcr.io/kromka-chleba/guix-dev:latest",
  "remoteUser": "root",
  "runArgs": ["--privileged"],
  "postStartCommand": "herd status"
}
```

> **Note:** The `--privileged` flag is required so that the Guix daemon can
> use Linux namespaces for isolated builds.  The devcontainer tooling starts
> the container with Shepherd as PID 1 and then attaches your shell via
> `docker exec`, which is the correct way to interact with a Guix system image
> (using `docker run --rm -it … bash` does **not** work because Shepherd
> blocks the container before a login shell can start).

### Running commands in the container

```bash
# Verify the Guix daemon is available
guix --version

# Build a package you have added or modified
guix build -L . my-new-package

# Open an interactive development shell with all native inputs of a package
guix shell -L . -D my-new-package

# Format a new package definition to the canonical Guix coding style
guix style -L . my-new-package

# Run the Guix test suite for a specific module (e.g. after editing gnu/packages/foo.scm)
guix build -L . --check my-new-package

# Evaluate a service definition change
guix system build -L . /path/to/system.scm
```

## Validating Guile/Scheme syntax

**Always check syntax before committing any `.scm` file** to catch parenthesis
errors and other syntax mistakes early:

```bash
# Check syntax of any Scheme file (replace the path with the file you edited)
guile --no-auto-compile -c '(load "/path/to/your/file.scm")'
```

This loads the file with Guile and reports any syntax errors (missing/extra
parentheses, unknown tokens, etc.) before they reach CI.  Run this on every
`.scm` file you create or modify.

## Workflow for implementing a new package or service

1. **Edit** the relevant `.scm` file under `gnu/packages/` or `gnu/services/`.
2. **Check syntax** with Guile (see above) to catch parenthesis errors early.
3. **Format** the package definition with `guix style`:
   ```bash
   guix style -L . <package-name>
   ```
   This automatically rewrites the definition to match the canonical Guix
   coding style (indentation, argument order, etc.).
4. **Test** inside the container:
   ```bash
   guix build -L . <package-name>
   ```
5. **Lint** the package definition:
   ```bash
   guix lint -L . <package-name>
   ```
6. **Check** that existing packages still build (no regressions):
   ```bash
   guix build -L . --keep-going <package-name>
   ```
7. Commit your changes and open a pull request.

## Important conventions

- All package definitions live in `gnu/packages/<category>.scm`.
- All service definitions live in `gnu/services/<category>.scm`.
- Guix uses **Guile Scheme** – follow the coding style of nearby definitions.
- After writing or editing a package, run `guix style -L . <package-name>` to
  automatically reformat it to the canonical Guix coding style.
- Use `specification->package` when resolving packages by name in system configs.
- Services that need HTTPS must set `SSL_CERT_DIR` and `SSL_CERT_FILE` via
  shepherd's `#:environment-variables` (see existing services as examples).
- Never use `guix system docker-image` (deprecated); use
  `guix system image --image-type=docker` instead.

## Rebuilding the Docker image

If you need to update the dev image (e.g. to add a new tool):

1. Edit `.github/guix-dev-docker.scm`.
2. Push to `master` — the Actions workflow rebuilds and pushes automatically.

For a manual build (e.g. first-time bootstrap) see `.github/DOCKER.md`.
