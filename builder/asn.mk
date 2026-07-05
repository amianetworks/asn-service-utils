# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## ASN artifact support extension.
##
## ASN and ASN service projects may include this file for service-utils-owned
## runtime/API defaults and version checks. Project dependency checkout
## maintenance belongs to WorkflowSpace project_dependencies or plain Git
## submodule setup.

##----------------------------------------------------------------------------##
## Required project inputs.
ifeq ($(strip $(SERVICE_UTILS_DIR)),)
$(error SERVICE_UTILS_DIR is required before including service-utils/builder/asn.mk)
endif

ifeq ($(strip $(ASN_SERVICE_API_VERSION)),)
$(error ASN_SERVICE_API_VERSION is required before including service-utils/builder/asn.mk)
endif

##----------------------------------------------------------------------------##
## service-utils paths and ASN runtime metadata.
ASN_BUILDER_DIR := $(SERVICE_UTILS_DIR)/builder
ASN_BUILDER_MAKEFILE := $(ASN_BUILDER_DIR)/asn.mk
ASN_VERSION_FILE ?= $(ASN_BUILDER_DIR)/ASN_VERSION

include $(ASN_VERSION_FILE)

ifeq ($(BUILD_MODE),pro)
ifneq ($(ASN_RUNTIME_MODE),pro)
$(error BUILD_MODE=pro requires ASN_RUNTIME_MODE=pro)
endif
endif

ASN_BUILD_IDENTITY ?= $(or $(strip $(PROJECT_ID)),$(strip $(SERVICE)))
GO_VERSION ?= $(ASN_BUILDER_GO_VERSION)

export SERVICE_UTILS_DIR
export ASN_SERVICE_API_VERSION ASN_RUNTIME_MODE ASN_RUNTIME_VERSION ASN_RUNTIME_VERSION_DEV ASN_RUNTIME_VERSION_PRO ASN_BUILDER_GO_VERSION
export CHECK_VERSION_ROWS CHECK_VERSION_EXTRA_ROWS CHECK_BUILD_ROWS CHECK_BUILD_EXTRA_ROWS

##----------------------------------------------------------------------------##
## Commands supplied by service-utils.
PROTO_TOOLS_CMD ?= bash $(ASN_BUILDER_DIR)/proto_tools.sh
BUILD_MANIFEST_CMD ?= bash $(ASN_BUILDER_DIR)/build_manifest.sh
BUILDER_BASE_IMAGE_CMD ?= bash $(ASN_BUILDER_DIR)/builder_base_image.sh
DEBIAN_PACKAGE_CMD ?= bash $(ASN_BUILDER_DIR)/debian_package.sh
STAGE_DOCS_CMD ?= bash $(ASN_BUILDER_DIR)/stage_docs.sh

##----------------------------------------------------------------------------##
## Generic artifact-builder defaults for ASN projects.
BUILD_CONTAINER_BASE_DOCKERFILE ?= $(ASN_BUILDER_DIR)/asn-artifact-base.dockerfile
BUILD_CONTAINER_BASE_IMAGE ?= asn-artifact-builder-base
BUILD_CONTAINER_RUNNER_IMAGE ?= $(if $(strip $(PROJECT_ID)),$(PROJECT_ID)-artifact-builder,asn-artifact-builder)
BUILD_CONTAINER_BASE_IMAGE_TAG ?= $(ASN_RUNTIME_VERSION)
BUILD_CONTAINER_BASE_API_VERSION ?= $(ASN_SERVICE_API_VERSION)
BUILD_CONTAINER_BASE_FRAMEWORK_VERSION ?= $(ASN_RUNTIME_VERSION)
BUILD_CONTAINER_BASE_GO_VERSION ?= $(GO_VERSION)
BUILD_CONTAINER_METADATA_FILES += $(ASN_VERSION_FILE)
BUILD_CONTAINER_CACHE_INPUTS += $(SERVICE_UTILS_DIR)/go.mod $(SERVICE_UTILS_DIR)/go.sum $(ASN_BUILDER_MAKEFILE)
BUILD_CONTAINER_SYMLINK_MOUNT_PATHS += $(SERVICE_UTILS_DIR)
ifneq ($(strip $(ASN_RUNTIME_MODE)),)
BUILD_CONTAINER_RUN_ARGS += --env ASN_RUNTIME_MODE="$(ASN_RUNTIME_MODE)"
endif

GO_MOD_REFERENCE_FILE ?= $(SERVICE_UTILS_DIR)/go.mod
GO_BUILD_PARALLELISM ?= 2
GO_BUILD_PARALLELISM_FLAG ?= $(if $(strip $(GO_BUILD_PARALLELISM)),-p=$(GO_BUILD_PARALLELISM),)
DEBIAN_DEPENDS_VERSION ?= $(ASN_RUNTIME_VERSION)
IMAGE_BUILD_ARG_VALUES ?= ASN_C_VERSION=$(ASN_RUNTIME_VERSION) ASN_SN_VERSION=$(ASN_RUNTIME_VERSION) SERVICE_VERSION=@VERSION_BUILD@

BUILD_MANIFEST_ARTIFACT_EXTRA_ARGS += \
	--service-utils-dir "$(SERVICE_UTILS_DIR)" \
	--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
	--asn-runtime-version "$(ASN_RUNTIME_VERSION)" \
	--builder-go-version "$(ASN_BUILDER_GO_VERSION)"

##----------------------------------------------------------------------------##
## Generic artifact-builder hook registration.
##
## Keep ASN-specific readiness wiring here. Shared Make only consumes these
## generic extension variables.
ASN_REGISTER_ARTIFACT_BUILDER_HOOKS ?= 1
ifeq ($(strip $(ASN_REGISTER_ARTIFACT_BUILDER_HOOKS)),1)
CHECK_PREPARE_TARGETS += check-version check-go-mod build-container-check
CHECK_LOCAL_TARGETS += check-build
PREPARE_CHECK_TARGETS += check-version check-go-mod
BUILD_PRECHECK_TARGETS += check-version check-go-mod build-container-check
endif

##----------------------------------------------------------------------------##
## ASN convenience targets.
ASN_DEFINE_BUILD_PLUGIN ?= 1
ASN_BUILD_PLUGIN_TARGET ?= build

.PHONY: check-version check-build

ifeq ($(strip $(ASN_DEFINE_BUILD_PLUGIN)),1)
.PHONY: build-plugin

build-plugin: $(ASN_BUILD_PLUGIN_TARGET)
endif

check-version:
	@$(BUILD_MANIFEST_CMD) check-version \
		--project "$(ASN_BUILD_IDENTITY)" \
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
		--project "$(ASN_BUILD_IDENTITY)" \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		$(BUILD_MANIFEST_ARGS)
