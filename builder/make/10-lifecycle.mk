# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Main targets ##
## Project-owned Makefiles define service variables and include this shared
## builder. Helper targets below own the common build, package, publish, and
## validation mechanics.

.PHONY: \
	$(SERVICE_UTILS_PUBLIC_TARGETS) \
	$(SERVICE_UTILS_PUBLIC_PATTERN_TARGETS) \
	$(SERVICE_UTILS_COMPAT_TARGETS) \
	$(SERVICE_UTILS_INTERNAL_TARGETS)

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
service_utils_manifest_producer_targets := check-version check-go-mod check-service-builder-base
service_utils_check_prepare_targets := $(service_utils_manifest_producer_targets) check-build $(CHECK_PREPARE_EXTRA_TARGETS)
service_utils_check_targets := check-prepare $(CHECK_LOCAL_EXTRA_TARGETS)
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

check: .check-local-start $(service_utils_check_targets)
	@echo ">> Local Check: [PASS]"

.check-local-start:
	@echo ">> Local Check"; \
	printf "  %15s : %s\n" "Scope" "version identity, manifest state, Go module compatibility, builder image"; \
	if [ -n "$(strip $(CHECK_LOCAL_EXTRA_TARGETS))" ]; then printf "  %15s : %s\n" "Extra Targets" "$(strip $(CHECK_LOCAL_EXTRA_TARGETS))"; fi; \
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

build-plugin: $(service_utils_manifest_producer_targets) proto-gen
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
# Consumers that own their build/build-all/build-fresh/build-plugin lifecycle
# can set SERVICE_UTILS_DEFINE_BUILD_LIFECYCLE := 0 before including this
# builder to suppress these shared definitions. The ASN Framework repo uses
# this: it builds framework artifacts (not downstream service plugins) and owns
# its own `build` rule, so leaving these defined here would make GNU Make merge
# the prerequisite lists (build would inherit build-plugin) and break the
# framework build. Default 1 preserves behavior for service repositories.
SERVICE_UTILS_DEFINE_BUILD_LIFECYCLE ?= 1
ifeq ($(SERVICE_UTILS_DEFINE_BUILD_LIFECYCLE),1)
$(eval $(service_utils_lifecycle_targets))
endif

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
