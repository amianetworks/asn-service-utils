# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Shared builder defaults and service contract expansion.
##
## Keep target recipes in the topic files. This file owns reusable defaults,
## compact-spec compatibility variables, and low-level Make helpers consumed by
## the rest of the shared builder.
SERVICE_UTILS_OWN_BUILD_TARGETS ?= yes
SERVICE_UTILS_OWN_CLEAN_TARGET ?= yes
SERVICE_UTILS_OWN_SET_VERSION_TARGET ?= yes
SERVICE_UTILS_RECURSIVE_MAKE ?= $(MAKE)

BUILD_MANIFEST_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/build_manifest.sh
BUILDER_BASE_IMAGE_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/builder_base_image.sh
PROTO_TOOLS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/proto_tools.sh
PUBLISH_VARS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/publish_vars.sh
DEBIAN_PACKAGE_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/debian_package.sh
BUILD_ENV_BASE_DOCKERFILE ?= $(SERVICE_UTILS_DIR)/builder/service.plugin.builder.base.dockerfile
BUILD_ENV_DOCKERFILE ?= $(SERVICE_UTILS_DIR)/builder/service.plugin.builder.dockerfile
BUILD_ENV_BASE_IMAGE ?= asn-service-builder-base
BUILD_ENV_IMAGE ?= asn-service-builder

# Framework-owned runtime and toolchain versions. The include stays optional so
# `make init` can repair a missing service-utils checkout, but checked build
# targets must pass `.check_service_utils_version_file` before they consume the
# values. Keep this before manifest argument defaults so DEP_VERSION_ASN is not
# captured as empty during Make expansion.
-include $(BUILD_ENV_ASN_VERSION_FILE)

DEBIAN_PATH ?= $(BUILD_DIR)/debian
DEBIAN_SERVICES ?= \
	$(SERVICE_MANAGER_DEBIAN_PACKAGE) \
	$(SERVICE_SN_DEBIAN_PACKAGE) \
	$(SERVICE_MANAGER_CLI_DEBIAN_PACKAGE) \
	$(SERVICE_CLIENT_CLI_DEBIAN_PACKAGE)
SERVICE_PLUGIN_REQUIRED_GLOBS ?= \
	$(BUILD_SVC_C_DIR)/*.conf \
	$(BUILD_SVC_SN_DIR)/*.conf

BUILD_MANIFEST_SCHEMA ?= service.build.manifest.v1
BUILD_MANIFEST_SOURCE_KEY ?= source_commit
BUILD_MANIFEST_SOURCE_LABEL ?= service
BUILD_MANIFEST_SERVICE_ARGS ?= \
	--service-utils-dir "$(SERVICE_UTILS_DIR)" \
	--schema "$(BUILD_MANIFEST_SCHEMA)" \
	--source-key "$(BUILD_MANIFEST_SOURCE_KEY)" \
	--source-label "$(BUILD_MANIFEST_SOURCE_LABEL)" \
	--plugin-required-artifacts "$(SERVICE_PLUGIN_REQUIRED_ARTIFACTS)" \
	--plugin-required-globs "$(SERVICE_PLUGIN_REQUIRED_GLOBS)"
BUILD_MANIFEST_DEFAULT_DOCS_ARGS ?= \
	--docs-required-artifacts "$(SERVICE_DOCS_REQUIRED_ARTIFACTS)" \
	--docs-version-file "$(SERVICE_DOCS_VERSION_FILE)" \
	--docs-version-key "$(SERVICE_DOCS_VERSION_KEY)"
BUILD_MANIFEST_ARGS ?= $(BUILD_MANIFEST_SERVICE_ARGS)
BUILD_MANIFEST_LANE ?=
BUILD_MANIFEST_QUERY_FILE ?= $(BUILD_MANIFEST_FILE)
BUILD_MANIFEST_KEY ?=
BUILD_MANIFEST_CORE_ARGS ?= --manifest "$(BUILD_MANIFEST_FILE)" --mode "$(BUILD_MODE)" --version "$(VERSION)" --build "$(BUILD)" --manager-build-dir "$(BUILD_SVC_C_DIR)" --servicenode-build-dir "$(BUILD_SVC_SN_DIR)" --client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" --debian-dir "$(DEBIAN_PATH)" --debian-services "$(DEBIAN_SERVICES)" --docker-images "$(DOCKER_IMAGES)"
BUILD_MANIFEST_COMMON_EXTRA_ARGS ?= $(BUILD_MANIFEST_DEFAULT_DOCS_ARGS)
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
SERVICE_GO_BUILD_SPECS ?=
SERVICE_GO_BUILD_KINDS ?= manager-plugin servicenode-plugin manager-cli client-daemon client-cli
service_go_build_spec_field = $(word $(2),$(subst |, ,$(1)))
service_go_build_spec_name = $(call service_go_build_spec_field,$(1),1)
service_go_build_spec_kind = $(call service_go_build_spec_field,$(1),2)
service_go_build_spec_out = $(call service_go_build_spec_field,$(1),3)
service_go_build_spec_src = $(call service_go_build_spec_field,$(1),4)
service_go_build_spec_env = $(if $(filter -,$(call service_go_build_spec_field,$(1),5)),,$(call service_go_build_spec_field,$(1),5))
service_go_build_flags_for_kind = $(strip $(if $(filter manager-plugin,$(1)),-buildmode=plugin $(SERVICE_C_GO_FLAGS),$(if $(filter servicenode-plugin,$(1)),-buildmode=plugin $(SERVICE_SN_GO_FLAGS),$(if $(filter manager-cli,$(1)),$(SERVICE_M_CLI_GO_FLAGS),$(if $(filter client-daemon client-cli,$(1)),$(SERVICE_C_CLI_GO_FLAGS))))))
service_go_build_spec_field_count = $(words $(subst |, ,$(1)))
service_go_build_spec_validate = $(if $(filter 5,$(call service_go_build_spec_field_count,$(1))),,$(error invalid SERVICE_GO_BUILD_SPECS item '$(1)': expected ID|kind|output|source|env; fields must not contain whitespace))$(if $(filter $(call service_go_build_spec_kind,$(1)),$(SERVICE_GO_BUILD_KINDS)),,$(error invalid SERVICE_GO_BUILD_SPECS kind '$(call service_go_build_spec_kind,$(1))' in item '$(1)': expected one of $(SERVICE_GO_BUILD_KINDS)))
define service_go_build_spec_defaults
SERVICE_GO_BUILD_OUT_$(call service_go_build_spec_name,$(1)) ?= $(call service_go_build_spec_out,$(1))
SERVICE_GO_BUILD_SRC_$(call service_go_build_spec_name,$(1)) ?= $(call service_go_build_spec_src,$(1))
SERVICE_GO_BUILD_ENV_$(call service_go_build_spec_name,$(1)) ?= $(call service_go_build_spec_env,$(1))
SERVICE_GO_BUILD_FLAGS_$(call service_go_build_spec_name,$(1)) ?= $(call service_go_build_flags_for_kind,$(call service_go_build_spec_kind,$(1)))
endef
$(foreach spec,$(SERVICE_GO_BUILD_SPECS),$(call service_go_build_spec_validate,$(spec)))
$(foreach spec,$(SERVICE_GO_BUILD_SPECS),$(eval $(call service_go_build_spec_defaults,$(spec))))
SERVICE_GO_BUILD_ARTIFACTS ?= $(foreach spec,$(SERVICE_GO_BUILD_SPECS),$(call service_go_build_spec_name,$(spec)))
SERVICE_GO_BUILD_OUTPUTS = $(strip $(foreach artifact,$(SERVICE_GO_BUILD_ARTIFACTS),$(SERVICE_GO_BUILD_OUT_$(artifact))))
SERVICE_GO_BUILD_TARGETS := $(addprefix .service-go-build-,$(SERVICE_GO_BUILD_ARTIFACTS))
SERVICE_PLUGIN_REQUIRED_EXTRA_ARTIFACTS ?= $(BUILD_SVC_CLIENTS_DIR)/client.conf
SERVICE_PLUGIN_REQUIRED_ARTIFACTS ?= $(strip $(SERVICE_GO_BUILD_OUTPUTS) $(SERVICE_PLUGIN_REQUIRED_EXTRA_ARTIFACTS))
SERVICE_ARTIFACT_COPY_SPECS ?=
SERVICE_DEBIAN_REQUIRED_ARTIFACTS ?=
SERVICE_DEBIAN_PACKAGE_COPY_SPECS ?=
SERVICE_LOCAL_MAKE_SPECS ?=
service_local_make_spec_field = $(word $(2),$(subst |, ,$(1)))
service_local_make_spec_name = $(call service_local_make_spec_field,$(1),1)
define service_local_make_spec_defaults
SERVICE_LOCAL_MAKE_DIR_$(call service_local_make_spec_name,$(1)) ?= $(call service_local_make_spec_field,$(1),2)
SERVICE_LOCAL_MAKE_GOAL_$(call service_local_make_spec_name,$(1)) ?= $(call service_local_make_spec_field,$(1),3)
endef
$(foreach spec,$(SERVICE_LOCAL_MAKE_SPECS),$(eval $(call service_local_make_spec_defaults,$(spec))))
SERVICE_LOCAL_MAKE_TARGETS ?= $(foreach spec,$(SERVICE_LOCAL_MAKE_SPECS),$(call service_local_make_spec_name,$(spec)))
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
define service_utils_shell_detect_dry_run
dry_run=0; \
scan_make_options=1; \
case "$$-" in *n*) dry_run=1 ;; esac; \
for make_flag in $$MAKEFLAGS $$MFLAGS; do \
	[ "$$scan_make_options" = "1" ] || continue; \
	case "$$make_flag" in \
		--) scan_make_options=0 ;; \
		--just-print|--dry-run|--recon) dry_run=1 ;; \
		--*) ;; \
		*=*) ;; \
		-*) case "$${make_flag#-}" in *n*) dry_run=1 ;; esac ;; \
		*) case "$$make_flag" in *n*) dry_run=1 ;; esac ;; \
	esac; \
done
endef
define service_utils_shell_detect_dry_run_eval
dry_run=0; \
scan_make_options=1; \
case "$$$$-" in *n*) dry_run=1 ;; esac; \
for make_flag in $$$$MAKEFLAGS $$$$MFLAGS; do \
	[ "$$$$scan_make_options" = "1" ] || continue; \
	case "$$$$make_flag" in \
		--) scan_make_options=0 ;; \
		--just-print|--dry-run|--recon) dry_run=1 ;; \
		--*) ;; \
		*=*) ;; \
		-*) case "$$$${make_flag#-}" in *n*) dry_run=1 ;; esac ;; \
		*) case "$$$$make_flag" in *n*) dry_run=1 ;; esac ;; \
	esac; \
done
endef

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
