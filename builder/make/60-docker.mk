# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Docker Image Handling ##

DOCKER_BUILD_PRE_TARGETS ?=
DOCKER_BUILD_INPUT_CHECK_TARGETS ?= .check-docker-build-inputs

build-docker: require-build-manifest $(DOCKER_BUILD_PRE_TARGETS) $(DOCKER_BUILD_INPUT_CHECK_TARGETS)
	@if [ -z "$(strip $(DOCKER_IMAGE_BUILD_SPECS))" ]; then \
		echo "ERROR: DOCKER_IMAGE_BUILD_SPECS is empty."; \
		exit 1; \
	fi
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	docker_build_args="$(DEP_DOCKER_BUILD_ARGS)"; \
	docker_build_args="$${docker_build_args//@VERSION_BUILD@/$$version_build}"; \
	for spec in $(DOCKER_IMAGE_BUILD_SPECS); do \
		image=$${spec%%:*}; \
		dockerfile=$${spec#*:}; \
		case "$$image" in ""|*[^A-Za-z0-9._/-]*) echo "ERROR: invalid Docker image name in DOCKER_IMAGE_BUILD_SPECS: $$image"; exit 2 ;; esac; \
		if [ "$$dockerfile" = "$$spec" ] || [ -z "$$dockerfile" ] || [ ! -f "$$dockerfile" ]; then \
			echo "ERROR: invalid Dockerfile in DOCKER_IMAGE_BUILD_SPECS item '$$spec'."; \
			exit 2; \
		fi; \
		echo ""; \
		echo "Building docker image: $$image:$$version_build"; \
		echo "Dockerfile: $$dockerfile; BUILD_ARGS: $$docker_build_args"; \
		docker buildx build \
			--progress=plain \
			--platform linux/amd64 \
			--load \
			-f "$$dockerfile" \
			$$docker_build_args \
			-t "$$image:$$version_build" \
			.; \
		echo "Successfully built docker image for $$image/$$version_build"; \
		echo ""; \
	done; \
	$(BUILD_MANIFEST_CMD) commit-lane \
		--lane docker \
		$(BUILD_MANIFEST_COMMON_ARGS) \
		--version-build "$$version_build"

.docker-build-image: .require-version-build-var
	$(call func_build_docker,$(IMAGE),$(VERSION_BUILD),$(DOCKERFILE),$(DEP_DOCKER_BUILD_ARGS))

DOCKER_PUSH_CHECK_TARGETS ?= .check-docker-release-mode .check-docker-publish-images
DOCKER_PUSH_VERSION ?= $(VERSION_BUILD)
DOCKER_PUSH_LATEST ?= $(if $(filter pro,$(BUILD_MODE)),yes,no)

.check-docker-release-mode:
	$(call func_check_release_mode)

.check-docker-build-inputs:
	@set -e; \
	version_build="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	missing=0; \
	for file_template in $(SERVICE_DOCKER_REQUIRED_ARTIFACTS); do \
		file="$${file_template//@VERSION_BUILD@/$$version_build}"; \
		if [ ! -f "$$file" ]; then \
			echo "Missing Docker input: $$file"; \
			missing=1; \
		fi; \
	done; \
	for glob_template in $(SERVICE_DOCKER_REQUIRED_GLOBS); do \
		glob="$${glob_template//@VERSION_BUILD@/$$version_build}"; \
		if matches="$$(compgen -G "$$glob" 2>&1)"; then \
			:; \
		elif [ -n "$$matches" ]; then \
			echo "ERROR: Docker input glob probe failed for $$glob"; \
			echo "$$matches"; \
			missing=1; \
		fi; \
		if [ -z "$$matches" ]; then \
			echo "Missing Docker input: $$glob"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" = "1" ]; then \
		echo "ERROR: Docker inputs for $$version_build are incomplete."; \
		echo "Expected version source: $(BUILD_MANIFEST_FILE)"; \
		echo "Run 'make $(SERVICE_ARTIFACT_BUILD_TARGET) && make build-debian' first, or 'make build-all' for the full local build."; \
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

# $(1): IMAGE_NAME
# $(2): VERSION
# $(3): DOCKERFILE
# $(4): BUILD_ARGS string
define func_build_docker
	@echo ""
	@echo "Building docker image: $(1):$(2)"
	@set -e; \
	docker_build_args="$(4)"; \
	docker_build_args="$${docker_build_args//@VERSION_BUILD@/$(2)}"; \
	echo "Dockerfile: $(3); BUILD_ARGS: $$docker_build_args"; \
	docker buildx build \
		--progress=plain \
		--platform linux/amd64 \
		--load \
		-f $(3) \
		$$docker_build_args \
		-t $(1):$(2) \
		.
	@echo "Successfully built docker image for $(1)/$(2)"
	@echo ""
endef

#------------------------------------------------------------------------------#
