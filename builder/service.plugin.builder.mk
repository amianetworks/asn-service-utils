# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

#$(info service.plugin.builder.mk loaded)

# The following variables must be definded. (predefined in make/config.mk)
#ASN_SERVICE_API_VERSION
#BUILD_ENV_BASE_IMAGE
#BUILD_ENV_BASE_IMAGE_TAG
#BUILD_ENV_BASE_IMAGE_REF
#BUILD_ENV_BASE_DOCKERFILE
#BUILD_ENV_IMAGE
#BUILD_ENV_DOCKERFILE
#BUILD_ENV_ASN_VERSION_FILE
#PRIVATE_GIT_SSH_KEY_FILE
#SERVICE_UTILS_DIR

##----------------------------------------------------------------------------##
## Lifecycle targets.
##
## Services should expose these names directly. `build-all` is the only legacy
## spelling kept, and it is a plain alias for `build`.
build-all: build

## `push-all` is Make-only artifact publication. Release validation and handoff
## remain outside the generic builder and should consume the published outputs.
push-all: push-docker push-debian

##----------------------------------------------------------------------------##
## Main targets ##
## All dependent used below targets are defined in service.plugin.build.env.mk.

.PHONY: \
	service-utils-init \
	prepare \
	build \
	build-all \
	push-all \
	check \
	check-prepare \
	check-vars \
	check-build-vars \
	check-push-vars \
	check-build \
	check-version \
	go-test \
	code-cleanup \
	deps-tidy \
	deps-update \
	code-format \
	code-check \
	code-inspect \
	proto-tools \
	proto-tools-check \
	proto-gen \
	proto-gen-force \
	stage-docs \
	require-build-manifest \
	.build-manifest-require-lane \
	.build-manifest-value \
	check-go-mod \
	build-debian \
	clean-debian \
	check-debian-inputs \
	check-push-debian-sites \
	push-debian \
	push-debian-cn \
	push-debian-us \
	push-debian-% \
	list-debian \
	list-debian-local \
	list-debian-cn \
	list-debian-us \
	list-debian-% \
	build-docker \
	clean-docker \
	check-push-docker-sites \
	push-docker \
	push-docker-cn \
	push-docker-us \
	list-docker \
	list-docker-local \
	list-docker-cn \
	list-docker-us \
	service-build-plugin \
	service-build-debian \
	prepare-service-builder-base \
	check-service-builder-base \
	service-build-once \
	service-build-once-docker-run \
	service-build-once-docker-build \
	build.plugin \
	check.deb \
	build.deb \
	.require-version-build-var \
	.check_service_utils_version_file \
	.check_vars \
	.check_build_vars \
	.check_push_vars \
	.print-docker-push-var \
	.print-debian-push-var \
	.check-docker-push-var \
	.check-debian-push-var \
	.check-docker-publish-images \
	.check-debian-publish-packages \
	.check-docker-build-inputs \
	build-fresh \
	build-init \
	build-prepare \
	debian \
	docker

# Root Makefiles own public `init` so missing service-utils can be repaired
# before this shared builder is included. This target owns post-bootstrap checks.
service-utils-init: .check_service_utils_version_file check-build-vars update_service_utils
	@$(MAKE) --no-print-directory check-build

# Build identity and manifest mutation make these lifecycle targets serial.
.NOTPARALLEL: build build-plugin build-fresh build-debian build-docker

BUILD_MANIFEST_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/build_manifest.sh
BUILD_MANIFEST_ARGS ?=
BUILD_MANIFEST_LANE ?=
BUILD_MANIFEST_QUERY_FILE ?= $(BUILD_MANIFEST_FILE)
BUILD_MANIFEST_KEY ?=
BUILD_MANIFEST_COMMON_ARGS ?= --manifest "$(BUILD_MANIFEST_FILE)" --mode "$(BUILD_MODE)" --version "$(VERSION)" --build "$(BUILD)" --manager-build-dir "$(BUILD_SVC_C_DIR)" --servicenode-build-dir "$(BUILD_SVC_SN_DIR)" --client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" --docs-dir "$(CURDIR)/build/docs" --debian-dir "$(DEBIAN_PATH)" --debian-services "$(DEBIAN_SERVICES)" --docker-images "$(DOCKER_IMAGES)" $(BUILD_MANIFEST_ARGS)
# Build identity is shared builder state. If the caller did not pass
# VERSION_BUILD explicitly, expose the current manifest version only when it
# matches the selected build mode and service VERSION.
VERSION_BUILD ?= $(shell $(BUILD_MANIFEST_CMD) active-version-build $(BUILD_MANIFEST_COMMON_ARGS))
SERVICE_BUILD_MAKEFILE ?= Makefile
SERVICE_BUILD_PLUGIN_TARGET ?= build.plugin
SERVICE_BUILD_DEBIAN_TARGET ?= build.deb
SERVICE_BUILD_CHECK_DEBIAN_TARGET ?= check.deb
SERVICE_BUILD_CLEAN_DIRS ?=
SERVICE_BUILD_DIRS ?= $(SERVICE_BUILD_CLEAN_DIRS)
SERVICE_GO_BUILD_ARTIFACTS ?=
SERVICE_GO_BUILD_TARGETS := $(addprefix .service-go-build-,$(SERVICE_GO_BUILD_ARTIFACTS))
SERVICE_ARTIFACT_COPY_SPECS ?=
SERVICE_DEBIAN_REQUIRED_ARTIFACTS ?=
SERVICE_DEBIAN_PACKAGE_COPY_SPECS ?=
SERVICE_LOCAL_MAKE_TARGETS ?=
STAGE_DOCS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/stage_docs.sh
STAGE_DOCS_DIR ?= $(CURDIR)/build/docs
STAGE_DOCS_REPORT_FILE ?=
SERVICE_DOCS_SOURCE_KEY ?= source_commit
SERVICE_DOCS_SERVED_KEY ?= docs_served_by_manager
SERVICE_DOCS_RUNTIME_ROOT_KEY ?= docs_runtime_root
SERVICE_DOCS_RUNTIME_ROOT ?= /var/www/$(SERVICE_NAME)
SERVICE_DOCS_ROUTES ?= /docs/
SERVICE_DOCS_INDEX_LINKS ?=
SERVICE_DOCS_STAGE_COPY_SPECS ?=
SERVICE_DOCS_STAGE_REQUIRED_FILES ?=
SERVICE_DOCS_STAGE_REQUIRED_FILES_dev ?=
SERVICE_DOCS_STAGE_REQUIRED_FILES_pro ?=
SERVICE_DOCS_PACKAGE_CHANNEL_dev ?=
SERVICE_DOCS_PACKAGE_CHANNEL_pro ?=
SERVICE_DOCS_DOCKER_IMAGE_INTENT_dev ?=
SERVICE_DOCS_DOCKER_IMAGE_INTENT_pro ?=
SERVICE_DOCS_DOCUMENTATION_CHANNEL_dev ?=
SERVICE_DOCS_DOCUMENTATION_CHANNEL_pro ?=
SERVICE_DOCS_ROLLBACK_REQUIREMENT_dev ?=
SERVICE_DOCS_ROLLBACK_REQUIREMENT_pro ?=

.PHONY: $(SERVICE_GO_BUILD_TARGETS)

define service_local_make_target
.PHONY: $(1)
$(1):
	@if [ -z "$(strip $(SERVICE_LOCAL_MAKE_DIR_$(1)))" ]; then \
		echo "ERROR: SERVICE_LOCAL_MAKE_DIR_$(1) is required."; \
		exit 2; \
	fi
	@$$(MAKE) --no-print-directory -C "$(strip $(SERVICE_LOCAL_MAKE_DIR_$(1)))" $(if $(strip $(SERVICE_LOCAL_MAKE_GOAL_$(1))),$(strip $(SERVICE_LOCAL_MAKE_GOAL_$(1))),$(1)) $(SERVICE_LOCAL_MAKE_ARGS_$(1))
endef
$(foreach target,$(SERVICE_LOCAL_MAKE_TARGETS),$(eval $(call service_local_make_target,$(target))))

# Build the required builder base image. Run this on a fresh build host or when
# builder/toolchain/dependency inputs change.
prepare: .check_service_utils_version_file prepare-service-builder-base
	@echo "Successfully built base image."
	@echo

check: check-build-vars check-prepare
	@echo "Local project check passed."

check-prepare: check-build check-service-builder-base

build: prepare build-plugin $(BUILD_EXTRA_TARGETS) build-debian build-docker

build-fresh: clean prepare build-plugin $(BUILD_EXTRA_TARGETS) build-debian build-docker
	@echo "Built fresh artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

build-plugin: check proto-gen
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) reserve-plugin-version \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_NUM_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		$(BUILD_MANIFEST_ARGS))"; \
	echo ">> Build Plugin Version"; \
	printf "  %15s : %s\n" "Version" "$$version_build"; \
	make --no-print-directory service-build-plugin VERSION_BUILD="$$version_build"; \
	if service_utils_ref="$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD 2>&1)"; then \
		:; \
	else \
		echo "WARN: could not resolve service-utils git ref: $$service_utils_ref" >&2; \
		service_utils_ref="unknown"; \
	fi; \
	$(BUILD_MANIFEST_CMD) commit-plugin \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_NUM_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--version-build "$$version_build" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
		--dep-version-asn "$(DEP_VERSION_ASN)" \
		--service-utils-ref "$$service_utils_ref" \
		$(BUILD_MANIFEST_ARGS)
	@echo "Built artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

# Any artifacts should be under build/. Cleaning is simple.
clean:
	@rm -rf build/

##----------------------------------------------------------------------------##
## Variable checks ##

.check_vars:
	@echo ">> Variable Inventory"; \
	echo "Secret values are redacted. This inventory is informational; run check-build-vars or check-push-vars for failing gates."; \
	echo ""; \
	printf "%-44s %-11s %-7s %s\n" "Variable" "Status" "Secret" "Used by"; \
	printf "%-44s %-11s %-7s %s\n" "--------" "------" "------" "-------"; \
	private_key="$${PRIVATE_GIT_SSH_KEY_FILE:-}"; \
	if [ -z "$$private_key" ]; then status="MISSING"; elif [ ! -r "$$private_key" ]; then status="UNREADABLE"; else status="SET"; fi; \
	printf "%-44s %-11s %-7s %s\n" "PRIVATE_GIT_SSH_KEY_FILE" "$$status" "yes" "check-build-vars, make init, make check"; \
	if [ -z "$(strip $(DOCKER_REGISTRY_SITES))" ]; then status="MISSING"; else status="SET"; fi; \
	printf "%-44s %-11s %-7s %s\n" "DOCKER_REGISTRY_SITES" "$$status" "no" "check-push-vars, push-docker"; \
	if [ -z "$(strip $(DEBIAN_REPO_SITES))" ]; then status="MISSING"; else status="SET"; fi; \
	printf "%-44s %-11s %-7s %s\n" "DEBIAN_REPO_SITES" "$$status" "no" "check-push-vars, push-debian"
	@for site in $(DOCKER_REGISTRY_SITES); do \
		$(MAKE) -s .print-docker-push-var SITE=$$site; \
	done
	@for site in $(DEBIAN_REPO_SITES); do \
		$(MAKE) -s .print-debian-push-var SITE=$$site; \
	done
	@echo ""; \
	echo "Variable inventory completed without printing secret values."; \
	echo "Run 'make check-build-vars' for the local build/init gate."; \
	echo "Run 'make check-push-vars' for selected Docker/Debian publish credentials."

.print-docker-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DOCKER)
	$(eval VAR_REGISTRY := $(DOCKER_REGISTRY_$(VAR_SITE)))
	@status="SET"; [ -n "$(VAR_REGISTRY)" ] || status="MISSING"; \
	printf "%-44s %-11s %-7s %s\n" "DOCKER_REGISTRY_$(VAR_SITE)" "$$status" "no" "push-docker-$(shell echo $(VAR_SITE) | tr A-Z a-z)"
	@status="SET"; [ -n "$(VAR_PROFILE)" ] || status="MISSING"; \
	printf "%-44s %-11s %-7s %s\n" "RELEASE_SECRET_PROFILE_$(VAR_SITE)" "$$status" "no" "$(VAR_AUTH_VAR)"
	@status="SET"; \
	effective_var="DOCKER_REGISTRY_$(VAR_SITE)_USER"; \
	effective_value="$${!effective_var:-}"; \
	if [ -z "$$effective_value" ]; then status="MISSING"; elif ! printf '%s' "$$effective_value" | grep -q ':'; then status="INVALID"; fi; \
	printf "%-44s %-11s %-7s %s\n" "$(VAR_AUTH_VAR)" "$$status" "yes" "DOCKER_REGISTRY_$(VAR_SITE)_USER, push-docker-$(shell echo $(VAR_SITE) | tr A-Z a-z)"

.print-debian-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DEBIAN)
	$(eval VAR_HOST := $(DEBIAN_REPO_HOST_$(VAR_SITE)))
	@status="SET"; [ -n "$(VAR_HOST)" ] || status="MISSING"; \
	printf "%-44s %-11s %-7s %s\n" "DEBIAN_REPO_HOST_$(VAR_SITE)" "$$status" "no" "push-debian-$(shell echo $(VAR_SITE) | tr A-Z a-z)"
	@status="SET"; [ -n "$(VAR_PROFILE)" ] || status="MISSING"; \
	printf "%-44s %-11s %-7s %s\n" "RELEASE_SECRET_PROFILE_$(VAR_SITE)" "$$status" "no" "$(VAR_AUTH_VAR)"
	@status="SET"; \
	effective_var="DEBIAN_REPO_USER_$(VAR_SITE)"; \
	effective_value="$${!effective_var:-}"; \
	if [ -z "$$effective_value" ]; then status="MISSING"; elif ! printf '%s' "$$effective_value" | grep -q ':'; then status="INVALID"; fi; \
	printf "%-44s %-11s %-7s %s\n" "$(VAR_AUTH_VAR)" "$$status" "yes" "DEBIAN_REPO_USER_$(VAR_SITE), push-debian-$(shell echo $(VAR_SITE) | tr A-Z a-z)"

.check_build_vars:
	@failed=0; \
	check_file_var() { \
		name="$$1"; value="$$2"; required="$$3"; secret="$$4"; \
		display="$$value"; \
		if [ "$$secret" = "yes" ] && [ -n "$$value" ]; then display="<set>"; fi; \
		if [ -z "$$value" ]; then \
			display="<empty>"; \
			if [ "$$required" = "yes" ]; then failed=1; fi; \
		elif [ ! -r "$$value" ]; then \
			display="$$display (unreadable)"; \
			failed=1; \
		fi; \
		printf "  %24s : %s\n" "$$name" "$$display"; \
	}; \
	echo ">> Build Variable Check"; \
	check_file_var "PRIVATE_GIT_SSH_KEY_FILE" "$${PRIVATE_GIT_SSH_KEY_FILE:-}" "yes" "yes"; \
	if [ "$$failed" -ne 0 ]; then \
		echo ""; \
		echo "Build variable check failed. Set PRIVATE_GIT_SSH_KEY_FILE to a readable private Git SSH key using one of the methods below."; \
		echo ""; \
		echo "Private Git SSH key file"; \
		echo "  Method 1: export it from ignored make/local.mk:"; \
		echo "    export PRIVATE_GIT_SSH_KEY_FILE := /path/to/private_git_key"; \
		echo "  Method 2: export it from ~/.zshrc or ~/.bashrc:"; \
		echo "    export PRIVATE_GIT_SSH_KEY_FILE=/path/to/private_git_key"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "Build variable check passed."; \
	echo "Run 'make check-vars' for the full redacted variable inventory."

.check_push_vars:
	@echo ">> Publish Variable Check"; \
	echo "Secret values are redacted."; \
	if [ -z "$(strip $(DOCKER_REGISTRY_SITES))" ]; then \
		echo "ERROR: DOCKER_REGISTRY_SITES is empty."; \
		exit 1; \
	fi; \
	if [ -z "$(strip $(DEBIAN_REPO_SITES))" ]; then \
		echo "ERROR: DEBIAN_REPO_SITES is empty."; \
		exit 1; \
	fi
	@for site in $(DOCKER_REGISTRY_SITES); do \
		$(MAKE) -s .check-docker-push-var SITE=$$site; \
	done
	@for site in $(DEBIAN_REPO_SITES); do \
		$(MAKE) -s .check-debian-push-var SITE=$$site; \
	done
	@echo ""; \
	echo "Publish variable check passed without printing secret values."

.check-docker-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DOCKER)
	$(eval VAR_REGISTRY := $(DOCKER_REGISTRY_$(VAR_SITE)))
	@if [ -z "$(VAR_REGISTRY)" ]; then \
		echo "ERROR: Docker registry $(VAR_SITE) is not configured."; \
		echo "Required: DOCKER_REGISTRY_$(VAR_SITE)."; \
		exit 1; \
	fi
	@effective_var="DOCKER_REGISTRY_$(VAR_SITE)_USER"; \
	effective_value="$${!effective_var:-}"; \
	if [ -z "$$effective_value" ]; then \
		echo "ERROR: Docker credential for $(VAR_SITE) is not configured."; \
		echo "Required: $(VAR_AUTH_VAR) (exported as DOCKER_REGISTRY_$(VAR_SITE)_USER)."; \
		exit 1; \
	fi
	@effective_var="DOCKER_REGISTRY_$(VAR_SITE)_USER"; \
	effective_value="$${!effective_var:-}"; \
	if ! printf '%s' "$$effective_value" | grep -q ':'; then \
		echo "ERROR: Docker credential for $(VAR_SITE) must use user:password format."; \
		echo "Fix: $(VAR_AUTH_VAR)."; \
		exit 1; \
	fi
	@printf "  %-24s : %s\n" "Docker $(VAR_SITE)" "credential set ($(VAR_AUTH_VAR))"

.check-debian-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DEBIAN)
	$(eval VAR_HOST := $(DEBIAN_REPO_HOST_$(VAR_SITE)))
	@if [ -z "$(VAR_HOST)" ]; then \
		echo "ERROR: Debian repo $(VAR_SITE) is not configured."; \
		echo "Required: DEBIAN_REPO_HOST_$(VAR_SITE)."; \
		exit 1; \
	fi
	@effective_var="DEBIAN_REPO_USER_$(VAR_SITE)"; \
	effective_value="$${!effective_var:-}"; \
	if [ -z "$$effective_value" ]; then \
		echo "ERROR: Debian credential for $(VAR_SITE) is not configured."; \
		echo "Required: $(VAR_AUTH_VAR) (exported as DEBIAN_REPO_USER_$(VAR_SITE))."; \
		exit 1; \
	fi
	@effective_var="DEBIAN_REPO_USER_$(VAR_SITE)"; \
	effective_value="$${!effective_var:-}"; \
	if ! printf '%s' "$$effective_value" | grep -q ':'; then \
		echo "ERROR: Debian credential for $(VAR_SITE) must use user:password format."; \
		echo "Fix: $(VAR_AUTH_VAR)."; \
		exit 1; \
	fi
	@printf "  %-24s : %s\n" "Debian $(VAR_SITE)" "credential set ($(VAR_AUTH_VAR))"

check-vars: .check_vars

check-build-vars: .check_build_vars

check-push-vars: .check_push_vars


check-build:
	@$(BUILD_MANIFEST_CMD) check-build \
		--service "$(SERVICE)" \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_NUM_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
		$(BUILD_MANIFEST_ARGS)
	@echo ""
	@$(MAKE) --no-print-directory check-go-mod

check-version: check-build

check-go-mod:
	@failed=0; compared=0; skipped=0; \
	root_requires=$$(mktemp); utils_requires=$$(mktemp); \
	if [ ! -f go.mod ]; then \
		echo ">> go.mod Conflict Check: [FAIL]"; \
		echo "            Missing root go.mod."; \
		rm -f "$$root_requires" "$$utils_requires"; \
		exit 1; \
	fi; \
	if [ ! -f "$(SERVICE_UTILS_DIR)/go.mod" ]; then \
		echo ">> go.mod Conflict Check: [FAIL]"; \
		echo "            Missing $(SERVICE_UTILS_DIR)/go.mod."; \
		rm -f "$$root_requires" "$$utils_requires"; \
		exit 1; \
	fi; \
	extract_requires() { \
		awk ' \
			$$1 == "require" && NF >= 3 { print $$2, $$3; next } \
			$$1 == "require" && $$2 == "(" { in_require = 1; next } \
			in_require && $$1 == ")" { in_require = 0; next } \
			in_require && NF >= 2 && $$1 !~ /^\/\// { print $$1, $$2 } \
		' "$$1" | sort; \
	}; \
	extract_requires go.mod > "$$root_requires"; \
	extract_requires $(SERVICE_UTILS_DIR)/go.mod > "$$utils_requires"; \
	while read -r module expected; do \
		[ -z "$$module" ] && continue; \
		actual=$$(awk -v module="$$module" '$$1 == module { print $$2; exit }' "$$root_requires"); \
		if [ -z "$$actual" ]; then \
			skipped=$$(expr $$skipped + 1); \
		elif [ "$$actual" != "$$expected" ]; then \
			compared=$$(expr $$compared + 1); \
			printf "            %-48s Root: %s, service-utils: %s. FAIL\n" "$$module" "$$actual" "$$expected"; \
			failed=1; \
		else \
			compared=$$(expr $$compared + 1); \
		fi; \
	done < "$$utils_requires"; \
	rm -f "$$root_requires" "$$utils_requires"; \
	if [ "$$failed" -ne 0 ]; then \
		echo ""; \
		echo ">> go.mod Conflict Check: [FAIL]"; \
		echo "            Shared package versions must match between root go.mod and service-utils/go.mod."; \
		exit 1; \
	fi; \
	echo ">> go.mod Conflict Check: [PASS]"; \
	printf "  %15s : %s matched\n" "Shared Packages" "$$compared"; \
	printf "  %15s : %s ignored\n" "Utils-only Mods" "$$skipped"
	@echo ""

##----------------------------------------------------------------------------##
## Source maintenance ##
##
## Consuming services may override package/path/tool variables in their own
## config, while service-utils owns the reusable Go source-maintenance recipes.

GOCACHE ?= $(CURDIR)/.cache/go-build
export GOCACHE
GO_TEST_FLAGS ?=
SERVICE_GO_CHECK_PACKAGES ?= ./...
SERVICE_GO_FORMAT_PACKAGES ?= ./...
SERVICE_GOIMPORTS_PATHS ?= .
SERVICE_GOIMPORTS_LOCAL ?= $(PACKAGE)
SERVICE_GOIMPORTS ?= goimports
SERVICE_ERRCHECK ?= errcheck
SERVICE_STATICCHECK ?= go run honnef.co/go/tools/cmd/staticcheck@v0.6.1
SERVICE_GOLANGCI_LINT ?= go run github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.8

go-test:
	@if [ -z "$(PKG)" ]; then \
		echo "ERROR: set PKG=./path/to/package for targeted Go validation."; \
		exit 2; \
	fi
	go test $(GO_TEST_FLAGS) $(PKG)

code-cleanup: deps-tidy code-format code-check

deps-tidy:
	@echo "running [go mod tidy]"
	@go mod tidy
	@echo "deps-tidy completed"

deps-update:
	@echo "WARNING: deps-update performs broad dependency upgrades with go get -u."
	@echo "Run only with explicit approval."
	@echo "running [go mod tidy]"
	@go mod tidy
	@echo "running [go get -u]"
	@go get -u
	@echo "running [go mod tidy]"
	@go mod tidy
	@echo "deps-update completed"

code-format:
	@set -e; \
	goimports_args=(); \
	if [ -n "$(strip $(SERVICE_GOIMPORTS_LOCAL))" ]; then goimports_args=(-local "$(SERVICE_GOIMPORTS_LOCAL)"); fi; \
	$(SERVICE_GOIMPORTS) -w "$${goimports_args[@]}" $(SERVICE_GOIMPORTS_PATHS); \
	go fmt $(SERVICE_GO_FORMAT_PACKAGES)
	@echo "code-format completed"

code-check:
	$(SERVICE_ERRCHECK) $(SERVICE_GO_CHECK_PACKAGES)
	go vet $(SERVICE_GO_CHECK_PACKAGES)
	$(SERVICE_STATICCHECK) $(SERVICE_GO_CHECK_PACKAGES)
	$(SERVICE_GOLANGCI_LINT) run
	@echo "code-check completed"

code-inspect: code-format code-check
	@echo "code-inspect completed"

##----------------------------------------------------------------------------##
## Protobuf generation ##
##
## Consuming services own PROTO_GEN_SPECS and PROTO_GEN_STATE_FILES. The shared
## builder owns the pinned tool staging, version checks, incremental stamp, and
## generation loop. Each PROTO_GEN_SPECS item is source-glob:generated-output-dir,
## where the output dir is relative to PROTO_OUT.

PROTOC_VERSION ?= libprotoc 34.1
PROTOC_RELEASE_VERSION ?= $(lastword $(PROTOC_VERSION))
PROTOC_GEN_GO_VERSION ?= v1.36.11
PROTOC_GEN_GO_GRPC_VERSION ?= v1.6.0
PROTO_TOOLS_DIR ?= .cache/proto-tools
PROTO_TOOLS_BIN := $(abspath $(PROTO_TOOLS_DIR)/bin)
PROTOC_LOCAL := $(PROTO_TOOLS_BIN)/protoc
PROTOC_RELEASE_DIR := $(abspath $(PROTO_TOOLS_DIR)/protoc-$(PROTOC_RELEASE_VERSION))
PROTOC_INCLUDE := $(PROTOC_RELEASE_DIR)/include
PROTOC_DOWNLOAD_BASE_URL ?= https://github.com/protocolbuffers/protobuf/releases/download/v$(PROTOC_RELEASE_VERSION)
PROTOC_AUTO_DOWNLOAD ?= 1
PROTO_OUT ?= .
PROTO_GEN_ENV := PATH="$(PROTO_TOOLS_BIN):$$PATH"
PROTO_GEN_STAMP ?= $(PROTO_TOOLS_DIR)/proto-gen.stamp
PROTO_GEN_FORCE ?= 0
PROTO_GEN_DEFAULT_OUT := $(abspath .)
PROTO_GEN_SPECS ?=
PROTO_GEN_STATE_FILES ?= $(PROTO_GEN_SPECS)
PROTOC_DEFAULTED := $(if $(filter undefined,$(origin PROTOC)),1,0)
PROTOC ?= $(PROTOC_LOCAL)

proto-tools:
	@set -e; \
	mkdir -p "$(PROTO_TOOLS_BIN)"; \
	protoc_platform() { \
		os="$$(uname -s)"; arch="$$(uname -m)"; \
		case "$$os/$$arch" in \
			Darwin/arm64) echo osx-aarch_64 ;; \
			Darwin/x86_64) echo osx-x86_64 ;; \
			Linux/x86_64) echo linux-x86_64 ;; \
			*) echo "ERROR: unsupported protoc platform $$os/$$arch. Install protoc $(PROTOC_VERSION) and set PROTOC=/path/to/protoc." >&2; exit 1 ;; \
		esac; \
	}; \
	stage_protoc_tree() { \
		tree="$$1"; source="$$2"; \
		[ -x "$$tree/bin/protoc" ] || return 1; \
		actual="$$("$$tree/bin/protoc" --version 2>&1 || true)"; \
		[ "$$actual" = "$(PROTOC_VERSION)" ] || return 1; \
		cp "$$tree/bin/protoc" "$(PROTOC_LOCAL)"; \
		chmod +x "$(PROTOC_LOCAL)"; \
		if [ -d "$$tree/include" ]; then \
			rm -rf "$(PROTOC_INCLUDE)"; \
			mkdir -p "$(PROTOC_RELEASE_DIR)"; \
			cp -R "$$tree/include" "$(PROTOC_INCLUDE)"; \
		fi; \
		echo "protoc $(PROTOC_VERSION) staged from $$source"; \
		return 0; \
	}; \
	stage_host_protoc() { \
		host_bin="$$1"; host_prefix="$$2"; source="$$3"; \
		[ -x "$$host_bin" ] || return 1; \
		actual="$$("$$host_bin" --version 2>&1 || true)"; \
		[ "$$actual" = "$(PROTOC_VERSION)" ] || return 1; \
		printf '%s\n' '#!/bin/sh' "exec \"$$host_bin\" \"\$$@\"" > "$(PROTOC_LOCAL)"; \
		chmod +x "$(PROTOC_LOCAL)"; \
		if [ -n "$$host_prefix" ] && [ -d "$$host_prefix/include" ]; then \
			rm -rf "$(PROTOC_INCLUDE)"; \
			mkdir -p "$(PROTOC_RELEASE_DIR)"; \
			cp -R "$$host_prefix/include" "$(PROTOC_INCLUDE)"; \
		fi; \
		echo "protoc $(PROTOC_VERSION) staged from $$source"; \
		return 0; \
	}; \
	ensure_protoc() { \
		if [ -x "$(PROTOC_LOCAL)" ] && [ "$$("$(PROTOC_LOCAL)" --version 2>&1 || true)" = "$(PROTOC_VERSION)" ]; then \
			echo "protoc $(PROTOC_VERSION) already staged"; \
			return 0; \
		fi; \
		host_protoc="$$(command -v protoc || true)"; \
		if [ -n "$$host_protoc" ] && [ "$$(protoc --version 2>&1 || true)" = "$(PROTOC_VERSION)" ]; then \
			host_prefix="$$(cd "$$(dirname "$$host_protoc")/.." && pwd -P || true)"; \
			stage_host_protoc "$$host_protoc" "$$host_prefix" PATH; \
			return 0; \
		fi; \
		if [ "$(PROTOC_AUTO_DOWNLOAD)" != "1" ]; then \
			echo "ERROR: protoc $(PROTOC_VERSION) is not staged and PATH does not provide a matching protoc." >&2; \
			echo "Run make proto-tools with network access, install protoc $(PROTOC_VERSION), or set PROTOC=/path/to/protoc." >&2; \
			exit 1; \
		fi; \
		command -v curl >/dev/null || { echo "ERROR: curl is required to download protoc $(PROTOC_VERSION)." >&2; exit 1; }; \
		command -v unzip >/dev/null || { echo "ERROR: unzip is required to unpack protoc $(PROTOC_VERSION)." >&2; exit 1; }; \
		platform="$$(protoc_platform)"; \
		cache_dir="$(PROTOC_RELEASE_DIR)/$$platform"; \
		if stage_protoc_tree "$$cache_dir" "download cache"; then \
			return 0; \
		fi; \
		archive="$$(mktemp "$${TMPDIR:-/tmp}/protoc-$(PROTOC_RELEASE_VERSION).XXXXXX.zip")"; \
		url="$(PROTOC_DOWNLOAD_BASE_URL)/protoc-$(PROTOC_RELEASE_VERSION)-$$platform.zip"; \
		echo "downloading protoc $(PROTOC_VERSION) from $$url"; \
		curl -fsSL "$$url" -o "$$archive"; \
		rm -rf "$$cache_dir"; \
		mkdir -p "$$cache_dir"; \
		unzip -q "$$archive" -d "$$cache_dir"; \
		rm -f "$$archive"; \
		stage_protoc_tree "$$cache_dir" "download"; \
	}; \
	ensure_tool() { \
		name="$$1"; module="$$2"; want="$$3"; pattern="$$4"; \
		target="$(PROTO_TOOLS_BIN)/$$name"; \
		if [ -x "$$target" ] && "$$target" --version 2>&1 | grep -Eq "$$pattern"; then \
			echo "$$name $$want already staged"; \
			return 0; \
		fi; \
		if command -v "$$name" >/dev/null && "$$name" --version 2>&1 | grep -Eq "$$pattern"; then \
			cp "$$(command -v "$$name")" "$$target"; \
			chmod +x "$$target"; \
			echo "$$name $$want staged from PATH"; \
			return 0; \
		fi; \
		echo "installing $$name $$want into $(PROTO_TOOLS_BIN)"; \
		GOBIN="$(PROTO_TOOLS_BIN)" go install "$$module@$$want"; \
		"$$target" --version 2>&1 | grep -Eq "$$pattern"; \
	}; \
	if [ "$(PROTOC_DEFAULTED)" = "1" ]; then \
		ensure_protoc; \
	else \
		echo "protoc override selected: $(PROTOC)"; \
	fi; \
	ensure_tool protoc-gen-go google.golang.org/protobuf/cmd/protoc-gen-go "$(PROTOC_GEN_GO_VERSION)" "protoc-gen-go $(PROTOC_GEN_GO_VERSION)$$"; \
	ensure_tool protoc-gen-go-grpc google.golang.org/grpc/cmd/protoc-gen-go-grpc "$(PROTOC_GEN_GO_GRPC_VERSION)" "protoc-gen-go-grpc $(patsubst v%,%,$(PROTOC_GEN_GO_GRPC_VERSION))$$"

proto-tools-check: proto-tools
	@set -e; \
	actual="$$($(PROTOC) --version)"; \
	if [ "$$actual" != "$(PROTOC_VERSION)" ]; then \
		echo "ERROR: $(PROTOC) version mismatch: got '$$actual', want '$(PROTOC_VERSION)'."; \
		echo "Install protoc $(PROTOC_VERSION) or override PROTOC_VERSION only after regenerating and reviewing protobuf output."; \
		exit 1; \
	fi; \
	$(PROTO_GEN_ENV) protoc-gen-go --version | grep -Eq "protoc-gen-go $(PROTOC_GEN_GO_VERSION)$$"; \
	$(PROTO_GEN_ENV) protoc-gen-go-grpc --version | grep -Eq "protoc-gen-go-grpc $(patsubst v%,%,$(PROTOC_GEN_GO_GRPC_VERSION))$$"; \
	echo "protobuf toolchain check passed"

proto-gen:
	@if [ -z "$(strip $(PROTO_GEN_SPECS))" ]; then \
		echo "ERROR: PROTO_GEN_SPECS is empty."; \
		exit 1; \
	fi
	@set -e; \
	default_out=0; \
	if [ "$(abspath $(PROTO_OUT))" = "$(PROTO_GEN_DEFAULT_OUT)" ]; then default_out=1; fi; \
	proto_state_hash() { \
		{ \
			printf 'PROTOC_VERSION=%s\n' "$(PROTOC_VERSION)"; \
			printf 'PROTOC_GEN_GO_VERSION=%s\n' "$(PROTOC_GEN_GO_VERSION)"; \
			printf 'PROTOC_GEN_GO_GRPC_VERSION=%s\n' "$(PROTOC_GEN_GO_GRPC_VERSION)"; \
			printf 'PROTO_GEN_SPECS=%s\n' "$(PROTO_GEN_SPECS)"; \
			for file in $(PROTO_GEN_STATE_FILES); do \
				[ -e "$$file" ] || continue; \
				printf 'file:%s\n' "$$file"; \
				shasum -a 256 "$$file"; \
			done; \
		} | shasum -a 256 | awk '{ print $$1 }'; \
	}; \
	if [ "$$default_out" = "1" ] && [ "$(PROTO_GEN_FORCE)" != "1" ] && [ -f "$(PROTO_GEN_STAMP)" ]; then \
		current="$$(proto_state_hash)"; \
		previous="$$(cat "$(PROTO_GEN_STAMP)")"; \
		if [ "$$current" = "$$previous" ]; then \
			echo "proto-gen skipped; generated protobuf output is current."; \
			exit 0; \
		fi; \
	fi; \
	$(MAKE) --no-print-directory proto-tools-check; \
	mkdir -p "$(PROTO_OUT)"; \
	for spec in $(PROTO_GEN_SPECS); do \
		proto_sources="$${spec%%:*}"; \
		generated_dir="$${spec#*:}"; \
		if [ "$$proto_sources" = "$$spec" ] || [ -z "$$generated_dir" ]; then \
			echo "ERROR: invalid PROTO_GEN_SPECS item '$$spec'; expected source-glob:generated-output-dir." >&2; \
			exit 1; \
		fi; \
		include_args="-I ."; [ -d "$(PROTOC_INCLUDE)" ] && include_args="$$include_args -I $(PROTOC_INCLUDE)"; \
		$(PROTO_GEN_ENV) $(PROTOC) $$include_args --go_out="$(PROTO_OUT)" --go_opt=paths=source_relative --go-grpc_out=require_unimplemented_servers=false:"$(PROTO_OUT)" --go-grpc_opt=paths=source_relative $$proto_sources; \
		if [ -d "$(PROTO_OUT)/$$generated_dir" ]; then \
			find "$(PROTO_OUT)/$$generated_dir" -name '*.pb.go' -exec gofmt -w {} +; \
		fi; \
	done; \
	if [ "$$default_out" = "1" ]; then \
		mkdir -p "$$(dirname "$(PROTO_GEN_STAMP)")"; \
		proto_state_hash > "$(PROTO_GEN_STAMP)"; \
	fi; \
	echo "proto-gen completed"

proto-gen-force: PROTO_GEN_FORCE=1
proto-gen-force: proto-gen

##----------------------------------------------------------------------------##
## Service-served documentation staging.
##
## Services declare docs content through SERVICE_DOCS_* variables; the shared
## target handles staging, release manifest metadata, checksums, and validation.
stage-docs:
	@set -e; \
	commit_manifest="$(if $(filter undefined,$(origin STAGE_DOCS_COMMIT_MANIFEST)),yes,$(STAGE_DOCS_COMMIT_MANIFEST))"; \
	version_build="$(STAGE_DOCS_VERSION_BUILD)"; \
	required_files="$(SERVICE_DOCS_STAGE_REQUIRED_FILES) $(SERVICE_DOCS_STAGE_REQUIRED_FILES_$(BUILD_MODE))"; \
	manifest_args=( \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(STAGE_DOCS_DIR)" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		$(BUILD_MANIFEST_ARGS) \
		--docs-required-artifacts "$(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml $(STAGE_DOCS_DIR)/release/DocsChecksums.tsv $(STAGE_DOCS_DIR)/index.html" \
		--docs-version-file "$(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml" \
		--docs-version-key "$(SERVICE_DOCS_VERSION_KEY)" \
	); \
	if [ "$$commit_manifest" = "yes" ]; then \
		version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane plugin "$${manifest_args[@]}")"; \
	fi; \
	report_args=(); \
	version_args=(); \
	if [ -n "$(STAGE_DOCS_REPORT_FILE)" ]; then report_args=(--report-file "$(STAGE_DOCS_REPORT_FILE)"); fi; \
	if [ -n "$$version_build" ]; then version_args=(--version-build "$$version_build"); fi; \
	$(STAGE_DOCS_CMD) \
		--mode "$(BUILD_MODE)" \
		"$${version_args[@]}" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--stage-dir "$(STAGE_DOCS_DIR)" \
		"$${report_args[@]}" \
		--service-name "$(SERVICE_NAME)" \
		--service-title "$(SERVICE)" \
		--version-key "$(SERVICE_DOCS_VERSION_KEY)" \
		--version-label "$(SERVICE_DOCS_VERSION_LABEL)" \
		--source-key "$(SERVICE_DOCS_SOURCE_KEY)" \
		--served-key "$(SERVICE_DOCS_SERVED_KEY)" \
		--runtime-root-key "$(SERVICE_DOCS_RUNTIME_ROOT_KEY)" \
		--runtime-root "$(SERVICE_DOCS_RUNTIME_ROOT)" \
		--copy-specs "$(SERVICE_DOCS_STAGE_COPY_SPECS)" \
		--index-links "$(SERVICE_DOCS_INDEX_LINKS)" \
		--routes "$(SERVICE_DOCS_ROUTES)" \
		--required-files "$$required_files" \
		--package-channel "$(SERVICE_DOCS_PACKAGE_CHANNEL_$(BUILD_MODE))" \
		--docker-image-intent "$(SERVICE_DOCS_DOCKER_IMAGE_INTENT_$(BUILD_MODE))" \
		--documentation-channel "$(SERVICE_DOCS_DOCUMENTATION_CHANNEL_$(BUILD_MODE))" \
		--rollback-requirement "$(SERVICE_DOCS_ROLLBACK_REQUIREMENT_$(BUILD_MODE))"; \
	if [ "$$commit_manifest" = "yes" ]; then \
		$(BUILD_MANIFEST_CMD) commit-lane --lane docs --version-build "$$version_build" "$${manifest_args[@]}"; \
	fi

set-version: check-build
	@echo "Modify config.mk to update the version and build."
	@echo "NOTE: Only CI/CD or maintainer should change the version with caution."

increment-build:
	@echo "ERROR: make increment-build has been removed."
	@echo "build-plugin now commits $(DEV_BUILD_FILE) only after plugin artifacts build successfully."
	@exit 2

##----------------------------------------------------------------------------##
## Debian Package handling ##

uppercase = $(shell echo $(1) | tr a-z A-Z)

require-build-manifest:
	@version_build="$$($(BUILD_MANIFEST_CMD) require-lane \
		--lane plugin \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		$(BUILD_MANIFEST_ARGS))"; \
	: "$$version_build"

.build-manifest-require-lane:
	@if [ -z "$(BUILD_MANIFEST_LANE)" ]; then \
		echo "ERROR: set BUILD_MANIFEST_LANE=plugin|docs|debian|docker."; \
		exit 2; \
	fi
	@$(BUILD_MANIFEST_CMD) require-lane --lane "$(BUILD_MANIFEST_LANE)" $(BUILD_MANIFEST_COMMON_ARGS)

.build-manifest-value:
	@if [ -z "$(BUILD_MANIFEST_KEY)" ]; then \
		echo "ERROR: set BUILD_MANIFEST_KEY=<manifest key>."; \
		exit 2; \
	fi
	@$(BUILD_MANIFEST_CMD) value --manifest "$(BUILD_MANIFEST_QUERY_FILE)" --key "$(BUILD_MANIFEST_KEY)" $(BUILD_MANIFEST_ARGS)

DEBIAN_BUILD_PRE_TARGETS ?=

# Build Debian packages from existing plugin artifacts.
build-debian: require-build-manifest check $(DEBIAN_BUILD_PRE_TARGETS) check-debian-inputs clean-debian
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane \
		--lane docs \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		$(BUILD_MANIFEST_ARGS))"; \
	make --no-print-directory service-build-debian VERSION_BUILD="$$version_build"; \
	$(BUILD_MANIFEST_CMD) commit-lane \
		--lane debian \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--version-build "$$version_build" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		$(BUILD_MANIFEST_ARGS)
	@echo "Built Debian packages (DIR):"
	@if [ -d "$(DEBIAN_PATH)" ]; then find ./$(DEBIAN_PATH) -maxdepth 1 -print; else echo "(none)"; fi
	@echo

clean-debian:
	@rm -rf "$(DEBIAN_PATH)"

check-debian-inputs:
	@$(MAKE) --no-print-directory -f $(SERVICE_BUILD_MAKEFILE) $(SERVICE_BUILD_CHECK_DEBIAN_TARGET)

DEBIAN_PUSH_CHECK_TARGETS ?= .check-debian-release-mode .check-debian-publish-packages
DEBIAN_PUSH_VERSION ?= $(VERSION_BUILD)

.check-debian-release-mode:
	$(call func_check_release_mode)

.check-debian-publish-packages:
	@set -e; \
	selected_version="$(DEBIAN_PUSH_VERSION)"; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	if [ -z "$$selected_version" ]; then \
		selected_version="$$version_build"; \
	elif [ "$$selected_version" != "$$version_build" ]; then \
		echo "check_publish_inputs ERROR: selected debian version '$$selected_version' does not match manifest version '$$version_build'." >&2; \
		echo "Manifest: $(BUILD_MANIFEST_FILE)" >&2; \
		exit 1; \
	fi; \
	missing=""; latest=""; \
	for service in $(DEBIAN_SERVICES); do \
		file="$(DEBIAN_PACKAGE_DIR)/$${service}_$${selected_version}_amd64.deb"; \
		if [ ! -f "$$file" ]; then \
			missing="$${missing}$${missing:+ }$${service}_$${selected_version}_amd64.deb"; \
			local_latest=""; \
			if [ -d "$(DEBIAN_PACKAGE_DIR)" ]; then \
				local_latest="$$(find "$(DEBIAN_PACKAGE_DIR)" -maxdepth 1 -type f -name "$${service}_*_amd64.deb" -print | sort -r | head -n 1)"; \
			fi; \
			if [ -n "$$local_latest" ]; then local_latest="$$(basename "$$local_latest")"; else local_latest="$${service}_(none)"; fi; \
			latest="$${latest}$${latest:+ }$$local_latest"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo ">> Debian Publish Package Check: [FAIL]"; \
		printf "  %15s : %s (%s)\n" "Version" "$$selected_version" "from $(BUILD_MANIFEST_FILE)"; \
		printf "  %15s : %s\n" "Missing" "$$missing"; \
		printf "  %15s : %s\n" "Latest" "$$latest"; \
		exit 1; \
	fi

include $(SERVICE_UTILS_DIR)/builder/debian.registry.mk

##----------------------------------------------------------------------------##
## Docker Image Handling ##

DOCKER_BUILD_PRE_TARGETS ?=
DOCKER_BUILD_INPUT_CHECK_TARGETS ?= .check-docker-build-inputs

build-docker: require-build-manifest $(DOCKER_BUILD_PRE_TARGETS) $(DOCKER_BUILD_INPUT_CHECK_TARGETS)
	@if [ -z "$(strip $(DOCKER_IMAGE_BUILD_SPECS))" ]; then \
		echo "ERROR: DOCKER_IMAGE_BUILD_SPECS is empty."; \
		exit 1; \
	fi
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane \
		--lane debian \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		$(BUILD_MANIFEST_ARGS))"; \
	for spec in $(DOCKER_IMAGE_BUILD_SPECS); do \
		image=$${spec%%:*}; \
		dockerfile=$${spec#*:}; \
		make -s .docker-build-image IMAGE=$$image DOCKERFILE=$$dockerfile VERSION_BUILD="$$version_build"; \
	done; \
	$(BUILD_MANIFEST_CMD) commit-lane \
		--lane docker \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--version-build "$$version_build" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		$(BUILD_MANIFEST_ARGS)

.docker-build-image: .require-version-build-var
	$(call func_build_docker,$(IMAGE),$(VERSION_BUILD),$(DOCKERFILE),$(DEP_DOCKER_BUILD_ARGS))

DOCKER_PUSH_CHECK_TARGETS ?= .check-docker-release-mode .check-docker-publish-images
DOCKER_PUSH_VERSION ?= $(VERSION_BUILD)
DOCKER_PUSH_LATEST ?= $(if $(filter pro,$(BUILD_MODE)),yes,no)

.check-docker-release-mode:
	$(call func_check_release_mode)

.check-docker-build-inputs:
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	missing=0; \
	for file_template in $(SERVICE_DOCKER_REQUIRED_ARTIFACTS); do \
		file="$${file_template//@VERSION_BUILD@/$$version_build}"; \
		if [ ! -f "$$file" ]; then \
			echo "Missing Docker input: $$file"; \
			missing=1; \
		fi; \
	done; \
	for glob_template in $(SERVICE_DOCKER_REQUIRED_GLOBS); do \
		glob="$${glob_template//@VERSION_BUILD@/$$version_build}"; \
		matches="$$(compgen -G "$$glob" || true)"; \
		if [ -z "$$matches" ]; then \
			echo "Missing Docker input: $$glob"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" = "1" ]; then \
		echo "ERROR: Docker inputs for $$version_build are incomplete."; \
		echo "Expected version source: $(BUILD_MANIFEST_FILE)"; \
		echo "Run 'make build-plugin && make build-debian' first, or 'make build' for the full local build."; \
		exit 1; \
	fi

.check-docker-publish-images:
	@set -e; \
	selected_version="$(DOCKER_PUSH_VERSION)"; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane docker $(BUILD_MANIFEST_COMMON_ARGS))"; \
	if [ -z "$$selected_version" ]; then \
		selected_version="$$version_build"; \
	elif [ "$$selected_version" != "$$version_build" ]; then \
		echo "check_publish_inputs ERROR: selected docker version '$$selected_version' does not match manifest version '$$version_build'." >&2; \
		echo "Manifest: $(BUILD_MANIFEST_FILE)" >&2; \
		exit 1; \
	fi; \
	missing=""; latest=""; \
	for image in $(DOCKER_IMAGES); do \
		ref="$$image:$$selected_version"; \
		if ! docker image inspect "$$ref" >/dev/null 2>&1; then \
			missing="$${missing}$${missing:+ }$$ref"; \
			if images_output="$$(docker images --format '{{.Repository}}\t{{.Tag}}' "$$image" 2>&1)"; then \
				local_latest="$$(printf '%s\n' "$$images_output" | awk -F '\t' '$$2 != "<none>" { print $$1 ":" $$2; exit }')"; \
			else \
				local_latest="$$image:(docker unavailable)"; \
			fi; \
			[ -n "$$local_latest" ] || local_latest="$$image:(none)"; \
			latest="$${latest}$${latest:+ }$$local_latest"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo ">> Docker Publish Image Check: [FAIL]"; \
		printf "  %15s : %s (%s)\n" "Version" "$$selected_version" "from $(BUILD_MANIFEST_FILE)"; \
		printf "  %15s : %s\n" "Missing" "$$missing"; \
		printf "  %15s : %s\n" "Latest" "$$latest"; \
		exit 1; \
	fi

include $(SERVICE_UTILS_DIR)/builder/docker.registry.mk
include $(SERVICE_UTILS_DIR)/builder/release.preflight.mk

# $(1): IMAGE_NAME
# $(2): VERSION
# $(3): DOCKERFILE
# $(4): BUILD_ARGS string
define func_build_docker
	@echo ""
	@echo "Building docker image: $(1):$(2)"
	@echo "Dockerfile: $(3); BUILD_ARGS: $(4)"
	@docker buildx build \
		--progress=plain \
		--platform linux/amd64 \
		--load \
		-f $(3) \
		$(4) \
		-t $(1):$(2) \
		.
	@echo "Successfully built docker image for $(1)/$(2)"
	@echo ""
endef

#------------------------------------------------------------------------------#

# Framework-owned runtime and toolchain versions. This include intentionally
# happens after service config so copied service projects inherit these values.
-include $(BUILD_ENV_ASN_VERSION_FILE)

.check_service_utils_version_file:
	@if [ ! -f "$(BUILD_ENV_ASN_VERSION_FILE)" ]; then \
		echo "ERROR: service-utils version metadata is missing: $(BUILD_ENV_ASN_VERSION_FILE)."; \
		echo "Run 'make init' to initialize or repair service-utils."; \
		exit 1; \
	fi
	@if [ -z "$(DEP_VERSION_ASN)" ] || [ -z "$(DEP_VERSION_GO)" ]; then \
		echo "ERROR: service-utils version metadata must define DEP_VERSION_ASN and DEP_VERSION_GO: $(BUILD_ENV_ASN_VERSION_FILE)."; \
		exit 1; \
	fi

BUILD_ENV_BASE_IMAGE_TAG ?= $(DEP_VERSION_ASN)
BUILD_ENV_BASE_IMAGE_REF ?= $(BUILD_ENV_BASE_IMAGE):$(BUILD_ENV_BASE_IMAGE_TAG)
SERVICE_GO_CACHE_PACKAGES ?= ./...
SERVICE_BUILDER_GOCACHE ?= $(CURDIR)/.cache/service-builder/go-build
SERVICE_BUILDER_INPUT_FILES ?= go.mod go.sum $(BUILD_ENV_BASE_DOCKERFILE) $(BUILD_ENV_MAKEFILE) $(BUILD_ENV_ASN_VERSION_FILE)

#------------------------------------------------------------------------------#

#------------------------------------------------------------------------------#
# Prepare for base docker image to build ASN Service Plugins.
prepare-service-builder-base: .check_service_utils_version_file
	@echo "Current working directory: ${PWD}"
	@echo "Building $(BUILD_ENV_BASE_IMAGE_REF)"

	@# Buildx updates the tag in place; avoid pre-removal because Docker Desktop
	@# can hang on absent container/image names.
	@service_go_mod_hash=$$(shasum -a 256 go.mod | awk '{ print $$1 }'); \
		builder_input_hash=$$( \
			{ \
				printf 'ASN_SERVICE_API_VERSION=%s\n' "$(ASN_SERVICE_API_VERSION)"; \
				printf 'DEP_VERSION_ASN=%s\n' "$(DEP_VERSION_ASN)"; \
				printf 'DEP_VERSION_GO=%s\n' "$(DEP_VERSION_GO)"; \
				printf 'SERVICE_GO_CACHE_PACKAGES=%s\n' "$(SERVICE_GO_CACHE_PACKAGES)"; \
				for file in $(SERVICE_BUILDER_INPUT_FILES); do \
					if [ -f "$$file" ]; then \
						printf 'file:%s\n' "$$file"; \
						shasum -a 256 "$$file"; \
					else \
						printf 'missing:%s\n' "$$file"; \
					fi; \
				done; \
			} | shasum -a 256 | awk '{ print $$1 }' \
		); \
		DOCKER_BUILDKIT=1 docker buildx build \
		--progress=plain \
		--platform linux/amd64 \
		--load \
		--build-arg GO_VERSION=$(DEP_VERSION_GO) \
		-f $(BUILD_ENV_BASE_DOCKERFILE) \
		--secret id=sshkey,src=$$PRIVATE_GIT_SSH_KEY_FILE \
		--label asn.service_api=$(ASN_SERVICE_API_VERSION) \
		--label asn.framework=$(DEP_VERSION_ASN) \
		--label asn.go=$(DEP_VERSION_GO) \
		--label asn.service_go_mod="$$service_go_mod_hash" \
		--label asn.builder_inputs="$$builder_input_hash" \
		-t $(BUILD_ENV_BASE_IMAGE_REF) .
	@echo ""
	@echo "Successfully built $(BUILD_ENV_BASE_IMAGE_REF) as the base image."
	@echo ""
	@echo "NOTE:"
	@echo " - This base image is local build infrastructure only; do not push or share it."
	@echo " - It installs the toolchain and downloads Go modules from the service go.mod/go.sum."
	@echo " - Service source is not copied into the base image; build targets run later from the mounted workspace."
	@echo " - MUST BE DONE everytime when service-api version changes."
	@echo " - MUST BE DONE everytime when the service go.mod/go.sum or builder inputs change."
	@echo " - Run \`docker images | grep asn\` to list the images."
	@echo " - Run \`make build-plugin\` to build plugin artifacts."
	@echo " - Run \`make build-debian\` to build Debian packages from plugin artifacts."
	@echo " - Run \`make build-docker\` to build standalone docker images, for non-plugin setup."
	@echo ""

# Check the local builder base image required to build ASN Service Plugins.
# This is a local Docker image check only; never query an online registry for it.
check-service-builder-base: .check_service_utils_version_file
	@image="$(BUILD_ENV_BASE_IMAGE_REF)"; \
	if ! docker_info=$$(docker info 2>&1); then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : unavailable\n" "Docker"; \
		echo "Local builder base image check failed: Docker daemon is not reachable."; \
		printf '%s\n' "$$docker_info" | sed -n '1,10p' | sed 's/^/  Docker Error             /'; \
		exit 1; \
	fi; \
	image_id=$$(docker images --no-trunc --format '{{.Repository}}:{{.Tag}} {{.ID}}' | awk -v image="$$image" '$$1 == image { print $$2; exit }'); \
	if [ -z "$$image_id" ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : %s (missing)\n" "Base Image" "$$image"; \
		echo "Local builder base image check failed: run make prepare before make build-plugin."; \
		exit 1; \
	fi; \
	inspect_err=$$(mktemp); \
	inspect_id=$$(docker image inspect "$$image_id" --format '{{.Id}}' 2>"$$inspect_err"); \
	inspect_status=$$?; \
	if [ "$$inspect_status" -ne 0 ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		if grep -qi "No such image" "$$inspect_err"; then \
			printf "  %-15s : %s (listed, unusable)\n" "Base Image" "$$image"; \
			echo "Local builder base image check failed: stale Docker image ID; run make prepare."; \
		else \
			printf "  %-15s : %s (inspect failed)\n" "Base Image" "$$image"; \
			echo "Local builder base image check failed: docker image inspect failed."; \
			sed 's/^/  Docker Error             /' "$$inspect_err"; \
		fi; \
		rm -f "$$inspect_err"; \
		exit 1; \
	fi; \
	rm -f "$$inspect_err"; \
	failed=0; \
	api=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.service_api" }}'); \
	framework=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.framework" }}'); \
	go_version=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.go" }}'); \
	go_mod=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.service_go_mod" }}'); \
	builder_inputs=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.builder_inputs" }}'); \
	expected_go_mod=$$(shasum -a 256 go.mod | awk '{ print $$1 }'); \
	expected_builder_inputs=$$( \
		{ \
			printf 'ASN_SERVICE_API_VERSION=%s\n' "$(ASN_SERVICE_API_VERSION)"; \
			printf 'DEP_VERSION_ASN=%s\n' "$(DEP_VERSION_ASN)"; \
			printf 'DEP_VERSION_GO=%s\n' "$(DEP_VERSION_GO)"; \
			printf 'SERVICE_GO_CACHE_PACKAGES=%s\n' "$(SERVICE_GO_CACHE_PACKAGES)"; \
			for file in $(SERVICE_BUILDER_INPUT_FILES); do \
				if [ -f "$$file" ]; then \
					printf 'file:%s\n' "$$file"; \
					shasum -a 256 "$$file"; \
				else \
					printf 'missing:%s\n' "$$file"; \
				fi; \
			done; \
		} | shasum -a 256 | awk '{ print $$1 }' \
	); \
	if [ "$$api" != "$(ASN_SERVICE_API_VERSION)" ]; then failed=1; fi; \
	if [ "$$framework" != "$(DEP_VERSION_ASN)" ]; then failed=1; fi; \
	if [ "$$go_version" != "$(DEP_VERSION_GO)" ]; then failed=1; fi; \
	if [ "$$go_mod" != "$$expected_go_mod" ]; then failed=1; fi; \
	if [ "$$builder_inputs" != "$$expected_builder_inputs" ]; then failed=1; fi; \
	if [ "$$failed" -ne 0 ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : %s\n" "Base Image" "$$image"; \
		printf "  %-15s : %s\n" "ID" "$${inspect_id#sha256:}"; \
		if [ "$$api" = "$(ASN_SERVICE_API_VERSION)" ]; then \
			printf "  %-15s : %s (expected as ASN_SERVICE_API_VERSION).\n" "API Version" "$${api:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s as ASN_SERVICE_API_VERSION). FAIL\n" "API Version" "$${api:-unknown}" "$(ASN_SERVICE_API_VERSION)"; \
		fi; \
		if [ "$$framework" = "$(DEP_VERSION_ASN)" ]; then \
			printf "  %-15s : %s (expected from service-utils)\n" "ASN Version" "$${framework:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from service-utils). FAIL\n" "ASN Version" "$${framework:-unknown}" "$(DEP_VERSION_ASN)"; \
		fi; \
		if [ "$$go_version" = "$(DEP_VERSION_GO)" ]; then \
			printf "  %-15s : %s (expected from service-utils)\n" "Go Version" "$${go_version:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from service-utils). FAIL\n" "Go Version" "$${go_version:-unknown}" "$(DEP_VERSION_GO)"; \
		fi; \
		if [ "$$go_mod" = "$$expected_go_mod" ]; then \
			printf "  %-15s : %s (expected from service go.mod).\n" "Service go.mod" "$${go_mod:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from service go.mod). FAIL\n" "Service go.mod" "$${go_mod:-missing}" "$$expected_go_mod"; \
		fi; \
		if [ "$$builder_inputs" = "$$expected_builder_inputs" ]; then \
			printf "  %-15s : %s (expected from builder inputs).\n" "Builder Inputs" "$${builder_inputs:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from builder inputs). FAIL\n" "Builder Inputs" "$${builder_inputs:-missing}" "$$expected_builder_inputs"; \
		fi; \
		echo "Local builder base image check failed. Run make prepare."; \
		exit 1; \
	fi; \
	cache_probe=$$(docker run --rm --platform $(SERVICE_BUILD_DOCKER_PLATFORM) \
		--mount type=bind,source="$(CURDIR)",target=$(SERVICE_BUILD_WORKDIR),readonly \
		--workdir $(SERVICE_BUILD_WORKDIR) \
		--env SERVICE_GO_CACHE_PACKAGES="$(SERVICE_GO_CACHE_PACKAGES)" \
		"$$image" sh -lc 'GOPROXY=off GOSUMDB=off go list -mod=readonly -deps $$SERVICE_GO_CACHE_PACKAGES >/dev/null' 2>&1); \
	cache_probe_status=$$?; \
	if [ "$$cache_probe_status" -ne 0 ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : %s\n" "Base Image" "$$image"; \
		printf "  %-15s : %s\n" "Packages" "$(SERVICE_GO_CACHE_PACKAGES)"; \
		echo "Local builder base image check failed: warmed Go module cache does not satisfy offline package resolution."; \
		printf '%s\n' "$$cache_probe" | sed -n '1,20p' | sed 's/^/  Go Error                 /'; \
		echo "Run make prepare after confirming private module access."; \
		exit 1; \
	fi; \
	echo ">> Builder Version and Base Image Check: [PASS]"; \
	printf "  %15s : %s\n" "Base Image" "$$image"; \
	printf "  %15s : %s\n" "ID" "$${inspect_id#sha256:}"; \
	printf "  %15s : %s (expected as ASN_SERVICE_API_VERSION).\n" "API Version" "$$api"; \
	printf "  %15s : %s (expected from service-utils)\n" "ASN Version" "$$framework"; \
	printf "  %15s : %s (expected from service-utils)\n" "Go Version" "$$go_version"; \
	printf "  %15s : %s (expected from service go.mod).\n" "Service go.mod" "$$go_mod"; \
	printf "  %15s : %s (expected from builder inputs).\n" "Builder Inputs" "$$builder_inputs"; \
	printf "  %15s : %s\n" "Offline Cache" "PASS"

define service_go_build_target
.service-go-build-$(1): .require-version-build-var
	@if [ -z "$$(strip $$(SERVICE_GO_BUILD_OUT_$(1)))" ] || [ -z "$$(strip $$(SERVICE_GO_BUILD_SRC_$(1)))" ]; then \
		echo "ERROR: SERVICE_GO_BUILD_OUT_$(1) and SERVICE_GO_BUILD_SRC_$(1) are required."; \
		exit 2; \
	fi
	@echo "Building service artifact: $(1)"
	@$$(SERVICE_GO_BUILD_ENV_$(1)) go build $$(SERVICE_GO_BUILD_FLAGS_$(1)) -o "$$(SERVICE_GO_BUILD_OUT_$(1))" $$(SERVICE_GO_BUILD_SRC_$(1))
endef
$(foreach artifact,$(SERVICE_GO_BUILD_ARTIFACTS),$(eval $(call service_go_build_target,$(artifact))))

build.plugin: .require-version-build-var
	@if [ -z "$(strip $(SERVICE_GO_BUILD_ARTIFACTS))" ]; then \
		echo "ERROR: SERVICE_GO_BUILD_ARTIFACTS is empty."; \
		exit 2; \
	fi
	@if [ -n "$(strip $(SERVICE_BUILD_CLEAN_DIRS))" ]; then \
		rm -rf $(SERVICE_BUILD_CLEAN_DIRS); \
	fi
	@if [ -n "$(strip $(SERVICE_BUILD_DIRS))" ]; then \
		mkdir -p $(SERVICE_BUILD_DIRS); \
	fi
	@$(MAKE) --no-print-directory $(SERVICE_GO_BUILD_TARGETS)
	@set -e; \
	for spec in $(SERVICE_ARTIFACT_COPY_SPECS); do \
		src_pattern="$${spec%%:*}"; \
		dest="$${spec#*:}"; \
		if [ "$$src_pattern" = "$$spec" ] || [ -z "$$dest" ]; then \
			echo "ERROR: invalid SERVICE_ARTIFACT_COPY_SPECS item '$$spec'; expected source-glob:destination."; \
			exit 2; \
		fi; \
		mkdir -p "$$dest"; \
		matched=0; \
		for src in $$src_pattern; do \
			[ -e "$$src" ] || continue; \
			cp -R "$$src" "$$dest"/; \
			matched=1; \
		done; \
		if [ "$$matched" -ne 1 ]; then \
			echo "ERROR: SERVICE_ARTIFACT_COPY_SPECS source matched nothing: $$src_pattern"; \
			exit 1; \
		fi; \
	done

check.deb:
	@echo "Checking Debian package inputs for: $(DEBIAN_SERVICES)"
	@set -e; \
	for svc in $(DEBIAN_SERVICES); do \
		echo ">>> Checking $$svc..."; \
		$(MAKE) --no-print-directory check-deb-$$svc; \
	done
	@set -e; \
	missing=0; \
	for file in $(SERVICE_DEBIAN_REQUIRED_ARTIFACTS); do \
		if [ ! -f "$$file" ]; then \
			echo "Missing Debian input: $$file"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "ERROR: Debian package inputs are incomplete."; \
		exit 1; \
	fi

build.deb: .require-version-build-var
	@rm -rf "$(DEBIAN_PATH)"
	@$(MAKE) --no-print-directory check.deb
	@echo "Building Debian packages for: $(DEBIAN_SERVICES)"
	@set -e; \
	for svc in $(DEBIAN_SERVICES); do \
		echo ">>> Building $$svc..."; \
		$(MAKE) --no-print-directory deb-$$svc; \
	done
	@set -e; \
	for spec in $(SERVICE_DEBIAN_PACKAGE_COPY_SPECS); do \
		package="$${spec%%:*}"; \
		rest="$${spec#*:}"; \
		src="$${rest%%:*}"; \
		dest="$${rest#*:}"; \
		if [ "$$package" = "$$spec" ] || [ "$$src" = "$$rest" ] || [ -z "$$package" ] || [ -z "$$src" ] || [ -z "$$dest" ]; then \
			echo "ERROR: invalid SERVICE_DEBIAN_PACKAGE_COPY_SPECS item '$$spec'; expected package:source:destination."; \
			exit 2; \
		fi; \
		if [ ! -e "$$src" ]; then \
			echo "ERROR: Debian package copy source is missing: $$src"; \
			exit 1; \
		fi; \
		root="$(DEBIAN_PATH)/$$package/$$dest"; \
		echo "Staging $$src into $$package:$$dest"; \
		rm -rf "$$root"; \
		mkdir -p "$$root"; \
		if [ -d "$$src" ]; then \
			cp -R "$$src"/. "$$root"/; \
		else \
			cp -R "$$src" "$$root"/; \
		fi; \
		dpkg-deb --build "$(DEBIAN_PATH)/$$package" "$(DEBIAN_PATH)/$${package}_$(VERSION_BUILD)_amd64.deb"; \
		echo "Repacked: $(DEBIAN_PATH)/$${package}_$(VERSION_BUILD)_amd64.deb"; \
	done

# Rebuild the base image, then build plugin artifacts with the normal builder.
service-build-from-scratch: prepare-service-builder-base service-build-plugin
	@echo "Successfully rebuilt the base image and plugin artifacts from scratch."
	@echo ""

# Build the plugins.
# Note: Actual targets are built inside a container using $(SERVICE_BUILD_MAKEFILE).
# - Target '$(SERVICE_BUILD_PLUGIN_TARGET)' is executed to build .so and CLI artifacts.
# - Target '$(SERVICE_BUILD_DEBIAN_TARGET)' is executed by 'make build-debian' to build .deb files.
# - No Docker images built here. Separate targets, build.docker*, are available.
service-build-plugin: .require-version-build-var
	@$(MAKE) --no-print-directory service-build-once BUILD_MAKE_TARGET=$(SERVICE_BUILD_PLUGIN_TARGET)

service-build-debian: .require-version-build-var
	@$(MAKE) --no-print-directory service-build-once BUILD_MAKE_TARGET=$(SERVICE_BUILD_DEBIAN_TARGET)

.require-version-build-var:
	@if [ -z "$(strip $(VERSION_BUILD))" ]; then \
		echo "ERROR: VERSION_BUILD is not set for this internal build step."; \
		echo "Use make build-plugin, make build-debian, or make build-docker so build/Manifest.yaml owns the version."; \
		exit 2; \
	fi

BUILD_MAKE_TARGET ?= build.targets
# Builder execution mode:
# - docker-run is the default fast path. It runs the requested internal make
#   target inside the prepared builder base image with the service workspace
#   bind-mounted as the artifact boundary.
# - docker-build keeps the older Dockerfile RUN + docker cp behavior as a
#   temporary migration fallback for services or hosts that cannot use bind
#   mounts with the local Docker daemon.
SERVICE_BUILD_EXECUTION_MODE ?= docker-run
SERVICE_BUILD_DOCKER_PLATFORM ?= linux/amd64
SERVICE_BUILD_WORKDIR ?= /asn-service
SERVICE_BUILD_SECRET_TARGET ?= /run/secrets/sshkey
SERVICE_BUILD_DOCKER_RUN_ARGS ?=

service-build-once:
	@case "$(SERVICE_BUILD_EXECUTION_MODE)" in \
		docker-run) \
			$(MAKE) --no-print-directory service-build-once-docker-run BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		docker-build) \
			$(MAKE) --no-print-directory service-build-once-docker-build BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		*) \
			echo "ERROR: SERVICE_BUILD_EXECUTION_MODE must be docker-run or docker-build, got '$(SERVICE_BUILD_EXECUTION_MODE)'."; \
			exit 2 ;; \
	esac

service-build-once-docker-run:
	@echo "Current working directory: ${PWD}"
	@echo "Start building with $(BUILD_ENV_BASE_IMAGE_REF)"
	@echo "Build target: $(BUILD_MAKE_TARGET)"

	@# Remove only a container that is known to exist. Docker Desktop can hang
	@# when asked to remove an absent named container.
	@if docker ps -a --format '{{.Names}}' | awk -v name="$(BUILD_ENV_IMAGE)" '$$0 == name { found=1 } END { exit !found }'; then \
		docker rm -f $(BUILD_ENV_IMAGE) >/dev/null; \
	fi

	@mkdir -p build "$(SERVICE_BUILDER_GOCACHE)"
	@echo "Running Docker builder container:"
	@echo "  image:       $(BUILD_ENV_BASE_IMAGE_REF)"
	@echo "  platform:    $(SERVICE_BUILD_DOCKER_PLATFORM)"
	@echo "  name:        $(BUILD_ENV_IMAGE)"
	@echo "  target:      $(BUILD_MAKE_TARGET)"
	@echo "  version:     $(VERSION_BUILD)"
	@echo "  workspace:   $(CURDIR) -> $(SERVICE_BUILD_WORKDIR)"
	@echo "  go cache:    $(SERVICE_BUILDER_GOCACHE) -> /root/.cache/go-build"
	@echo "  secret:      PRIVATE_GIT_SSH_KEY_FILE -> $(SERVICE_BUILD_SECRET_TARGET) (readonly)"
	@docker run --rm --platform $(SERVICE_BUILD_DOCKER_PLATFORM) --name $(BUILD_ENV_IMAGE) \
		$(SERVICE_BUILD_DOCKER_RUN_ARGS) \
		--mount type=bind,source="$(CURDIR)",target=$(SERVICE_BUILD_WORKDIR) \
		--mount type=bind,source="$$PRIVATE_GIT_SSH_KEY_FILE",target=$(SERVICE_BUILD_SECRET_TARGET),readonly \
		--mount type=bind,source="$(SERVICE_BUILDER_GOCACHE)",target=/root/.cache/go-build \
		--env BUILD_MODE="$(BUILD_MODE)" \
		--env VERSION_BUILD="$(VERSION_BUILD)" \
		--env GOCACHE=/root/.cache/go-build \
		--workdir $(SERVICE_BUILD_WORKDIR) \
		$(BUILD_ENV_BASE_IMAGE_REF) \
		make -f $(SERVICE_BUILD_MAKEFILE) $(BUILD_MAKE_TARGET) BUILD_MODE="$(BUILD_MODE)" VERSION_BUILD="$(VERSION_BUILD)"
	@echo ""
	@echo "Successfully ran builder target $(BUILD_MAKE_TARGET) in $(BUILD_ENV_BASE_IMAGE_REF)."
	@echo ""
	@echo "NOTE:"
	@echo " - If the ASN Service API has updated, make sure the base image has been rebuilt."
	@echo " - Run 'make check' if you need to verify the prepared base image labels before building."
	@echo ""

service-build-once-docker-build:
	@echo "Current working directory: ${PWD}"
	@echo "Start building $(BUILD_ENV_IMAGE):latest"
	@echo "Build target: $(BUILD_MAKE_TARGET)"

	@# Remove only a container that is known to exist. Docker Desktop can hang
	@# when asked to remove an absent named container.
	@if docker ps -a --format '{{.Names}}' | awk -v name="$(BUILD_ENV_IMAGE)" '$$0 == name { found=1 } END { exit !found }'; then \
		docker rm -f $(BUILD_ENV_IMAGE) >/dev/null; \
	fi

	@# Build the service environment image and run the target in a Dockerfile RUN step.
	@echo "Running Docker builder fallback:"
	@echo "  docker buildx build --platform $(SERVICE_BUILD_DOCKER_PLATFORM) -f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest"
	@echo "  base image:  $(BUILD_ENV_BASE_IMAGE_REF)"
	@echo "  build mode:  $(BUILD_MODE)"
	@echo "  version:     $(VERSION_BUILD)"
	@echo "  target:      $(BUILD_MAKE_TARGET)"
	@DOCKER_BUILDKIT=1 docker buildx build --progress=plain --platform $(SERVICE_BUILD_DOCKER_PLATFORM) $(BUILD_ARGS) \
		--load \
		--build-arg BUILD_ENV_BASE_IMAGE=$(BUILD_ENV_BASE_IMAGE_REF) \
		--build-arg BUILD_MODE=$(BUILD_MODE) \
		--build-arg VERSION_BUILD=$(VERSION_BUILD) \
		--build-arg MAKE_TARGET=$(BUILD_MAKE_TARGET) \
		--build-arg SERVICE_BUILD_MAKEFILE=$(SERVICE_BUILD_MAKEFILE) \
		--secret id=sshkey,src=$$PRIVATE_GIT_SSH_KEY_FILE \
		-f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest .
	@echo "Successfully built $(BUILD_ENV_IMAGE):latest."
	@docker run -d --platform $(SERVICE_BUILD_DOCKER_PLATFORM) --name $(BUILD_ENV_IMAGE) $(BUILD_ENV_IMAGE):latest
	@echo ""
	@mkdir -p build
	@docker cp $(BUILD_ENV_IMAGE):/build ./

	@# Clean up.
	@printf "%s" "Removed: "
	@docker rm -f $(BUILD_ENV_IMAGE)
	@echo ""
	@echo "Successfully ran builder target $(BUILD_MAKE_TARGET), then removed $(BUILD_ENV_IMAGE):latest."
	@echo ""
	@echo "NOTE:"
	@echo " - docker-build execution is kept for migration fallback; docker-run is the default executor."
	@echo " - If the ASN Service API has updated, make sure the base image has been rebuilt."
	@echo " - Run 'make check' if you need to verify the prepared base image labels before building."
	@echo ""


###
# Generic deb input check rule: check-deb-<service>
check-deb-%:
	$(eval SERVICE_NAME := $*)
	$(eval SERVICE_CONFIG := debian/deb.$(SERVICE_NAME).config)
	$(eval SERVICE_CONTROL := debian/deb.$(SERVICE_NAME).control)
	@if [ ! -f $(SERVICE_CONFIG) ]; then \
		echo "Missing config: $(SERVICE_CONFIG)"; exit 1; \
	fi
	@if [ ! -f $(SERVICE_CONTROL) ]; then \
		echo "Missing control: $(SERVICE_CONTROL)"; exit 1; \
	fi
	$(eval include $(SERVICE_CONFIG))
	@echo "SERVICE_NAME: $(SERVICE_NAME)"
	@missing=0; \
	for pair in $(DEBIAN_FILES); do \
		SRC=$$(echo $$pair | cut -d: -f1); \
		if [ ! -e "$$SRC" ]; then \
			echo "Missing Debian input: $$SRC"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "Build plugin artifacts before running make build-debian."; \
		exit 1; \
	fi

REMOVED_TARGET_REPLACEMENT_build-init := init
REMOVED_TARGET_REPLACEMENT_build-prepare := prepare
REMOVED_TARGET_REPLACEMENT_debian := build-debian
REMOVED_TARGET_REPLACEMENT_docker := build-docker

build-init build-prepare debian docker:
	@echo "ERROR: make $@ has been removed."
	@echo "Use 'make $(REMOVED_TARGET_REPLACEMENT_$@)'."
	@exit 2

###
# Generic deb packaging rule: deb-<service>
deb-%: check-deb-%
	$(eval SERVICE_NAME := $*)
	$(eval SERVICE_CONFIG := debian/deb.$(SERVICE_NAME).config)
	$(eval SERVICE_CONTROL := debian/deb.$(SERVICE_NAME).control)
	$(eval include $(SERVICE_CONFIG))
	$(eval DEB_SVC_DIR := $(DEBIAN_PATH)/$(SERVICE_NAME))

	@echo "DEBIAN_PATH: $(DEB_SVC_DIR)"
	@mkdir -p $(DEB_SVC_DIR)/DEBIAN

	@# Generate control file from service-specific control template
	@sed -e "s/@VERSION@/$(VERSION_BUILD)/" \
	     -e "s/@DEPENDS@/$(DEP_VERSION_ASN)/" \
	     -e "s/@SERVICE@/$(SERVICE_NAME)/" \
	     $(SERVICE_CONTROL) > $(DEB_SVC_DIR)/DEBIAN/control

	$(eval SERVICE_POSTINST := debian/deb.$(SERVICE_NAME).postinst)
	@if [ -f $(SERVICE_POSTINST) ]; then \
		cp $(SERVICE_POSTINST) $(DEB_SVC_DIR)/DEBIAN/postinst; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/postinst; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/postinst; \
	fi

	$(eval SERVICE_POSTRM := debian/deb.$(SERVICE_NAME).postrm)
	@if [ -f $(SERVICE_POSTRM) ]; then \
		cp $(SERVICE_POSTRM) $(DEB_SVC_DIR)/DEBIAN/postrm; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/postrm; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/postrm; \
	fi

	$(eval SERVICE_PREINST := debian/deb.$(SERVICE_NAME).preinst)
	@if [ -f $(SERVICE_PREINST) ]; then \
		cp $(SERVICE_PREINST) $(DEB_SVC_DIR)/DEBIAN/preinst; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/preinst; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/preinst; \
	fi

	$(eval SERVICE_PRERM := debian/deb.$(SERVICE_NAME).prerm)
	@if [ -f $(SERVICE_PRERM) ]; then \
		cp $(SERVICE_PRERM) $(DEB_SVC_DIR)/DEBIAN/prerm; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/prerm; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/prerm; \
	fi

	$(eval SERVICE_FILE := debian/deb.$(SERVICE_NAME).service)
	@if [ -f $(SERVICE_FILE) ]; then \
		mkdir -p $(DEB_SVC_DIR)/lib/systemd/system; \
		cp $(SERVICE_FILE) $(DEB_SVC_DIR)/lib/systemd/system/$(SERVICE_NAME).service; \
	fi

	@if [ -f debian/conffiles.$(SERVICE_NAME) ]; then \
			echo "Copying service-specific conffiles for $(SERVICE_NAME)..."; \
			cp debian/conffiles.$(SERVICE_NAME) $(DEB_SVC_DIR)/DEBIAN/conffiles; \
			chmod 644 $(DEB_SVC_DIR)/DEBIAN/conffiles; \
		else \
			echo "No conffiles found for $(SERVICE_NAME), skipping"; \
		fi

	@# Copy files from DEBIAN_FILES
	@for pair in $(DEBIAN_FILES); do \
		SRC=$$(echo $$pair | cut -d: -f1); \
		DST=$$(echo $$pair | cut -d: -f2 | sed 's@^/@@'); \
		echo "Processing file: $$SRC -> $(DEB_SVC_DIR)/$$DST"; \
		mkdir -p $(DEB_SVC_DIR)/$$DST; \
		cp "$$SRC" "$(DEB_SVC_DIR)/$$DST/" || { echo "Failed to copy $$SRC"; exit 1; }; \
#		chmod 644 "$(DEB_SVC_DIR)/$$DST/$$(basename $$SRC)"; \
	done
	@echo "Prepared to packing .deb."

	$(eval DEB_FILE_NAME := $(DEB_SVC_DIR)_$(VERSION_BUILD)_amd64.deb)
	@dpkg-deb --build $(DEB_SVC_DIR) $(DEB_FILE_NAME)
	@echo "Packed: $(DEB_FILE_NAME)."


clean-deb-%:
	@echo "Cleaning $*..."
	@rm -rf "$(DEBIAN_PATH)/$*"

# Debug purpose
show-prepare:
	@echo "Current working directory: ${PWD}"
	@echo "Starting $(BUILD_ENV_BASE_IMAGE_REF)"
	docker run --rm --platform linux/amd64 --name $(BUILD_ENV_BASE_IMAGE) $(BUILD_ENV_BASE_IMAGE_REF) ls -l /

	@echo " Ran the container once to show the artifacts."

#------------------------------------------------------------------------------#
init_service_utils:
	@if [ -z "$(SERVICE_UTILS_DIR)" ]; then \
		echo "ERROR: SERVICE_UTILS_DIR is not set."; \
		exit 1; \
	fi
	@if [ -d "$(SERVICE_UTILS_DIR)" ] && git_probe=$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --is-inside-work-tree 2>&1) && [ "$$git_probe" = "true" ]; then \
		echo "service-utils is already present."; \
	else \
		echo "Initializing service-utils submodule."; \
		git submodule sync --recursive $(SERVICE_UTILS_DIR); \
		git submodule update --init --recursive $(SERVICE_UTILS_DIR); \
	fi

update_service_utils: init_service_utils
	@if [ -z "$(ASN_SERVICE_API_VERSION)" ]; then \
		echo "ERROR: ASN_SERVICE_API_VERSION is not set."; \
		exit 1; \
	fi
	@expected="v$(ASN_SERVICE_API_VERSION)"; \
	if current=$$(git -C "$(SERVICE_UTILS_DIR)" symbolic-ref --quiet --short HEAD 2>&1); then :; \
	elif current=$$(git -C "$(SERVICE_UTILS_DIR)" describe --tags --exact-match 2>&1); then :; \
	else current=$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD); fi; \
	cd $(SERVICE_UTILS_DIR) && \
	git fetch --prune origin && \
	if [ "$$current" = "$$expected" ]; then \
		if git show-ref --verify --quiet refs/remotes/origin/v$(ASN_SERVICE_API_VERSION); then \
			git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); \
		else \
			echo "service-utils ref $$current already selected (tag, no pull needed)."; \
		fi; \
	else \
		echo "Selecting service-utils ref $$expected"; \
		if git show-ref --verify --quiet refs/remotes/origin/v$(ASN_SERVICE_API_VERSION); then \
			if git show-ref --verify --quiet refs/heads/v$(ASN_SERVICE_API_VERSION); then \
				git checkout v$(ASN_SERVICE_API_VERSION); \
				git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); \
			else \
				git checkout -b v$(ASN_SERVICE_API_VERSION) origin/v$(ASN_SERVICE_API_VERSION); \
			fi; \
		elif git show-ref --verify --quiet refs/tags/v$(ASN_SERVICE_API_VERSION); then \
			git checkout v$(ASN_SERVICE_API_VERSION); \
		else \
			echo "ERROR: service-utils ref v$(ASN_SERVICE_API_VERSION) was not found as an origin branch or tag."; \
			exit 1; \
		fi; \
	fi
