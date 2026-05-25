# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

#$(info service.plugin.builder.mk loaded)

# The following variables must be definded. (predefined in make/config.mk)
#ASN_SERVICE_API_VERSION
#BUILD_ENV_BASE_IMAGE
#BUILD_ENV_BASE_IMAGE_TAG
#BUILD_ENV_BASE_IMAGE_REF
#BUILD_ENV_BASE_DOCKERFILE
#BUILD_ENV_IMAGE
#BUILD_ENV_DOCKERFILE
#BUILD_ENV_ASN_VERSION_FILE
#PRIVATE_GIT_SSH_KEY_FILE
#SERVICE_UTILS_DIR

##----------------------------------------------------------------------------##
## Lifecycle targets.
##
## Services should expose these names directly. `build-all` is the only legacy
## spelling kept, and it is a plain alias for `build`.
build-all: build

##----------------------------------------------------------------------------##
## Main targets ##
## All dependent used below targets are defined in service.plugin.build.env.mk.

.PHONY: \
	init \
	prepare \
	build \
	build-all \
	check \
	check-build \
	check-version \
	require-build-manifest \
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
	prepare-service-builder-base \
	check-service-builder-base \
	service-build-once \
	service-build-once-docker-run \
	service-build-once-docker-build \
	.require-version-build-var \
	build-fresh \
	build-init \
	build-prepare \
	debian \
	docker

# Explicitly initialize or realign service-utils. Normal build targets do not
# refresh the submodule.
init: update_service_utils

# Build identity and manifest mutation make these lifecycle targets serial.
.NOTPARALLEL: build build-plugin build-fresh build-debian build-docker stage-docs

# Build the required builder base image. Run this on a fresh build host or when
# builder/toolchain/dependency inputs change.
prepare: prepare-service-builder-base
	@echo "Successfully built base image."
	@echo

check: check-build check-service-builder-base

build: prepare build-plugin $(BUILD_EXTRA_TARGETS) build-debian build-docker

build-fresh: clean prepare build-plugin $(BUILD_EXTRA_TARGETS) build-debian build-docker
	@echo "Built fresh artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

build-plugin: check proto-gen
	@set -e; \
	version_build="$$(bash make/build_manifest.sh reserve-plugin-version \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_NUM_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)")"; \
	echo ">> Build Plugin Version"; \
	printf "  %15s : %s\n" "Version" "$$version_build"; \
	make --no-print-directory service-build-plugin VERSION_BUILD="$$version_build"; \
	if service_utils_ref="$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD 2>&1)"; then \
		:; \
	else \
		echo "WARN: could not resolve service-utils git ref: $$service_utils_ref" >&2; \
		service_utils_ref="unknown"; \
	fi; \
	bash make/build_manifest.sh commit-plugin \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_NUM_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--version-build "$$version_build" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)" \
		--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
		--dep-version-asn "$(DEP_VERSION_ASN)" \
		--service-utils-ref "$$service_utils_ref"
	@echo "Built artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

# Any artifacts should be under build/. Cleaning is simple.
clean:
	@rm -rf build/


check-build:
	@bash make/build_manifest.sh check-build \
		--service "$(SERVICE)" \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_NUM_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--asn-service-api-version "$(ASN_SERVICE_API_VERSION)"
	@echo ""
	@$(MAKE) --no-print-directory check-go-mod

check-version: check-build

check-go-mod:
	@failed=0; compared=0; skipped=0; \
	root_requires=$$(mktemp); utils_requires=$$(mktemp); \
	if [ ! -f go.mod ]; then \
		echo ">> go.mod Conflict Check: [FAIL]"; \
		echo "            Missing root go.mod."; \
		rm -f "$$root_requires" "$$utils_requires"; \
		exit 1; \
	fi; \
	if [ ! -f "$(SERVICE_UTILS_DIR)/go.mod" ]; then \
		echo ">> go.mod Conflict Check: [FAIL]"; \
		echo "            Missing $(SERVICE_UTILS_DIR)/go.mod."; \
		rm -f "$$root_requires" "$$utils_requires"; \
		exit 1; \
	fi; \
	extract_requires() { \
		awk ' \
			$$1 == "require" && NF >= 3 { print $$2, $$3; next } \
			$$1 == "require" && $$2 == "(" { in_require = 1; next } \
			in_require && $$1 == ")" { in_require = 0; next } \
			in_require && NF >= 2 && $$1 !~ /^\/\// { print $$1, $$2 } \
		' "$$1" | sort; \
	}; \
	extract_requires go.mod > "$$root_requires"; \
	extract_requires $(SERVICE_UTILS_DIR)/go.mod > "$$utils_requires"; \
	while read -r module expected; do \
		[ -z "$$module" ] && continue; \
		actual=$$(awk -v module="$$module" '$$1 == module { print $$2; exit }' "$$root_requires"); \
		if [ -z "$$actual" ]; then \
			skipped=$$(expr $$skipped + 1); \
		elif [ "$$actual" != "$$expected" ]; then \
			compared=$$(expr $$compared + 1); \
			printf "            %-48s Root: %s, service-utils: %s. FAIL\n" "$$module" "$$actual" "$$expected"; \
			failed=1; \
		else \
			compared=$$(expr $$compared + 1); \
		fi; \
	done < "$$utils_requires"; \
	rm -f "$$root_requires" "$$utils_requires"; \
	if [ "$$failed" -ne 0 ]; then \
		echo ""; \
		echo ">> go.mod Conflict Check: [FAIL]"; \
		echo "            Shared package versions must match between root go.mod and service-utils/go.mod."; \
		exit 1; \
	fi; \
	echo ">> go.mod Conflict Check: [PASS]"; \
	printf "  %15s : %s matched\n" "Shared Packages" "$$compared"; \
	printf "  %15s : %s ignored\n" "Utils-only Mods" "$$skipped"
	@echo ""

set-version: check-build
	@echo "Modify config.mk to update the version and build."
	@echo "NOTE: Only CI/CD or maintainer should change the version with caution."

increment-build:
	@echo "ERROR: make increment-build has been removed."
	@echo "build-plugin now commits $(DEV_BUILD_FILE) only after plugin artifacts build successfully."
	@exit 2

##----------------------------------------------------------------------------##
## Debian Package handling ##

uppercase = $(shell echo $(1) | tr a-z A-Z)

require-build-manifest:
	@version_build="$$(bash make/build_manifest.sh require-lane \
		--lane plugin \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)")"; \
	: "$$version_build"

# Build Debian packages from existing plugin artifacts.
build-debian: require-build-manifest check stage-docs check-debian-inputs clean-debian
	@set -e; \
	version_build="$$(bash make/build_manifest.sh require-lane \
		--lane docs \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)")"; \
	make --no-print-directory service-build-debian VERSION_BUILD="$$version_build"; \
	bash make/build_manifest.sh commit-lane \
		--lane debian \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--version-build "$$version_build" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)"
	@echo "Built Debian packages (DIR):"
	@if [ -d "$(DEBIAN_PATH)" ]; then find ./$(DEBIAN_PATH) -maxdepth 1 -print; else echo "(none)"; fi
	@echo

clean-debian:
	@rm -rf "$(DEBIAN_PATH)"

check-debian-inputs:
	@$(MAKE) --no-print-directory -f make/internal.mk check.deb

DEBIAN_PUSH_CHECK_TARGETS ?= .check-debian-release-mode
DEBIAN_PUSH_VERSION ?= $(VERSION_BUILD)

.check-debian-release-mode:
	$(call func_check_release_mode)

include $(SERVICE_UTILS_DIR)/builder/debian.registry.mk

##----------------------------------------------------------------------------##
## Docker Image Handling ##

build-docker: require-build-manifest check-docker-inputs
	@if [ -z "$(strip $(DOCKER_IMAGE_BUILD_SPECS))" ]; then \
		echo "ERROR: DOCKER_IMAGE_BUILD_SPECS is empty."; \
		exit 1; \
	fi
	@set -e; \
	version_build="$$(bash make/build_manifest.sh require-lane \
		--lane debian \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)")"; \
	for spec in $(DOCKER_IMAGE_BUILD_SPECS); do \
		image=$${spec%%:*}; \
		dockerfile=$${spec#*:}; \
		make -s .docker-build-image IMAGE=$$image DOCKERFILE=$$dockerfile VERSION_BUILD="$$version_build"; \
	done; \
	bash make/build_manifest.sh commit-lane \
		--lane docker \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--mode "$(BUILD_MODE)" \
		--version "$(VERSION)" \
		--build "$(BUILD)" \
		--version-build "$$version_build" \
		--manager-build-dir "$(BUILD_SVC_C_DIR)" \
		--servicenode-build-dir "$(BUILD_SVC_SN_DIR)" \
		--client-build-dir "$(BUILD_SVC_CLIENTS_DIR)" \
		--docs-dir "$(CURDIR)/build/docs" \
		--debian-dir "$(DEBIAN_PATH)" \
		--debian-services "$(DEBIAN_SERVICES)" \
		--docker-images "$(DOCKER_IMAGES)"

.docker-build-image: .require-version-build-var
	$(call func_build_docker,$(IMAGE),$(VERSION_BUILD),$(DOCKERFILE),$(DEP_DOCKER_BUILD_ARGS))

DOCKER_PUSH_CHECK_TARGETS ?= .check-docker-release-mode
DOCKER_PUSH_VERSION ?= $(VERSION_BUILD)
DOCKER_PUSH_LATEST ?= $(if $(filter pro,$(BUILD_MODE)),yes,no)

.check-docker-release-mode:
	$(call func_check_release_mode)

include $(SERVICE_UTILS_DIR)/builder/docker.registry.mk
include $(SERVICE_UTILS_DIR)/builder/release.preflight.mk

# $(1): IMAGE_NAME
# $(2): VERSION
# $(3): DOCKERFILE
# $(4): BUILD_ARGS string
define func_build_docker
	@echo ""
	@echo "Building docker image: $(1):$(2)"
	@echo "Dockerfile: $(3); BUILD_ARGS: $(4)"
	@docker buildx build \
		--progress=plain \
		--platform linux/amd64 \
		--load \
		-f $(3) \
		$(4) \
		-t $(1):$(2) \
		.
	@echo "Successfully built docker image for $(1)/$(2)"
	@echo ""
endef

#------------------------------------------------------------------------------#

# Framework-owned runtime and toolchain versions. This include intentionally
# happens after service config so copied service projects inherit these values.
include $(BUILD_ENV_ASN_VERSION_FILE)

BUILD_ENV_BASE_IMAGE_TAG ?= $(DEP_VERSION_ASN)
BUILD_ENV_BASE_IMAGE_REF ?= $(BUILD_ENV_BASE_IMAGE):$(BUILD_ENV_BASE_IMAGE_TAG)
SERVICE_GO_CACHE_PACKAGES ?= ./...
SERVICE_BUILDER_GOCACHE ?= $(CURDIR)/.cache/service-builder/go-build
SERVICE_BUILDER_INPUT_FILES ?= go.mod go.sum $(BUILD_ENV_BASE_DOCKERFILE) $(BUILD_ENV_MAKEFILE) $(BUILD_ENV_ASN_VERSION_FILE)

#------------------------------------------------------------------------------#

#------------------------------------------------------------------------------#
# Prepare for base docker image to build ASN Service Plugins.
prepare-service-builder-base:
	@echo "Current working directory: ${PWD}"
	@echo "Building $(BUILD_ENV_BASE_IMAGE_REF)"

	@# Buildx updates the tag in place; avoid pre-removal because Docker Desktop
	@# can hang on absent container/image names.
	@service_go_mod_hash=$$(shasum -a 256 go.mod | awk '{ print $$1 }'); \
		builder_input_hash=$$( \
			{ \
				printf 'ASN_SERVICE_API_VERSION=%s\n' "$(ASN_SERVICE_API_VERSION)"; \
				printf 'DEP_VERSION_ASN=%s\n' "$(DEP_VERSION_ASN)"; \
				printf 'DEP_VERSION_GO=%s\n' "$(DEP_VERSION_GO)"; \
				printf 'SERVICE_GO_CACHE_PACKAGES=%s\n' "$(SERVICE_GO_CACHE_PACKAGES)"; \
				for file in $(SERVICE_BUILDER_INPUT_FILES); do \
					if [ -f "$$file" ]; then \
						printf 'file:%s\n' "$$file"; \
						shasum -a 256 "$$file"; \
					else \
						printf 'missing:%s\n' "$$file"; \
					fi; \
				done; \
			} | shasum -a 256 | awk '{ print $$1 }' \
		); \
		DOCKER_BUILDKIT=1 docker buildx build \
		--progress=plain \
		--platform linux/amd64 \
		--load \
		--build-arg GO_VERSION=$(DEP_VERSION_GO) \
		-f $(BUILD_ENV_BASE_DOCKERFILE) \
		--secret id=sshkey,src=$$PRIVATE_GIT_SSH_KEY_FILE \
		--label asn.service_api=$(ASN_SERVICE_API_VERSION) \
		--label asn.framework=$(DEP_VERSION_ASN) \
		--label asn.go=$(DEP_VERSION_GO) \
		--label asn.service_go_mod="$$service_go_mod_hash" \
		--label asn.builder_inputs="$$builder_input_hash" \
		-t $(BUILD_ENV_BASE_IMAGE_REF) .
	@echo ""
	@echo "Successfully built $(BUILD_ENV_BASE_IMAGE_REF) as the base image."
	@echo ""
	@echo "NOTE:"
	@echo " - This base image is local build infrastructure only; do not push or share it."
	@echo " - It installs the toolchain and downloads Go modules from the service go.mod/go.sum."
	@echo " - Service source is not copied into the base image; build targets run later from the mounted workspace."
	@echo " - MUST BE DONE everytime when service-api version changes."
	@echo " - MUST BE DONE everytime when the service go.mod/go.sum or builder inputs change."
	@echo " - Run \`docker images | grep asn\` to list the images."
	@echo " - Run \`make build-plugin\` to build plugin artifacts."
	@echo " - Run \`make build-debian\` to build Debian packages from plugin artifacts."
	@echo " - Run \`make build-docker\` to build standalone docker images, for non-plugin setup."
	@echo ""

# Check the local builder base image required to build ASN Service Plugins.
# This is a local Docker image check only; never query an online registry for it.
check-service-builder-base:
	@image="$(BUILD_ENV_BASE_IMAGE_REF)"; \
	if ! docker_info=$$(docker info 2>&1); then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : unavailable\n" "Docker"; \
		echo "Local builder base image check failed: Docker daemon is not reachable."; \
		printf '%s\n' "$$docker_info" | sed -n '1,10p' | sed 's/^/  Docker Error             /'; \
		exit 1; \
	fi; \
	image_id=$$(docker images --no-trunc --format '{{.Repository}}:{{.Tag}} {{.ID}}' | awk -v image="$$image" '$$1 == image { print $$2; exit }'); \
	if [ -z "$$image_id" ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : %s (missing)\n" "Base Image" "$$image"; \
		echo "Local builder base image check failed: run make prepare before make build-plugin."; \
		exit 1; \
	fi; \
	inspect_err=$$(mktemp); \
	inspect_id=$$(docker image inspect "$$image_id" --format '{{.Id}}' 2>"$$inspect_err"); \
	inspect_status=$$?; \
	if [ "$$inspect_status" -ne 0 ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		if grep -qi "No such image" "$$inspect_err"; then \
			printf "  %-15s : %s (listed, unusable)\n" "Base Image" "$$image"; \
			echo "Local builder base image check failed: stale Docker image ID; run make prepare."; \
		else \
			printf "  %-15s : %s (inspect failed)\n" "Base Image" "$$image"; \
			echo "Local builder base image check failed: docker image inspect failed."; \
			sed 's/^/  Docker Error             /' "$$inspect_err"; \
		fi; \
		rm -f "$$inspect_err"; \
		exit 1; \
	fi; \
	rm -f "$$inspect_err"; \
	failed=0; \
	api=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.service_api" }}'); \
	framework=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.framework" }}'); \
	go_version=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.go" }}'); \
	go_mod=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.service_go_mod" }}'); \
	builder_inputs=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.builder_inputs" }}'); \
	expected_go_mod=$$(shasum -a 256 go.mod | awk '{ print $$1 }'); \
	expected_builder_inputs=$$( \
		{ \
			printf 'ASN_SERVICE_API_VERSION=%s\n' "$(ASN_SERVICE_API_VERSION)"; \
			printf 'DEP_VERSION_ASN=%s\n' "$(DEP_VERSION_ASN)"; \
			printf 'DEP_VERSION_GO=%s\n' "$(DEP_VERSION_GO)"; \
			printf 'SERVICE_GO_CACHE_PACKAGES=%s\n' "$(SERVICE_GO_CACHE_PACKAGES)"; \
			for file in $(SERVICE_BUILDER_INPUT_FILES); do \
				if [ -f "$$file" ]; then \
					printf 'file:%s\n' "$$file"; \
					shasum -a 256 "$$file"; \
				else \
					printf 'missing:%s\n' "$$file"; \
				fi; \
			done; \
		} | shasum -a 256 | awk '{ print $$1 }' \
	); \
	if [ "$$api" != "$(ASN_SERVICE_API_VERSION)" ]; then failed=1; fi; \
	if [ "$$framework" != "$(DEP_VERSION_ASN)" ]; then failed=1; fi; \
	if [ "$$go_version" != "$(DEP_VERSION_GO)" ]; then failed=1; fi; \
	if [ "$$go_mod" != "$$expected_go_mod" ]; then failed=1; fi; \
	if [ "$$builder_inputs" != "$$expected_builder_inputs" ]; then failed=1; fi; \
	if [ "$$failed" -ne 0 ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : %s\n" "Base Image" "$$image"; \
		printf "  %-15s : %s\n" "ID" "$${inspect_id#sha256:}"; \
		if [ "$$api" = "$(ASN_SERVICE_API_VERSION)" ]; then \
			printf "  %-15s : %s (expected as ASN_SERVICE_API_VERSION).\n" "API Version" "$${api:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s as ASN_SERVICE_API_VERSION). FAIL\n" "API Version" "$${api:-unknown}" "$(ASN_SERVICE_API_VERSION)"; \
		fi; \
		if [ "$$framework" = "$(DEP_VERSION_ASN)" ]; then \
			printf "  %-15s : %s (expected from service-utils)\n" "ASN Version" "$${framework:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from service-utils). FAIL\n" "ASN Version" "$${framework:-unknown}" "$(DEP_VERSION_ASN)"; \
		fi; \
		if [ "$$go_version" = "$(DEP_VERSION_GO)" ]; then \
			printf "  %-15s : %s (expected from service-utils)\n" "Go Version" "$${go_version:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from service-utils). FAIL\n" "Go Version" "$${go_version:-unknown}" "$(DEP_VERSION_GO)"; \
		fi; \
		if [ "$$go_mod" = "$$expected_go_mod" ]; then \
			printf "  %-15s : %s (expected from service go.mod).\n" "Service go.mod" "$${go_mod:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from service go.mod). FAIL\n" "Service go.mod" "$${go_mod:-missing}" "$$expected_go_mod"; \
		fi; \
		if [ "$$builder_inputs" = "$$expected_builder_inputs" ]; then \
			printf "  %-15s : %s (expected from builder inputs).\n" "Builder Inputs" "$${builder_inputs:-unknown}"; \
		else \
			printf "  %-15s : %s (expected %s from builder inputs). FAIL\n" "Builder Inputs" "$${builder_inputs:-missing}" "$$expected_builder_inputs"; \
		fi; \
		echo "Local builder base image check failed. Run make prepare."; \
		exit 1; \
	fi; \
	cache_probe=$$(docker run --rm --platform $(SERVICE_BUILD_DOCKER_PLATFORM) \
		--mount type=bind,source="$(CURDIR)",target=$(SERVICE_BUILD_WORKDIR),readonly \
		--workdir $(SERVICE_BUILD_WORKDIR) \
		--env SERVICE_GO_CACHE_PACKAGES="$(SERVICE_GO_CACHE_PACKAGES)" \
		"$$image" sh -lc 'GOPROXY=off GOSUMDB=off go list -mod=readonly -deps $$SERVICE_GO_CACHE_PACKAGES >/dev/null' 2>&1); \
	cache_probe_status=$$?; \
	if [ "$$cache_probe_status" -ne 0 ]; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : %s\n" "Base Image" "$$image"; \
		printf "  %-15s : %s\n" "Packages" "$(SERVICE_GO_CACHE_PACKAGES)"; \
		echo "Local builder base image check failed: warmed Go module cache does not satisfy offline package resolution."; \
		printf '%s\n' "$$cache_probe" | sed -n '1,20p' | sed 's/^/  Go Error                 /'; \
		echo "Run make prepare after confirming private module access."; \
		exit 1; \
	fi; \
	echo ">> Builder Version and Base Image Check: [PASS]"; \
	printf "  %15s : %s\n" "Base Image" "$$image"; \
	printf "  %15s : %s\n" "ID" "$${inspect_id#sha256:}"; \
	printf "  %15s : %s (expected as ASN_SERVICE_API_VERSION).\n" "API Version" "$$api"; \
	printf "  %15s : %s (expected from service-utils)\n" "ASN Version" "$$framework"; \
	printf "  %15s : %s (expected from service-utils)\n" "Go Version" "$$go_version"; \
	printf "  %15s : %s (expected from service go.mod).\n" "Service go.mod" "$$go_mod"; \
	printf "  %15s : %s (expected from builder inputs).\n" "Builder Inputs" "$$builder_inputs"; \
	printf "  %15s : %s\n" "Offline Cache" "PASS"

# Rebuild the base image, then build plugin artifacts with the normal builder.
service-build-from-scratch: prepare-service-builder-base service-build-plugin
	@echo "Successfully rebuilt the base image and plugin artifacts from scratch."
	@echo ""

# Build the plugins.
# Note: Actual targets are built inside a container, so check out make/internal.mk for more details.
# - Target 'build.plugin' is executed to build .so and CLI artifacts.
# - Target 'build.deb' is executed by 'make build-debian' to build .deb files.
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

service-build-once:
	@case "$(SERVICE_BUILD_EXECUTION_MODE)" in \
		docker-run) \
			$(MAKE) --no-print-directory service-build-once-docker-run BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		docker-build) \
			$(MAKE) --no-print-directory service-build-once-docker-build BUILD_MAKE_TARGET="$(BUILD_MAKE_TARGET)" ;; \
		*) \
			echo "ERROR: SERVICE_BUILD_EXECUTION_MODE must be docker-run or docker-build, got '$(SERVICE_BUILD_EXECUTION_MODE)'."; \
			exit 2 ;; \
	esac

service-build-once-docker-run:
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
		make -f make/internal.mk $(BUILD_MAKE_TARGET) BUILD_MODE="$(BUILD_MODE)" VERSION_BUILD="$(VERSION_BUILD)"
	@echo ""
	@echo "Successfully ran builder target $(BUILD_MAKE_TARGET) in $(BUILD_ENV_BASE_IMAGE_REF)."
	@echo ""
	@echo "NOTE:"
	@echo " - If the ASN Service API has updated, make sure the base image has been rebuilt."
	@echo " - Run 'make check' if you need to verify the prepared base image labels before building."
	@echo ""

service-build-once-docker-build:
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


###
# Generic deb input check rule: check-deb-<service>
check-deb-%:
	$(eval SERVICE_NAME := $*)
	$(eval SERVICE_CONFIG := debian/deb.$(SERVICE_NAME).config)
	$(eval SERVICE_CONTROL := debian/deb.$(SERVICE_NAME).control)
	@if [ ! -f $(SERVICE_CONFIG) ]; then \
		echo "Missing config: $(SERVICE_CONFIG)"; exit 1; \
	fi
	@if [ ! -f $(SERVICE_CONTROL) ]; then \
		echo "Missing control: $(SERVICE_CONTROL)"; exit 1; \
	fi
	$(eval include $(SERVICE_CONFIG))
	@echo "SERVICE_NAME: $(SERVICE_NAME)"
	@missing=0; \
	for pair in $(DEBIAN_FILES); do \
		SRC=$$(echo $$pair | cut -d: -f1); \
		if [ ! -e "$$SRC" ]; then \
			echo "Missing Debian input: $$SRC"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "Build plugin artifacts before running make build-debian."; \
		exit 1; \
	fi

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
	$(eval include $(SERVICE_CONFIG))
	$(eval DEB_SVC_DIR := $(DEBIAN_PATH)/$(SERVICE_NAME))

	@echo "DEBIAN_PATH: $(DEB_SVC_DIR)"
	@mkdir -p $(DEB_SVC_DIR)/DEBIAN

	@# Generate control file from service-specific control template
	@sed -e "s/@VERSION@/$(VERSION_BUILD)/" \
	     -e "s/@DEPENDS@/$(DEP_VERSION_ASN)/" \
	     -e "s/@SERVICE@/$(SERVICE_NAME)/" \
	     $(SERVICE_CONTROL) > $(DEB_SVC_DIR)/DEBIAN/control

	$(eval SERVICE_POSTINST := debian/deb.$(SERVICE_NAME).postinst)
	@if [ -f $(SERVICE_POSTINST) ]; then \
		cp $(SERVICE_POSTINST) $(DEB_SVC_DIR)/DEBIAN/postinst; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/postinst; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/postinst; \
	fi

	$(eval SERVICE_POSTRM := debian/deb.$(SERVICE_NAME).postrm)
	@if [ -f $(SERVICE_POSTRM) ]; then \
		cp $(SERVICE_POSTRM) $(DEB_SVC_DIR)/DEBIAN/postrm; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/postrm; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/postrm; \
	fi

	$(eval SERVICE_PREINST := debian/deb.$(SERVICE_NAME).preinst)
	@if [ -f $(SERVICE_PREINST) ]; then \
		cp $(SERVICE_PREINST) $(DEB_SVC_DIR)/DEBIAN/preinst; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/preinst; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/preinst; \
	fi

	$(eval SERVICE_PRERM := debian/deb.$(SERVICE_NAME).prerm)
	@if [ -f $(SERVICE_PRERM) ]; then \
		cp $(SERVICE_PRERM) $(DEB_SVC_DIR)/DEBIAN/prerm; \
		chmod 755 $(DEB_SVC_DIR)/DEBIAN/prerm; \
		chmod +x $(DEB_SVC_DIR)/DEBIAN/prerm; \
	fi

	$(eval SERVICE_FILE := debian/deb.$(SERVICE_NAME).service)
	@if [ -f $(SERVICE_FILE) ]; then \
		mkdir -p $(DEB_SVC_DIR)/lib/systemd/system; \
		cp $(SERVICE_FILE) $(DEB_SVC_DIR)/lib/systemd/system/$(SERVICE_NAME).service; \
	fi

	@if [ -f debian/conffiles.$(SERVICE_NAME) ]; then \
			echo "Copying service-specific conffiles for $(SERVICE_NAME)..."; \
			cp debian/conffiles.$(SERVICE_NAME) $(DEB_SVC_DIR)/DEBIAN/conffiles; \
			chmod 644 $(DEB_SVC_DIR)/DEBIAN/conffiles; \
		else \
			echo "No conffiles found for $(SERVICE_NAME), skipping"; \
		fi

	@# Copy files from DEBIAN_FILES
	@for pair in $(DEBIAN_FILES); do \
		SRC=$$(echo $$pair | cut -d: -f1); \
		DST=$$(echo $$pair | cut -d: -f2 | sed 's@^/@@'); \
		echo "Processing file: $$SRC -> $(DEB_SVC_DIR)/$$DST"; \
		mkdir -p $(DEB_SVC_DIR)/$$DST; \
		cp "$$SRC" "$(DEB_SVC_DIR)/$$DST/" || { echo "Failed to copy $$SRC"; exit 1; }; \
#		chmod 644 "$(DEB_SVC_DIR)/$$DST/$$(basename $$SRC)"; \
	done
	@echo "Prepared to packing .deb."

	$(eval DEB_FILE_NAME := $(DEB_SVC_DIR)_$(VERSION_BUILD)_amd64.deb)
	@dpkg-deb --build $(DEB_SVC_DIR) $(DEB_FILE_NAME)
	@echo "Packed: $(DEB_FILE_NAME)."


clean-deb-%:
	@echo "Cleaning $*..."
	@rm -rf "$(DEBIAN_PATH)/$*"

# Debug purpose
show-prepare:
	@echo "Current working directory: ${PWD}"
	@echo "Starting $(BUILD_ENV_BASE_IMAGE_REF)"
	docker run --rm --platform linux/amd64 --name $(BUILD_ENV_BASE_IMAGE) $(BUILD_ENV_BASE_IMAGE_REF) ls -l /

	@echo " Ran the container once to show the artifacts."

#------------------------------------------------------------------------------#
init_service_utils:
	@if [ -z "$(SERVICE_UTILS_DIR)" ]; then \
		echo "ERROR: SERVICE_UTILS_DIR is not set."; \
		exit 1; \
	fi
	@if [ -d "$(SERVICE_UTILS_DIR)" ] && git_probe=$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --is-inside-work-tree 2>&1) && [ "$$git_probe" = "true" ]; then \
		echo "service-utils is already present."; \
	else \
		echo "Initializing service-utils submodule."; \
		git submodule sync --recursive $(SERVICE_UTILS_DIR); \
		git submodule update --init --recursive $(SERVICE_UTILS_DIR); \
	fi

update_service_utils: init_service_utils
	@if [ -z "$(ASN_SERVICE_API_VERSION)" ]; then \
		echo "ERROR: ASN_SERVICE_API_VERSION is not set."; \
		exit 1; \
	fi
	@expected="v$(ASN_SERVICE_API_VERSION)"; \
	if current=$$(git -C "$(SERVICE_UTILS_DIR)" symbolic-ref --quiet --short HEAD 2>&1); then :; \
	elif current=$$(git -C "$(SERVICE_UTILS_DIR)" describe --tags --exact-match 2>&1); then :; \
	else current=$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD); fi; \
	cd $(SERVICE_UTILS_DIR) && \
	git fetch --prune origin && \
	if [ "$$current" = "$$expected" ]; then \
		if git show-ref --verify --quiet refs/remotes/origin/v$(ASN_SERVICE_API_VERSION); then \
			git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); \
		else \
			echo "service-utils ref $$current already selected (tag, no pull needed)."; \
		fi; \
	else \
		echo "Selecting service-utils ref $$expected"; \
		if git show-ref --verify --quiet refs/remotes/origin/v$(ASN_SERVICE_API_VERSION); then \
			if git show-ref --verify --quiet refs/heads/v$(ASN_SERVICE_API_VERSION); then \
				git checkout v$(ASN_SERVICE_API_VERSION); \
				git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); \
			else \
				git checkout -b v$(ASN_SERVICE_API_VERSION) origin/v$(ASN_SERVICE_API_VERSION); \
			fi; \
		elif git show-ref --verify --quiet refs/tags/v$(ASN_SERVICE_API_VERSION); then \
			git checkout v$(ASN_SERVICE_API_VERSION); \
		else \
			echo "ERROR: service-utils ref v$(ASN_SERVICE_API_VERSION) was not found as an origin branch or tag."; \
			exit 1; \
		fi; \
	fi
