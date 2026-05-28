# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

#$(info service.plugin.builder.mk loaded)

# Shared builder recipes use Bash arrays and pattern substitutions. Declare the
# shell contract here so service repositories that include this file directly do
# not inherit GNU Make's default /bin/sh by accident.
SHELL := /bin/bash

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
## Services expose shared build lifecycle names by default. Framework repos can
## set SERVICE_UTILS_OWN_BUILD_TARGETS=no before including this file and provide
## their own public build map while still using the shared helper targets below.
SERVICE_UTILS_OWN_BUILD_TARGETS ?= yes

## `push-all` is Make-only artifact publication. Release validation and handoff
## remain outside the generic builder and should consume the published outputs.
push-all: push-docker push-debian

##----------------------------------------------------------------------------##
## Main targets ##
## Project-owned Makefiles define service variables and include this shared
## builder. Helper targets below own the common build, package, publish, and
## validation mechanics.

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
	.check-docker-release-mode \
	.check-debian-release-mode \
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
BUILDER_BASE_IMAGE_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/builder_base_image.sh
PROTO_TOOLS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/proto_tools.sh
PUBLISH_VARS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/publish_vars.sh
DEBIAN_PACKAGE_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/debian_package.sh

# Framework-owned runtime and toolchain versions. The include stays optional so
# `make init` can repair a missing service-utils checkout, but checked build
# targets must pass `.check_service_utils_version_file` before they consume the
# values. Keep this before manifest argument defaults so DEP_VERSION_ASN is not
# captured as empty during Make expansion.
-include $(BUILD_ENV_ASN_VERSION_FILE)

BUILD_MANIFEST_ARGS ?=
BUILD_MANIFEST_LANE ?=
BUILD_MANIFEST_QUERY_FILE ?= $(BUILD_MANIFEST_FILE)
BUILD_MANIFEST_KEY ?=
BUILD_MANIFEST_CORE_ARGS ?= --manifest "$(BUILD_MANIFEST_FILE)" --mode "$(BUILD_MODE)" --version "$(VERSION)" --build "$(BUILD)" --manager-build-dir "$(BUILD_SVC_C_DIR)" --servicenode-build-dir "$(BUILD_SVC_SN_DIR)" --client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" --debian-dir "$(DEBIAN_PATH)" --debian-services "$(DEBIAN_SERVICES)" --docker-images "$(DOCKER_IMAGES)"
BUILD_MANIFEST_COMMON_EXTRA_ARGS ?=
BUILD_MANIFEST_COMMON_ARGS ?= $(BUILD_MANIFEST_CORE_ARGS) --docs-dir "$(CURDIR)/build/docs" $(BUILD_MANIFEST_ARGS) $(BUILD_MANIFEST_COMMON_EXTRA_ARGS)
BUILD_MANIFEST_RESERVE_ARGS ?= --version "$(VERSION)" --mode "$(BUILD_MODE)" --build "$(BUILD)" --dev-start "$(BUILD_NUM_DEV)" --dev-file "$(DEV_BUILD_FILE)" --manifest "$(BUILD_MANIFEST_FILE)" $(BUILD_MANIFEST_ARGS)
BUILD_MANIFEST_COMMIT_PLUGIN_ARGS ?= $(BUILD_MANIFEST_COMMON_ARGS) --dev-start "$(BUILD_NUM_DEV)" --dev-file "$(DEV_BUILD_FILE)" --asn-service-api-version "$(ASN_SERVICE_API_VERSION)" --dep-version-asn "$(DEP_VERSION_ASN)"
BUILD_MANIFEST_STAGE_DOCS_EXTRA_ARGS ?= $(BUILD_MANIFEST_ARGS)
BUILD_MANIFEST_STAGE_DOCS_ARGS ?= $(BUILD_MANIFEST_CORE_ARGS) --docs-dir "$(STAGE_DOCS_DIR)" $(BUILD_MANIFEST_STAGE_DOCS_EXTRA_ARGS) --docs-required-artifacts "$(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml $(STAGE_DOCS_DIR)/release/DocsChecksums.tsv $(STAGE_DOCS_DIR)/index.html" --docs-version-file "$(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml" --docs-version-key "$(SERVICE_DOCS_VERSION_KEY)"
# Build identity is shared builder state. If the caller did not pass
# VERSION_BUILD explicitly, leave it empty here and let recipes query
# build_manifest.sh with fail-visible shell commands. Parse-time $(shell ...)
# calls cannot propagate exit status, which makes manifest failures easy to miss.
VERSION_BUILD ?=
SERVICE_BUILD_MAKEFILE ?= Makefile
SERVICE_RECURSIVE_MAKE ?= $(MAKE)
SERVICE_BUILD_PLUGIN_TARGET ?= build.plugin
SERVICE_BUILD_DEBIAN_TARGET ?= build.deb
SERVICE_BUILD_CHECK_DEBIAN_TARGET ?= check.deb
SERVICE_ARTIFACT_BUILD_TARGET ?= build-plugin
SERVICE_BUILD_CLEAN_DIRS ?=
SERVICE_BUILD_DIRS ?= $(SERVICE_BUILD_CLEAN_DIRS)
SERVICE_CLEAN_DIRS ?= build/
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

# Destructive shared targets are limited to the generated artifact tree. The
# Make-side assertion catches bad command-line overrides before a shell recipe
# can interpret punctuation, and the shell-side guard remains readable in dry
# runs and logs.
semicolon := ;
ampersand := &
pipe := |
lt := <
gt := >
backtick := `
squote := '
dquote := "
dollar_char := $$
left_paren := (
right_paren := )
left_brace := {
right_brace := }
left_bracket := [
right_bracket := ]
asterisk := *
question := ?
service_utils_path_shell_chars := $(semicolon) $(ampersand) $(pipe) $(lt) $(gt) $(backtick) $(squote) $(dquote) $(dollar_char) $(left_paren) $(right_paren) $(left_brace) $(right_brace) $(left_bracket) $(right_bracket) $(asterisk) $(question)
service_utils_path_has_shell_chars = $(strip $(foreach char,$(service_utils_path_shell_chars),$(findstring $(char),$(1))))
service_utils_build_path_allowed = $(and $(filter build build/ build/% ./build ./build/ ./build/%,$(1)),$(if $(findstring ..,$(1)),,$(if $(filter /%,$(1)),,$(if $(call service_utils_path_has_shell_chars,$(1)),,$(1)))))
service_utils_unsafe_build_paths = $(strip $(foreach path,$(1),$(if $(call service_utils_build_path_allowed,$(path)),,$(path))))
service_utils_assert_build_paths = $(if $(strip $(1)),$(if $(call service_utils_unsafe_build_paths,$(1)),$(error $(2) contains unsafe path(s): $(call service_utils_unsafe_build_paths,$(1)))))

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

define service_utils_owned_lifecycle_targets
## `build-all` is the only legacy spelling kept, and it is a plain alias for
## `build` in service repositories that use the shared lifecycle directly.
build-all: build

build: prepare build-plugin $(BUILD_EXTRA_TARGETS) build-debian build-docker

build-fresh: clean prepare build-plugin $(BUILD_EXTRA_TARGETS) build-debian build-docker
	@echo "Built fresh artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

build-plugin: check proto-gen
	@set -e; \
	version_build="$$$$($(BUILD_MANIFEST_CMD) reserve-plugin-version $(BUILD_MANIFEST_RESERVE_ARGS))"; \
	echo ">> Build Plugin Version"; \
	printf "  %15s : %s\n" "Version" "$$$$version_build"; \
	$$(SERVICE_RECURSIVE_MAKE) --no-print-directory service-build-plugin VERSION_BUILD="$$$$version_build"; \
	if service_utils_ref="$$$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD 2>&1)"; then \
		:; \
	else \
		echo "WARN: could not resolve service-utils git ref: $$$$service_utils_ref" >&2; \
		service_utils_ref="unknown"; \
	fi; \
	$$(BUILD_MANIFEST_CMD) commit-plugin \
		$$(BUILD_MANIFEST_COMMIT_PLUGIN_ARGS) \
		--version-build "$$$$version_build" \
		--service-utils-ref "$$$$service_utils_ref"
	@echo "Built artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo
endef
$(if $(filter yes,$(SERVICE_UTILS_OWN_BUILD_TARGETS)),$(eval $(service_utils_owned_lifecycle_targets)))

# Any artifacts should be under build/. Guard this shared clean path so a bad
# override cannot remove source, config, or parent directories.
clean:
	$(call service_utils_assert_build_paths,$(SERVICE_CLEAN_DIRS),SERVICE_CLEAN_DIRS)
	@set -e; \
	if [ -z "$(strip $(SERVICE_CLEAN_DIRS))" ]; then \
		echo "No service clean directories configured."; \
		exit 0; \
	fi; \
	for path in $(SERVICE_CLEAN_DIRS); do \
		case "$$path" in \
			""|"."|"/"|*"/.."|*"/../"*|".."|"../"*) echo "ERROR: refusing unsafe clean path: '$$path'."; exit 2 ;; \
			build|build/|build/*|./build|./build/|./build/*) rm -rf "$$path" ;; \
			*) echo "ERROR: refusing clean path outside build/: $$path"; exit 2 ;; \
		esac; \
	done

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
	@$(PUBLISH_VARS_CMD) print --kind docker --site "$(VAR_SITE)" --endpoint-name "DOCKER_REGISTRY_$(VAR_SITE)" --endpoint "$(VAR_REGISTRY)" --profile "$(VAR_PROFILE)" --auth-var "$(VAR_AUTH_VAR)" --credential-var "DOCKER_REGISTRY_$(VAR_SITE)_USER" --used-by "push-docker-$(call lowercase,$(VAR_SITE))"

.print-debian-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DEBIAN)
	$(eval VAR_HOST := $(DEBIAN_REPO_HOST_$(VAR_SITE)))
	@$(PUBLISH_VARS_CMD) print --kind debian --site "$(VAR_SITE)" --endpoint-name "DEBIAN_REPO_HOST_$(VAR_SITE)" --endpoint "$(VAR_HOST)" --profile "$(VAR_PROFILE)" --auth-var "$(VAR_AUTH_VAR)" --credential-var "DEBIAN_REPO_USER_$(VAR_SITE)" --used-by "push-debian-$(call lowercase,$(VAR_SITE))"

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
	@$(PUBLISH_VARS_CMD) check --kind docker --site "$(VAR_SITE)" --endpoint-name "DOCKER_REGISTRY_$(VAR_SITE)" --endpoint "$(VAR_REGISTRY)" --profile "$(VAR_PROFILE)" --auth-var "$(VAR_AUTH_VAR)" --credential-var "DOCKER_REGISTRY_$(VAR_SITE)_USER"

.check-debian-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DEBIAN)
	$(eval VAR_HOST := $(DEBIAN_REPO_HOST_$(VAR_SITE)))
	@$(PUBLISH_VARS_CMD) check --kind debian --site "$(VAR_SITE)" --endpoint-name "DEBIAN_REPO_HOST_$(VAR_SITE)" --endpoint "$(VAR_HOST)" --profile "$(VAR_PROFILE)" --auth-var "$(VAR_AUTH_VAR)" --credential-var "DEBIAN_REPO_USER_$(VAR_SITE)"

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
	@$(PROTO_GEN_ENV) $(PROTO_TOOLS_CMD) tools \
		--protoc-version "$(PROTOC_VERSION)" \
		--protoc-release-version "$(PROTOC_RELEASE_VERSION)" \
		--protoc-gen-go-version "$(PROTOC_GEN_GO_VERSION)" \
		--protoc-gen-go-grpc-version "$(PROTOC_GEN_GO_GRPC_VERSION)" \
		--tools-dir "$(PROTO_TOOLS_DIR)" \
		--download-base-url "$(PROTOC_DOWNLOAD_BASE_URL)" \
		--auto-download "$(PROTOC_AUTO_DOWNLOAD)" \
		--protoc-defaulted "$(PROTOC_DEFAULTED)" \
		--protoc "$(PROTOC)"

proto-tools-check:
	@$(PROTO_GEN_ENV) $(PROTO_TOOLS_CMD) tools-check \
		--protoc-version "$(PROTOC_VERSION)" \
		--protoc-release-version "$(PROTOC_RELEASE_VERSION)" \
		--protoc-gen-go-version "$(PROTOC_GEN_GO_VERSION)" \
		--protoc-gen-go-grpc-version "$(PROTOC_GEN_GO_GRPC_VERSION)" \
		--tools-dir "$(PROTO_TOOLS_DIR)" \
		--download-base-url "$(PROTOC_DOWNLOAD_BASE_URL)" \
		--auto-download "$(PROTOC_AUTO_DOWNLOAD)" \
		--protoc-defaulted "$(PROTOC_DEFAULTED)" \
		--protoc "$(PROTOC)"

proto-gen:
	@$(PROTO_GEN_ENV) $(PROTO_TOOLS_CMD) gen \
		--protoc-version "$(PROTOC_VERSION)" \
		--protoc-release-version "$(PROTOC_RELEASE_VERSION)" \
		--protoc-gen-go-version "$(PROTOC_GEN_GO_VERSION)" \
		--protoc-gen-go-grpc-version "$(PROTOC_GEN_GO_GRPC_VERSION)" \
		--tools-dir "$(PROTO_TOOLS_DIR)" \
		--download-base-url "$(PROTOC_DOWNLOAD_BASE_URL)" \
		--auto-download "$(PROTOC_AUTO_DOWNLOAD)" \
		--protoc-defaulted "$(PROTOC_DEFAULTED)" \
		--protoc "$(PROTOC)" \
		--proto-out "$(PROTO_OUT)" \
		--default-out "$(PROTO_GEN_DEFAULT_OUT)" \
		--stamp "$(PROTO_GEN_STAMP)" \
		--force "$(PROTO_GEN_FORCE)" \
		--specs "$(PROTO_GEN_SPECS)" \
		--state-files "$(PROTO_GEN_STATE_FILES)"

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
	if [ "$$commit_manifest" = "yes" ]; then \
		version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane plugin $(BUILD_MANIFEST_STAGE_DOCS_ARGS))"; \
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
		$(BUILD_MANIFEST_CMD) commit-lane --lane docs --version-build "$$version_build" $(BUILD_MANIFEST_STAGE_DOCS_ARGS); \
	fi

set-version: check-build
	@echo "Modify config.mk to update the version and build."
	@echo "NOTE: Only CI/CD or maintainer should change the version with caution."

increment-build:
	@echo "ERROR: make increment-build has been removed."
	@echo "$(SERVICE_ARTIFACT_BUILD_TARGET) now commits $(DEV_BUILD_FILE) only after artifacts build successfully."
	@exit 2

##----------------------------------------------------------------------------##
## Debian Package handling ##

uppercase = $(strip $(subst z,Z,$(subst y,Y,$(subst x,X,$(subst w,W,$(subst v,V,$(subst u,U,$(subst t,T,$(subst s,S,$(subst r,R,$(subst q,Q,$(subst p,P,$(subst o,O,$(subst n,N,$(subst m,M,$(subst l,L,$(subst k,K,$(subst j,J,$(subst i,I,$(subst h,H,$(subst g,G,$(subst f,F,$(subst e,E,$(subst d,D,$(subst c,C,$(subst b,B,$(subst a,A,$(1))))))))))))))))))))))))))))
lowercase = $(strip $(subst Z,z,$(subst Y,y,$(subst X,x,$(subst W,w,$(subst V,v,$(subst U,u,$(subst T,t,$(subst S,s,$(subst R,r,$(subst Q,q,$(subst P,p,$(subst O,o,$(subst N,n,$(subst M,m,$(subst L,l,$(subst K,k,$(subst J,j,$(subst I,i,$(subst H,h,$(subst G,g,$(subst F,f,$(subst E,e,$(subst D,d,$(subst C,c,$(subst B,b,$(subst A,a,$(1))))))))))))))))))))))))))))

define func_check_release_mode
	@set -e; \
	case "$(BUILD_MODE)" in \
		dev|pro) : ;; \
		*) echo "ERROR: BUILD_MODE must be dev or pro for publish targets, got '$(BUILD_MODE)'."; exit 2 ;; \
	esac; \
	case "$(RELEASE_CHANNEL)" in \
		""|unknown) echo "ERROR: RELEASE_CHANNEL is not configured for BUILD_MODE=$(BUILD_MODE)."; exit 2 ;; \
	esac
endef

require-build-manifest:
	@version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane plugin $(BUILD_MANIFEST_COMMON_ARGS))"; \
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
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane docs $(BUILD_MANIFEST_COMMON_ARGS))"; \
	$(MAKE) --no-print-directory service-build-debian VERSION_BUILD="$$version_build"; \
	$(BUILD_MANIFEST_CMD) commit-lane \
		--lane debian \
		$(BUILD_MANIFEST_COMMON_ARGS) \
		--version-build "$$version_build"
	@echo "Built Debian packages (DIR):"
	@if [ -d "$(DEBIAN_PATH)" ]; then find ./$(DEBIAN_PATH) -maxdepth 1 -print; else echo "(none)"; fi
	@echo

clean-debian:
	$(call service_utils_assert_build_paths,$(DEBIAN_PATH),DEBIAN_PATH)
	@set -e; \
	path="$(DEBIAN_PATH)"; \
	case "$$path" in \
		""|"."|"/"|*"/.."|*"/../"*|".."|"../"*) echo "ERROR: refusing unsafe Debian clean path: '$$path'."; exit 2 ;; \
		build|build/|build/*|./build|./build/|./build/*) rm -rf "$$path" ;; \
		*) echo "ERROR: refusing Debian clean path outside build/: $$path"; exit 2 ;; \
	esac

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
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	for spec in $(DOCKER_IMAGE_BUILD_SPECS); do \
		image=$${spec%%:*}; \
		dockerfile=$${spec#*:}; \
		case "$$image" in ""|*[^A-Za-z0-9._/-]*) echo "ERROR: invalid Docker image name in DOCKER_IMAGE_BUILD_SPECS: $$image"; exit 2 ;; esac; \
		if [ "$$dockerfile" = "$$spec" ] || [ -z "$$dockerfile" ] || [ ! -f "$$dockerfile" ]; then \
			echo "ERROR: invalid Dockerfile in DOCKER_IMAGE_BUILD_SPECS item '$$spec'."; \
			exit 2; \
		fi; \
		echo ""; \
		echo "Building docker image: $$image:$$version_build"; \
		echo "Dockerfile: $$dockerfile; BUILD_ARGS: $(DEP_DOCKER_BUILD_ARGS)"; \
		docker buildx build \
			--progress=plain \
			--platform linux/amd64 \
			--load \
			-f "$$dockerfile" \
			$(DEP_DOCKER_BUILD_ARGS) \
			-t "$$image:$$version_build" \
			.; \
		echo "Successfully built docker image for $$image/$$version_build"; \
		echo ""; \
	done; \
	$(BUILD_MANIFEST_CMD) commit-lane \
		--lane docker \
		$(BUILD_MANIFEST_COMMON_ARGS) \
		--version-build "$$version_build"

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
		if matches="$$(compgen -G "$$glob" 2>&1)"; then \
			:; \
		elif [ -n "$$matches" ]; then \
			echo "ERROR: Docker input glob probe failed for $$glob"; \
			echo "$$matches"; \
			missing=1; \
		fi; \
		if [ -z "$$matches" ]; then \
			echo "Missing Docker input: $$glob"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" = "1" ]; then \
		echo "ERROR: Docker inputs for $$version_build are incomplete."; \
		echo "Expected version source: $(BUILD_MANIFEST_FILE)"; \
		echo "Run 'make $(SERVICE_ARTIFACT_BUILD_TARGET) && make build-debian' first, or 'make build-all' for the full local build."; \
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
		inspect_output=$$(mktemp); \
		if docker image inspect "$$ref" > "$$inspect_output" 2>&1; then \
			rm -f "$$inspect_output"; \
			:; \
		else \
			missing="$${missing}$${missing:+ }$$ref"; \
			if [ -s "$$inspect_output" ]; then \
				latest="$${latest}$${latest:+ }docker-inspect-error:$$ref"; \
				sed "s/^/Docker inspect $$ref: /" "$$inspect_output"; \
			fi; \
			rm -f "$$inspect_output"; \
			if images_output="$$(docker images --format '{{.Repository}}\t{{.Tag}}' "$$image" 2>&1)"; then \
				local_latest="$$(printf '%s\n' "$$images_output" | awk -F '\t' '$$2 != "<none>" { print $$1 ":" $$2; exit }')"; \
			else \
				if [ -n "$$images_output" ]; then printf "%s\n" "$$images_output" | sed "s/^/Docker images $$image: /"; fi; \
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
SERVICE_BUILDER_HELPER_FILES ?= $(SERVICE_UTILS_DIR)/builder/builder_base_image.sh
SERVICE_BUILDER_INPUT_FILES ?= go.mod go.sum $(BUILD_ENV_BASE_DOCKERFILE) $(BUILD_ENV_MAKEFILE) $(BUILD_ENV_ASN_VERSION_FILE) $(SERVICE_BUILDER_HELPER_FILES)

#------------------------------------------------------------------------------#

#------------------------------------------------------------------------------#
# Prepare for base docker image to build ASN Service Plugins.
prepare-service-builder-base: .check_service_utils_version_file
	@echo "Current working directory: ${PWD}"
	@echo "Building $(BUILD_ENV_BASE_IMAGE_REF)"

	@# Buildx updates the tag in place; avoid pre-removal because Docker Desktop
	@# can hang on absent container/image names.
	@$(BUILDER_BASE_IMAGE_CMD) prepare \
		--image "$(BUILD_ENV_BASE_IMAGE_REF)" \
		--dockerfile "$(BUILD_ENV_BASE_DOCKERFILE)" \
		--context "$(CURDIR)" \
		--ssh-key "$$PRIVATE_GIT_SSH_KEY_FILE" \
		--api-version "$(ASN_SERVICE_API_VERSION)" \
		--framework-version "$(DEP_VERSION_ASN)" \
		--go-version "$(DEP_VERSION_GO)" \
		--cache-packages "$(SERVICE_GO_CACHE_PACKAGES)" \
		--input-files "$(SERVICE_BUILDER_INPUT_FILES)" \
		--platform "$(SERVICE_BUILD_DOCKER_PLATFORM)"
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
	@echo " - Run \`make $(SERVICE_ARTIFACT_BUILD_TARGET)\` to build artifacts."
	@echo " - Run \`make build-debian\` to build Debian packages from artifacts."
	@echo " - Run \`make build-docker\` to build standalone docker images, for non-plugin setup."
	@echo ""

# Check the local builder base image required to build ASN Service Plugins.
# This is a local Docker image check only; never query an online registry for it.
check-service-builder-base: .check_service_utils_version_file
	@$(BUILDER_BASE_IMAGE_CMD) check \
		--image "$(BUILD_ENV_BASE_IMAGE_REF)" \
		--context "$(CURDIR)" \
		--api-version "$(ASN_SERVICE_API_VERSION)" \
		--framework-version "$(DEP_VERSION_ASN)" \
		--go-version "$(DEP_VERSION_GO)" \
		--cache-packages "$(SERVICE_GO_CACHE_PACKAGES)" \
		--input-files "$(SERVICE_BUILDER_INPUT_FILES)" \
		--platform "$(SERVICE_BUILD_DOCKER_PLATFORM)" \
		--workdir "$(SERVICE_BUILD_WORKDIR)"

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
	$(call service_utils_assert_build_paths,$(SERVICE_BUILD_CLEAN_DIRS),SERVICE_BUILD_CLEAN_DIRS)
	@if [ -n "$(strip $(SERVICE_BUILD_CLEAN_DIRS))" ]; then \
		set -e; \
		for path in $(SERVICE_BUILD_CLEAN_DIRS); do \
			case "$$path" in \
				build|build/|build/*|./build|./build/|./build/*) rm -rf "$$path" ;; \
				*) echo "ERROR: refusing service build clean path outside build/: $$path"; exit 2 ;; \
			esac; \
		done; \
	fi
	$(call service_utils_assert_build_paths,$(SERVICE_BUILD_DIRS),SERVICE_BUILD_DIRS)
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
	@set -e; \
	path="$(DEBIAN_PATH)"; \
	case "$$path" in \
		""|"."|"/"|*"/.."|*"/../"*|".."|"../"*) echo "ERROR: refusing unsafe Debian clean path: '$$path'."; exit 2 ;; \
		build|build/|build/*|./build|./build/|./build/*) rm -rf "$$path" ;; \
		*) echo "ERROR: refusing Debian clean path outside build/: $$path"; exit 2 ;; \
	esac
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
		echo "Use make $(SERVICE_ARTIFACT_BUILD_TARGET), make build-debian, or make build-docker so build/Manifest.yaml owns the version."; \
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

service-build-once: .require-version-build-var
	@case "$(SERVICE_BUILD_EXECUTION_MODE)" in \
		docker-run) \
			$(MAKE) --no-print-directory service-build-once-docker-run BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		docker-build) \
			$(MAKE) --no-print-directory service-build-once-docker-build BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		*) \
			echo "ERROR: SERVICE_BUILD_EXECUTION_MODE must be docker-run or docker-build, got '$(SERVICE_BUILD_EXECUTION_MODE)'."; \
			exit 2 ;; \
	esac

service-build-once-docker-run: .require-version-build-var
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

service-build-once-docker-build: .require-version-build-var
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
	$(if $(wildcard $(SERVICE_CONFIG)),$(eval include $(SERVICE_CONFIG)))
	@$(DEBIAN_PACKAGE_CMD) check --service "$(SERVICE_NAME)" --config "$(SERVICE_CONFIG)" --control "$(SERVICE_CONTROL)" --files "$(DEBIAN_FILES)"

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
	$(if $(wildcard $(SERVICE_CONFIG)),$(eval include $(SERVICE_CONFIG)))
	@$(DEBIAN_PACKAGE_CMD) build --service "$(SERVICE_NAME)" --config "$(SERVICE_CONFIG)" --control "$(SERVICE_CONTROL)" --files "$(DEBIAN_FILES)" --debian-path "$(DEBIAN_PATH)" --version-build "$(VERSION_BUILD)" --depends-version "$(DEP_VERSION_ASN)"


clean-deb-%:
	$(call service_utils_assert_build_paths,$(DEBIAN_PATH),DEBIAN_PATH)
	@set -e; \
	stem="$*"; \
	case "$$stem" in \
		""|"."|".."|*..*|*[^A-Za-z0-9._-]*) \
			echo "ERROR: refusing unsafe Debian clean target stem: '$$stem'."; \
			exit 2 ;; \
	esac; \
	path="$(DEBIAN_PATH)/$$stem"; \
	case "$$path" in \
		build/*|./build/*) echo "Cleaning $$path..."; rm -rf "$$path" ;; \
		*) echo "ERROR: refusing Debian clean path outside build/: $$path"; exit 2 ;; \
	esac

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
