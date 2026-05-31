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
| Shared builder contract | `service-utils` | `service.plugin.builder.mk` include index plus `builder/make/*.mk` fragments for `prepare`, `check`, `build-plugin`, `stage-docs`, `build-debian`, `build-docker`, push/list targets, removed-target guidance. |
| Helper scripts | `service-utils/builder/*.sh` | Manifest mutation, builder-base freshness, proto tool staging/generation, publish variable checks, Debian package metadata/building. |
| Generated evidence | consuming service build output | `build/Manifest.yaml`, `build/docs`, `build/debian`, local Docker images. |

Do not copy `service-utils` helper scripts into service repositories. If a
procedure is reusable, move it into `service-utils`; if it is service-specific,
declare the inputs in config and keep the recipe small.

## Migration Sequence

1. Sync `service-utils` to the ASN Framework approved ref.

```bash
ASN_SERVICE_API_VERSION=26.6.6
git submodule update --init service-utils
git -C service-utils fetch origin
git -C service-utils checkout "v${ASN_SERVICE_API_VERSION}"
git -C service-utils pull --ff-only origin "v${ASN_SERVICE_API_VERSION}"
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
| `stage-docs` | Stage service-served docs and commit docs lane evidence. |
| `build-debian` | Build Debian packages from existing plugin/docs artifacts. |
| `build-docker` | Build Docker images from existing Debian/package inputs. |
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
SERVICE_GO_BUILD_SPECS := \
	MANAGER_PLUGIN|manager-plugin|$(BUILD_SVC_C_DIR)/$(SERVICE_NAME).so|manager/main.go|- \
	SERVICENODE_PLUGIN|servicenode-plugin|$(BUILD_SVC_SN_DIR)/$(SERVICE_NAME).so|servicenode/main.go|-

SERVICE_ARTIFACT_COPY_SPECS := \
	manager/config/*.conf:$(BUILD_SVC_C_DIR) \
	servicenode/config/*.conf:$(BUILD_SVC_SN_DIR)

SERVICE_DEBIAN_REQUIRED_ARTIFACTS := $(BUILD_DIR)/docs/release/ReleaseManifest.yaml
SERVICE_DEBIAN_PACKAGE_COPY_SPECS := \
	$(SERVICE_MANAGER_DEBIAN_PACKAGE):$(BUILD_DIR)/docs:var/www/$(SERVICE_NAME)/manager

SERVICE_DOCKER_REQUIRED_ARTIFACTS = \
	$(BUILD_SVC_C_DIR)/$(SERVICE_NAME).so \
	$(DEBIAN_PATH)/$(SERVICE_SN_DEBIAN_PACKAGE)_@VERSION_BUILD@_amd64.deb
SERVICE_DOCKER_REQUIRED_GLOBS := $(BUILD_SVC_C_DIR)/*.conf
```

`service-utils` derives default `DEBIAN_PATH`, `DEBIAN_SERVICES`,
`SERVICE_PLUGIN_REQUIRED_GLOBS`, and the Go-built portion of
`SERVICE_PLUGIN_REQUIRED_ARTIFACTS` from the service naming/build-dir variables
and `SERVICE_GO_BUILD_SPECS`. Services may use
`SERVICE_PLUGIN_REQUIRED_EXTRA_ARTIFACTS` for non-Go generated files such as
copied config. Override the full artifact list only for intentionally
non-standard plugin layouts.

6. Use manifest-owned build identity.

Services should provide schema/source identity only:

```make
BUILD_MANIFEST_SCHEMA := <service>.build.manifest.v1
BUILD_MANIFEST_SOURCE_KEY := <service>_commit
BUILD_MANIFEST_SOURCE_LABEL := <SERVICE>
```

`service-utils` derives `BUILD_MANIFEST_CMD`, service identity args, default docs
args, `BUILD_MANIFEST_ARGS`, and `BUILD_MANIFEST_COMMON_EXTRA_ARGS`.

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
DOCKER_REGISTRY_SITES ?= CN US
DEBIAN_REPO_SITES ?= CN
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
PACKAGE
SERVICE_UTILS_DIR
ASN_SERVICE_API_VERSION
VERSION
BUILD
BUILD_MODE
BUILD_NUM_DEV
DEV_BUILD_FILE
BUILD_MANIFEST_FILE
BUILD_DIR
BUILD_SVC_C_DIR
BUILD_SVC_SN_DIR
BUILD_SVC_CLIENTS_DIR
DOCKER_IMAGES
DOCKER_IMAGE_BUILD_SPECS
BUILD_MANIFEST_SCHEMA
BUILD_MANIFEST_SOURCE_KEY
BUILD_MANIFEST_SOURCE_LABEL
SERVICE_GO_BUILD_SPECS
SERVICE_ARTIFACT_COPY_SPECS
SERVICE_DEBIAN_REQUIRED_ARTIFACTS
SERVICE_DOCKER_REQUIRED_ARTIFACTS
```

The root Makefile supplies the pre-include `BUILD_ENV_MAKEFILE` and
`BUILD_ENV_ASN_VERSION_FILE` bootstrap defaults.
The shared builder supplies standard ASN-service defaults for generic builder
image variables, manifest wrapper args, `DEBIAN_PATH`, `DEBIAN_SERVICES`,
`SERVICE_PLUGIN_REQUIRED_ARTIFACTS`, `SERVICE_PLUGIN_REQUIRED_GLOBS`, and
derived proto generation variables.

Services with docs, clients, local API docs, or custom release topology should
also define the relevant `SERVICE_DOCS_*`, `SERVICE_LOCAL_MAKE_*`,
`SERVICE_DOCKER_REQUIRED_GLOBS`, `DEBIAN_REPO_*`, and `DOCKER_REGISTRY_*`
variables.

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
make stage-docs
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
