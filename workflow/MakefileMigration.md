# Refreshed Makefile Migration Guide

Status: reusable migration guide for ASN Framework and ASN Service repositories
Scope: services that consume `service-utils/builder/service.plugin.builder.mk`
Audience: ASN Framework release engineers, service maintainers, DevOps, and coding agents

## Purpose

The refreshed builder design makes the consuming service Makefile a thin
contract layer and keeps reusable mechanics in `service-utils`.

After a service syncs to a compatible `service-utils` ref, use this guide to
adopt the same design that SWAN now uses:

- root `Makefile` owns public entry points, help, workflow gateways, and the
  service-utils bootstrap door;
- service `make/config.mk` is the single portable place for service-specific
  product, artifact, docs, package, image, and publish topology declarations;
- `service-utils/builder/service.plugin.builder.mk` is the public builder
  include and loads focused `service-utils/builder/make/*.mk` fragments for
  lifecycle, checks, source/proto, docs, packaging, Docker, and executor logic;
- generated `build/Manifest.yaml` owns artifact identity and lane status.

Use `CheckPlanTargetMigration.md` with this guide when migrating `check*` and
`plan*` targets. It covers the simplified public target set, removed target
names, and ASN Framework row-provider configuration.

The desired end state is that service Makefiles read like stable contracts.
Procedural shell should live in reusable `service-utils` helpers unless it is
truly service-specific.

## Design Layers

| Layer | Owned by | Contains |
|---|---|---|
| Root command map | consuming service | `help`, `init`, workflow gateway, guarded service-utils include, small root utilities. |
| Service contract config | consuming service | Single declarative `make/config.mk` for `VERSION`, `ASN_SERVICE_API_VERSION`, artifact inventories, docs staging, Debian/Docker topology, publish sites. |
| Shared builder contract | `service-utils` | `service.plugin.builder.mk` include index plus `builder/make/*.mk` fragments for `prepare`, `check`, `build-plugin`, internal docs staging, `build-debian`, `build-docker`, push/list targets, removed-target guidance. |
| Helper scripts | `service-utils/builder/*.sh` | Manifest mutation, builder-base freshness, proto tool staging/generation, publish variable checks, Debian package metadata/building. |
| Generated evidence | consuming service build output | `build/Manifest.yaml`, `build/docs`, `build/debian`, local Docker images. |

Do not copy `service-utils` helper scripts into service repositories. If a
procedure is reusable, move it into `service-utils`; if it is service-specific,
declare the inputs in config and keep the recipe small.

## Migration Sequence

1. Sync `service-utils` to the ASN Framework approved ref.

```bash
ASN_SERVICE_API_VERSION=26.7.2
SERVICE_UTILS_REF="release/${ASN_SERVICE_API_VERSION}"
git submodule update --init service-utils
git -C service-utils fetch origin
git -C service-utils checkout "${SERVICE_UTILS_REF}"
git -C service-utils pull --ff-only origin "${SERVICE_UTILS_REF}"
```

If the service root already has the refreshed bootstrap door, prefer:

```bash
make init
```

`make init` may perform networked git operations and move the submodule. Run it
only when the service needs initialization or realignment.

2. Move service-specific declarations into `make/config.mk`.

Keep the config layer declarative and portable. `make/config.mk` should describe
service identity, versions, artifact inventories, docs contents, package/image
names, publish topology, and project-local delegates in one file. Avoid
`$(shell ...)` for build identity and avoid embedded recipes.

3. Keep the root `Makefile` small.

The root should:

- set `SHELL := /bin/bash` when recipes use Bash features;
- include `make/config.mk`;
- provide `help` and any workflow gateway the service owns;
- optionally include `$(BUILD_ENV_MAKEFILE)`;
- guard shared targets when `service-utils` is missing;
- implement `init` as the bootstrap/realignment door;
- leave shared build, package, Docker, Debian, proto, and publish mechanics to
  `service-utils`.

4. Adopt the shared lifecycle target names.

| Public target | Meaning |
|---|---|
| `init` | Initialize or realign `service-utils`, then run service-utils build checks. |
| `prepare` | Build or refresh the local builder base image. |
| `check` | Validate build variables, build identity, go.mod compatibility, and builder readiness. |
| `build-plugin` | Reserve the manifest-owned version and build plugin/service artifacts. |
| `build-docs` | Service-local public target that generates service docs and calls the shared internal docs staging helper. |
| `build-debian` | Build Debian packages from the manifest-owned plugin/docs contract. |
| `build-docker` | Build Docker images from the manifest-owned Debian lane. |
| `build` | Run the full local artifact build in order. |
| `plan-push` | Preview selected publish destinations without publishing. |
| `push-docker-*`, `push-debian-*` | Publish only after explicit approval. |

Removed names should fail with migration guidance:

| Removed target | Replacement |
|---|---|
| `build-init` | `init` |
| `build-prepare` | `prepare` |
| `debian` | `build-debian` |
| `docker` | `build-docker` |
| `increment-build` | no replacement; `build-plugin` owns DEV reservation and commit. |

5. Replace procedural local targets with config variables.

Use the shared targets by declaring service-specific inventories:

```make
SERVICE_GO_ARTIFACTS := SERVICE_P_CONTROLLER SERVICE_P_SERVICENODE

SERVICE_P_CONTROLLER := $(SERVICE_BUILD_DIR_C)/$(SERVICE_NAME).so $(SERVICE_GO_SOURCE_C)/main.go - -buildmode=plugin $(SERVICE_GO_FLAGS_C)
SERVICE_P_SERVICENODE := $(SERVICE_BUILD_DIR_SN)/$(SERVICE_NAME).so $(SERVICE_GO_SOURCE_SN)/main.go - -buildmode=plugin $(SERVICE_GO_FLAGS_SN)

SERVICE_FILE_ARTIFACTS := \
	SERVICE_FILE_CONTROLLER_CONFIG \
	SERVICE_FILE_SERVICENODE_CONFIG

SERVICE_FILE_CONTROLLER_CONFIG := controller/config/*.conf $(SERVICE_BUILD_DIR_C)
SERVICE_FILE_SERVICENODE_CONFIG := servicenode/config/*.conf $(SERVICE_BUILD_DIR_SN)

SERVICE_GO_CACHE_SPECS := SERVICE_CACHE_CONTROLLER SERVICE_CACHE_SERVICENODE
SERVICE_CACHE_CONTROLLER := ./$(SERVICE_GO_SOURCE_C)
SERVICE_CACHE_SERVICENODE := ./$(SERVICE_GO_SOURCE_SN)

## Debian package configs may include directories; directory sources are staged
## into the destination root.
## Example deb.<service>.config item:
##   build/docs:var/www/$(SERVICE_NAME)/controller

SERVICE_DOCKERFILE_C ?= docker/$(SERVICE_NAME)-controller.dockerfile
SERVICE_DOCKERFILE_SN ?= docker/$(SERVICE_NAME)-servicenode.dockerfile
```

`service-utils` derives default `DEBIAN_PATH`, `DEBIAN_SERVICES`,
`SERVICE_DOCKER_COMPONENTS`, `DOCKER_IMAGES`, `SERVICE_PLUGIN_REQUIRED_GLOBS`,
and the Go-built portion of `SERVICE_PLUGIN_REQUIRED_ARTIFACTS` from the service
naming/build-dir variables, the `SERVICE_P_*` specs listed in
`SERVICE_GO_ARTIFACTS`, and the file specs listed in `SERVICE_FILE_ARTIFACTS`.
Override the full artifact list only for
intentionally non-standard plugin layouts.

6. Use manifest-owned build identity.

Services normally inherit the generic manifest schema/source defaults from
`service-utils`:

```make
BUILD_MANIFEST_SCHEMA ?= service.build.manifest.v1
BUILD_MANIFEST_SOURCE_KEY ?= source_commit
BUILD_MANIFEST_SOURCE_LABEL ?= service
```

`service-utils` derives `BUILD_MANIFEST_CMD`, service identity args, default docs
args, `BUILD_MANIFEST_ARGS`, and `BUILD_MANIFEST_COMMON_EXTRA_ARGS`. Override
these only when a service intentionally owns a different manifest contract.

Do not compute `VERSION_BUILD` from ad hoc shell in tracked service config.
The shared builder resolves the active version from `build/Manifest.yaml` only
when the manifest matches the current `BUILD_MODE` and service `VERSION`.

7. Adopt shared proto tooling when the service has protobuf generation.

Declare proto sources:

```make
PROTO_SOURCE_FILES := proto/foo.proto proto/bar.proto
```

`service-utils` derives `PROTO_GENERATED_FILES`, `PROTO_GEN_SPECS`, and
`PROTO_GEN_STATE_FILES`.

Then use:

```bash
make proto-tools-check
make proto-gen
```

The shared helper owns tool staging, version checks, downloads, incremental
stamps, and generation loops.

8. Adopt shared publish checks.

Keep non-secret topology in tracked config:

```make
DOCKER_REGISTRIES ?= CN US
DEBIAN_REPOSITORIES ?= CN
RELEASE_SECRET_PROFILE_CN ?= ASN_CN
DOCKER_REGISTRY_CN ?= registry.example.cn
DEBIAN_REPO_HOST_CN ?= https://apt.example.cn/api
DOCKER_REGISTRY_CN_USER = $(RELEASE_SECRET_AUTH_$(RELEASE_SECRET_PROFILE_CN)_DOCKER)
DEBIAN_REPO_USER_CN = $(RELEASE_SECRET_AUTH_$(RELEASE_SECRET_PROFILE_CN)_DEBIAN)
```

Keep secret values in ignored local files, shell environment, or CI secrets.
Use:

```bash
make check-vars
make plan-push
```

Do not publish images, packages, snapshots, or deployment changes without
explicit approval.

## Minimum Service Config Contract

Every migrated service should define or intentionally inherit:

```text
SERVICE
SERVICE_NAME
SERVICE_GO_PACKAGE
SERVICE_UTILS_DIR
ASN_SERVICE_API_VERSION
VERSION
BUILD
BUILD_MODE
BUILD_DEV
DEV_BUILD_FILE
BUILD_MANIFEST_FILE
BUILD_DIR
SERVICE_BUILD_DIR_C
SERVICE_BUILD_DIR_SN
SERVICE_BUILD_DIR_CLIENT
SERVICE_PACKAGE_C
SERVICE_PACKAGE_SN
SERVICE_PACKAGE_C_CLI
SERVICE_PACKAGE_CLIENT
SERVICE_GO_ARTIFACTS
SERVICE_P_*
SERVICE_FILE_ARTIFACTS
```

The root Makefile supplies the pre-include `BUILD_ENV_MAKEFILE` and
`BUILD_ENV_ASN_VERSION_FILE` bootstrap defaults.
The shared builder supplies standard ASN-service defaults for generic builder
image variables, manifest wrapper args, `DEBIAN_PATH`, `DEBIAN_SERVICES`,
`SERVICE_DOCKER_COMPONENTS`, `DOCKER_IMAGES`,
`SERVICE_PLUGIN_REQUIRED_ARTIFACTS`, `SERVICE_PLUGIN_REQUIRED_GLOBS`, and
derived proto generation variables.

Services with docs, clients, local API docs, or custom release topology should
also define the relevant `SERVICE_DOCS_*`, `DEBIAN_REPO_*`, and
`DOCKER_REGISTRY_*` variables. Service-specific target delegates and ordering
such as `build-docs`, `check-docs`, and `build-debian: build-docs` should be
declared as targets in the consuming service root Makefile, not as shared
lifecycle or config variables.

## ASN Framework Release Checklist

ASN Framework owns the reusable runtime/toolchain tuple. For each framework
release:

1. Update `builder/ASN_VERSION` through the framework-owned version process.
2. Verify `DEP_VERSION_ASN` matches the ASN Framework runtime release.
3. Verify `DEP_VERSION_GO` matches the supported builder Go toolchain.
4. Verify `service-utils` helper scripts and builder Dockerfiles are committed.
5. Publish the approved `service-utils` branch or tag.
6. Tell service teams the compatible tuple:

```text
ASN_SERVICE_API_VERSION
service-utils branch/tag/commit
DEP_VERSION_ASN
DEP_VERSION_GO
minimum Makefile migration guide revision
```

Service teams should not edit `builder/ASN_VERSION` locally unless they are
performing framework/runtime dependency maintenance.

## Consuming Service Validation

After migration, run the cheapest checks first:

```bash
make check-build
make check
make proto-tools-check
```

If the builder base image is missing or stale:

```bash
make prepare
```

Then build in lane order:

```bash
make build-plugin
make build-docs
make build-debian
make build-docker
```

Review:

- `build/Manifest.yaml` has the expected `build_mode` and `version_build`;
- plugin, docs, Debian, and Docker lanes are `PASS` when those lanes apply;
- `service_utils_ref` is the intended commit/ref;
- Debian package versions and Docker image tags use the same manifest-owned
  `version_build`;
- publish plans report the manifest-owned version.

## Rollback

Rollback is a service-utils ref rollback, not an ASN runtime rollback.

If a service cannot complete migration:

1. Keep or return that service to its previous known-good `service-utils` ref.
2. Record the service name, API version, previous ref, target ref, failure
   reason, and affected targets.
3. Do not reintroduce local `.BUILD_FILE` increments or duplicated publish
   credential checks.
4. Fix the reusable helper in `service-utils` when the failure is generic;
   fix the service config when the failure is service-specific.

For executor-specific issues, temporarily use:

```bash
make build-plugin SERVICE_BUILD_EXECUTION_MODE=docker-build
```

See `BuilderExecutionMigration.md` for details and constraints.
