# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

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

define service_utils_owned_set_version_target
set-version: check-build
	@echo "Modify make/config.mk to update the version and build."
	@echo "NOTE: Only CI/CD or maintainer should change the version with caution."
endef
$(if $(filter yes,$(SERVICE_UTILS_OWN_SET_VERSION_TARGET)),$(eval $(service_utils_owned_set_version_target)))

increment-build:
	@echo "ERROR: make increment-build has been removed."
	@echo "$(SERVICE_ARTIFACT_BUILD_TARGET) now commits $(DEV_BUILD_FILE) only after artifacts build successfully."
	@exit 2

