# ASN Service Utils

`service-utils` is a shared utility submodule for ASN Services implemented as plugins.

It is not the ASN Service API itself. The ASN Service API is provided by the `asn-service-api` Go module. This repository contains the common builder, Docker, config, topology, and dependency metadata used by services that plug into the ASN Framework.

## Repository Layout

```text
builder/    Makefiles, Dockerfiles, and ASN Framework version metadata for plugin builds
config/     ASN Controller and ASN Service Node config templates and topology examples
docker/     Docker Compose examples and cluster-generation helper
proto/      ASN manager/local protobuf definitions used by utility tooling
workflow/   ASN Service API and version-control design notes
go.mod      Go dependencies used by service-utils itself
```

## Version Control Model

ASN Services have several related but separate versions:

| Version | Controlled By | Meaning |
|---|---|---|
| ASN Service API version | Consuming service `ASN_SERVICE_API_VERSION` and consuming service `go.mod` | Go API contract used by the service plugin. |
| `service-utils` checkout | Consuming service submodule commit, or `update_service_utils` | Builder/config/deploy utility version paired with the API version. |
| ASN Framework/runtime version | `builder/ASN_VERSION` `DEP_VERSION_ASN` | ASN Controller / ASN Service Node runtime dependency version. |
| Builder Go toolchain version | `builder/ASN_VERSION` `DEP_VERSION_GO` | Go version installed in service-plugin builder images. |
| ASN Service product version | Consuming service `VERSION`, `BUILD`, and `BUILD_MODE` | Product artifact version for that service. |

The intended relationship, also documented in consuming service `make/config.mk` comments, is:

```text
ASN_SERVICE_API    ASN_SERVICE_UTILS    ASN Framework    ASN Service
git tag/version    git branch/tag       runtime version  product version
```

The API version and `service-utils` checkout are normally paired. In the current Makefile convention, a consuming service sets:

```make
ASN_SERVICE_API_VERSION := <api-version>
SERVICE_UTILS_REF := release/$(ASN_SERVICE_API_VERSION)
```

and the builder helper can update this submodule with:

```make
git checkout $(SERVICE_UTILS_REF)
```

The ASN Framework/runtime version is separate. It is recorded in:

```text
builder/ASN_VERSION
```

as:

```make
DEP_VERSION_ASN=<framework-version>
DEP_VERSION_GO=<go-version>
```

`DEP_VERSION_ASN` and `DEP_VERSION_GO` are set by ASN Framework release tooling. Every ASN Framework P6 must verify these values match the framework `VERSION` and `GO_VERSION` before release evidence is accepted. Service plugin work should not edit `builder/ASN_VERSION` directly unless the task is explicitly ASN Framework/runtime or builder toolchain version maintenance.

The consuming service product version is independent from both the API version and the framework/runtime version.

## Makefile Control Order

A typical consuming service Makefile includes files in this order:

1. The service includes its own `make/config.mk`.
2. The service config sets product version fields and `ASN_SERVICE_API_VERSION`.
3. The service Makefile includes `service-utils/builder/service.plugin.builder.mk`.
4. `service.plugin.builder.mk` includes `builder/ASN_VERSION`.

Because `builder/ASN_VERSION` is included after the service config, its `DEP_VERSION_ASN` and `DEP_VERSION_GO` values are the effective ASN Framework/runtime dependency and builder Go toolchain for builder/package/runtime dependency paths under normal Make execution.

This is why `ASN_SERVICE_API_VERSION` and `DEP_VERSION_ASN` must not be treated as the same version. They are a compatibility pair.

## Service Implementation Contract

ASN owns the framework runtime. A service owns its product behavior.

Controller side:

- The ASN Framework provides `controller.ASNController`.
- The service implements `controller.ASNServiceController`.
- The service exports:

```go
func NewASNServiceController() controller.ASNServiceController
```

Service Node side:

- The ASN Framework provides `servicenode.ASNServiceNode`.
- The service implements `servicenode.ASNService`.
- The service exports:

```go
func NewASNService(asnServiceNode servicenode.ASNServiceNode) (servicenode.ASNService, error)
```

For lifecycle, state, operation, and concurrency rules, see:

- `workflow/Design.md`
- the `asn-service-api` package comments

For version-control details, see:

- `workflow/VersionControl.md`
- `workflow/ASNFrameworkAdoption.md`
- `workflow/MakefileMigration.md`
- `workflow/CheckPlanTargetMigration.md`

## Using service-utils in a Service

A consuming service should:

1. Set `ASN_SERVICE_API_VERSION` in its build config.
2. Use a root `go.mod` dependency that matches the intended ASN Service API version.
3. Add `service-utils` as a submodule at the intended compatible checkout.
4. Include `service-utils/builder/service.plugin.builder.mk` from its root Makefile.
5. Provide the service-specific build targets expected by the builder, usually through the service's internal makefile.
6. Rebuild the builder base image when the service API, framework/runtime dependency, Go toolchain, protobuf tooling, private dependencies, or builder Dockerfiles change.

Common high-level targets exposed by consuming services include:

```bash
make version-report
make version-check
make init
make prepare
make build-plugin
make build-debian
make build-docker
make plan-push
```

Exact target names may vary by service repository.

`version-report` and `version-check` do not sync `service-utils` or build artifacts. `init` is the approved synchronization point that can run `update_service_utils`; `prepare` owns local builder-base preparation before code build.

`service-build-once` defaults to the shared `docker-run` executor: it runs the requested internal target inside the prepared builder base image with the service checkout bind-mounted as the artifact boundary. The older Dockerfile execution path is still available temporarily with `SERVICE_BUILD_EXECUTION_MODE=docker-build`. For adoption steps, configuration knobs, risks, and rollback guidance, see `workflow/BuilderExecutionMigration.md`.

Manifest-aware build adoption is documented in `workflow/ASNFrameworkAdoption.md`.
The step-by-step refreshed Makefile migration path for ASN Framework and
consuming service repositories is documented in `workflow/MakefileMigration.md`.
The simplified `check*`/`plan*` target migration, including ASN Framework row
providers, is documented in `workflow/CheckPlanTargetMigration.md`.

## Build Outputs

A plugin build normally produces artifacts similar to:

```text
build/
+-- controller/
|   +-- <service>.so
|   +-- config files
+-- servicenode/
    +-- <service>.so
    +-- config files
```

Service repositories may also build service-specific CLIs, client daemons, Debian packages, Docker images, or deployment bundles.

## Deployment Assets

The `docker/` and `config/` directories contain reusable examples for deploying ASN Controller, ASN Service Nodes, and service plugins.

Treat these as templates. Production deployment requires service-specific review of:

- runtime image versions,
- database/cache/time-series dependencies,
- IAM dependencies,
- config paths,
- certificates,
- service plugin locations,
- topology files,
- host networking and port behavior.

## Release Safety Rules

- Do not assume `ASN_SERVICE_API_VERSION` equals `DEP_VERSION_ASN`.
- Do not edit `builder/ASN_VERSION` from a service repo unless explicitly performing ASN Framework dependency version maintenance.
- Do not run `update_service_utils` casually; it performs networked git operations and can move the submodule checkout.
- Keep registry and Debian repository URLs in tracked config, but keep credential
  values in ignored local files, shell environment, or CI secret injection.
- Use `make plan-push` to inspect release destinations and readiness without
  printing secrets, tagging images, uploading packages, or publishing repository
  snapshots.
- Do not publish packages, push images, or run deployment commands without explicit approval.
- Record the intended API, `service-utils`, framework/runtime, builder Go toolchain, and service product version pairing for every release.
