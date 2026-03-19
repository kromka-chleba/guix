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
  "postStartCommand": "herd status"
}
```

### Running commands in the container

```bash
# Verify the Guix daemon is available
guix --version

# Build a package you have added or modified
guix build -L . my-new-package

# Open an interactive development shell with all native inputs of a package
guix shell -L . -D my-new-package

# Run the Guix test suite for a specific module (e.g. after editing gnu/packages/foo.scm)
guix build -L . --check my-new-package

# Evaluate a service definition change
guix system build -L . /path/to/system.scm
```

## Workflow for implementing a new package or service

1. **Edit** the relevant `.scm` file under `gnu/packages/` or `gnu/services/`.
2. **Test** inside the container:
   ```bash
   guix build -L . <package-name>
   ```
3. **Lint** the package definition:
   ```bash
   guix lint -L . <package-name>
   ```
4. **Check** that existing packages still build (no regressions):
   ```bash
   guix build -L . --keep-going <package-name>
   ```
5. Commit your changes and open a pull request.

## Important conventions

- All package definitions live in `gnu/packages/<category>.scm`.
- All service definitions live in `gnu/services/<category>.scm`.
- Guix uses **Guile Scheme** – follow the coding style of nearby definitions.
- Use `specification->package` when resolving packages by name in system configs.
- Services that need HTTPS must set `SSL_CERT_DIR` and `SSL_CERT_FILE` via
  shepherd's `#:environment-variables` (see existing services as examples).
- Never use `guix system docker-image` (deprecated); use
  `guix system image --image-type=docker` instead.

## Rebuilding the Docker image

If you need to update the dev image (e.g. to add a new tool):

1. Edit `.github/guix-dev-docker.scm`.
2. Run `.github/bin/build-guix-docker.sh` on a machine with Guix installed.
3. Push the new image to the registry (`docker push ghcr.io/kromka-chleba/guix-dev:latest`).

See `.github/DOCKER.md` for full details.
