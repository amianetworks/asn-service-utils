# Builder Execution Migration Book

Status: reusable migration guide for service repositories
Scope: ASN Services that consume `service-utils/builder/service.plugin.builder.mk`
Audience: service maintainers, release engineers, and coding agents

## Purpose

`service-build-once` now defaults to `SERVICE_BUILD_EXECUTION_MODE=docker-run`.

The old behavior built a short-lived service builder image for every requested target, copied the whole Docker build context into that image, ran `make -f make/internal.mk <target>` in a Dockerfile `RUN` step, started a container from the result, and copied `/build` back to the host.

The new default runs the requested target directly in the prepared builder base image with the service workspace bind-mounted at `/asn-service`. The service `build/` directory remains the host artifact boundary, so the target can produce plugin artifacts, Debian packages, Docker inputs, or other project-owned build outputs without a per-target source-context copy.

## What Changed

Default executor:

```bash
SERVICE_BUILD_EXECUTION_MODE=docker-run
```

Fallback executor:

```bash
SERVICE_BUILD_EXECUTION_MODE=docker-build
```

The default `docker-run` path uses:

- the prepared builder base image, `$(BUILD_ENV_BASE_IMAGE_REF)`;
- the current service checkout mounted at `$(SERVICE_BUILD_WORKDIR)`, default `/asn-service`;
- the private Git SSH key mounted read-only at `$(SERVICE_BUILD_SECRET_TARGET)`, default `/run/secrets/sshkey`;
- `make -f make/internal.mk $(BUILD_MAKE_TARGET)` as the in-container command.

The prepared builder base image installs the toolchain and downloads Go modules from `go.*`. It does not copy the service source tree and does not run service compile targets such as `build.so`; that work belongs to the mounted workspace executor.

The fallback `docker-build` path keeps the older Dockerfile execution and `docker cp` behavior so projects can migrate gradually.

## Why This Is Faster

The old target executor paid for Docker build context transfer and an intermediate target image even when the prepared base image already had the required toolchain and dependency cache.

The new executor avoids:

- copying the source tree into a target image for every build target;
- building an intermediate image only to run one Make target;
- copying the whole `/build` tree out of a stopped container.

The build still uses the same prepared toolchain image and the same internal make target, but the workspace mount makes outputs appear directly in the service checkout.

## Compatibility Contract

Consuming services should treat `build/` as the artifact boundary.

Recommended target responsibilities:

| Target type | Recommended behavior |
|---|---|
| Producer targets, such as `build.plugin` | Compile source and write artifacts under `build/`. |
| Packaging targets, such as `build.deb` | Consume already-produced inputs from `build/`; do not rebuild expensive producer artifacts unless explicitly documented. |
| Docker image targets | Consume staged package/image inputs from `build/` and project source files included by `.dockerignore`. |
| Docs or metadata staging targets | Stage generated docs or metadata under a project-owned `build/` subdirectory before packaging. |

This split keeps expensive build work in producer targets and makes package/image assembly reproducible and cheap.

## Migration Steps

1. Update the consuming service's `service-utils` submodule to a checkout that contains this migration.
2. Run the service's existing version and base-image checks.

```bash
make check
```

3. If the base image is missing or stale, rebuild it.

```bash
make prepare
```

4. Confirm the default executor is `docker-run`.

```bash
make -n service-build-once BUILD_MAKE_TARGET=build.plugin
```

The dry run should show `docker run --rm`, a bind mount for the service checkout, and the prepared `$(BUILD_ENV_BASE_IMAGE_REF)`.

5. Build plugin artifacts.

```bash
make build-plugin
```

6. Review packaging targets. Package assembly should consume existing artifacts from `build/` instead of rebuilding plugin artifacts.

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
| `SERVICE_BUILD_EXECUTION_MODE` | `docker-run` | Select `docker-run` or temporary `docker-build` fallback. |
| `SERVICE_BUILD_DOCKER_PLATFORM` | `linux/amd64` | Platform passed to Docker. |
| `SERVICE_BUILD_WORKDIR` | `/asn-service` | In-container workspace mount path. |
| `SERVICE_BUILD_SECRET_TARGET` | `/run/secrets/sshkey` | In-container read-only private Git key path. |
| `SERVICE_BUILD_DOCKER_RUN_ARGS` | empty | Extra `docker run` flags, such as additional mounts, env vars, proxy settings, or user mapping. |

Example with an extra Go cache mount:

```bash
make build-plugin SERVICE_BUILD_DOCKER_RUN_ARGS='--mount type=volume,source=asn-go-cache,target=/root/.cache/go-build'
```

Example temporary fallback:

```bash
make build-debian SERVICE_BUILD_EXECUTION_MODE=docker-build
```

## When To Use The Fallback

Use `SERVICE_BUILD_EXECUTION_MODE=docker-build` temporarily when:

- the Docker daemon is remote and cannot access the local service checkout path for bind mounts;
- the host has a policy that blocks bind mounts from the workspace;
- a service still depends on Dockerfile-specific side effects from `service.plugin.builder.dockerfile`;
- migration validation is still in progress and the old behavior is needed as a comparison point.

The desired end state is `docker-run`. Treat fallback use as a migration exception and record why it is needed.

## Risks And Checks

Linux file ownership:

- The default container user may write root-owned files into `build/` on Linux hosts.
- If a service needs host-user ownership, evaluate `SERVICE_BUILD_DOCKER_RUN_ARGS='--user <uid>:<gid>'` with that service's builder image and cache paths before adopting it.

Remote Docker daemon:

- `docker-run` requires the Docker daemon to resolve the host workspace bind path.
- Remote BuildKit setups may need the fallback until they provide an equivalent shared filesystem.

Secret path:

- The private Git key is mounted at `SERVICE_BUILD_SECRET_TARGET`.
- The prepared base image must have SSH configuration that reads that path.

Base image freshness:

- Rebuild the base image after service API, framework/runtime dependency, Go toolchain, protobuf tooling, private module dependency, service `go.mod`, or builder Dockerfile changes.
- `make check` verifies the local builder base image labels before build targets run.
- The base image should remain source-free. If a `make prepare` log shows `COPY . .` or `make -f make/internal.mk build.so`, the consuming project is using an old `service-utils` checkout or a project-specific builder Dockerfile that still needs migration.

Packaging correctness:

- Packaging targets should fail clearly when required `build/` inputs are missing.
- Do not hide missing producer artifacts by silently rebuilding them during package assembly unless that is the explicit project contract.

## Rollback

For a single command:

```bash
make build-plugin SERVICE_BUILD_EXECUTION_MODE=docker-build
```

For a shell session:

```bash
export SERVICE_BUILD_EXECUTION_MODE=docker-build
```

Rollback should not require source changes. If a project must keep the fallback permanently, document the host or project constraint in that service repository.
