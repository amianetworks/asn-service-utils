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
	check-version \
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
	service-build-once \
	build-init \
	build-prepare \
	debian \
	docker

# Explicitly initialize or realign service-utils. Normal build targets do not
# refresh the submodule.
init: update_service_utils

# Build the required builder base image. Run this on a fresh build host or when
# ASN_SERVICE_API_VERSION changes.
prepare: clean proto-gen prepare-service-builder-base
	@echo "Successfully built base image."
	@echo

check: check-version check-service-builder-base

build: prepare build-plugin $(BUILD_EXTRA_TARGETS) build-debian build-docker

build-fresh: clean proto-gen service-build-from-scratch
	@echo "Built new base image and artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

build-plugin: check clean increment-build proto-gen service-build-plugin
	@echo "Built artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

# Any artifacts should be under build/. Cleaning is simple.
clean: .init_build_file
	@rm -rf build/


check-version:
	@next_build=$$(expr $(CURRENT_BUILD) + 1); \
	echo ">> Version Check"; \
	printf "  %15s : %s\n" "Service" "$(SERVICE)"; \
	printf "  %15s : %s\n" "ASN Service API" "$(ASN_SERVICE_API_VERSION)"; \
	printf "  %15s : %s\n" "Build Mode" "$(BUILD_MODE)"; \
	printf "  %15s : %s\n" "Current Version" "$(VERSION_BUILD)"; \
	printf "  %15s : $(VERSION).%s\n" "Next Version" "$$next_build"
	@echo ""
	@$(MAKE) --no-print-directory check-go-mod

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

set-version: check-version
	@echo "Modify config.mk to update the version and build."
	@echo "NOTE: Only CI/CD or maintainer should change the version with caution."

increment-build: .increment_build

##----------------------------------------------------------------------------##
## Debian Package handling ##

uppercase = $(shell echo $(1) | tr a-z A-Z)

# Build Debian packages from existing plugin artifacts.
build-debian: check check-debian-inputs clean-debian service-build-debian
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

build-docker:
	@if [ -z "$(strip $(DOCKER_IMAGE_BUILD_SPECS))" ]; then \
		echo "ERROR: DOCKER_IMAGE_BUILD_SPECS is empty."; \
		exit 1; \
	fi
	@for spec in $(DOCKER_IMAGE_BUILD_SPECS); do \
		image=$${spec%%:*}; \
		dockerfile=$${spec#*:}; \
		$(MAKE) -s .docker-build-image IMAGE=$$image DOCKERFILE=$$dockerfile; \
	done

.docker-build-image:
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

#------------------------------------------------------------------------------#

#------------------------------------------------------------------------------#
# Prepare for base docker image to build ASN Service Plugins.
prepare-service-builder-base:
	@echo "Current working directory: ${PWD}"
	@echo "Building $(BUILD_ENV_BASE_IMAGE_REF)"

	@# Buildx updates the tag in place; avoid pre-removal because Docker Desktop
	@# can hang on absent container/image names.
	@service_go_mod_hash=$$(shasum -a 256 go.mod | awk '{ print $$1 }'); \
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
		-t $(BUILD_ENV_BASE_IMAGE_REF) .
	@echo ""
	@echo "Successfully built $(BUILD_ENV_BASE_IMAGE_REF) as the base image."
	@echo ""
	@echo "NOTE:"
	@echo " - This base image is local build infrastructure only; do not push or share it."
	@echo " - It warms Go modules and build cache from the service go.mod, then deletes the project workdir for later builds."
	@echo " - MUST BE DONE everytime when service-api version changes."
	@echo " - MUST BE DONE everytime when the service go.mod changes."
	@echo " - Run \`docker images | grep asn\` to list the images."
	@echo " - Run \`make build-plugin\` to build plugin artifacts."
	@echo " - Run \`make build-debian\` to build Debian packages from plugin artifacts."
	@echo " - Run \`make build-docker\` to build standalone docker images, for non-plugin setup."
	@echo ""

# Check the local builder base image required to build ASN Service Plugins.
# This is a local Docker image check only; never query an online registry for it.
check-service-builder-base:
	@image="$(BUILD_ENV_BASE_IMAGE_REF)"; \
	if ! docker info >/dev/null 2>&1; then \
		echo ">> Builder Version and Base Image Check: [FAIL]"; \
		printf "  %-15s : unavailable\n" "Docker"; \
		echo "Local builder base image check failed: Docker daemon is not reachable."; \
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
	api=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.service_api" }}' 2>/dev/null); \
	framework=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.framework" }}' 2>/dev/null); \
	go_version=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.go" }}' 2>/dev/null); \
	go_mod=$$(docker image inspect "$$image_id" --format '{{ index .Config.Labels "asn.service_go_mod" }}' 2>/dev/null); \
	expected_go_mod=$$(shasum -a 256 go.mod | awk '{ print $$1 }'); \
	if [ "$$api" != "$(ASN_SERVICE_API_VERSION)" ]; then failed=1; fi; \
	if [ "$$framework" != "$(DEP_VERSION_ASN)" ]; then failed=1; fi; \
	if [ "$$go_version" != "$(DEP_VERSION_GO)" ]; then failed=1; fi; \
	if [ "$$go_mod" != "$$expected_go_mod" ]; then failed=1; fi; \
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
		echo "Local builder base image check failed. Run make prepare."; \
		exit 1; \
	fi; \
	echo ">> Builder Version and Base Image Check: [PASS]"; \
	printf "  %15s : %s\n" "Base Image" "$$image"; \
	printf "  %15s : %s\n" "ID" "$${inspect_id#sha256:}"; \
	printf "  %15s : %s (expected as ASN_SERVICE_API_VERSION).\n" "API Version" "$$api"; \
	printf "  %15s : %s (expected from service-utils)\n" "ASN Version" "$$framework"; \
	printf "  %15s : %s (expected from service-utils)\n" "Go Version" "$$go_version"; \
	printf "  %15s : %s (expected from service go.mod).\n" "Service go.mod" "$$go_mod"

# Rebuild the base image, then build plugin artifacts with the normal builder.
service-build-from-scratch: prepare-service-builder-base service-build-plugin
	@echo "Successfully rebuilt the base image and plugin artifacts from scratch."
	@echo ""

# Build the plugins.
# Note: Actual targets are built inside a container, so check out make/internal.mk for more details.
# - Target 'build.plugin' is executed to build .so and CLI artifacts.
# - Target 'build.deb' is executed by 'make build-debian' to build .deb files.
# - No Docker images built here. Separate targets, build.docker*, are available.
service-build-plugin:
	@$(MAKE) --no-print-directory service-build-once BUILD_MAKE_TARGET=build.plugin

service-build-debian:
	@$(MAKE) --no-print-directory service-build-once BUILD_MAKE_TARGET=build.deb

BUILD_MAKE_TARGET ?= build.targets

service-build-once:
	@echo "Current working directory: ${PWD}"
	@echo "Start building $(BUILD_ENV_IMAGE):latest"
	@echo "Build target: $(BUILD_MAKE_TARGET)"

	@# Remove only a container that is known to exist. Docker Desktop can hang
	@# when asked to remove an absent named container.
	@if docker ps -a --format '{{.Names}}' | awk -v name="$(BUILD_ENV_IMAGE)" '$$0 == name { found=1 } END { exit !found }'; then \
		docker rm -f $(BUILD_ENV_IMAGE) >/dev/null; \
	fi

#	@docker buildx build --platform linux/amd64 --build-arg MAKE_TARGET=$(MAKE_TARGETS)") \
#		-f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest .

	@# Build the service environment image.
	@DOCKER_BUILDKIT=1 docker buildx build --progress=plain --platform linux/amd64 $(BUILD_ARGS) \
		--load \
		--build-arg BUILD_ENV_BASE_IMAGE=$(BUILD_ENV_BASE_IMAGE_REF) \
		--build-arg MAKE_TARGET=$(BUILD_MAKE_TARGET) \
		--secret id=sshkey,src=$$PRIVATE_GIT_SSH_KEY_FILE \
		-f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest .
	@echo "Successfully built $(BUILD_ENV_IMAGE):latest."
	@docker run -d --platform linux/amd64 --name $(BUILD_ENV_IMAGE) $(BUILD_ENV_IMAGE):latest
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
	@echo " - If the ASN Service API has updated, make sure the base image has been rebuilt."
	@echo " - TODO: version check could be done to avoid mismatch of versions."
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

build-init build-prepare debian docker:
	@case "$@" in \
		build-init) replacement="init" ;; \
		build-prepare) replacement="prepare" ;; \
		debian) replacement="build-debian" ;; \
		docker) replacement="build-docker" ;; \
	esac; \
	echo "ERROR: make $@ has been removed."; \
	echo "Use 'make $$replacement'."; \
	exit 2

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
	@if [ -d "$(SERVICE_UTILS_DIR)" ] && git -C "$(SERVICE_UTILS_DIR)" rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
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
	current=$$(git -C "$(SERVICE_UTILS_DIR)" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$(SERVICE_UTILS_DIR)" describe --tags --exact-match 2>/dev/null || git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD); \
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
