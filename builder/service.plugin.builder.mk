# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

#$(info service.plugin.builder.mk loaded)

# Shared builder recipes use Bash arrays and pattern substitutions. Declare the
# shell contract here so service repositories that include this file directly do
# not inherit GNU Make's default /bin/sh by accident.
SHELL := /bin/bash

# The following variables must be defined by the consuming service config or
# root bootstrap. Generic defaults live in builder/make/*.mk.
#ASN_SERVICE_API_VERSION
#BUILD_ENV_ASN_VERSION_FILE
#PRIVATE_GIT_SSH_KEY_FILE
#SERVICE_UTILS_DIR

SERVICE_UTILS_BUILDER_MAKE_DIR := $(SERVICE_UTILS_DIR)/builder/make
SERVICE_UTILS_BUILDER_OWNED_FRAGMENT_FILES := \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/00-contract.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/10-lifecycle.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/20-checks.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/30-source-proto.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/40-docs.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/50-debian.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/60-docker.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/70-executor.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/80-debian-rules.mk \
	$(SERVICE_UTILS_BUILDER_MAKE_DIR)/90-service-utils-init.mk

include $(SERVICE_UTILS_BUILDER_OWNED_FRAGMENT_FILES)
