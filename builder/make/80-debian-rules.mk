# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

###
# Generic deb input check rule: check-deb-<service>
check-deb-%:
	$(eval SERVICE_NAME := $*)
	$(eval SERVICE_CONFIG := debian/deb.$(SERVICE_NAME).config)
	$(eval SERVICE_CONTROL := debian/deb.$(SERVICE_NAME).control)
	$(if $(wildcard $(SERVICE_CONFIG)),$(eval include $(SERVICE_CONFIG)))
	@$(DEBIAN_PACKAGE_CMD) check --service "$(SERVICE_NAME)" --config "$(SERVICE_CONFIG)" --control "$(SERVICE_CONTROL)" --files "$(DEBIAN_FILES)"

REMOVED_TARGET_REPLACEMENT_build-init := init
REMOVED_TARGET_REPLACEMENT_build-prepare := prepare
REMOVED_TARGET_REPLACEMENT_debian := build-debian
REMOVED_TARGET_REPLACEMENT_docker := build-docker

build-init build-prepare debian docker:
	@echo "ERROR: make $@ has been removed."
	@echo "Use 'make $(REMOVED_TARGET_REPLACEMENT_$@)'."
	@exit 2

###
# Generic deb packaging rule: deb-<service>
deb-%: check-deb-%
	$(eval SERVICE_NAME := $*)
	$(eval SERVICE_CONFIG := debian/deb.$(SERVICE_NAME).config)
	$(eval SERVICE_CONTROL := debian/deb.$(SERVICE_NAME).control)
	$(if $(wildcard $(SERVICE_CONFIG)),$(eval include $(SERVICE_CONFIG)))
	@$(DEBIAN_PACKAGE_CMD) build --service "$(SERVICE_NAME)" --config "$(SERVICE_CONFIG)" --control "$(SERVICE_CONTROL)" --files "$(DEBIAN_FILES)" --debian-path "$(DEBIAN_PATH)" --version-build "$(VERSION_BUILD)" --depends-version "$(DEP_VERSION_ASN)"


clean-deb-%:
	$(call service_utils_assert_build_paths,$(DEBIAN_PATH),DEBIAN_PATH)
	@set -e; \
	stem="$*"; \
	case "$$stem" in \
		""|"."|".."|*..*|*[^A-Za-z0-9._-]*) \
			echo "ERROR: refusing unsafe Debian clean target stem: '$$stem'."; \
			exit 2 ;; \
	esac; \
	path="$(DEBIAN_PATH)/$$stem"; \
	case "$$path" in \
		build/*|./build/*) echo "Cleaning $$path..."; rm -rf "$$path" ;; \
		*) echo "ERROR: refusing Debian clean path outside build/: $$path"; exit 2 ;; \
	esac
