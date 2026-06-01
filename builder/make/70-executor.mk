# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

.check_service_utils_version_file:
	@if [ ! -f "$(BUILD_ENV_ASN_VERSION_FILE)" ]; then \
		echo "ERROR: service-utils version metadata is missing: $(BUILD_ENV_ASN_VERSION_FILE)."; \
		echo "Run 'make init' to initialize or repair service-utils."; \
		exit 1; \
	fi
	@if [ -z "$(DEP_VERSION_ASN)" ] || [ -z "$(DEP_VERSION_GO)" ]; then \
		echo "ERROR: service-utils version metadata must define DEP_VERSION_ASN and DEP_VERSION_GO: $(BUILD_ENV_ASN_VERSION_FILE)."; \
		exit 1; \
	fi

BUILD_ENV_BASE_IMAGE_TAG ?= $(DEP_VERSION_ASN)
BUILD_ENV_BASE_IMAGE_REF ?= $(BUILD_ENV_BASE_IMAGE):$(BUILD_ENV_BASE_IMAGE_TAG)
SERVICE_BUILDER_GOCACHE ?= $(CURDIR)/.cache/service-builder/go-build
SERVICE_BUILDER_HELPER_FILES ?= $(SERVICE_UTILS_DIR)/builder/builder_base_image.sh
SERVICE_BUILDER_MAKEFILES ?= $(BUILD_ENV_MAKEFILE) $(wildcard $(SERVICE_UTILS_DIR)/builder/make/*.mk)
SERVICE_BUILDER_INPUT_FILES ?= go.mod go.sum $(BUILD_ENV_BASE_DOCKERFILE) $(SERVICE_BUILDER_MAKEFILES) $(BUILD_ENV_ASN_VERSION_FILE) $(SERVICE_BUILDER_HELPER_FILES)

#------------------------------------------------------------------------------#

#------------------------------------------------------------------------------#
# Prepare for base docker image to build ASN Service Plugins.
prepare-service-builder-base: .check_service_utils_version_file
	@echo "Current working directory: ${PWD}"
	@echo "Building $(BUILD_ENV_BASE_IMAGE_REF)"

	@# Buildx updates the tag in place; avoid pre-removal because Docker Desktop
	@# can hang on absent container/image names.
	@$(BUILDER_BASE_IMAGE_CMD) prepare \
		--image "$(BUILD_ENV_BASE_IMAGE_REF)" \
		--dockerfile "$(BUILD_ENV_BASE_DOCKERFILE)" \
		--context "$(CURDIR)" \
		--ssh-key "$$PRIVATE_GIT_SSH_KEY_FILE" \
		--api-version "$(ASN_SERVICE_API_VERSION)" \
		--framework-version "$(DEP_VERSION_ASN)" \
		--go-version "$(DEP_VERSION_GO)" \
		--cache-packages "$(SERVICE_GO_CACHE_PACKAGES)" \
		--input-files "$(SERVICE_BUILDER_INPUT_FILES)" \
		--platform "$(SERVICE_BUILD_DOCKER_PLATFORM)"
	@echo ""
	@echo "Successfully built $(BUILD_ENV_BASE_IMAGE_REF) as the base image."
	@echo ""
	@echo "NOTE:"
	@echo " - This base image is local build infrastructure only; do not push or share it."
	@echo " - It installs the toolchain and downloads Go modules from the service go.mod/go.sum."
	@echo " - Service source is not copied into the base image; build targets run later from the mounted workspace."
	@echo " - Rebuild each time the service API version changes."
	@echo " - Rebuild each time the service go.mod/go.sum or builder inputs change."
	@echo " - Run \`docker images | grep asn\` to list the images."
	@echo " - Run \`make build-plugin\` to build artifacts."
	@echo " - Run \`make build-debian\` to build Debian packages from artifacts."
	@echo " - Run \`make build-docker\` to build standalone docker images, for non-plugin setup."
	@echo ""

# Check the local builder base image required to build ASN Service Plugins.
# This is a local Docker image check only; never query an online registry for it.
check-service-builder-base: .check_service_utils_version_file
	@$(BUILDER_BASE_IMAGE_CMD) check \
		--image "$(BUILD_ENV_BASE_IMAGE_REF)" \
		--context "$(CURDIR)" \
		--api-version "$(ASN_SERVICE_API_VERSION)" \
		--framework-version "$(DEP_VERSION_ASN)" \
		--go-version "$(DEP_VERSION_GO)" \
		--cache-packages "$(SERVICE_GO_CACHE_PACKAGES)" \
		--input-files "$(SERVICE_BUILDER_INPUT_FILES)" \
		--platform "$(SERVICE_BUILD_DOCKER_PLATFORM)" \
		--workdir "$(SERVICE_BUILD_WORKDIR)"

define service_go_artifact_target
.service-build-artifact-$(1): .require-version-build-var
	@if [ -z "$$(strip $$(call service_go_artifact_output,$(1)))" ] || [ -z "$$(strip $$(call service_go_artifact_source,$(1)))" ]; then \
		echo "ERROR: $(1) must be '<output> <source> <env-or-> <flags-or->'."; \
		exit 2; \
	fi
	@echo "Building service artifact: $(1)"
	@$$(call service_go_artifact_env,$(1)) go build $$(call service_go_artifact_flags,$(1)) -o "$$(call service_go_artifact_output,$(1))" $$(call service_go_artifact_source,$(1))
endef
$(foreach artifact,$(SERVICE_GO_ARTIFACTS),$(eval $(call service_go_artifact_target,$(artifact))))

define service_file_artifact_target
.service-build-artifact-$(1):
	@src_pattern="$$(call service_file_artifact_source,$(1))"; \
	dest="$$(call service_file_artifact_dest,$(1))"; \
	if [ -z "$$$$src_pattern" ] || [ -z "$$$$dest" ]; then \
		echo "ERROR: $(1) must be '<source-glob> <destination-dir>'."; \
		exit 2; \
	fi; \
	echo "Building service artifact: $(1)"; \
	mkdir -p "$$$$dest"; \
	matched=0; \
	for src in $$$$src_pattern; do \
		[ -e "$$$$src" ] || continue; \
		cp -R "$$$$src" "$$$$dest"/; \
		matched=1; \
	done; \
	if [ "$$$$matched" -ne 1 ]; then \
		echo "ERROR: $(1) source matched nothing: $$$$src_pattern"; \
		exit 1; \
	fi
endef
$(foreach artifact,$(SERVICE_FILE_ARTIFACTS),$(eval $(call service_file_artifact_target,$(artifact))))

build.plugin: .require-version-build-var
	@if [ -z "$(strip $(SERVICE_BUILD_ARTIFACTS))" ]; then \
		echo "ERROR: SERVICE_BUILD_ARTIFACTS is empty."; \
		exit 2; \
	fi
	$(call service_utils_assert_build_paths,$(SERVICE_BUILD_CLEAN_DIRS),SERVICE_BUILD_CLEAN_DIRS)
	@if [ -n "$(strip $(SERVICE_BUILD_CLEAN_DIRS))" ]; then \
		set -e; \
		for path in $(SERVICE_BUILD_CLEAN_DIRS); do \
			case "$$path" in \
				build|build/|build/*|./build|./build/|./build/*) rm -rf "$$path" ;; \
				*) echo "ERROR: refusing service build clean path outside build/: $$path"; exit 2 ;; \
			esac; \
		done; \
	fi
	$(call service_utils_assert_build_paths,$(SERVICE_BUILD_DIRS),SERVICE_BUILD_DIRS)
	@if [ -n "$(strip $(SERVICE_BUILD_DIRS))" ]; then \
		mkdir -p $(SERVICE_BUILD_DIRS); \
	fi
	@$(MAKE) --no-print-directory $(SERVICE_BUILD_ARTIFACT_TARGETS)

check.deb:
	@$(service_utils_shell_detect_dry_run); \
	if [ "$$dry_run" = "1" ]; then \
			echo ">> Debian Inputs"; \
			printf "  %15s : %s\n" "Services" "$(DEBIAN_SERVICES)"; \
			printf "  %15s : %s\n" "Mode" "dry-run"; \
			echo; \
			exit 0; \
	fi; \
	set -e; \
	echo ">> Debian Inputs"; \
	missing=0; \
	for svc in $(DEBIAN_SERVICES); do \
		if ! output="$$( $(MAKE) --no-print-directory -s check-deb-$$svc 2>&1 )"; then \
			if [ -n "$$output" ]; then \
				printf "%s\n" "$$output" | sed '/^make\[[0-9][0-9]*\]: \*\*\*/d;/^make: \*\*\*/d'; \
			fi; \
			missing=1; \
		elif [ -n "$$output" ]; then \
			printf "%s\n" "$$output"; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "ERROR: Debian package inputs are incomplete."; \
		exit 1; \
	fi
	@echo ">> Debian Inputs: [PASS]"

build.deb: .require-version-build-var
	@set -e; \
	path="$(DEBIAN_PATH)"; \
	case "$$path" in \
		""|"."|"/"|*"/.."|*"/../"*|".."|"../"*) echo "ERROR: refusing unsafe Debian clean path: '$$path'."; exit 2 ;; \
		build|build/|build/*|./build|./build/|./build/*) rm -rf "$$path" ;; \
		*) echo "ERROR: refusing Debian clean path outside build/: $$path"; exit 2 ;; \
	esac
	@echo "Building Debian packages for: $(DEBIAN_SERVICES)"
	@set -e; \
	for svc in $(DEBIAN_SERVICES); do \
		echo ">>> Building $$svc..."; \
		$(MAKE) --no-print-directory deb-$$svc; \
	done

# Rebuild the base image, then build plugin artifacts with the normal builder.
service-build-from-scratch: prepare-service-builder-base service-build-plugin
	@echo "Successfully rebuilt the base image and plugin artifacts from scratch."
	@echo ""

# Build the plugins.
# Note: Actual artifact targets are built inside a container from the service
# Makefile.
# - Target 'build.plugin' builds .so and CLI artifacts.
# - Target 'build.deb' builds .deb files and lets package producers validate
#   their inputs.
# - No Docker images built here. Separate targets, build.docker*, are available.
service-build-plugin: .require-version-build-var
	@$(MAKE) --no-print-directory service-build-once BUILD_MAKE_TARGET=build.plugin

service-build-debian: .require-version-build-var
	@$(MAKE) --no-print-directory service-build-once BUILD_MAKE_TARGET=build.deb

.require-version-build-var:
	@if [ -z "$(strip $(VERSION_BUILD))" ]; then \
		echo "ERROR: VERSION_BUILD is not set for this internal build step."; \
		echo "Use make build-plugin, make build-debian, or make build-docker so build/Manifest.yaml owns the version."; \
		exit 2; \
	fi

BUILD_MAKE_TARGET ?= build.targets
# Builder execution mode:
# - docker-run is the default fast path. It runs the requested internal make
#   target inside the prepared builder base image with the service workspace
#   bind-mounted as the artifact boundary.
# - docker-build keeps the older Dockerfile RUN + docker cp behavior as a
#   temporary migration fallback for services or hosts that cannot use bind
#   mounts with the local Docker daemon.
SERVICE_BUILD_EXECUTION_MODE ?= docker-run
SERVICE_BUILD_DOCKER_PLATFORM ?= linux/amd64
SERVICE_BUILD_WORKDIR ?= /asn-service
SERVICE_BUILD_SECRET_TARGET ?= /run/secrets/sshkey
SERVICE_BUILD_DOCKER_RUN_ARGS ?=

service-build-once: .require-version-build-var
	@case "$(SERVICE_BUILD_EXECUTION_MODE)" in \
		docker-run) \
			$(MAKE) --no-print-directory service-build-once-docker-run BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		docker-build) \
			$(MAKE) --no-print-directory service-build-once-docker-build BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		*) \
			echo "ERROR: SERVICE_BUILD_EXECUTION_MODE must be docker-run or docker-build, got '$(SERVICE_BUILD_EXECUTION_MODE)'."; \
			exit 2 ;; \
	esac

service-build-once-docker-run: .require-version-build-var
	@echo "Current working directory: ${PWD}"
	@echo "Start building with $(BUILD_ENV_BASE_IMAGE_REF)"
	@echo "Build target: $(BUILD_MAKE_TARGET)"

	@# Remove only a container that is known to exist. Docker Desktop can hang
	@# when asked to remove an absent named container.
	@if docker ps -a --format '{{.Names}}' | awk -v name="$(BUILD_ENV_IMAGE)" '$$0 == name { found=1 } END { exit !found }'; then \
		docker rm -f $(BUILD_ENV_IMAGE) >/dev/null; \
	fi

	@mkdir -p build "$(SERVICE_BUILDER_GOCACHE)"
	@echo "Running Docker builder container:"
	@echo "  image:       $(BUILD_ENV_BASE_IMAGE_REF)"
	@echo "  platform:    $(SERVICE_BUILD_DOCKER_PLATFORM)"
	@echo "  name:        $(BUILD_ENV_IMAGE)"
	@echo "  target:      $(BUILD_MAKE_TARGET)"
	@echo "  version:     $(VERSION_BUILD)"
	@echo "  workspace:   $(CURDIR) -> $(SERVICE_BUILD_WORKDIR)"
	@echo "  go cache:    $(SERVICE_BUILDER_GOCACHE) -> /root/.cache/go-build"
	@echo "  secret:      PRIVATE_GIT_SSH_KEY_FILE -> $(SERVICE_BUILD_SECRET_TARGET) (readonly)"
	@docker run --rm --platform $(SERVICE_BUILD_DOCKER_PLATFORM) --name $(BUILD_ENV_IMAGE) \
		$(SERVICE_BUILD_DOCKER_RUN_ARGS) \
		--mount type=bind,source="$(CURDIR)",target=$(SERVICE_BUILD_WORKDIR) \
		--mount type=bind,source="$$PRIVATE_GIT_SSH_KEY_FILE",target=$(SERVICE_BUILD_SECRET_TARGET),readonly \
		--mount type=bind,source="$(SERVICE_BUILDER_GOCACHE)",target=/root/.cache/go-build \
		--env BUILD_MODE="$(BUILD_MODE)" \
		--env VERSION_BUILD="$(VERSION_BUILD)" \
		--env GOCACHE=/root/.cache/go-build \
		--workdir $(SERVICE_BUILD_WORKDIR) \
		$(BUILD_ENV_BASE_IMAGE_REF) \
		make -f Makefile $(BUILD_MAKE_TARGET) BUILD_MODE="$(BUILD_MODE)" VERSION_BUILD="$(VERSION_BUILD)"
	@echo ""
	@echo "Successfully ran builder target $(BUILD_MAKE_TARGET) in $(BUILD_ENV_BASE_IMAGE_REF)."
	@echo ""
	@echo "NOTE:"
	@echo " - If the ASN Service API has updated, make sure the base image has been rebuilt."
	@echo " - Run 'make check' if you need to verify the prepared base image labels before building."
	@echo ""

service-build-once-docker-build: .require-version-build-var
	@echo "Current working directory: ${PWD}"
	@echo "Start building $(BUILD_ENV_IMAGE):latest"
	@echo "Build target: $(BUILD_MAKE_TARGET)"

	@# Remove only a container that is known to exist. Docker Desktop can hang
	@# when asked to remove an absent named container.
	@if docker ps -a --format '{{.Names}}' | awk -v name="$(BUILD_ENV_IMAGE)" '$$0 == name { found=1 } END { exit !found }'; then \
		docker rm -f $(BUILD_ENV_IMAGE) >/dev/null; \
	fi

	@# Build the service environment image and run the target in a Dockerfile RUN step.
	@echo "Running Docker builder fallback:"
	@echo "  docker buildx build --platform $(SERVICE_BUILD_DOCKER_PLATFORM) -f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest"
	@echo "  base image:  $(BUILD_ENV_BASE_IMAGE_REF)"
	@echo "  build mode:  $(BUILD_MODE)"
	@echo "  version:     $(VERSION_BUILD)"
	@echo "  target:      $(BUILD_MAKE_TARGET)"
	@DOCKER_BUILDKIT=1 docker buildx build --progress=plain --platform $(SERVICE_BUILD_DOCKER_PLATFORM) $(BUILD_ARGS) \
		--load \
		--build-arg BUILD_ENV_BASE_IMAGE=$(BUILD_ENV_BASE_IMAGE_REF) \
		--build-arg BUILD_MODE=$(BUILD_MODE) \
		--build-arg VERSION_BUILD=$(VERSION_BUILD) \
		--build-arg MAKE_TARGET=$(BUILD_MAKE_TARGET) \
		--secret id=sshkey,src=$$PRIVATE_GIT_SSH_KEY_FILE \
		-f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest .
	@echo "Successfully built $(BUILD_ENV_IMAGE):latest."
	@docker run -d --platform $(SERVICE_BUILD_DOCKER_PLATFORM) --name $(BUILD_ENV_IMAGE) $(BUILD_ENV_IMAGE):latest
	@echo ""
	@mkdir -p build
	@docker cp $(BUILD_ENV_IMAGE):/build ./

	@# Clean up.
	@printf "%s" "Removed: "
	@docker rm -f $(BUILD_ENV_IMAGE)
	@echo ""
	@echo "Successfully ran builder target $(BUILD_MAKE_TARGET), then removed $(BUILD_ENV_IMAGE):latest."
	@echo ""
	@echo "NOTE:"
	@echo " - docker-build execution is kept for migration fallback; docker-run is the default executor."
	@echo " - If the ASN Service API has updated, make sure the base image has been rebuilt."
	@echo " - Run 'make check' if you need to verify the prepared base image labels before building."
	@echo ""
