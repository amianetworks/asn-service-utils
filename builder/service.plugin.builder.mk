# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

#$(info service.plugin.builder.mk loaded)

# The following variables must be definded. (predefined in make/config.mk)
#BUILD_ENV_BASE_IMAGE
#BUILD_ENV_BASE_DOCKERFILE
#BUILD_ENV_IMAGE
#BUILD_ENV_DOCKERFILE
#SSH_PRIVATE_KEY

#------------------------------------------------------------------------------#
service-build-:
	@echo "Current working directory: ${PWD}"
	@echo "Start building $(BUILD_ENV_IMAGE):latest"



#------------------------------------------------------------------------------#
# Prepare for base docker image to build ASN Service Plugins.
prepare-service-builder-base:
	@echo "Current working directory: ${PWD}"
	@echo "Building $(BUILD_ENV_BASE_IMAGE):latest"

	 # Clean up previously built images.
	-docker stop $(BUILD_ENV_BASE_IMAGE)
	-docker rm $(BUILD_ENV_BASE_IMAGE)
	-docker rmi $(BUILD_ENV_BASE_IMAGE):latest

	 # Build the base image and run 'build' once to get all go packages.
	@DOCKER_BUILDKIT=1 docker buildx build \
		--platform linux/amd64 \
		-f $(BUILD_ENV_BASE_DOCKERFILE) \
		--secret id=sshkey,src=$(SSH_PRIVATE_KEY) \
		-t $(BUILD_ENV_BASE_IMAGE):latest .
	@echo ""
	@echo "Successfully built $(BUILD_ENV_BASE_IMAGE):latest as the base image."
	@echo ""
	@echo "NOTE:"
	@echo " - MUST BE DONE everytime when service-api version changes."
	@echo " - Run \`docker images | grep asn\` to list the images."
	@echo " - Run \`make build-plugin\` to build the plugin artifacts, .so and .deb."
	@echo " - Run \`make build-docker\` to build standalone docker images, for non-plugin setup."
	@echo ""

# Check Prepare for base docker image to build ASN Service Plugins.
check-service-builder-base:
	@docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^$(BUILD_ENV_BASE_IMAGE)(:|$$)' || echo "No Builder Base Image Found."


# Rebuild everything from scratch.
service-build-from-scratch:
	@echo "Current working directory: ${PWD}"
	@echo "Start building $(BUILD_ENV_BASE_IMAGE):latest"

	 # Clean up previously built images.
	-docker stop $(BUILD_ENV_BASE_IMAGE)
	-docker rm $(BUILD_ENV_BASE_IMAGE)
	-docker rmi $(BUILD_ENV_BASE_IMAGE):latest

	 # Build the base image and run 'build' once.
	@DOCKER_BUILDKIT=1 docker buildx build \
		--platform linux/amd64 \
		-f $(BUILD_ENV_BASE_DOCKERFILE) \
		--secret id=sshkey,src=$(SSH_PRIVATE_KEY) \
		-t $(BUILD_ENV_BASE_IMAGE):latest .
	@echo "Successfully built $(BUILD_ENV_BASE_IMAGE):latest."

	@docker run -itd --platform linux/amd64 --name $(BUILD_ENV_BASE_IMAGE) $(BUILD_ENV_BASE_IMAGE):latest
	@mkdir -p build
	@echo ""
	@docker cp $(BUILD_ENV_BASE_IMAGE):/build ./
	@echo ""

	 # Clean up.
	@echo -n "Stopped: "
	@docker stop $(BUILD_ENV_BASE_IMAGE)
	@echo -n "Removed: "
	@docker rm $(BUILD_ENV_BASE_IMAGE)
	@echo ""
	@echo "Successfully built plugin artifacts, then removed $(BUILD_ENV_BASE_IMAGE):latest."
	@echo "You may run \`docker images | grep asn\` to check them out. "
	@echo ""
	@echo "NOTE:"
	@echo " - A base image of builder has been built, as well as the .so files."
	@echo " - Run \`docker images | grep asn\` to list the images."
	@echo ""

# Build the plugins.
# Note: Actual targets are built inside a container, so check out make/internal.mk for more details.
# - Target 'build.so' is executed to build .so files.
# - Target 'build.deb' is executed to build .deb files.
# - No Docker images built here. Separate targets, build.docker*, are available.
service-build-once:
	@echo "Current working directory: ${PWD}"
	@echo "Start building $(BUILD_ENV_IMAGE):latest"

	 # Clean up previously built images.
	-docker stop $(BUILD_ENV_IMAGE)
	-docker rm $(BUILD_ENV_IMAGE)
	-docker rmi $(BUILD_ENV_IMAGE):latest

#	@docker buildx build --platform linux/amd64 --build-arg MAKE_TARGET=$(MAKE_TARGETS)") \
#		-f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest .

	 # Build the service environment image.
	@docker buildx build --platform linux/amd64 $(BUILD_ARGS) \
		-f $(BUILD_ENV_DOCKERFILE) -t $(BUILD_ENV_IMAGE):latest .
	@echo "Successfully built $(BUILD_ENV_IMAGE):latest."
	@docker run -d --platform linux/amd64 --name $(BUILD_ENV_IMAGE) $(BUILD_ENV_IMAGE):latest
	@echo ""
	@mkdir -p build
	@docker cp $(BUILD_ENV_IMAGE):/build ./

	 # Clean up.
	@echo -n "Stopped: "
	@docker stop $(BUILD_ENV_IMAGE)
	@echo -n "Removed: "
	@docker rm $(BUILD_ENV_IMAGE)
	@docker rmi $(BUILD_ENV_IMAGE):latest
	@echo ""
	@echo "Successfully built plugin artifacts, then removed $(BUILD_ENV_IMAGE):latest."
	@echo ""
	@echo "NOTE:"
	@echo " - If the ASN Service API has updated, make sure the base image has been rebuilt."
	@echo " - TODO: version check could be done to avoid mismatch of versions."
	@echo ""


###
# Generic deb packaging rule: deb-<service>
deb-%: 
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
	$(eval DEB_SVC_DIR := $(DEBIAN_PATH)/$(SERVICE_NAME))

	@echo "SERVICE_NAME: $(SERVICE_NAME)"
	@echo "DEBIAN_PATH: $(DEB_SVC_DIR)"
	@mkdir -p $(DEB_SVC_DIR)/DEBIAN

	@# Generate control file from service-specific control template
	@sed -e "s/@VERSION@/$(VERSION_BUILD)/" \
	     -e "s/@DEPENDS@/$(DEP_VERSION_ASN_C)/" \
	     -e "s/@SERVICE@/$(SERVICE_NAME)/" \
	     $(SERVICE_CONTROL) > $(DEB_SVC_DIR)/DEBIAN/control

	@# Create postinst script
	@printf "#!/bin/bash\nset -e\nsystemctl restart asnc\n" > $(DEB_SVC_DIR)/DEBIAN/postinst
	@chmod +x $(DEB_SVC_DIR)/DEBIAN/postinst
	@cp $(DEB_SVC_DIR)/DEBIAN/postinst $(DEB_SVC_DIR)/DEBIAN/postrm

	@# Copy files from DEBIAN_FILES
	@for pair in $(DEBIAN_FILES); do \
		SRC=$$(echo $$pair | cut -d: -f1); \
		DST=$$(echo $$pair | cut -d: -f2 | sed 's@^/@@'); \
		echo "Processing file: $$SRC -> $(DEB_SVC_DIR)/$$DST"; \
		mkdir -p $(DEB_SVC_DIR)/$$DST; \
		cp "$$SRC" "$(DEB_SVC_DIR)/$$DST/" || { echo "Failed to copy $$SRC"; exit 1; }; \
		chmod 644 "$(DEB_SVC_DIR)/$$DST/$$(basename $$SRC)"; \
	done
	@echo "Prepared to packing .deb."

	$(eval DEB_FILE_NAME := $(DEB_SVC_DIR)_$(VERSION_BUILD)_amd64.deb)
	@dpkg-deb --build $(DEB_SVC_DIR) $(DEB_FILE_NAME)
	@echo "Packed: $(DEB_FILE_NAME)."


clean-deb-%:
	@echo "Cleaning $*..."
	@rm -rf $DEB_SVC_DIR

# Debug purpose
show-prepare:
	@echo "Current working directory: ${PWD}"
	@echo "Starting $(BUILD_ENV_BASE_IMAGE):latest"
	docker run --rm --platform linux/amd64 --name $(BUILD_ENV_BASE_IMAGE) $(BUILD_ENV_BASE_IMAGE):latest ls -l /

	@echo " Ran the container once to show the artifacts."

