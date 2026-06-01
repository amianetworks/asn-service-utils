# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Debian Package handling ##

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

# Build Debian packages from existing plugin artifacts.
build-debian: require-build-manifest check check-debian-inputs clean-debian
	@$(service_utils_shell_detect_dry_run); \
	if [ "$$dry_run" = "1" ]; then \
			echo ">> Build Debian Packages"; \
			printf "  %15s : %s\n" "Version" "DRY-RUN-VERSION"; \
			printf "  %15s : %s\n" "Output" "$(DEBIAN_PATH)"; \
			echo; \
			exit 0; \
	fi; \
	set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane plugin $(BUILD_MANIFEST_COMMON_ARGS))"; \
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
		build|build/|build/*|./build|./build/|./build/*) \
			mkdir -p build; \
			build_abs="$$(cd build && pwd -P)"; \
			if [ -e "$$path" ]; then \
				path_parent="$$(dirname "$$path")"; \
				mkdir -p "$$path_parent"; \
				path_parent_abs="$$(cd "$$path_parent" && pwd -P)"; \
				path_abs="$$path_parent_abs/$$(basename "$$path")"; \
				case "$$path_abs/" in "$$build_abs"/*) : ;; *) echo "ERROR: Debian clean path escapes real build directory: $$path"; exit 2 ;; esac; \
			fi; \
			rm -rf "$$path" ;; \
		*) echo "ERROR: refusing Debian clean path outside build/: $$path"; exit 2 ;; \
	esac

check-debian-inputs:
	@set +e; \
	output="$$( $(MAKE) --no-print-directory -s check.deb 2>&1 )"; \
	status="$$?"; \
	if [ -n "$$output" ]; then \
		printf "%s\n" "$$output" | sed '/^make\[[0-9][0-9]*\]: \*\*\*/d;/^make: \*\*\*/d'; \
	fi; \
	exit "$$status"

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
