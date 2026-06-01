# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Docker Image Handling ##

service_utils_docker_components := C SN
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

define service_utils_docker_check_component
image="$(strip $(SERVICE_DOCKER_IMAGE_$(1)))"; \
dockerfile="$(strip $(SERVICE_DOCKERFILE_$(1)))"; \
package="$(strip $(SERVICE_PACKAGE_$(1)))"; \
if [ -n "$$image$$dockerfile$$package" ]; then \
	[ -n "$$image" ] || { echo "ERROR: SERVICE_DOCKER_IMAGE_$(1) is required when SERVICE_DOCKERFILE_$(1) or SERVICE_PACKAGE_$(1) is set."; exit 2; }; \
	case "$$image" in ""|*[^A-Za-z0-9._/-]*) echo "ERROR: invalid SERVICE_DOCKER_IMAGE_$(1): $$image"; exit 2 ;; esac; \
	[ -n "$$dockerfile" ] || { echo "ERROR: SERVICE_DOCKERFILE_$(1) is required for $$image."; exit 2; }; \
	if [ ! -f "$$dockerfile" ]; then echo "ERROR: SERVICE_DOCKERFILE_$(1) does not exist: $$dockerfile"; exit 2; fi; \
	if [ -n "$$package" ]; then \
		case "$$package" in *:*|*[^A-Za-z0-9+._-]*) echo "ERROR: invalid SERVICE_PACKAGE_$(1): $$package"; exit 2 ;; esac; \
		file="$$(service_docker_package_file "$$package")"; \
		if [ ! -f "$$file" ]; then \
			echo "Missing Docker package input for $$image: $$file"; \
			missing=1; \
		fi; \
	fi; \
fi;
endef

# Docker images install Debian packages derived from the service image,
# Dockerfile, and package variables.
# Services that package docs must make their Debian target produce those docs.
build-docker: require-build-manifest .check-docker-build-inputs
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
	$(service_utils_docker_package_file_func) \
	missing=0; \
	$(foreach component,$(service_utils_docker_components),$(call service_utils_docker_check_component,$(component))) \
	if [ "$$missing" = "1" ]; then \
		echo "ERROR: Docker inputs for $$version_build are incomplete."; \
		echo "Expected version source: $(BUILD_MANIFEST_FILE)"; \
		echo "Run 'make build-plugin && make build-debian' first, or 'make build-all' for the full local build."; \
		exit 1; \
	fi

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
	fi; \
	missing=""; latest=""; \
	for image in $(DOCKER_IMAGES); do \
		ref="$$image:$$selected_version"; \
		inspect_output=$$(mktemp); \
		if docker image inspect "$$ref" > "$$inspect_output" 2>&1; then \
			rm -f "$$inspect_output"; \
			:; \
		else \
			missing="$${missing}$${missing:+ }$$ref"; \
			if [ -s "$$inspect_output" ]; then \
				latest="$${latest}$${latest:+ }docker-inspect-error:$$ref"; \
				sed "s/^/Docker inspect $$ref: /" "$$inspect_output"; \
			fi; \
			rm -f "$$inspect_output"; \
			if images_output="$$(docker images --format '{{.Repository}}\t{{.Tag}}' "$$image" 2>&1)"; then \
				local_latest="$$(printf '%s\n' "$$images_output" | awk -F '\t' '$$2 != "<none>" { print $$1 ":" $$2; exit }')"; \
			else \
				if [ -n "$$images_output" ]; then printf "%s\n" "$$images_output" | sed "s/^/Docker images $$image: /"; fi; \
				local_latest="$$image:(docker unavailable)"; \
			fi; \
			[ -n "$$local_latest" ] || local_latest="$$image:(none)"; \
			latest="$${latest}$${latest:+ }$$local_latest"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo ">> Docker Publish Image Check: [FAIL]"; \
		printf "  %15s : %s (%s)\n" "Version" "$$selected_version" "from $(BUILD_MANIFEST_FILE)"; \
		printf "  %15s : %s\n" "Missing" "$$missing"; \
		printf "  %15s : %s\n" "Latest" "$$latest"; \
		exit 1; \
	fi

include $(SERVICE_UTILS_DIR)/builder/docker.registry.mk
include $(SERVICE_UTILS_DIR)/builder/release.preflight.mk

#------------------------------------------------------------------------------#
