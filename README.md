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
| ASN Service product version | Consuming service `VERSION`, `BUILD`, and `BUILD_MODE` | Product artifact version for that service. |

The intended relationship, also documented in consuming service `make/config.mk` comments, is:

```text
ASN_SERVICE_API    ASN_SERVICE_UTILS    ASN Framework    ASN Service
git tag/version    git branch/tag       runtime version  product version
```

The API version and `service-utils` checkout are normally paired. In the current Makefile convention, a consuming service sets:

```make
ASN_SERVICE_API_VERSION := <api-version>
```

and the builder helper can update this submodule with:

```make
git checkout v$(ASN_SERVICE_API_VERSION)
```

The ASN Framework/runtime version is separate. It is recorded in:

```text
builder/ASN_VERSION
```

as:

```make
DEP_VERSION_ASN=<framework-version>
```

`DEP_VERSION_ASN` is set by ASN Framework release tooling. Service plugin work should not edit `builder/ASN_VERSION` directly unless the task is explicitly ASN Framework/runtime version maintenance.

The consuming service product version is independent from both the API version and the framework/runtime version.

## Makefile Control Order

A typical consuming service Makefile includes files in this order:

1. The service includes its own `make/config.mk`.
2. The service config sets product version fields and `ASN_SERVICE_API_VERSION`.
3. The service Makefile includes `service-utils/builder/service.plugin.builder.mk`.
4. `service.plugin.builder.mk` includes `builder/ASN_VERSION`.

Because `builder/ASN_VERSION` is included after the service config, its `DEP_VERSION_ASN` value is the effective ASN Framework/runtime dependency for builder/package/runtime dependency paths under normal Make execution.

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
make build-prepare
make build-plugin
```

Exact target names may vary by service repository.

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
- Do not edit `builder/ASN_VERSION` from a service repo unless explicitly performing ASN Framework/runtime version maintenance.
- Do not run `update_service_utils` casually; it performs networked git operations and can move the submodule checkout.
- Do not publish packages, push images, or run deployment commands without explicit approval.
- Record the intended API, `service-utils`, framework/runtime, and service product version pairing for every release.
