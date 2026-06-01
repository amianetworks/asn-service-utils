# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Shared builder defaults and service contract expansion.
##
## Keep target recipes in the topic files. This file owns reusable defaults and
## low-level Make helpers consumed by the rest of the shared builder.

## Shared builder target taxonomy.
##
## Public targets are the stable Make entry points consuming service repositories
## can expect after including service.plugin.builder.mk. Public pattern targets
## are stable selectors for configured publish/list sites. Internal targets are
## implementation details for builder recipes and should not be copied into new
## service Makefiles. Removed targets are compatibility shims that print the
## supported replacement.
SERVICE_UTILS_PUBLIC_TARGETS := \
	prepare \
	build \
	build-all \
	build-fresh \
	clean \
	check \
	check-prepare \
	check-vars \
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
	build-plugin \
	build-debian \
	build-docker \
	clean-debian \
	clean-docker \
	set-version \
	plan-push \
	plan-push-docker \
	plan-push-debian \
	push-all \
	push-docker \
	push-docker-cn \
	push-docker-us \
	push-debian \
	push-debian-cn \
	push-debian-us \
	list-docker \
	list-docker-local \
	list-docker-cn \
	list-docker-us \
	list-debian \
	list-debian-local \
	list-debian-cn \
	list-debian-us

SERVICE_UTILS_PUBLIC_PATTERN_TARGETS := \
	push-docker-% \
	push-debian-% \
	list-docker-% \
	list-debian-%

SERVICE_UTILS_COMPAT_TARGETS := \
	build-init \
	build-prepare \
	debian \
	docker

SERVICE_UTILS_INTERNAL_TARGETS := \
	service-utils-init \
	.check-local-start \
	.check-prepare-start \
	.deps-update-standalone \
	.service-docs-stage \
	require-build-manifest \
	.build-manifest-require-lane \
	.build-manifest-value \
	check-go-mod \
	check-debian-inputs \
	check-push-debian-sites \
	check-push-docker-sites \
	service-build-plugin \
	service-build-debian \
	service-build-from-scratch \
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
	.print-publish-profile-var \
	.print-docker-push-var \
	.print-debian-push-var \
	.check-docker-release-mode \
	.check-debian-release-mode \
	.check-docker-publish-images \
	.check-debian-publish-packages \
	.check-docker-build-inputs

uppercase = $(strip $(subst z,Z,$(subst y,Y,$(subst x,X,$(subst w,W,$(subst v,V,$(subst u,U,$(subst t,T,$(subst s,S,$(subst r,R,$(subst q,Q,$(subst p,P,$(subst o,O,$(subst n,N,$(subst m,M,$(subst l,L,$(subst k,K,$(subst j,J,$(subst i,I,$(subst h,H,$(subst g,G,$(subst f,F,$(subst e,E,$(subst d,D,$(subst c,C,$(subst b,B,$(subst a,A,$(1))))))))))))))))))))))))))))
lowercase = $(strip $(subst Z,z,$(subst Y,y,$(subst X,x,$(subst W,w,$(subst V,v,$(subst U,u,$(subst T,t,$(subst S,s,$(subst R,r,$(subst Q,q,$(subst P,p,$(subst O,o,$(subst N,n,$(subst M,m,$(subst L,l,$(subst K,k,$(subst J,j,$(subst I,i,$(subst H,h,$(subst G,g,$(subst F,f,$(subst E,e,$(subst D,d,$(subst C,c,$(subst B,b,$(subst A,a,$(1))))))))))))))))))))))))))))

define func_check_release_mode
	@set -e; \
	case "$(BUILD_MODE)" in \
		dev|pro) : ;; \
		*) echo "ERROR: BUILD_MODE must be dev or pro for publish targets, got '$(BUILD_MODE)'."; exit 2 ;; \
	esac
endef

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

BUILD_DIR ?= build
SERVICE_BUILD_DIR_C ?= $(BUILD_DIR)/controller
SERVICE_BUILD_DIR_SN ?= $(BUILD_DIR)/servicenode
SERVICE_BUILD_DIR_CLIENT ?= $(BUILD_DIR)/client
DEBIAN_PATH ?= $(BUILD_DIR)/debian
SERVICE_DEBIAN_PACKAGES ?= $(strip \
	$(SERVICE_PACKAGE_C) \
	$(SERVICE_PACKAGE_SN) \
	$(SERVICE_PACKAGE_C_CLI) \
	$(SERVICE_PACKAGE_CLIENT))
DEBIAN_SERVICES ?= $(SERVICE_DEBIAN_PACKAGES)
SERVICE_DOCKER_COMPONENTS ?= C SN
SERVICE_DOCKER_IMAGES ?= $(strip $(SERVICE_DOCKER_IMAGE_C) $(SERVICE_DOCKER_IMAGE_SN))
DOCKER_IMAGES ?= $(SERVICE_DOCKER_IMAGES)

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
BUILD_MANIFEST_CORE_ARGS ?= \
	--manifest "$(BUILD_MANIFEST_FILE)" \
	--mode "$(BUILD_MODE)" \
	--version "$(VERSION)" \
	--build "$(BUILD)" \
	--debian-dir "$(DEBIAN_PATH)" \
	--debian-services "$(DEBIAN_SERVICES)" \
	--docker-images "$(DOCKER_IMAGES)" \
	--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
	--asn-version "$(ASN_VERSION)" \
	--dep-version-asn "$(DEP_VERSION_ASN)" \
	--go-version "$(GO_VERSION)" \
	--dep-version-go "$(DEP_VERSION_GO)"
BUILD_MANIFEST_COMMON_EXTRA_ARGS ?= $(BUILD_MANIFEST_DEFAULT_DOCS_ARGS)
BUILD_MANIFEST_COMMON_ARGS ?= $(BUILD_MANIFEST_CORE_ARGS) --docs-dir "$(CURDIR)/build/docs" $(BUILD_MANIFEST_ARGS) $(BUILD_MANIFEST_COMMON_EXTRA_ARGS)
BUILD_MANIFEST_RESERVE_ARGS ?= --version "$(VERSION)" --mode "$(BUILD_MODE)" --build "$(BUILD)" --dev-start "$(BUILD_DEV)" --dev-file "$(DEV_BUILD_FILE)" --manifest "$(BUILD_MANIFEST_FILE)" $(BUILD_MANIFEST_ARGS)
BUILD_MANIFEST_COMMIT_PLUGIN_ARGS ?= $(BUILD_MANIFEST_COMMON_ARGS) --dev-start "$(BUILD_DEV)" --dev-file "$(DEV_BUILD_FILE)"
BUILD_MANIFEST_STAGE_DOCS_EXTRA_ARGS ?= $(BUILD_MANIFEST_ARGS)
BUILD_MANIFEST_STAGE_DOCS_ARGS ?= $(BUILD_MANIFEST_CORE_ARGS) --docs-dir "$(STAGE_DOCS_DIR)" $(BUILD_MANIFEST_STAGE_DOCS_EXTRA_ARGS) --docs-required-artifacts "$(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml $(STAGE_DOCS_DIR)/release/DocsChecksums.tsv $(STAGE_DOCS_DIR)/index.html" --docs-version-file "$(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml" --docs-version-key "$(SERVICE_DOCS_VERSION_KEY)"
# Build identity is shared builder state. If the caller did not pass
# VERSION_BUILD explicitly, leave it empty here and let recipes query
# build_manifest.sh with fail-visible shell commands. Parse-time $(shell ...)
# calls cannot propagate exit status, which makes manifest failures easy to miss.
VERSION_BUILD ?=
SERVICE_BUILD_CLEAN_DIRS ?=
SERVICE_BUILD_DIRS ?= $(SERVICE_BUILD_CLEAN_DIRS)
SERVICE_CLEAN_DIRS ?= build/
CHECK_LOCAL_EXTRA_TARGETS ?=
CHECK_PREPARE_EXTRA_TARGETS ?=
# Set this in the consuming service before including service.plugin.builder.mk
# when build-debian needs service-local producer prerequisites.
SERVICE_BUILD_DEBIAN_PREREQS ?=
SERVICE_GO_ARTIFACTS ?=
SERVICE_FILE_ARTIFACTS ?=
SERVICE_BUILD_ARTIFACTS = $(strip $(SERVICE_GO_ARTIFACTS) $(SERVICE_FILE_ARTIFACTS))
service_go_artifact_output = $(word 1,$($(1)))
service_go_artifact_source = $(word 2,$($(1)))
service_go_artifact_env = $(if $(filter -,$(word 3,$($(1)))),,$(word 3,$($(1))))
service_go_artifact_flags = $(if $(filter -,$(word 4,$($(1)))),$(wordlist 5,$(words $($(1))),$($(1))),$(wordlist 4,$(words $($(1))),$($(1))))
service_go_artifact_validate = $(if $(strip $(1)),,$(error invalid SERVICE_GO_ARTIFACTS entry: empty artifact id))$(if $(strip $($(1))),,$(error $(1) is required))$(if $(strip $(call service_go_artifact_output,$(1))),,$(error $(1) output is required))$(if $(strip $(call service_go_artifact_source,$(1))),,$(error $(1) source is required))$(if $(word 3,$($(1))),,$(error $(1) env is required; use - when empty))$(if $(word 4,$($(1))),,$(error $(1) flags are required; use - when empty))
service_file_artifact_source = $(word 1,$($(1)))
service_file_artifact_dest = $(word 2,$($(1)))
service_file_artifact_output = $(if $(findstring *,$(call service_file_artifact_source,$(1))),,$(call service_file_artifact_dest,$(1))/$(notdir $(call service_file_artifact_source,$(1))))
service_file_artifact_glob = $(if $(findstring *,$(call service_file_artifact_source,$(1))),$(call service_file_artifact_dest,$(1))/$(notdir $(call service_file_artifact_source,$(1))))
service_file_artifact_validate = $(if $(strip $(1)),,$(error invalid SERVICE_FILE_ARTIFACTS entry: empty artifact id))$(if $(strip $($(1))),,$(error $(1) is required))$(if $(strip $(call service_file_artifact_source,$(1))),,$(error $(1) source is required))$(if $(strip $(call service_file_artifact_dest,$(1))),,$(error $(1) destination is required))
$(foreach artifact,$(SERVICE_GO_ARTIFACTS),$(call service_go_artifact_validate,$(artifact)))
$(foreach artifact,$(SERVICE_FILE_ARTIFACTS),$(call service_file_artifact_validate,$(artifact)))
SERVICE_BUILD_GO_OUTPUTS = $(strip $(foreach artifact,$(SERVICE_GO_ARTIFACTS),$(call service_go_artifact_output,$(artifact))))
SERVICE_BUILD_FILE_OUTPUTS = $(strip $(foreach artifact,$(SERVICE_FILE_ARTIFACTS),$(call service_file_artifact_output,$(artifact))))
SERVICE_BUILD_FILE_GLOBS = $(strip $(foreach artifact,$(SERVICE_FILE_ARTIFACTS),$(call service_file_artifact_glob,$(artifact))))
SERVICE_BUILD_ARTIFACT_TARGETS := $(addprefix .service-build-artifact-,$(SERVICE_BUILD_ARTIFACTS))
SERVICE_PLUGIN_REQUIRED_ARTIFACTS ?= $(strip $(SERVICE_BUILD_GO_OUTPUTS) $(SERVICE_BUILD_FILE_OUTPUTS))
SERVICE_PLUGIN_REQUIRED_GLOBS ?= $(SERVICE_BUILD_FILE_GLOBS)
SERVICE_GO_CACHE_SPECS ?=
service_go_cache_spec = $(if $($(1)),$($(1)),$(1))
SERVICE_GO_CACHE_PACKAGES ?= $(or $(strip $(foreach spec,$(SERVICE_GO_CACHE_SPECS),$(call service_go_cache_spec,$(spec)))),./...)
STAGE_DOCS_CMD ?= bash $(SERVICE_UTILS_DIR)/builder/stage_docs.sh
STAGE_DOCS_DIR ?= $(CURDIR)/build/docs
STAGE_DOCS_REPORT_FILE ?=
SERVICE_DOCS_REQUIRED_ARTIFACTS ?= $(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml $(STAGE_DOCS_DIR)/release/DocsChecksums.tsv $(STAGE_DOCS_DIR)/index.html
SERVICE_DOCS_VERSION_FILE ?= $(STAGE_DOCS_DIR)/release/ReleaseManifest.yaml
SERVICE_DOCS_VERSION_KEY ?= $(SERVICE_NAME)_version_build
SERVICE_DOCS_VERSION_LABEL ?= $(or $(SERVICE),$(SERVICE_NAME)) Version Build
SERVICE_DOCS_SOURCE_KEY ?= $(SERVICE_NAME)_source_commit
SERVICE_DOCS_SERVED_KEY ?= docs_served_by_service
SERVICE_DOCS_RUNTIME_ROOT_KEY ?= docs_runtime_root
SERVICE_DOCS_RUNTIME_ROOT ?= /var/www/$(SERVICE_NAME)
service_utils_docs_package_root = $(patsubst /%,%,$(SERVICE_DOCS_RUNTIME_ROOT))
SERVICE_DOCS_STAGE_MANIFEST ?= docs/service-docs.tsv
SERVICE_DOCS_ROUTES ?= /docs/
SERVICE_DOCS_INDEX_LINKS ?=
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

.PHONY: $(SERVICE_BUILD_ARTIFACT_TARGETS)
