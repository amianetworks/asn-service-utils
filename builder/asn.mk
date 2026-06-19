# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## ASN artifact-builder extension.
##
## ASN service projects include this file before AM Workflow's neutral
## workflow/make/artifact-builder.mk. This file owns ASN runtime/API dependency
## checks and registers them into the neutral lifecycle hook lists.

ifeq ($(strip $(SERVICE_UTILS_DIR)),)
$(error SERVICE_UTILS_DIR is required before including service-utils/builder/asn.mk)
endif

ifeq ($(strip $(ASN_SERVICE_API_VERSION)),)
$(error ASN_SERVICE_API_VERSION is required before including service-utils/builder/asn.mk)
endif

include $(SERVICE_UTILS_DIR)/builder/ASN_VERSION

ifeq ($(BUILD_MODE),pro)
ifneq ($(ASN_RUNTIME_MODE),pro)
$(error BUILD_MODE=pro requires ASN_RUNTIME_MODE=pro)
endif
endif

export SERVICE_UTILS_DIR
export ASN_SERVICE_API_VERSION ASN_RUNTIME_MODE ASN_RUNTIME_VERSION ASN_RUNTIME_VERSION_DEV ASN_RUNTIME_VERSION_PRO ASN_BUILDER_GO_VERSION
export CHECK_VERSION_ROWS CHECK_VERSION_EXTRA_ROWS CHECK_BUILD_ROWS CHECK_BUILD_EXTRA_ROWS

PROTO_TOOLS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/proto_tools.sh

BUILD_CONTAINER_BASE_DOCKERFILE ?= $(SERVICE_UTILS_DIR)/builder/asn-artifact-base.dockerfile
BUILD_CONTAINER_BASE_IMAGE ?= asn-artifact-builder-base
BUILD_CONTAINER_RUNNER_IMAGE ?= $(if $(strip $(PROJECT_ID)),$(PROJECT_ID)-artifact-builder,asn-artifact-builder)
BUILD_CONTAINER_BASE_IMAGE_TAG ?= $(ASN_RUNTIME_VERSION)
BUILD_CONTAINER_BASE_API_VERSION ?= $(ASN_SERVICE_API_VERSION)
BUILD_CONTAINER_BASE_FRAMEWORK_VERSION ?= $(ASN_RUNTIME_VERSION)
BUILD_CONTAINER_BASE_GO_VERSION ?= $(ASN_BUILDER_GO_VERSION)
BUILD_CONTAINER_METADATA_FILES += $(SERVICE_UTILS_DIR)/builder/ASN_VERSION
BUILD_CONTAINER_CACHE_INPUTS += $(SERVICE_UTILS_DIR)/go.mod $(SERVICE_UTILS_DIR)/go.sum $(SERVICE_UTILS_DIR)/builder/asn.mk
BUILD_CONTAINER_SYMLINK_MOUNT_PATHS += $(SERVICE_UTILS_DIR)

GO_MOD_REFERENCE_FILE ?= $(SERVICE_UTILS_DIR)/go.mod
GO_BUILD_PARALLELISM ?= 2
GO_BUILD_PARALLELISM_FLAG ?= $(if $(strip $(GO_BUILD_PARALLELISM)),-p=$(GO_BUILD_PARALLELISM),)
DEBIAN_DEPENDS_VERSION ?= $(ASN_RUNTIME_VERSION)
IMAGE_BUILD_ARG_VALUES ?= ASN_C_VERSION=$(ASN_RUNTIME_VERSION) ASN_SN_VERSION=$(ASN_RUNTIME_VERSION)

BUILD_MANIFEST_ARTIFACT_EXTRA_ARGS += \
	--service-utils-dir "$(SERVICE_UTILS_DIR)" \
	--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
	--asn-runtime-version "$(ASN_RUNTIME_VERSION)" \
	--builder-go-version "$(ASN_BUILDER_GO_VERSION)"

ASN_DEFINE_BUILD_PLUGIN ?= 1
ASN_BUILD_PLUGIN_TARGET ?= build

CHECK_PREPARE_TARGETS += check-version check-go-mod build-container-check
CHECK_LOCAL_TARGETS += check-build
PREPARE_CHECK_TARGETS += check-version check-go-mod
BUILD_PRECHECK_TARGETS += check-version check-go-mod build-container-check

.PHONY: update-service-utils check-version check-build

ifeq ($(strip $(ASN_DEFINE_BUILD_PLUGIN)),1)
.PHONY: build-plugin

build-plugin: $(ASN_BUILD_PLUGIN_TARGET)
endif

update-service-utils:
	@if [ -z "$(strip $(SERVICE_UTILS_DIR))" ]; then printf '%s\n' "ERROR: SERVICE_UTILS_DIR is not set."; exit 2; fi
	@if [ -z "$(strip $(SERVICE_UTILS_BRANCH))" ]; then printf '%s\n' "ERROR: SERVICE_UTILS_BRANCH is not set."; exit 2; fi
	@if ! git -C "$(SERVICE_UTILS_DIR)" rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		printf '%s\n' "ERROR: $(SERVICE_UTILS_DIR) is not a git checkout; run 'make init' first."; \
		exit 2; \
	fi
	@if git -C "$(SERVICE_UTILS_DIR)" ls-remote --exit-code --heads origin "$(SERVICE_UTILS_BRANCH)" >/dev/null 2>&1; then \
		printf '%s\n' "Updating $(SERVICE_UTILS_DIR) from origin/$(SERVICE_UTILS_BRANCH)"; \
		git -C "$(SERVICE_UTILS_DIR)" fetch origin "$(SERVICE_UTILS_BRANCH):refs/remotes/origin/$(SERVICE_UTILS_BRANCH)"; \
		git -C "$(SERVICE_UTILS_DIR)" checkout "$(SERVICE_UTILS_BRANCH)" 2>/dev/null || git -C "$(SERVICE_UTILS_DIR)" checkout -b "$(SERVICE_UTILS_BRANCH)" --track "origin/$(SERVICE_UTILS_BRANCH)"; \
		git -C "$(SERVICE_UTILS_DIR)" merge --ff-only "origin/$(SERVICE_UTILS_BRANCH)"; \
	elif git -C "$(SERVICE_UTILS_DIR)" show-ref --verify --quiet "refs/heads/$(SERVICE_UTILS_BRANCH)"; then \
		printf '%s\n' "Using local $(SERVICE_UTILS_DIR) branch $(SERVICE_UTILS_BRANCH) (origin ref unavailable)"; \
		git -C "$(SERVICE_UTILS_DIR)" checkout "$(SERVICE_UTILS_BRANCH)"; \
	else \
		printf '%s\n' "ERROR: origin/$(SERVICE_UTILS_BRANCH) is unavailable and no local $(SERVICE_UTILS_BRANCH) branch exists."; \
		exit 2; \
	fi

check-version:
	@$(BUILD_MANIFEST_CMD) check-version \
		--service "$(SERVICE)" \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--go-version "$(GO_VERSION)" \
		$(BUILD_MANIFEST_ARGS)

check-build:
	@$(BUILD_MANIFEST_CMD) check-build \
		--service "$(SERVICE)" \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		$(BUILD_MANIFEST_ARGS)
