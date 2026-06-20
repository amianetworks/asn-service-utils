# ASN Service Utils Version Control

Status: initial reusable design note for review  
Scope: version-control behavior for ASN Service Plugins that consume `service-utils`  
Last reviewed: 2026-04-30

## Purpose

`service-utils` is the shared utility submodule for ASN Services implemented as plugins. It provides builder makefiles, builder Dockerfiles, ASN config templates, Docker Compose templates, topology examples, protobuf definitions, and ASN-side dependency metadata.

This document explains how versions are controlled so service maintainers and coding agents do not confuse:

- ASN Service product version.
- ASN Service build number.
- ASN service API version.
- ASN Framework/runtime version.
- `service-utils` checkout version.
- Builder image/toolchain version.

The rules here are generic for ASN Services. Service-specific design documents should record the concrete values used by each service release.

The consuming service's `make/config.mk` should be treated as the service-side entry point for version intent. Its version comments describe four related columns:

| Column | Meaning |
|---|---|
| `ASN_SERVICE_API` | The API contract version selected by the service. |
| `ASN_SERVICE_UTILS` | The `service-utils` branch/tag paired with that API version. |
| `ASN(Framework)` | The ASN Controller / ASN Service Node runtime version dependency. |
| `ASN Services` | The consuming service's own product version. |

These columns are related, but they are not one version number.

## Version Sources

### ASN Service Product Version

Source:

- The consuming service project, usually `make/config.mk`.

Typical variables:

- `VERSION`
- `BUILD`
- `BUILD_MODE`
- `BUILD_DEV`
- `DEV_BUILD_FILE`
- `BUILD_MANIFEST_FILE`
- `VERSION_BUILD`

Meaning:

- `VERSION` is the service product version family.
- `BUILD` is the maintainer-controlled production build number.
- `BUILD_MODE=dev` usually uses an untracked DEV counter and a generated build manifest.
- `BUILD_MODE=pro` usually uses the production `BUILD` value.
- `VERSION_BUILD` is the final version string used by built artifacts.

Control rule:

- All runtime components, CLIs, plugin artifacts, and packages for one service release should use the same `VERSION_BUILD`.
- Development and production build-number ranges should be distinct.
- CI/CD should be the source of truth for production release build numbers when a service uses automated release pipelines.

### ASN Service API Version

Sources:

- The consuming service project, usually `make/config.mk`.
- The consuming service project's `go.mod`.
- `service-utils/go.mod` as the utility submodule's own dependency reference.

Typical variable/package:

- `ASN_SERVICE_API_VERSION`
- `SERVICE_UTILS_REF`
- `asn.amiasys.com/asn-service-api/v26`

Meaning:

- This is the Go service API contract used by ASN Service Plugin code and service utility code.
- It controls compile-time interfaces, lifecycle contracts, operation APIs, framework-facing service interfaces, and Go dependency resolution.

Control rule:

- The consuming service's configured `ASN_SERVICE_API_VERSION` expresses release intent for the service API.
- The consuming service's configured `SERVICE_UTILS_REF` is used by `update_service_utils` to choose a `service-utils` checkout.
- The consuming service's `go.mod` controls the actual Go service API dependency used to compile that service.
- `service-utils/go.mod` records the API dependency for the utility submodule itself. It is compatibility evidence, not the primary compile authority for the consuming service.
- These API references should use the intended same ASN service API version unless there is a documented compatibility exception.
- When `ASN_SERVICE_API_VERSION` changes, the artifact base image must be rebuilt because it caches Go packages and plugin build dependencies.
- Changing the service API version is a compatibility-sensitive change and should be treated as release work.

### ASN Framework Runtime And Toolchain Dependency Versions

Source:

- `service-utils/builder/ASN_VERSION`

Variables:

- `ASN_RUNTIME_VERSION_DEV`
- `ASN_RUNTIME_VERSION_PRO`
- `ASN_RUNTIME_MODE`
- `ASN_RUNTIME_VERSION`
- `ASN_BUILDER_GO_VERSION`

Meaning:

- `ASN_RUNTIME_VERSION_PRO` is the stable ASN Framework/runtime dependency used by default.
- `ASN_RUNTIME_VERSION_DEV` is the approved ASN DEV runtime dependency for explicit integration testing.
- `ASN_RUNTIME_MODE` selects `pro` or `dev`; services default it to `pro`.
- `ASN_RUNTIME_VERSION` is the selected ASN Framework/runtime dependency used by builder and packaging assets.
- It is consumed by `service-utils/builder/asn.mk` through `include $(SERVICE_UTILS_DIR)/builder/ASN_VERSION`.
- It is injected into Debian package control files as `@DEPENDS@`.
- Consuming service projects may also pass `ASN_RUNTIME_VERSION` into Docker build arguments for ASN Controller and ASN Service Node runtime images.
- `ASN_BUILDER_GO_VERSION` is the Go version required for service-plugin builder images.
- In the common Makefile flow, the consuming service includes its own config first, then includes `service-utils/builder/asn.mk`, then includes the neutral AM Workflow `workflow/make/artifact-builder.mk`. `builder/asn.mk` reads selected `ASN_RUNTIME_VERSION` and `ASN_BUILDER_GO_VERSION` from service-utils for normal Make execution.

Control rule:

- `ASN_RUNTIME_VERSION` is not the same thing as `ASN_SERVICE_API_VERSION`.
- These values do not have to be identical.
- They must be treated as a compatibility pair: the selected ASN Framework/runtime version must support the selected ASN service API version.
- `ASN_RUNTIME_VERSION_DEV`, `ASN_RUNTIME_VERSION_PRO`, and `ASN_BUILDER_GO_VERSION` are released by ASN Framework `make set-version` during P6/version maintenance. Service plugin build or workflow work should not edit them directly unless the task is explicitly ASN Framework dependency version maintenance.

### service-utils Checkout Version

Sources:

- The consuming service project's `.gitmodules`.
- The consuming service's project-selected `service-utils/builder/asn.mk`.
- The Workflow Space `project_dependencies` managed module entry.
- The current submodule checkout state.
- The consuming service's API/util pairing policy in `make/config.mk` comments.

Intended behavior:

- `ASN_SERVICE_UTILS` is paired with `ASN_SERVICE_API` in the consuming service's version policy.
- the Workflow Space project dependency resolver prepares the selected
  service-utils module checkout and consumer symlinks.

Meaning:

- The intended active checkout for build work is selected by the Workflow Space
  project dependency registry plus the consuming service's `SERVICE_UTILS_BRANCH`
  intent, which usually derives from `ASN_SERVICE_API_VERSION`.
- A consuming service's `.gitmodules` branch, current submodule checkout, and
  managed module ref may differ if the module was manually moved or if
  repository metadata is stale.
- The submodule may be in detached HEAD after an automated checkout of a version branch or tag.

Control rule:

- Before build or release work, record the intended `service-utils` checkout source:
  - the consuming service project's `.gitmodules` branch,
  - the current submodule branch/tag/commit,
  - and the `SERVICE_UTILS_REF` target used by `update_service_utils`.
- If `.gitmodules`, current checkout, and `SERVICE_UTILS_REF` disagree, document whether this is intentional before publishing artifacts.
- Do not run `update_service_utils` casually: it performs networked git operations and can move the submodule checkout.

### Builder Toolchain Version

Sources:

- `service-utils/builder/ASN_VERSION`.
- `service-utils/builder/asn-artifact-base.dockerfile`.

Typical variables/files:

- `ASN_BUILDER_GO_VERSION`
- Ubuntu base image in the builder Dockerfile.
- Go version installed by the builder Dockerfile.
- protobuf compiler packages installed by the builder Dockerfile.
- `BUILD_CONTAINER_BASE_IMAGE`
- `BUILD_CONTAINER_RUNNER_IMAGE`

Meaning:

- The artifact base image is the cached dependency/toolchain layer.
- The artifact base image downloads module dependencies from `go.*`, but it must not copy the consuming service source tree or run service compile targets.
- The artifact base image check must prove the warmed module cache can resolve the configured service package closure offline; label checks alone are not sufficient.
- The default artifact target executor runs build targets inside the artifact base image with the consuming service workspace bind-mounted as the artifact boundary.
- The artifact base image must be refreshed when service API or toolchain dependency expectations change.

Control rule:

- Toolchain versions are separate from service product version and ASN Framework/runtime version.
- `ASN_BUILDER_GO_VERSION` is framework-owned and is carried through `service-utils/builder/ASN_VERSION`, just like `ASN_RUNTIME_VERSION_DEV` and `ASN_RUNTIME_VERSION_PRO`.
- Every ASN Framework P6 must verify that `ASN_RUNTIME_VERSION_PRO` matches the framework PRO `VERSION.BUILD`, `ASN_RUNTIME_VERSION_DEV` matches the latest approved ASN DEV build manifest, and `ASN_BUILDER_GO_VERSION` matches the framework `GO_VERSION`; stale values mean `make set-version` has not been run for the selected release identity.
- The artifact base image is local state and should not be assumed correct only because source files are correct.
- Rebuild the base image when `ASN_SERVICE_API_VERSION`, Go version, protobuf requirements, private module dependencies, `go.mod`/`go.sum`, the configured service package closure, or builder Dockerfile/Makefile content changes.
- A workspace-local Go build cache may be mounted into builder runs to speed repeated compilation, but the module cache remains image-owned by default so `check-prepare` cannot be accidentally satisfied by host state.
- See `BuilderExecutionMigration.md` before changing container executor settings.
- See `ASNFrameworkAdoption.md` before migrating an ASN Framework release or consuming service repository to the manifest-aware builder contract.
- See `MakefileMigration.md` for the refreshed Makefile layering, variable checklist, bootstrap pattern, and service adoption sequence.

## Build-Time Version Flow

High-level flow:

```text
Consuming service make/config.mk
  |
  +-- VERSION / BUILD / BUILD_MODE
  |     |
  |     +--> VERSION_BUILD
  |            |
  |            +--> Go linker flags for service binaries/plugins
  |            +--> Debian package version
  |
  +-- ASN_SERVICE_API_VERSION
  |     |
  |     +--> Go module dependency expectation
  |     +--> rebuild trigger for artifact base image
  |
  +-- SERVICE_UTILS_REF
  |     |
  |     +--> service-utils checkout target, usually release/$(ASN_SERVICE_API_VERSION)
  |
  +-- service-utils/builder/asn.mk
        |
        v
service-utils/builder/ASN_VERSION
  |
  +-- ASN_RUNTIME_MODE selects dev/pro
  +-- effective ASN_RUNTIME_VERSION
  +-- effective ASN_BUILDER_GO_VERSION
        |
        +--> Debian package dependency version
        +--> Docker build args for ASN runtime dependency
        +--> artifact-builder Docker Go toolchain version
```

## Artifact Version Effects

### Go Artifacts

Consuming services normally use linker flags from their own build configuration to stamp component versions.

Expected behavior:

- Controller or manager plugin/runtime artifacts use `v$(VERSION_BUILD)`.
- Service Node plugin/runtime artifacts use `v$(VERSION_BUILD)`.
- Service-specific CLIs or daemons use `v$(VERSION_BUILD)` when they are part of the same release.

### Debian Packages

The shared AM Workflow artifact builder replaces package control placeholders:

- `@VERSION@` becomes `$(VERSION_BUILD)`.
- `@DEPENDS@` becomes `$(ASN_RUNTIME_VERSION)`.
- `@SERVICE@` becomes the Debian service name.

This means Debian package version and ASN runtime dependency version are controlled by different sources.

### Docker Images

Consuming service projects may define Docker build arguments such as:

```make
--build-arg ASN_C_VERSION=$(ASN_RUNTIME_VERSION)
--build-arg ASN_SN_VERSION=$(ASN_RUNTIME_VERSION)
```

This means Docker runtime dependency versions should be driven by `ASN_RUNTIME_VERSION`, not by `ASN_SERVICE_API_VERSION`.

### service-utils Checkout

The ASN extension target `update_service_utils` attempts to check out `service-utils` to `$(SERVICE_UTILS_REF)`.

This means changing `SERVICE_UTILS_REF` can also change the builder/config/deployment templates used by the build.

## Required Compatibility Checks

Before build or release work, verify:

1. The consuming service's configured `ASN_SERVICE_API_VERSION` matches the intended Go API version.
2. The consuming service's `go.mod` uses the same intended ASN service API version.
3. `service-utils` checkout state is intentional for the selected `SERVICE_UTILS_REF`.
4. `service-utils/go.mod` uses the same intended ASN service API version, or a documented compatible exception exists.
5. `service-utils/builder/ASN_VERSION` `ASN_RUNTIME_MODE` is `pro` by default, or explicitly set to `dev` for ASN DEV integration.
6. `service-utils/builder/ASN_VERSION` `ASN_RUNTIME_VERSION` is an intended compatible ASN Framework/runtime version.
7. `service-utils/builder/ASN_VERSION` `ASN_BUILDER_GO_VERSION` is the intended artifact-builder Go toolchain version.
8. Builder base image has been rebuilt after any API/toolchain/dependency change.
9. Debian and Docker dependency versions are expected to follow `ASN_RUNTIME_VERSION`.
10. Service product artifacts are expected to follow `VERSION_BUILD`.

## Mechanism Review

The current mechanism is workable, but it is not very clear or friendly for maintainers.

Good parts:

- The version model separates ASN service API, `service-utils`, ASN Framework/runtime, and service product versions.
- `make/config.mk` gives each consuming service one visible place to declare service-side version intent.
- `builder/ASN_VERSION` keeps the ASN Framework/runtime dependency under ASN Framework release control.
- Build-number checks prevent development build numbers from being published to production repositories and production build numbers from being published to the development repository.
- Debian package generation uses the service product version for package version and `ASN_RUNTIME_VERSION` for ASN runtime dependency.

Unclear or risky parts:

- Old `DEP_*` version names are not contract names. Service-side config should use `ASN_RUNTIME_MODE`, and the selected `ASN_RUNTIME_VERSION` and `ASN_BUILDER_GO_VERSION` must come from `builder/ASN_VERSION`.
- `update_service_utils` runs through the explicit `make init` lifecycle target and can move the submodule checkout based on `ASN_SERVICE_API_VERSION`.
- There is no read-only target that reports all version authorities before a build.
- `build-plugin` increments the development build number as a side effect.
- `prepare` combines cleanup, protobuf generation, and Docker builder image work after `init` has aligned `service-utils`.
- The service API version must be kept in both service config and root `go.mod`, but there is no explicit consistency check.
- The utility submodule's `go.mod` can look like a control point even though it is only the utility module's own dependency reference.

Implemented checks:

- `version-report` prints service product version, build mode, root Go API dependency, configured `ASN_SERVICE_API_VERSION`, `service-utils` checkout, `service-utils/go.mod` API dependency, `ASN_RUNTIME_MODE`, and effective `ASN_RUNTIME_VERSION`.
- `version-check` fails when API, `service-utils`, or ASN Framework dependency controls are inconsistent.

Recommended improvements:

- Keep `version-report` and `version-check` free of submodule-sync and build-artifact side effects.
- Consider adding a release-specific check that validates the selected repository target against `BUILD_MODE` before publishing.
- Keep service-side config free of derived ASN runtime/toolchain defaults; `service-utils/builder/ASN_VERSION` owns those values and `service-utils/builder/asn.mk` reads them.
- Make build-number incrementing an explicit step for release workflows, or clearly distinguish the `make check` gate from `increment-build`.
- Document the approved API/utils/framework pairing in release notes before building artifacts.

## Agentic Workflow Rules

Agents working on ASN Service Plugin versioning should follow these rules:

- Do not assume `ASN_SERVICE_API_VERSION` and `ASN_RUNTIME_VERSION` must be equal.
- Do not edit `service-utils/builder/ASN_VERSION` unless explicitly assigned ASN Framework dependency version maintenance.
- Do not change dependency versions without approval.
- Do not run `update_service_utils`, `make init`, `make prepare`, Docker builds, package publishing, or networked release operations without approval.
- Do not reproduce credentials from consuming service build configuration in workflow docs or logs.
- When reporting a version issue, classify it as one of:
  - service product/build version issue,
  - ASN service API version issue,
  - ASN Framework/runtime dependency issue,
  - `service-utils` checkout issue,
  - builder toolchain/cache issue,
  - artifact packaging/publishing issue.

## Open Questions

- How should each ASN Service record the approved compatibility pairing between `ASN_SERVICE_API_VERSION` and `ASN_RUNTIME_VERSION`?
- Should consuming services pin `service-utils` by branch, tag, or exact commit for reproducible releases?
- Should `update_service_utils` use a branch, tag, or exact commit?
- Should there be a read-only version check target that reports all version sources without changing the submodule checkout?
- Should CI/CD be the only actor allowed to update production build numbers?
