# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

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
	.check-local-start \
	.check-prepare-start \
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
	.service-docs-stage \
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
	.check-docker-build-inputs \
	build-fresh \
	build-init \
	build-prepare \
	debian \
	docker

# Build identity and manifest mutation make these lifecycle targets serial.
# Public check/report targets are also serialized so readable output does not
# interleave when callers use parallel Make.
.NOTPARALLEL: check check-prepare check-vars check-build check-version check-go-mod check-service-builder-base build build-plugin build-fresh build-debian build-docker

# Build the required builder base image. Run this on a fresh build host or when
# builder/toolchain/dependency inputs change.
prepare: .check_service_utils_version_file prepare-service-builder-base
	@echo "Successfully built base image."
	@echo

# Check target taxonomy:
# - check: canonical local readiness aggregate for humans/agents.
# - check-prepare: build-readiness bundle used by lifecycle and workflow targets.
# - check-vars: redacted inventory only.
# Extension contract:
# - CHECK_VERSION_ROWS and CHECK_BUILD_ROWS replace the default identity rows.
# - CHECK_VERSION_EXTRA_ROWS and CHECK_BUILD_EXTRA_ROWS append rows to the
#   active identity sections.
service_utils_check_prepare_targets := check-version check-go-mod check-build check-service-builder-base
CHECK_BUILD_EXTRA_ROWS ?=
CHECK_VERSION_EXTRA_ROWS ?=
export CHECK_BUILD_ROWS CHECK_VERSION_ROWS CHECK_BUILD_EXTRA_ROWS CHECK_VERSION_EXTRA_ROWS

# Root Makefiles own public `init` so missing service-utils can be repaired
# before this shared builder is included. This target owns post-bootstrap checks.
service-utils-init: .check_service_utils_version_file .check_build_vars update_service_utils
	@$(MAKE) --no-print-directory check-build

# `push-all` is Make-only artifact publication. Release validation and handoff
# remain outside the generic builder and should consume the published outputs.
push-all: push-docker push-debian

check: .check-local-start check-prepare
	@echo ">> Local Check: [PASS]"

.check-local-start:
	@echo ">> Local Check"; \
	printf "  %15s : %s\n" "Scope" "version identity, manifest state, Go module compatibility, builder image"; \
	echo ""

check-prepare: .check-prepare-start $(service_utils_check_prepare_targets)
	@echo ">> Local Readiness: [PASS]"

.check-prepare-start:
	@echo ">> Local Readiness"; \
	printf "  %15s : %s\n" "Targets" "$(strip $(service_utils_check_prepare_targets))"; \
	echo ""

define service_utils_lifecycle_targets
## `build-all` is the only legacy spelling kept, and it is a plain alias for
## `build` in service repositories that use the shared lifecycle directly.
build-all: build

build: prepare build-plugin build-debian build-docker

build-fresh: clean prepare build-plugin build-debian build-docker
	@echo "Built fresh artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

build-plugin: check proto-gen
	@set -e; \
	$(service_utils_shell_detect_dry_run_eval); \
	if [ "$$$$dry_run" = "1" ]; then \
		version_build="DRY-RUN-VERSION"; \
		echo ">> Build Plugin Version"; \
		printf "  %15s : %s\n" "Version" "$$$$version_build"; \
		exit 0; \
	else \
		version_build="$$$$($(BUILD_MANIFEST_CMD) reserve-plugin-version $(BUILD_MANIFEST_RESERVE_ARGS))"; \
	fi; \
	clear_reserved_build() { \
		if ! clear_output="$$$$($(BUILD_MANIFEST_CMD) clear-reserved-plugin-version $(BUILD_MANIFEST_RESERVE_ARGS) --version-build "$$$$version_build" 2>&1)"; then \
			echo "WARN: failed to clear reserved DEV build version $$$$version_build after build failure." >&2; \
			printf '%s\n' "$$$$clear_output" >&2; \
		fi; \
	}; \
	trap 'status=$$$$?; if [ "$$$$status" -ne 0 ]; then clear_reserved_build; fi; exit "$$$$status"' EXIT; \
	mkdir -p "$(BUILD_DIR)"; \
	echo ">> Build Plugin Version"; \
	printf "  %15s : %s\n" "Version" "$$$$version_build"; \
	$$(MAKE) --no-print-directory service-build-plugin VERSION_BUILD="$$$$version_build"; \
	if service_utils_ref="$$$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD 2>&1)"; then \
		:; \
	else \
		echo "WARN: could not resolve service-utils git ref: $$$$service_utils_ref" >&2; \
		service_utils_ref="unknown"; \
	fi; \
	$$(BUILD_MANIFEST_CMD) commit-plugin \
		$$(BUILD_MANIFEST_COMMIT_PLUGIN_ARGS) \
		--version-build "$$$$version_build" \
		--service-utils-ref "$$$$service_utils_ref"; \
	trap - EXIT
	@echo "Built artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo
endef
$(eval $(service_utils_lifecycle_targets))

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
