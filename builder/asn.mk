# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## ASN service-builder extension.
##
## ASN service projects include this file before AM Workflow's neutral
## workflow/make/service-builder.mk. This file owns ASN runtime/API dependency
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

PROTO_TOOLS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/proto_tools.sh

BUILD_CONTAINER_BASE_DOCKERFILE ?= $(SERVICE_UTILS_DIR)/builder/service.plugin.builder.base.dockerfile
BUILD_CONTAINER_RUNNER_DOCKERFILE ?= $(SERVICE_UTILS_DIR)/builder/service.plugin.builder.dockerfile
BUILD_CONTAINER_BASE_IMAGE ?= asn-service-builder-base
BUILD_CONTAINER_RUNNER_IMAGE ?= asn-service-builder
BUILD_CONTAINER_BASE_IMAGE_TAG ?= $(ASN_RUNTIME_VERSION)
BUILD_CONTAINER_BASE_API_VERSION ?= $(ASN_SERVICE_API_VERSION)
BUILD_CONTAINER_BASE_FRAMEWORK_VERSION ?= $(ASN_RUNTIME_VERSION)
BUILD_CONTAINER_BASE_GO_VERSION ?= $(ASN_BUILDER_GO_VERSION)
BUILD_CONTAINER_METADATA_FILES += $(SERVICE_UTILS_DIR)/builder/ASN_VERSION
BUILD_CONTAINER_CACHE_INPUTS += $(SERVICE_UTILS_DIR)/go.mod $(SERVICE_UTILS_DIR)/go.sum $(SERVICE_UTILS_DIR)/builder/asn.mk
BUILD_CONTAINER_SYMLINK_MOUNT_PATHS += $(SERVICE_UTILS_DIR)

GO_MOD_REFERENCE_FILE ?= $(SERVICE_UTILS_DIR)/go.mod
DEBIAN_DEPENDS_VERSION ?= $(ASN_RUNTIME_VERSION)
IMAGE_BUILD_ARG_VALUES ?= ASN_C_VERSION=$(ASN_RUNTIME_VERSION) ASN_SN_VERSION=$(ASN_RUNTIME_VERSION)

BUILD_MANIFEST_SERVICE_EXTRA_ARGS += \
	--service-utils-dir "$(SERVICE_UTILS_DIR)" \
	--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
	--asn-runtime-version "$(ASN_RUNTIME_VERSION)" \
	--builder-go-version "$(ASN_BUILDER_GO_VERSION)"

CHECK_PREPARE_TARGETS += check-version check-go-mod check-service-builder-base
CHECK_LOCAL_TARGETS += check-build
PREPARE_CHECK_TARGETS += check-version check-go-mod
BUILD_PRECHECK_TARGETS += check-version check-go-mod check-service-builder-base

.PHONY: check-version check-build

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
