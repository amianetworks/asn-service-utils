# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

#$(info service.plugin.builder.mk loaded)

# The following variables must be definded. (predefined in make/config.mk)
#ASN_SERVICE_API_VERSION
#BUILD_ENV_BASE_IMAGE
#BUILD_ENV_BASE_DOCKERFILE
#BUILD_ENV_IMAGE
#BUILD_ENV_DOCKERFILE
#BUILD_ENV_ASN_VERSION_FILE
#SSH_PRIVATE_KEY
#SERVICE_UTILS_DIR

##----------------------------------------------------------------------------##
## *All* Targets
# *-all targets could be used as it.
build-all:
	@$(MAKE) build-prepare
	@$(MAKE) build-plugin
	@$(MAKE) build-docker

#push-all:
#	@$(MAKE) push-base
#	@$(MAKE) debs-push
#	@$(MAKE) docker-push


##----------------------------------------------------------------------------##
## Main targets ##
## All dependent used below targets are defined in service.plugin.build.env.mk.

.PHONY: check-version check-go-mod

# Ensure service-utils exists, then select the branch/tag matching ASN_SERVICE_API_VERSION
# only when the current checkout is not already on the expected ref.
build-init: update_service_utils

# Build the required builder base image. Run this on a fresh build host or when
# ASN_SERVICE_API_VERSION changes.
build-prepare: build-init clean proto-gen prepare-service-builder-base
	@echo "Successfully built base image."
	@echo

check-prepare: check-version check-service-builder-base


build-fresh: build-init clean proto-gen service-build-from-scratch
	@echo "Built new base image and artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

build-plugin: check-prepare clean increment-build proto-gen service-build-once
	@echo "Built artifacts (DIR):"
	@find ./build -maxdepth 1 -print
	@echo

# Any artifacts should be under build/. Cleaning is simple.
clean: .init_build_file
	@rm -rf build/


check-vars: .check_vars

check-version: .init_build_file
	@echo "          Service: $(SERVICE)"
	@echo "  ASN SERVICE_API: [$(ASN_SERVICE_API_VERSION)]"
	@echo ""
	@echo "       Build Mode: $(BUILD_MODE)"
	@echo "  Current Version: [$(VERSION_BUILD)]"
	@echo "       Next Build: ($$(expr $(CURRENT_BUILD))->$$(expr $(CURRENT_BUILD) + 1))"
	@echo ""
	@$(MAKE) --no-print-directory check-go-mod

check-go-mod:
	@failed=0; compared=0; skipped=0; \
	root_requires=$$(mktemp); utils_requires=$$(mktemp); \
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
			printf "  %-48s Version: %s (expected %s). FAIL\n" "$$module" "$$actual" "$$expected"; \
			failed=1; \
		else \
			compared=$$(expr $$compared + 1); \
		fi; \
	done < "$$utils_requires"; \
	rm -f "$$root_requires" "$$utils_requires"; \
	if [ "$$failed" -ne 0 ]; then \
		echo ""; \
		echo ">>go.mod conflict check failed: shared packages must use the same versions."; \
		exit 1; \
	fi; \
	echo ">>go.mod conflict check passed: $$compared shared packages matched; $$skipped service-utils-only packages ignored."
	@echo ""

set-version: check-version
	@echo "Modify config.mk to update the version and build."
	@echo "NOTE: Only CI/CD or maintainer should change the version with caution."

increment-build: .increment_build

##----------------------------------------------------------------------------##
## Debian Package handling ##

uppercase = $(shell echo $(1) | tr a-z A-Z)

# Push and publish Debian packages.
debs:
	@echo "Please make target \"build-plugin\" instead."

# Push and publish Debian packages.
debs-push-%:
	$(eval REPO := $(call uppercase,$*))
	$(eval S_PATH := ${DEBIAN_PATH})
	$(eval T_HOST := ${DEB_REPO_HOST_$(REPO)})
	$(eval T_USER := ${DEB_REPO_USER_$(REPO)})
	$(eval T_PATH := ${DEB_REPO_PATH_$(REPO)})
	$(eval T_SUBREPO := ${DEB_REPO_SUBREPO_$(REPO)})
	$(eval T_SNAPSHOT := ${DEB_REPO_SUBREPO_$(REPO)}-$(shell date +%s))
	$(eval DISTS := ${DEBIAN_DIST_STABLE})

	$(eval T_T := ${T_USER}@${T_HOST})
	@$(call func_check_version_for_repo,$(REPO),$(CURRENT_BUILD))
	$(call func_push_debs)


# List local debs and debs of the same service in the repo.
debs-list-%:
	$(eval REPO := $(call uppercase,$*))
	$(eval S_PATH := ${DEBIAN_PATH})
	$(eval T_HOST := ${DEB_REPO_HOST_$(REPO)})
	$(eval T_USER := ${DEB_REPO_USER_$(REPO)})
	$(eval T_PATH := ${DEB_REPO_PATH_$(REPO)})
	$(eval T_SUBREPO := ${DEB_REPO_SUBREPO_$(REPO)})
	$(eval DISTS := ${DEBIAN_DIST_STABLE})

	$(eval T_T := ${T_USER}@${T_HOST})
	$(call func_list_debs)



# Function: func_check_variable
func_check_variable = $(if $(value $(1)),,$(error $(1) is not set))

# Function: func_check_version_for_repo
# Check if the build number is valid for the target repository
# $(1): REPO (DEV, CN, COM, etc.)
# $(2): BUILD_NUMBER
define func_check_version_for_repo
	@echo "Checking version compatibility for repository: $(1)"
	@echo "Current build number: $(2)"
	@if [ "$(1)" = "DEV" ]; then \
		if [ $(2) -lt 100 ]; then \
			echo "❌ ERROR: Build number $(2) is not allowed for DEV repository."; \
			echo "   DEV repository requires build number >= 100"; \
			echo "   Current version: $(VERSION_BUILD)"; \
			echo ""; \
			echo "   Please use BUILD_MODE=dev to build packages for DEV repository."; \
			exit 1; \
		else \
			echo "✅ Version check passed: Build number $(2) is valid for DEV repository (>= 100)"; \
		fi; \
	else \
		if [ $(2) -ge 100 ]; then \
			echo "❌ ERROR: Build number $(2) is not allowed for $(1) repository."; \
			echo "   Production repositories (CN, COM) require build number < 100"; \
			echo "   Current version: $(VERSION_BUILD)"; \
			echo ""; \
			echo "   Please use BUILD_MODE=pro and set BUILD number < 100 in make/config.mk"; \
			exit 1; \
		else \
			echo "✅ Version check passed: Build number $(2) is valid for $(1) repository (< 100)"; \
		fi; \
	fi
	@echo ""
endef

# Function to push debian packages.
define func_push_debs
	$(call func_check_variable,T_HOST)
	$(call func_check_variable,T_USER)
	$(call func_check_variable,T_PATH)
	$(call func_check_variable,S_PATH)
	$(call func_check_variable,T_SUBREPO)
	$(call func_check_variable,DEBIAN_SERVICES)
	$(call func_check_variable,DISTS)

	@echo "🧹 Cleaning up temporary directory before upload..."
	@http_code=$$(curl -k -s -w "%{http_code}" -o /tmp/curl_response.txt -X DELETE -u "$(T_USER)" "$(T_HOST)/files/${T_SUBREPO}"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "✅ Temporary directory cleaned successfully (HTTP $$http_code)"; \
	elif [ "$$http_code" -eq 404 ]; then \
		echo "ℹ️  Temporary directory does not exist (HTTP $$http_code) - will be created"; \
	else \
		echo "⚠️  Warning: Failed to clean temporary directory (HTTP $$http_code)"; \
		cat /tmp/curl_response.txt 2>/dev/null; \
		echo "   Continuing with upload..."; \
	fi; \
	rm -f /tmp/curl_response.txt
	@echo ""

	@echo "🔍 Checking for duplicate packages in repository..."
	@response=$$(curl -k -s -X GET -u "$(T_USER)" -H "Content-Type: application/json" "$(T_HOST)/repos/$(T_SUBREPO)/packages"); \
	if [ -z "$$response" ]; then \
		echo "⚠️  Warning: Could not fetch repository package list"; \
		echo "   Continuing with upload..."; \
	else \
		duplicate_found=false; \
		for svc in $(DEBIAN_SERVICES); do \
			files=$$(ls $(S_PATH)/$$svc*.deb 2>/dev/null); \
			if [ -z "$$files" ]; then \
				continue; \
			fi; \
			for file in $$files; do \
				pkg_name=$$(dpkg-deb -f $$file Package 2>/dev/null); \
				pkg_version=$$(dpkg-deb -f $$file Version 2>/dev/null); \
				if [ -n "$$pkg_name" ] && [ -n "$$pkg_version" ]; then \
					if echo "$$response" | grep -q "\"$$pkg_name\" \"$$pkg_version\""; then \
						echo "❌ ERROR: Package $$pkg_name version $$pkg_version already exists in repository"; \
						duplicate_found=true; \
					fi; \
				fi; \
			done; \
		done; \
	   if [ "$$duplicate_found" = "true" ]; then \
			echo ""; \
			echo "❌ Duplicate package(s) found in repository. Aborting upload."; \
			echo "   Please increment the version number and rebuild."; \
			exit 1; \
		else \
			echo "✅ No duplicate packages found"; \
		fi; \
	fi
	@echo ""

	@echo "- Locally built .deb files  for services: \"$(DEBIAN_SERVICES)\""
	@echo ""
	@upload_success=true; \
	uploaded_files=""; \
	for svc in $(DEBIAN_SERVICES); do \
		files=$$(ls $(S_PATH)/$$svc*.deb 2>/dev/null); \
		if [ -z "$$files" ]; then \
			echo "⚠️  No .deb files found for $$svc in $(S_PATH)"; \
			continue; \
		fi; \
		for file in $$files; do \
			echo -n "📦 Uploading $$(basename $$file) to temporary directory..."; \
			http_code=$$(curl -k -s -w "%{http_code}" -o /tmp/curl_response.txt -X POST -u "$(T_USER)" -F file=@$$file "$(T_HOST)/files/${T_SUBREPO}"); \
			if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
				echo " ✅ (HTTP $$http_code)"; \
				uploaded_files="$$uploaded_files$$file "; \
			else \
				echo " ❌ Failed (HTTP $$http_code)"; \
				cat /tmp/curl_response.txt 2>/dev/null; \
				echo ""; \
				upload_success=false; \
				break 2; \
			fi; \
		done; \
	done; \
	rm -f /tmp/curl_response.txt; \
	if [ "$$upload_success" = "false" ]; then \
		echo ""; \
		echo "❌ Upload failed. Cleaning up temporary files..."; \
		for file in $$uploaded_files; do \
			filename=$$(basename $$file); \
			echo -n "   Deleting $$filename from temporary directory..."; \
			curl -k -s -X DELETE -u "$(T_USER)" "$(T_HOST)/files/${T_SUBREPO}/$$filename" >/dev/null 2>&1; \
			echo " done"; \
		done; \
		echo ""; \
		echo "❌ ERROR: Debian package upload failed. Process aborted."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "✅ All files uploaded successfully to temporary directory"; \
	echo ""

	@echo "📋 Pushing files from temporary directory to repository..."
	@http_code=$$(curl -k -s -w "%{http_code}" -o /tmp/curl_response.txt -X POST -u "$(T_USER)" "$(T_HOST)/repos/${T_SUBREPO}/file/${T_SUBREPO}"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "✅ Files pushed to repository successfully (HTTP $$http_code)"; \
	else \
		echo "❌ Failed to push files to repository (HTTP $$http_code)"; \
		cat /tmp/curl_response.txt 2>/dev/null; \
		echo ""; \
		echo "⚠️  WARNING: Files remain in temporary directory ${T_SUBREPO}"; \
		echo "   Manual cleanup may be required"; \
		rm -f /tmp/curl_response.txt; \
		exit 1; \
	fi; \
	rm -f /tmp/curl_response.txt
	@echo ""

	@echo "📸 Creating Snapshot ${T_SNAPSHOT}..."
	@http_code=$$(curl -k -s -w "%{http_code}" -o /tmp/curl_response.txt -X POST -u "$(T_USER)" -H "Content-Type: application/json" -d "{\"Name\": \"${T_SNAPSHOT}\", \"Description\": \"Snapshot created by Makefile. \"}" "$(T_HOST)/repos/${T_SUBREPO}/snapshots"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "✅ Snapshot created successfully (HTTP $$http_code)"; \
	else \
		echo "❌ Failed to create snapshot (HTTP $$http_code)"; \
		cat /tmp/curl_response.txt 2>/dev/null; \
		rm -f /tmp/curl_response.txt; \
		exit 1; \
	fi; \
	rm -f /tmp/curl_response.txt
	@echo ""

	@echo "🚀 Publishing Snapshot ${T_SNAPSHOT}..."
	@http_code=$$(curl -k -s -w "%{http_code}" -o /tmp/curl_response.txt -X PUT -u "$(T_USER)" -H "Content-Type: application/json" -d "{ \"Snapshots\": [{\"Component\": \"main\", \"Name\": \"${T_SNAPSHOT}\"}],\"SigningOptions\": {\"Skip\": false}}" "$(T_HOST)/publish/:/${T_SUBREPO}"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "✅ Snapshot published successfully (HTTP $$http_code)"; \
	else \
		echo "❌ Failed to publish snapshot (HTTP $$http_code)"; \
		cat /tmp/curl_response.txt 2>/dev/null; \
		rm -f /tmp/curl_response.txt; \
		exit 1; \
	fi; \
	rm -f /tmp/curl_response.txt
	@echo ""
	@echo "🎉 Debian package deployment completed successfully!"
	@echo ""
endef

# Function to list debian packages.
define func_list_debs
	$(call func_check_variable,T_HOST)
	$(call func_check_variable,T_USER)
	$(call func_check_variable,T_PATH)
	$(call func_check_variable,S_PATH)
	$(call func_check_variable,T_SUBREPO)
	$(call func_check_variable,DEBIAN_SERVICES)
	$(call func_check_variable,DISTS)

	@echo "========================================"
	@echo "📦 Locally Built .deb Packages"
	@echo "========================================"
	@echo "Services: \"$(DEBIAN_SERVICES)\""
	@echo ""
	@if find $(S_PATH) -maxdepth 1 -name "*.deb" -print -quit 2>/dev/null | grep -q .; then \
		printf "%-50s %-15s %-10s\n" "FILENAME" "SIZE" "MODIFIED"; \
		printf "%-50s %-15s %-10s\n" "--------" "----" "--------"; \
		find $(S_PATH) -maxdepth 1 -name "*.deb" -exec sh -c 'printf "%-50s %-15s %-10s\n" "$$(basename "{}")" "$$(ls -lh "{}" | awk "{print \$$5}")" "$$(stat -f "%Sm" -t "%Y-%m-%d" "{}")"' \; | sort; \
	else \
		echo "(none)"; \
	fi
	@echo ""
	@echo "========================================"
	@echo "🌐 Remote Repository Packages"
	@echo "========================================"
	@echo "Repository: $(T_SUBREPO)"
	@echo ""
	@response=$$(curl -k -s -X GET -u "$(T_USER)" -H "Content-Type: application/json" "$(T_HOST)/repos/$(T_SUBREPO)/packages"); \
	if [ -z "$$response" ]; then \
		echo "(empty response from server)"; \
	elif command -v jq >/dev/null 2>&1; then \
		echo "$$response" | jq -e . >/dev/null 2>&1; \
		if [ $$? -eq 0 ]; then \
			count=$$(echo "$$response" | jq 'length'); \
			echo "$$response" | jq -r 'if type == "array" and length > 0 then (map(split(" ") | {pkg: .[1], ver: .[2], arch: (.[0] | ltrimstr("P")), hash: .[3], verparts: (.[2] | split(".") | map(tonumber))}) | sort_by([.pkg, .verparts]) | ["PACKAGE", "VERSION", "ARCH", "HASH"] as $$headers | ($$headers | @tsv), (["--------", "-------", "----", "----"] | @tsv), (.[] | [.pkg, .ver, .arch, .hash] | @tsv)) else "(no packages found)" end' \
			| column -t -s $$'\t'; \
			echo ""; \
			echo "Total: $$count package(s)"; \
		else \
			echo "⚠️  Invalid JSON response:"; \
			echo "$$response"; \
		fi; \
	else \
		echo "⚠️  jq not installed - showing raw response:"; \
		echo "   Install jq for better formatting: brew install jq"; \
		echo ""; \
		echo "$$response" | python3 -m json.tool 2>/dev/null || echo "$$response"; \
	fi
	@echo ""
	@echo "========================================"
endef

##----------------------------------------------------------------------------##
## Docker Image Handling ##

#------------------------------------------------------------------------------#

include $(BUILD_ENV_ASN_VERSION_FILE)

#------------------------------------------------------------------------------#

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
		--label asn.service_api=$(ASN_SERVICE_API_VERSION) \
		--label asn.framework=$(DEP_VERSION_ASN) \
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

# Check the builder base image required to build ASN Service Plugins.
check-service-builder-base:
	@if ! docker info >/dev/null 2>&1; then \
		echo "ERROR: Docker daemon is not reachable."; \
		echo "       check-prepare cannot verify $(BUILD_ENV_BASE_IMAGE):latest without Docker access."; \
		echo "       Fix Docker access or rerun in an approved Docker-capable environment."; \
		echo "Builder base image check failed."; \
		exit 1; \
	fi; \
	if ! docker image inspect $(BUILD_ENV_BASE_IMAGE):latest >/dev/null 2>&1; then \
		echo "ERROR: builder base image ($(BUILD_ENV_BASE_IMAGE):latest) was not found."; \
		echo "       Run build-prepare before build-plugin."; \
		echo "Builder base image check failed."; \
		exit 1; \
	fi; \
	failed=0; \
	api=$$(docker image inspect $(BUILD_ENV_BASE_IMAGE):latest --format '{{ index .Config.Labels "asn.service_api" }}' 2>/dev/null); \
	framework=$$(docker image inspect $(BUILD_ENV_BASE_IMAGE):latest --format '{{ index .Config.Labels "asn.framework" }}' 2>/dev/null); \
	print_check() { label="$$1"; actual="$$2"; expected="$$3"; if [ "$$actual" = "$$expected" ]; then printf "  %-24s Version: %s (expected). PASS\n" "$$label" "$${actual:-unknown}"; else printf "  %-24s Version: %s (expected %s). FAIL\n" "$$label" "$${actual:-unknown}" "$$expected"; failed=1; fi; }; \
	print_check "Builder API" "$$api" "$(ASN_SERVICE_API_VERSION)"; \
	print_check "Builder ASN Framework" "$$framework" "$(DEP_VERSION_ASN)"; \
	if [ "$$failed" -ne 0 ]; then \
		echo "Builder base image check failed. Run build-prepare."; \
		exit 1; \
	fi; \
	echo "Builder base image check passed: $(BUILD_ENV_BASE_IMAGE):latest matches API/framework versions."

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
		--label asn.service_api=$(ASN_SERVICE_API_VERSION) \
		--label asn.framework=$(DEP_VERSION_ASN) \
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
	@DOCKER_BUILDKIT=1 docker buildx build --platform linux/amd64 $(BUILD_ARGS) \
		--secret id=sshkey,src=$(SSH_PRIVATE_KEY) \
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
	@rm -rf $DEB_SVC_DIR

# Debug purpose
show-prepare:
	@echo "Current working directory: ${PWD}"
	@echo "Starting $(BUILD_ENV_BASE_IMAGE):latest"
	docker run --rm --platform linux/amd64 --name $(BUILD_ENV_BASE_IMAGE) $(BUILD_ENV_BASE_IMAGE):latest ls -l /

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
	if [ "$$current" = "$$expected" ]; then \
		echo "service-utils ref $$current already selected."; \
	else \
		echo "Selecting service-utils ref $$expected"; \
		cd $(SERVICE_UTILS_DIR) && \
		git fetch --prune origin && \
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
