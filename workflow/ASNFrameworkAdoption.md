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

The artifact builder now expects consuming services to provide a build manifest
command through `BUILD_MANIFEST_CMD`. SWAN sets this to the generic
`bash service-utils/builder/build_manifest.sh` helper and supplies
service-specific artifact lists from its root Make/config layer.

The important behavior changes are:

| Area | Previous behavior | New behavior |
|---|---|---|
| Build status | `check-version` printed the current and next version. | `check-build` validates the active manifest and still keeps `check-version` as an alias. |
| DEV build number | A local `.BUILD_FILE` could be incremented before artifacts existed. | `DEV_BUILD_FILE` is committed only after successful plugin artifacts; `reserve-plugin-version` prevents concurrent duplicate DEV identities. |
| Artifact identity | Debian and Docker targets could recompute or infer `VERSION_BUILD`. | `build/Manifest.yaml` owns the artifact version and lane status. |
| Package/image order | Package and image targets could run without a shared artifact contract. | Producers commit manifest lanes after validating their outputs; consumers require the lane and trust the manifest. |
| Internal build targets | Private artifact executor targets could be called without `VERSION_BUILD`. | Internal build steps require `VERSION_BUILD`; top-level targets pass the manifest-owned value. |
| Builder base image check | Labels were the main freshness check. | Builder input hashes and offline Go dependency resolution are checked too. |
| Executor | Dockerfile target execution was the normal path. | `docker-run` is the only shared container executor. |
| Publish diagnostics | Some optional local/remote probes hid stderr. | Registry, Docker, and Debian checks now surface actionable failures. |

## Framework Release Responsibilities

ASN Framework owns the runtime and toolchain dependency values stored in:

```text
builder/ASN_VERSION
```

For every ASN Framework release:

1. Run the framework release version command that updates `ASN_RUNTIME_VERSION_DEV`,
   `ASN_RUNTIME_VERSION_PRO`, and `ASN_BUILDER_GO_VERSION`.
2. Verify `ASN_RUNTIME_VERSION_PRO` matches the ASN Framework PRO `VERSION.BUILD`.
3. Verify `ASN_RUNTIME_VERSION_DEV` matches the latest approved ASN DEV build manifest.
4. Verify `ASN_BUILDER_GO_VERSION` matches the framework-supported `GO_VERSION`.
5. Commit and publish the `service-utils` branch or tag that consuming services
   will use, for example `v26.7.6`.
6. Communicate the compatible tuple:

```text
ASN_SERVICE_API_VERSION
service-utils branch/tag
ASN_RUNTIME_VERSION_PRO
ASN_RUNTIME_VERSION_DEV
ASN_BUILDER_GO_VERSION
minimum consuming-service Makefile contract
```

Do not ask service repositories to edit `builder/ASN_VERSION` locally. That file
is framework-owned release metadata.

## Consuming Service Requirements

A service repository that includes `service-utils/builder/asn.mk` before the
AM Workflow Space `workflow/make/artifact-builder.mk` include must provide the
following service-local contract.

### Required Configuration

`make/config.mk` or the equivalent service config must define:

```make
SERVICE := <SERVICE>
SERVICE_NAME := <service-name>
SERVICE_GO_PACKAGE := <service-go-module>
SERVICE_GO_SOURCE_C ?= controller
SERVICE_GO_SOURCE_SN ?= servicenode
SERVICE_GO_SOURCE_CLIENT ?= client

VERSION := <service-version-family>
BUILD := <maintainer-build-number>
BUILD_MODE ?= dev
BUILD_DEV := <first-dev-build-number>

DEV_BUILD_FILE ?= .DEV_BUILD_FILE
BUILD_MANIFEST_FILE ?= build/Manifest.yaml
BUILD_DIR := build

ASN_SERVICE_API_VERSION := <api-version>
SERVICE_UTILS_DIR := service-utils

SERVICE_BUILD_DIR_C ?= $(BUILD_DIR)/controller
SERVICE_BUILD_DIR_SN ?= $(BUILD_DIR)/servicenode
SERVICE_BUILD_DIR_CLIENT ?= $(BUILD_DIR)/client

SERVICE_PACKAGE_C ?= $(SERVICE_NAME)-controller
SERVICE_PACKAGE_SN ?= $(SERVICE_NAME)-servicenode
SERVICE_PACKAGE_C_CLI ?= $(SERVICE_NAME)-controller-cli
SERVICE_PACKAGE_CLIENT ?= $(SERVICE_NAME)-client-cli

SERVICE_DOCKER_IMAGE_C ?= $(SERVICE_PACKAGE_C)
SERVICE_DOCKER_IMAGE_SN ?= $(SERVICE_PACKAGE_SN)
SERVICE_DOCKERFILE_C ?= docker/$(SERVICE_NAME)-controller.dockerfile
SERVICE_DOCKERFILE_SN ?= docker/$(SERVICE_NAME)-servicenode.dockerfile
PROTO_SOURCE_FILES := <proto-source-globs>
```

The root Makefile includes `service-utils/builder/asn.mk` before the neutral AM
Workflow artifact builder. `builder/asn.mk` reads service-utils support metadata
and registers ASN checks; the neutral artifact builder derives builder image
paths, manifest schema/source defaults, manifest argument wrappers,
`DEBIAN_PATH`, `DEBIAN_PACKAGES`, artifact inventories, proto generation specs,
and proto stamp inputs from the service identity, derived package/build names,
and compact artifact specs above. Define those variables in service config only
when a service intentionally breaks the standard ASN service layout.

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
They should also avoid rechecking every upstream file; the producer that commits
the manifest lane owns those artifact checks.
Service repositories should declare their artifact contents in config variables
and let the artifact builder run the reusable inner targets:

```make
SERVICE_GO_ARTIFACTS := SERVICE_P_CONTROLLER
SERVICE_P_CONTROLLER := $(SERVICE_BUILD_DIR_C)/$(SERVICE_NAME).so $(SERVICE_GO_SOURCE_C)/main.go - -buildmode=plugin $(SERVICE_GO_FLAGS_C)
SERVICE_FILE_ARTIFACTS := SERVICE_FILE_CONTROLLER_CONFIG
SERVICE_FILE_CONTROLLER_CONFIG := controller/config/*.conf $(SERVICE_BUILD_DIR_C)
SERVICE_GO_CACHE_SPECS := SERVICE_CACHE_CONTROLLER
SERVICE_CACHE_CONTROLLER := ./$(SERVICE_GO_SOURCE_C)
SERVICE_DOCS_STAGE_MANIFEST ?= docs/service-docs.tsv
SERVICE_DOCS_VERSION_KEY := <service_docs_version_key>
SERVICE_DOCS_SOURCE_KEY := <service_source_commit_key>
SERVICE_DOCS_RUNTIME_ROOT := /var/www/$(SERVICE_NAME)
```

`build.artifacts`, `check.deb`, `build.deb`, and the internal docs staging helper
are shared service-utils functions. Do not add service-specific private Make
targets or project-local scripts for those mechanics unless the service has a
genuinely non-generic artifact boundary. Service-owned docs manifests should list docs
content; config should keep only service-specific docs metadata overrides that
the generic builder cannot derive. The shared target should perform staging,
checksums, release manifest metadata, and manifest lane updates.

## Builder Base Image Adoption

The prepared builder base image is now stricter. Its freshness check includes:

- `ASN_SERVICE_API_VERSION`;
- `ASN_RUNTIME_VERSION`;
- `ASN_BUILDER_GO_VERSION`;
- `go.mod`;
- files listed by `ARTIFACT_BUILDER_INPUT_FILES`;
- `SERVICE_GO_CACHE_PACKAGES`;
- an offline `go list -deps` probe.

Services may tune:

```make
SERVICE_GO_CACHE_SPECS := SERVICE_CACHE_CONTROLLER SERVICE_CACHE_SERVICENODE
SERVICE_CACHE_CONTROLLER := ./$(SERVICE_GO_SOURCE_C)
SERVICE_CACHE_SERVICENODE := ./$(SERVICE_GO_SOURCE_SN)
BUILD_CONTAINER_METADATA_FILES += $(SERVICE_UTILS_DIR)/builder/ASN_VERSION
BUILD_CONTAINER_CACHE_INPUTS += $(SERVICE_UTILS_DIR)/go.mod $(SERVICE_UTILS_DIR)/go.sum
ARTIFACT_BUILDER_GOCACHE ?= $(CURDIR)/.cache/artifact-builder/go-build
```

Run `make prepare` whenever these inputs change. Run `make check` before
release builds to confirm the local image still matches source intent.

For executor migration details, use `BuilderExecutionMigration.md`.

## Adoption Sequence

1. Update the service's `service-utils` submodule to the framework-approved ref.
2. Declare service artifact, docs, Docker, and Debian content in config
   variables consumed by the artifact builder.
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

For executor issues, keep or return the service to its previous known-good
`service-utils` ref and record the host constraint. For manifest issues, do not
reintroduce `.BUILD_FILE` increments. Fix the service-local manifest script or
temporarily keep the service on the previous `service-utils` ref until the
manifest contract is implemented.

Rollback from the manifest-aware builder is a submodule/ref rollback, not a
runtime Framework rollback. Record the service, API version, `service-utils`
ref, `ASN_RUNTIME_VERSION`, and reason before publishing artifacts from a rolled
back service.
