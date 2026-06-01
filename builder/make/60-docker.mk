# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Docker Image Handling ##

service_utils_docker_components := $(SERVICE_DOCKER_COMPONENTS)
service_utils_docker_build_args = $(addprefix --build-arg ,$(SERVICE_DOCKER_BUILD_ARGS))
service_utils_docker_package_file_func = service_docker_package_file() { printf '%s/%s_%s_amd64.deb\n' "$(DEBIAN_PATH)" "$$1" "$$version_build"; };

define service_utils_docker_build_component
image="$(strip $(SERVICE_DOCKER_IMAGE_$(1)))"; \
dockerfile="$(strip $(SERVICE_DOCKERFILE_$(1)))"; \
package="$(strip $(SERVICE_PACKAGE_$(1)))"; \
if [ -n "$$image$$dockerfile$$package" ]; then \
	[ -n "$$image" ] || { echo "ERROR: SERVICE_DOCKER_IMAGE_$(1) is required when SERVICE_DOCKERFILE_$(1) or SERVICE_PACKAGE_$(1) is set."; exit 2; }; \
	case "$$image" in ""|*[^A-Za-z0-9._/-]*) echo "ERROR: invalid SERVICE_DOCKER_IMAGE_$(1): $$image"; exit 2 ;; esac; \
	[ -n "$$dockerfile" ] || { echo "ERROR: SERVICE_DOCKERFILE_$(1) is required for $$image."; exit 2; }; \
	if [ ! -f "$$dockerfile" ]; then echo "ERROR: SERVICE_DOCKERFILE_$(1) does not exist: $$dockerfile"; exit 2; fi; \
	image_build_args="$$docker_build_args"; \
	if [ -n "$$package" ]; then \
		case "$$package" in *:*|*[^A-Za-z0-9+._-]*) echo "ERROR: invalid SERVICE_PACKAGE_$(1): $$package"; exit 2 ;; esac; \
		debian_file="$$(service_docker_package_file "$$package")"; \
		image_build_args="$$image_build_args --build-arg SERVICE_PACKAGE=$$package --build-arg SERVICE_DEBIAN_FILE=$$debian_file"; \
	fi; \
	echo ""; \
	echo "Building docker image: $$image:$$version_build"; \
	echo "Dockerfile: $$dockerfile; BUILD_ARGS: $$image_build_args"; \
	docker buildx build \
		--progress=plain \
		--platform linux/amd64 \
		--load \
		-f "$$dockerfile" \
		$$image_build_args \
		-t "$$image:$$version_build" \
		.; \
	echo "Successfully built docker image for $$image/$$version_build"; \
	echo ""; \
fi;
endef

# Docker images consume the manifest-owned Debian lane. The Docker build command
# will fail naturally if a declared package file has been removed after the lane
# was committed; the preflight contract itself is the manifest.
build-docker: require-build-manifest
	@if [ -z "$(strip $(DOCKER_IMAGES))" ]; then \
		echo "ERROR: no service Docker images are configured."; \
		exit 1; \
	fi
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	$(service_utils_docker_package_file_func) \
	docker_build_args="$(service_utils_docker_build_args)"; \
	docker_build_args="$${docker_build_args//@VERSION_BUILD@/$$version_build}"; \
	$(foreach component,$(service_utils_docker_components),$(call service_utils_docker_build_component,$(component))) \
	$(BUILD_MANIFEST_CMD) commit-lane \
		--lane docker \
		$(BUILD_MANIFEST_COMMON_ARGS) \
		--version-build "$$version_build"

DOCKER_PUSH_VERSION ?= $(VERSION_BUILD)
DOCKER_PUSH_LATEST ?= $(if $(filter pro,$(BUILD_MODE)),yes,no)

.check-docker-release-mode:
	$(call func_check_release_mode)

.check-docker-build-inputs:
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	printf ">> Docker Inputs\n"; \
	printf "  %15s : %s (%s)\n" "Version" "$$version_build" "trusted from $(BUILD_MANIFEST_FILE)"

.check-docker-publish-images:
	@set -e; \
	selected_version="$(DOCKER_PUSH_VERSION)"; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane docker $(BUILD_MANIFEST_COMMON_ARGS))"; \
	if [ -z "$$selected_version" ]; then \
		selected_version="$$version_build"; \
	elif [ "$$selected_version" != "$$version_build" ]; then \
		echo "check_publish_inputs ERROR: selected docker version '$$selected_version' does not match manifest version '$$version_build'." >&2; \
		echo "Manifest: $(BUILD_MANIFEST_FILE)" >&2; \
		exit 1; \
	fi

include $(SERVICE_UTILS_DIR)/builder/docker.registry.mk
include $(SERVICE_UTILS_DIR)/builder/release.preflight.mk

#------------------------------------------------------------------------------#
