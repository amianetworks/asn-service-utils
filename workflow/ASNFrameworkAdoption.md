# ASN Framework Adoption Guide

Status: migration guide for ASN Framework and ASN Service maintainers
Scope: adopting the manifest-aware `service-utils` builder changes
Audience: ASN Framework release engineers, service maintainers, DevOps, and coding agents

## Purpose

Recent `service-utils` builder changes make ASN Service builds manifest-aware. A
consuming service no longer treats the next build number as a loose Makefile
calculation. Instead, plugin, documentation, Debian, Docker, and publish steps
share one generated build receipt.

This guide explains how ASN Framework releases and ASN Service repositories
should adopt those changes without mixing framework runtime versioning,
service API versioning, and service product versioning.

Use `MakefileMigration.md` as the step-by-step service repository migration
guide. This document explains the framework/service responsibilities behind
that migration.

## What Changed

The shared builder now expects consuming services to provide a build manifest
command through `BUILD_MANIFEST_CMD`. SWAN sets this to the generic
`bash service-utils/builder/build_manifest.sh` helper and supplies
service-specific artifact lists from its root Make/config layer.

The important behavior changes are:

| Area | Previous behavior | New behavior |
|---|---|---|
| Build status | `check-version` printed the current and next version. | `check-build` validates the active manifest and still keeps `check-version` as an alias. |
| DEV build number | A local `.BUILD_FILE` could be incremented before artifacts existed. | `DEV_BUILD_FILE` is committed only after successful plugin artifacts; `reserve-plugin-version` prevents concurrent duplicate DEV identities. |
| Artifact identity | Debian and Docker targets could recompute or infer `VERSION_BUILD`. | `build/Manifest.yaml` owns the artifact version and lane status. |
| Package/image order | Package and image targets could run without proving upstream artifacts. | `build-debian` requires plugin and docs lanes; `build-docker` requires the Debian lane. |
| Internal build targets | Internal `service-build-*` targets could be called without `VERSION_BUILD`. | Internal build steps require `VERSION_BUILD`; top-level targets pass the manifest-owned value. |
| Builder base image check | Labels were the main freshness check. | Builder input hashes and offline Go dependency resolution are checked too. |
| Executor | Dockerfile target execution was the normal path. | `docker-run` is the default; `docker-build` remains a migration fallback. |
| Publish diagnostics | Some optional local/remote probes hid stderr. | Registry, Docker, and Debian checks now surface actionable failures. |

## Framework Release Responsibilities

ASN Framework owns the runtime and toolchain dependency values stored in:

```text
builder/ASN_VERSION
```

For every ASN Framework release:

1. Run the framework release version command that updates `DEP_VERSION_ASN` and
   `DEP_VERSION_GO`.
2. Verify `DEP_VERSION_ASN` matches the ASN Framework `VERSION`.
3. Verify `DEP_VERSION_GO` matches the framework-supported `GO_VERSION`.
4. Commit and publish the `service-utils` branch or tag that consuming services
   will use, for example `v26.6.6`.
5. Communicate the compatible tuple:

```text
ASN_SERVICE_API_VERSION
service-utils branch/tag
DEP_VERSION_ASN
DEP_VERSION_GO
minimum consuming-service Makefile contract
```

Do not ask service repositories to edit `builder/ASN_VERSION` locally. That file
is framework-owned release metadata.

## Consuming Service Requirements

A service repository that includes `service-utils/builder/service.plugin.builder.mk`
must provide the following service-local contract.

### Required Configuration

`make/config.mk` or the equivalent service config must define:

```make
VERSION := <service-version-family>
BUILD := <maintainer-build-number>
BUILD_MODE ?= dev
BUILD_NUM_DEV := <first-dev-build-number>

DEV_BUILD_FILE ?= .DEV_BUILD_FILE
BUILD_MANIFEST_FILE ?= build/Manifest.yaml
BUILD_MANIFEST_CMD := bash service-utils/builder/build_manifest.sh
BUILD_MANIFEST_SERVICE_ARGS := --schema <schema> --source-key <source-key> ...
BUILD_MANIFEST_ARGS = $(BUILD_MANIFEST_SERVICE_ARGS)
BUILD_MANIFEST_COMMON_EXTRA_ARGS = <docs-or-service-default-extra-args>

ASN_SERVICE_API_VERSION := <api-version>
SERVICE_UTILS_DIR := service-utils
BUILD_ENV_MAKEFILE := $(SERVICE_UTILS_DIR)/builder/service.plugin.builder.mk
BUILD_ENV_ASN_VERSION_FILE := $(SERVICE_UTILS_DIR)/builder/ASN_VERSION

BUILD_SVC_C_DIR := build/controller
BUILD_SVC_SN_DIR := build/servicenode
BUILD_SVC_CLIENTS_DIR := build/client
DEBIAN_PATH := build/debian
DEBIAN_SERVICES := <package names>
DOCKER_IMAGES := <image names>
DOCKER_IMAGE_BUILD_SPECS := <image:dockerfile pairs>
PROTO_GEN_SPECS := <proto-source-glob:generated-output-dir pairs>
PROTO_GEN_STATE_FILES := <files that invalidate default proto-gen stamp>
```

The root Makefile, or the equivalent non-config Make layer, should resolve
`VERSION_BUILD` from the active `build/Manifest.yaml` only when the manifest
`build_mode` matches the current `BUILD_MODE`. Keep service config declarative;
do not put shell-evaluated manifest parsing in the tracked config file. A stale
DEV manifest from another `VERSION` or a PRO manifest with the wrong build
number must not be accepted.

See `MakefileMigration.md` for the full variable checklist, root Makefile
bootstrap pattern, removed target mapping, publish topology pattern, and
validation sequence.

### Required Build Helpers

The consuming service must import or provide service-specific equivalents of
these Make-owned behaviors:

```text
BUILD_MANIFEST_CMD
private Docker input gate
private Docker/Debian publish artifact gates
```

`BUILD_MANIFEST_CMD` must support:

| Command | Required purpose |
|---|---|
| `check-build` | Print build status and reject stale manifest identity. |
| `reserve-plugin-version` | Reserve a DEV version before plugin artifact generation. |
| `commit-plugin` | Write plugin lane evidence only after plugin artifacts exist. |
| `require-lane` | Validate a lane before downstream package/image/publish steps. |
| `commit-lane` | Add docs, Debian, or Docker lane evidence after successful output checks. |
| `value` | Read manifest fields for docs and workflow tooling. |

The manifest should record at least:

```yaml
build_mode: dev|pro
version_build: <service-version-build>
asn_service_api_version: <api-version>
dep_version_asn: <framework-version>
service_utils_ref: <commit-or-ref>
lanes:
  plugin:
    status: PASS
  docs:
    status: PASS
  debian:
    status: PASS
  docker:
    status: PASS
```

Services may add more evidence fields, but downstream checks should continue to
key off `build_mode`, `version_build`, and lane status.

### Required Makefile Integration

Use the new top-level flow:

```text
make prepare
make build-plugin
make build-debian
make build-docker
make check
```

The old lifecycle names are compatibility errors:

| Removed target | Replacement |
|---|---|
| `build-init` | `init` |
| `build-prepare` | `prepare` |
| `debian` | `build-debian` |
| `docker` | `build-docker` |
| `increment-build` | no replacement; use `build-plugin` |

Package and Docker targets should consume existing manifest-owned artifacts.
They should not silently rebuild plugin artifacts or choose a new version.
Service repositories should declare their artifact contents in config variables
and let the shared builder run the reusable inner targets:

```make
SERVICE_GO_BUILD_ARTIFACTS := MANAGER_PLUGIN SERVICENODE_PLUGIN
SERVICE_GO_BUILD_OUT_MANAGER_PLUGIN := $(BUILD_SVC_C_DIR)/$(SERVICE_NAME).so
SERVICE_GO_BUILD_SRC_MANAGER_PLUGIN := $(SERVICE_C_SRC)/main.go
SERVICE_ARTIFACT_COPY_SPECS := manager/config/*.conf:$(BUILD_SVC_C_DIR)
SERVICE_DEBIAN_REQUIRED_ARTIFACTS := $(BUILD_DIR)/docs/release/ReleaseManifest.yaml
SERVICE_DEBIAN_PACKAGE_COPY_SPECS := $(SERVICE_MANAGER_DEBIAN_PACKAGE):$(BUILD_DIR)/docs:var/www/$(SERVICE_NAME)/manager
SERVICE_DOCS_STAGE_COPY_SPECS := docs/api:api docs/design:design
SERVICE_DOCS_STAGE_REQUIRED_FILES := index.html release/ReleaseManifest.yaml
SERVICE_DOCS_VERSION_KEY := <service_docs_version_key>
SERVICE_DOCS_SOURCE_KEY := <service_source_commit_key>
SERVICE_DOCS_RUNTIME_ROOT := /var/www/$(SERVICE_NAME)
DEBIAN_BUILD_PRE_TARGETS ?= stage-docs
DOCKER_BUILD_PRE_TARGETS ?= stage-docs
```

`build.plugin`, `check.deb`, `build.deb`, and `stage-docs` are shared
service-utils functions. Do not add service-specific private Make targets or
project-local scripts for those mechanics unless the service has a genuinely
non-generic artifact boundary. Service-owned config should list docs content,
required files, and metadata keys; the shared target should perform staging,
checksums, release manifest metadata, and manifest lane updates.

## Builder Base Image Adoption

The prepared builder base image is now stricter. Its freshness check includes:

- `ASN_SERVICE_API_VERSION`;
- `DEP_VERSION_ASN`;
- `DEP_VERSION_GO`;
- `go.mod`;
- files listed by `SERVICE_BUILDER_INPUT_FILES`;
- `SERVICE_GO_CACHE_PACKAGES`;
- an offline `go list -deps` probe.

Services may tune:

```make
SERVICE_GO_CACHE_PACKAGES ?= ./...
SERVICE_BUILDER_INPUT_FILES ?= go.mod go.sum $(BUILD_ENV_BASE_DOCKERFILE) $(BUILD_ENV_MAKEFILE) $(BUILD_ENV_ASN_VERSION_FILE)
SERVICE_BUILDER_GOCACHE ?= $(CURDIR)/.cache/service-builder/go-build
```

Run `make prepare` whenever these inputs change. Run `make check` before
release builds to confirm the local image still matches source intent.

For executor migration details, including `SERVICE_BUILD_EXECUTION_MODE`, use
`BuilderExecutionMigration.md`.

## Adoption Sequence

1. Update the service's `service-utils` submodule to the framework-approved ref.
2. Declare service artifact, docs, Docker, and Debian content in config
   variables consumed by the shared builder.
3. Replace old `.BUILD_FILE` usage with `DEV_BUILD_FILE` and
   `BUILD_MANIFEST_FILE`.
4. Update top-level help and CI commands to use `check-build`,
   `build-plugin`, `build-debian`, and `build-docker`.
5. Rebuild the builder base image.

```bash
make prepare
```

6. Run the cheap contract checks.

```bash
make check
```

7. Build artifacts in order.

```bash
make build-plugin
make build-debian
make build-docker
```

8. Inspect `build/Manifest.yaml` and verify all expected lanes are `PASS`.
9. Run the service workflow or release dry run.
10. Only after approval, run publish targets.

## Validation Checklist

A migrated service is ready for release workflow use when:

- `make check-build` rejects a stale manifest from another `VERSION`.
- Two concurrent DEV plugin builds cannot receive the same `VERSION_BUILD`.
- `make build-debian` fails if plugin or docs artifacts are missing.
- `make build-docker` fails if Debian artifacts are missing.
- `make plan-push` reports the manifest-owned version.
- `make check` fails clearly when Docker is unavailable or the builder base
  image is stale.
- `BUILD_MODE=pro make -n build-plugin` uses `VERSION.BUILD` and does not touch
  DEV counters.

## Rollback

For executor issues, use the documented fallback:

```bash
make build-plugin SERVICE_BUILD_EXECUTION_MODE=docker-build
```

For manifest issues, do not reintroduce `.BUILD_FILE` increments. Fix the
service-local manifest script or temporarily keep the service on the previous
`service-utils` ref until the manifest contract is implemented.

Rollback from the manifest-aware builder is a submodule/ref rollback, not a
runtime Framework rollback. Record the service, API version, `service-utils`
ref, `DEP_VERSION_ASN`, and reason before publishing artifacts from a rolled
back service.
