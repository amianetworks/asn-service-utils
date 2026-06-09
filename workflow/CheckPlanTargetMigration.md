# Check And Plan Target Migration Guide

Status: reusable migration guide for ASN Framework and ASN Service repositories
Scope: repositories that include `service-utils/builder/service.plugin.builder.mk`
Audience: ASN Framework release engineers, service maintainers, DevOps, and coding agents

## Purpose

The refreshed `check*` and `plan*` design removes duplicate public targets and
uses one shared output model across services and ASN Framework.

Use this guide when migrating an ASN Framework or ASN Service repository to the
same target design used by SWAN.

The intended public surface is:

```text
make check
make check-vars
make plan-push
make plan-push-docker
make plan-push-debian
```

Do not keep compatibility aliases for removed targets. If an old command is
still referenced by docs, scripts, workflow contracts, or CI, update the caller.

## What Changed

Removed public targets:

| Removed target | Replacement |
|---|---|
| `check-init-vars` | `check-vars` for visibility; `init` owns the private-key gate. |
| `check-build-vars` | `check-vars` for visibility; `init` owns the private-key gate. |
| `check-push-vars` | `plan-push`, `plan-push-docker`, or `plan-push-debian`. |
| `check-release-config` | `plan-push`. |
| `check-release-config-strict` | `plan-push`. |
| `plan-push-preview` | Removed. Advisory topology without artifacts is not useful. |
| `plan-push-readiness` | `plan-push`. Strict readiness is the default. |

Kept shared lifecycle targets:

| Target | Why it remains |
|---|---|
| `check` | Canonical local readiness gate. |
| `check-vars` | Redacted inventory for build and publish variables. |
| `check-prepare` | Lifecycle bundle used by build and workflow recipes. |
| `check-version` | Identity row renderer used by `check`. |
| `check-build` | Build manifest row renderer used by `check`. |
| `check-go-mod` | Go module compatibility gate used by `check`. |
| `check-service-builder-base` | Builder base-image gate used by `check`. |
| `.check_build_vars` | Internal private-key gate used by `init`; not a user command. |

## Output Rules

Use plain section headers:

```text
>> Section Name
```

Use right-aligned rows:

```text
            Label : value
```

Use verdict suffixes only for gates:

```text
>> Section Name: [PASS]
>> Section Name: [FAIL]
```

Do not add `[INFO]`.

## Row Provider Model

The shared builder must not force service-only rows onto ASN Framework.

`check-version` and `check-build` are row renderers. A consuming repository can:

| Variable | Effect |
|---|---|
| `CHECK_VERSION_ROWS` | Replace all default `check-version` rows. |
| `CHECK_VERSION_EXTRA_ROWS` | Append rows to `check-version`. |
| `CHECK_BUILD_ROWS` | Replace all default `check-build` rows. |
| `CHECK_BUILD_EXTRA_ROWS` | Append rows to `check-build`. |
| `CHECK_LOCAL_EXTRA_TARGETS` | Append extra gates to `make check`. |
| `CHECK_PREPARE_EXTRA_TARGETS` | Append extra gates to `make check-prepare`. |

Supported placeholders:

| Placeholder | Meaning |
|---|---|
| `@SERVICE@` | Service display name. Empty for repos that do not define one. |
| `@VERSION_BUILD@` | Active build version. |
| `@ASN_SERVICE_API_VERSION@` | ASN Service API version implemented by a service. |
| `@ASN_VERSION@` | ASN Framework version. Falls back to `DEP_VERSION_ASN`. |
| `@DEP_VERSION_ASN@` | Framework dependency version consumed by a service. |
| `@GO_VERSION@` | Effective Go toolchain version. |
| `@DEP_VERSION_GO@` | Go version from builder metadata. |
| `@BUILD_MODE@` | Active build mode. |
| `@MANIFEST@` | Build manifest path. |
| `@BUILT_VERSION@` | Version currently recorded in the manifest. |
| `@NEXT_BUILD@` | Next local DEV build version. |

## ASN Framework Migration

ASN Framework has no service identity row. Its own version is the ASN version
that services consume as `DEP_VERSION_ASN`.

Set framework-owned rows near the framework build config:

```make
ASN_VERSION ?= $(VERSION)

define CHECK_VERSION_ROWS
ASN Framework=@ASN_VERSION@
Go Toolchain=@GO_VERSION@
endef
```

If the framework has additional readiness checks, append them without changing
the shared builder:

```make
CHECK_PREPARE_EXTRA_TARGETS += check-asn-framework-modules
CHECK_LOCAL_EXTRA_TARGETS += check-asn-framework-release-inputs
```

Expected framework output:

```text
>> Version Identity
  ASN Framework : 26.7.1
   Go Toolchain : 1.26.3
```

There is no `Service` row.

## ASN Service Migration

Most service repositories can keep the default service rows:

```text
Service=@SERVICE@
Version Build=@VERSION_BUILD@
ASN Service API=@ASN_SERVICE_API_VERSION@
ASN Framework=@DEP_VERSION_ASN@
Go Toolchain=@GO_VERSION@
```

Services can append product-specific rows:

```make
CHECK_VERSION_EXTRA_ROWS += Product Channel=@BUILD_MODE@
CHECK_BUILD_EXTRA_ROWS += Docs Version=@VERSION_BUILD@
```

Do not duplicate the API/framework/toolchain checks in service-owned recipes.
They already flow through `check-version`, `check-go-mod`, and
`check-service-builder-base`.

## Root Makefile Cleanup

Remove old targets from root help, guarded-goal lists, CI scripts, workflow
contracts, and operator docs:

```text
check-init-vars
check-build-vars
check-push-vars
check-release-config
check-release-config-strict
plan-push-preview
plan-push-readiness
```

Do not replace them with aliases.

Keep only the public commands users should run:

```text
check
check-vars
plan-push
plan-push-docker
plan-push-debian
```

## Init And Private Key Gate

`check-vars` is informational. It shows private-key status without printing the
path value when it is secret.

`init` should call the internal `.check_build_vars` helper before any operation
that needs `PRIVATE_GIT_SSH_KEY_FILE`.

Example:

```make
service-utils-init: .check_service_utils_version_file .check_build_vars update_service_utils
	@$(MAKE) --no-print-directory check-build
```

Do not expose `.check_build_vars` as a public user command.

## Publish Plan Migration

`plan-push` is now the strict no-upload publish readiness command.

It checks:

- private Git key;
- Docker and Debian site topology;
- selected credential variables without printing secrets;
- Docker login config when enabled;
- manifest lane identity;
- manifest-declared Docker and Debian artifact coordinates.

Lane-specific commands are still public:

```text
make plan-push-docker
make plan-push-debian
```

Do not reintroduce `plan-push-preview`.

## Validation Checklist

Run these after migration:

```bash
make help
make check-vars
make check-version
make check
make plan-push-docker
make plan-push-debian
```

Verify removed commands fail:

```bash
for target in \
  check-init-vars \
  check-build-vars \
  check-push-vars \
  check-release-config \
  check-release-config-strict \
  plan-push-preview \
  plan-push-readiness
do
  make "$target" && exit 1 || true
done
```

ASN Framework should also verify row replacement:

```bash
make check-version CHECK_VERSION_ROWS=$'ASN Framework=@ASN_VERSION@\nGo Toolchain=@GO_VERSION@'
```

Expected output contains `ASN Framework` and does not contain `Service`.

## Common Mistakes

- Keeping old aliases in the root Makefile. Remove callers instead.
- Adding `[INFO]` headers. Use plain `>> Section Name`.
- Left-aligning labels. Keep the shared right-aligned format.
- Treating `ASN_SERVICE_API_VERSION` and `DEP_VERSION_ASN` as the same value.
- Making ASN Framework inherit service rows.
- Reimplementing publish readiness in service-owned shell when `plan-push*`
  already owns it.
- Using `check-vars` as a failing gate. It is inventory; gates belong to `init`,
  `check`, and `plan-push*`.
