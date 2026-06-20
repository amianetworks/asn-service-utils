# Builder Execution Migration Book

Status: active AM Workflow artifact-builder contract
Scope: ASN service projects that include service-utils/builder/asn.mk before
the shared AM Workflow artifact builder
Audience: service maintainers, release engineers, and coding agents

## Purpose

`.artifact-build-run` uses the shared `docker-run` executor by default. The
executor runs the requested internal target inside the prepared artifact base
image with the service workspace bind-mounted as the artifact boundary.

The old Dockerfile target executor has been removed. New services must not add a
runner Dockerfile or per-target image build path.

## What Changed

Default executor:

```bash
ARTIFACT_BUILD_EXECUTOR=container
BUILD_CONTAINER_MODE=docker-run
```

The `docker-run` path uses:

- the prepared artifact base image, `$(BUILD_CONTAINER_BASE_IMAGE_REF)`;
- the current service checkout mounted at `$(BUILD_CONTAINER_WORKDIR)`, default
  `/project`;
- the Workflow Space mounted read-only at
  `$(BUILD_CONTAINER_WORKFLOW_SPACE_ROOT)`;
- the private Git SSH key mounted read-only at `$(BUILD_CONTAINER_SECRET_TARGET)`,
  default `/run/secrets/sshkey`;
- `make -f Makefile $(BUILD_MAKE_TARGET)` as the in-container command.

The prepared artifact base image installs the toolchain and downloads Go modules
from `go.*`. It does not copy the service source tree and does not run service
compile targets; that work belongs to the mounted workspace executor.

## Why This Is Faster

The previous executor paid for Docker build context transfer and an intermediate
target image even when the prepared base image already had the required toolchain
and dependency cache.

The current executor avoids:

- copying the source tree into a target image for every build target;
- building an intermediate image only to run one Make target;
- copying the whole `/build` tree out of a stopped container.

The build still uses the same prepared toolchain image and the same internal Make
target, but the workspace mount makes outputs appear directly in the service
checkout.

## Compatibility Contract

Consuming services should treat `build/` as the artifact boundary.

| Target type | Recommended behavior |
|---|---|
| Producer targets, such as `build.artifacts` | Compile source and write artifacts under `build/`. |
| Packaging targets, such as `build.deb` | Consume already-produced inputs from `build/`; do not rebuild expensive producer artifacts unless explicitly documented. |
| Docker image targets | Consume staged package/image inputs from `build/` and project source files included by `.dockerignore`. |
| Docs or metadata staging targets | Stage generated docs or metadata under a project-owned `build/` subdirectory before packaging. |

This split keeps expensive build work in producer targets and makes package/image
assembly reproducible and cheap.

## Migration Steps

1. Update the consuming service's `service-utils` submodule to a checkout that
   contains the artifact builder.
2. Run the service's existing version and base-image checks.

```bash
make check
```

3. If the base image is missing or stale, rebuild it.

```bash
make prepare
```

4. Confirm the executor uses `docker-run`.

```bash
make -n .artifact-build-run BUILD_MAKE_TARGET=build.artifacts
```

The dry run should show `docker run --rm`, a bind mount for the service checkout,
and the prepared `$(BUILD_CONTAINER_BASE_IMAGE_REF)`.

5. Build plugin artifacts.

```bash
make build-plugin
```

6. Review packaging targets. Package assembly should consume existing artifacts
   from `build/` instead of rebuilding plugin artifacts.
7. Build package artifacts.

```bash
make build-debian
```

8. Run the consuming project's nearest contract or release check.

```bash
make check
```

Use the project's workflow or release validation command when it has one.

## Configuration Knobs

| Variable | Default | Use |
|---|---|---|
| `BUILD_CONTAINER_MODE` | `docker-run` | Executor mode. Only `docker-run` is supported. |
| `BUILD_CONTAINER_PLATFORM` | `linux/amd64` | Platform passed to Docker. |
| `BUILD_CONTAINER_WORKDIR` | `/project` | In-container workspace mount path. |
| `BUILD_CONTAINER_WORKFLOW_SPACE_ROOT` | `/am-workflow-space` | In-container read-only Workflow Space mount path. |
| `BUILD_CONTAINER_SECRET_TARGET` | `/run/secrets/sshkey` | In-container read-only private Git key path. |
| `BUILD_CONTAINER_RUN_ARGS` | empty | Extra `docker run` flags, such as additional mounts, env vars, proxy settings, or user mapping. |

Example with an extra Go cache mount:

```bash
make build-plugin BUILD_CONTAINER_RUN_ARGS='--mount type=volume,source=asn-go-cache,target=/root/.cache/go-build'
```

## Risks And Checks

Linux file ownership:

- The default container user may write root-owned files into `build/` on Linux
  hosts.
- If a service needs host-user ownership, evaluate
  `BUILD_CONTAINER_RUN_ARGS='--user <uid>:<gid>'` with that service's builder
  image and cache paths before adopting it.

Remote Docker daemon:

- `docker-run` requires the Docker daemon to resolve the host workspace bind
  path.
- Hosts without workspace bind-mount support are not compatible with this
  executor contract.

Secret path:

- The private Git key is mounted at `BUILD_CONTAINER_SECRET_TARGET`.
- The prepared base image must have SSH configuration that reads that path.

Base image freshness:

- Rebuild the base image after service API, framework/runtime dependency, Go
  toolchain, protobuf tooling, private module dependency, service `go.mod`, or
  builder Dockerfile changes.
- `make check` verifies the local artifact base image labels before build
  targets run.
- The base image should remain source-free. If a `make prepare` log shows
  `COPY . .` or a compile target running inside the base-image Dockerfile, the
  consuming project is using an old `service-utils` checkout or a project-specific
  builder Dockerfile that still needs migration.

Packaging correctness:

- Packaging targets should fail clearly when required `build/` inputs are
  missing.
- Do not hide missing producer artifacts by silently rebuilding them during
  package assembly unless that is the explicit project contract.

## Rollback

Rollback is a service-utils ref rollback.

If a service cannot use the `docker-run` executor, keep or return that service to
its previous known-good `service-utils` ref, record the host constraint, and fix
the shared executor contract or service configuration before moving forward.
