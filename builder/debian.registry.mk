# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Shared Debian repository targets for ASN framework and services.

DEBIAN_PUSH_CHECK_TARGETS ?=
DEBIAN_PUSH_VERSION ?= $(VERSION_BUILD)
DEBIAN_REPO_SITES ?= $(DEBIAN_REPOS)
DEBIAN_RELEASE_CHANNEL ?= $(RELEASE_CHANNEL)
DEBIAN_TARGET_HINT ?= 'make push-debian-cn', 'make push-debian-us', or 'make push-debian'
DEBIAN_PACKAGE_DIR ?= $(DEBIAN_PATH)
DEBIAN_LOCAL_PACKAGE_DIRS ?= $(DEBIAN_PACKAGE_DIR)
DEBIAN_PACKAGE_FILES ?=
DEBIAN_REQUIRE_REMOTE_AUTH ?= yes
DEBIAN_METADATA_CMD ?= $(DEBIAN_PACKAGE_CMD) metadata

# The list/push recipes read credentials through shell variables such as
# $${DEBIAN_REPO_USER_CN} so curl invocations do not contain make-expanded
# secret values. Export the selected site variables because projects often
# derive them from RELEASE_SECRET_* values in config.mk or ignored local.mk.
debian_registry_uppercase = $(shell echo $(1) | tr a-z A-Z)
DEBIAN_REPO_USER_EXPORTS := $(foreach site,$(DEBIAN_REPO_SITES),DEBIAN_REPO_USER_$(call debian_registry_uppercase,$(site)))
export $(DEBIAN_REPO_USER_EXPORTS)

func_check_variable = $(if $(value $(1)),,$(error $(1) is not set))

.PHONY: \
	push-debian push-debian-cn push-debian-us push-debian-% check-push-debian-sites \
	list-debian list-debian-local list-debian-cn list-debian-us list-debian-%

push-debian: $(DEBIAN_PUSH_CHECK_TARGETS) check-push-debian-sites
	@for site in $(DEBIAN_REPO_SITES); do \
		$(MAKE) -s .push-debian-site SITE=$$site; \
	done

# Site-specific targets are thin selectors. The aggregate target owns all
# validation and push behavior, so site shortcuts cannot drift from it.
push-debian-cn: $(DEBIAN_PUSH_CHECK_TARGETS)
	@$(MAKE) -s push-debian DEBIAN_REPO_SITES=CN

push-debian-us: $(DEBIAN_PUSH_CHECK_TARGETS)
	@$(MAKE) -s push-debian DEBIAN_REPO_SITES=US

push-debian-%: $(DEBIAN_PUSH_CHECK_TARGETS)
	@$(MAKE) -s push-debian DEBIAN_REPO_SITES=$(call uppercase,$*)

check-push-debian-sites:
	@if [ -z "$(strip $(DEBIAN_REPO_SITES))" ]; then \
		echo "ERROR: DEBIAN_REPO_SITES is empty."; \
		exit 1; \
	fi
	@for site in $(DEBIAN_REPO_SITES); do \
		$(MAKE) -s .check-debian-repo SITE=$$site; \
	done
	@echo "Debian publish site preflight passed: $(DEBIAN_REPO_SITES)"
	@echo ""

.check-debian-repo:
	$(eval DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval DEBIAN_USER_SET := $(if $(strip $(DEBIAN_REPO_USER_$(DEBIAN_SITE))),yes,no))
	$(eval DEBIAN_USER_FORMAT := $(if $(findstring :,$(DEBIAN_REPO_USER_$(DEBIAN_SITE))),user:password,invalid))
	@if [ -z "$(DEBIAN_REPO_HOST_$(DEBIAN_SITE))" ]; then \
		echo "ERROR: Debian repo $(DEBIAN_SITE) is not configured."; \
		echo "Required: DEBIAN_REPO_HOST_$(DEBIAN_SITE)."; \
		exit 1; \
	fi
	@if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ] && [ "$(DEBIAN_USER_SET)" != "yes" ]; then \
		echo "ERROR: Debian repo $(DEBIAN_SITE) is not fully configured."; \
		echo "Required: DEBIAN_REPO_HOST_$(DEBIAN_SITE), DEBIAN_REPO_USER_$(DEBIAN_SITE)."; \
		exit 1; \
	fi
	@if [ "$(DEBIAN_USER_SET)" = "yes" ] && [ "$(DEBIAN_USER_FORMAT)" != "user:password" ]; then \
		echo "ERROR: Debian repo credential for $(DEBIAN_SITE) must use user:password format."; \
		exit 1; \
	fi

.push-debian-site:
	$(eval DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval DEBIAN_CHANNEL := $(if $(strip $(DEBIAN_RELEASE_CHANNEL)),$(call uppercase,$(DEBIAN_RELEASE_CHANNEL)),$(DEBIAN_SITE)))
	$(eval T_HOST := $(if ${DEBIAN_REPO_HOST_$(DEBIAN_SITE)},${DEBIAN_REPO_HOST_$(DEBIAN_SITE)},__UNCONFIGURED__))
	$(eval T_USER_VAR := DEBIAN_REPO_USER_$(DEBIAN_SITE))
	$(eval T_USER_SET := $(if $(strip $(DEBIAN_REPO_USER_$(DEBIAN_SITE))),yes,no))
	$(eval T_USER_FORMAT := $(if $(findstring :,$(DEBIAN_REPO_USER_$(DEBIAN_SITE))),user:password,invalid))
	$(eval T_SUBREPO := $(if ${DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL)},${DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL)},__UNCONFIGURED__))
	$(eval T_SNAPSHOT := ${T_SUBREPO}-$(shell date +%s))
	@if [ "$(T_HOST)" = "__UNCONFIGURED__" ] || [ "$(T_USER_SET)" != "yes" ]; then \
		echo "ERROR: Debian repo $(DEBIAN_SITE) is not fully configured."; \
		echo "Required: DEBIAN_REPO_HOST_$(DEBIAN_SITE), DEBIAN_REPO_USER_$(DEBIAN_SITE)."; \
		exit 1; \
	fi
	@if [ "$(T_USER_SET)" = "yes" ] && [ "$(T_USER_FORMAT)" != "user:password" ]; then \
		echo "ERROR: Debian repo credential for $(DEBIAN_SITE) must use user:password format."; \
		exit 1; \
	fi
	@if [ "$(T_SUBREPO)" = "__UNCONFIGURED__" ]; then \
		echo "ERROR: DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL) is not configured."; \
		exit 1; \
	fi
	@echo ">> Debian Publish Target"
	@printf "  %15s : %s\n" "Site" "$(DEBIAN_SITE)"
	@printf "  %15s : %s\n" "Repo Host" "$(T_HOST)"
	@printf "  %15s : %s\n" "Subrepo" "$(T_SUBREPO)"
	@printf "  %15s : %s\n" "Version" "$(DEBIAN_PUSH_VERSION)"
	@echo ""
	$(call func_push_debs)

list-debian: list-debian-local
	@if [ -z "$(strip $(DEBIAN_REPO_SITES))" ]; then \
		echo "No Debian repository sites configured."; \
		echo ""; \
	else \
		for site in $(DEBIAN_REPO_SITES); do \
			$(MAKE) -s .list-debian-site SITE=$$site; \
		done; \
	fi

list-debian-local:
	$(call func_list_local_debs)

# Site-specific list targets mirror the push selector model: they only set the
# configured site list, while `list-debian` owns local and remote list behavior.
list-debian-cn:
	@$(MAKE) -s list-debian DEBIAN_REPO_SITES=CN

list-debian-us:
	@$(MAKE) -s list-debian DEBIAN_REPO_SITES=US

list-debian-%:
	@$(MAKE) -s list-debian DEBIAN_REPO_SITES=$(call uppercase,$*)

.list-debian-site:
	$(eval DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval DEBIAN_CHANNEL := $(if $(strip $(DEBIAN_RELEASE_CHANNEL)),$(call uppercase,$(DEBIAN_RELEASE_CHANNEL)),$(DEBIAN_SITE)))
	$(eval T_HOST := $(if ${DEBIAN_REPO_HOST_$(DEBIAN_SITE)},${DEBIAN_REPO_HOST_$(DEBIAN_SITE)},__UNCONFIGURED__))
	$(eval T_USER_VAR := DEBIAN_REPO_USER_$(DEBIAN_SITE))
	$(eval T_USER_SET := $(if $(strip $(DEBIAN_REPO_USER_$(DEBIAN_SITE))),yes,no))
	$(eval T_USER_FORMAT := $(if $(findstring :,$(DEBIAN_REPO_USER_$(DEBIAN_SITE))),user:password,invalid))
	$(eval T_SUBREPO := $(if ${DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL)},${DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL)},__UNCONFIGURED__))
	@if [ "$(T_HOST)" = "__UNCONFIGURED__" ]; then \
		echo "Debian repo $(DEBIAN_SITE) is not configured."; \
		echo "Required: DEBIAN_REPO_HOST_$(DEBIAN_SITE)."; \
		if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		echo ""; \
	fi
	@if [ "$(T_HOST)" != "__UNCONFIGURED__" ] && [ "$(T_USER_SET)" != "yes" ]; then \
		echo "Debian repo credentials are not configured for $(DEBIAN_SITE)."; \
		echo "Set DEBIAN_REPO_USER_$(DEBIAN_SITE)='user:password' to list remote packages."; \
		if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		echo ""; \
	fi
	@if [ "$(T_HOST)" != "__UNCONFIGURED__" ] && [ "$(T_USER_SET)" = "yes" ] && [ "$(T_USER_FORMAT)" != "user:password" ]; then \
		echo "Debian repo credential for $(DEBIAN_SITE) must use user:password format."; \
		if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		echo ""; \
	fi
	@if [ "$(T_HOST)" != "__UNCONFIGURED__" ] && [ "$(T_USER_SET)" = "yes" ] && [ "$(T_SUBREPO)" = "__UNCONFIGURED__" ]; then \
		echo "DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL) is not configured."; \
		if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		echo ""; \
	fi
	$(if $(and $(filter-out __UNCONFIGURED__,$(T_HOST)),$(filter yes,$(T_USER_SET)),$(filter user:password,$(T_USER_FORMAT)),$(filter-out __UNCONFIGURED__,$(T_SUBREPO))),$(call func_list_remote_debs),@:)

define func_push_debs
	$(call func_check_variable,T_HOST)
	$(call func_check_variable,T_USER_VAR)
	$(call func_check_variable,T_SUBREPO)

	@package_files="$(DEBIAN_PACKAGE_FILES)"; \
	if [ -z "$$package_files" ]; then \
		if [ -d "$(DEBIAN_PACKAGE_DIR)" ]; then \
			for svc in $(DEBIAN_SERVICES); do \
				files=$$(find "$(DEBIAN_PACKAGE_DIR)" -maxdepth 1 -type f -name "$${svc}_*.deb" -print | sort); \
				if [ -n "$$files" ]; then package_files="$$package_files $$files"; fi; \
			done; \
		else \
			echo "Debian package directory is missing: $(DEBIAN_PACKAGE_DIR)"; \
		fi; \
	fi; \
	if [ -z "$$package_files" ]; then \
		echo "ERROR: no Debian package files found."; \
		echo "Run make build-debian before $(DEBIAN_TARGET_HINT)."; \
		exit 1; \
	fi; \
	echo "- Locally built .deb files"; \
	echo ""; \
	missing_files=false; \
	for file in $$package_files; do \
		if [ ! -f "$$file" ]; then \
			echo "Package file not found: $$file"; \
			missing_files=true; \
		else \
			printf "  %s\n" "$$file"; \
		fi; \
	done; \
	if [ "$$missing_files" = "true" ]; then \
		echo ""; \
		echo "ERROR: Debian package file check failed before any remote repository mutation."; \
		echo "Run make build-debian before $(DEBIAN_TARGET_HINT)."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "Cleaning temporary upload directory..."; \
	http_code=$$(curl -k -sS -w "%{http_code}" -o /tmp/curl_response.txt -X DELETE -u "$${$(T_USER_VAR)}" "$(T_HOST)/files/${T_SUBREPO}"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Temporary directory cleaned successfully (HTTP $$http_code)"; \
	elif [ "$$http_code" -eq 404 ]; then \
		echo "Temporary directory does not exist (HTTP $$http_code); it will be created."; \
	else \
		echo "Warning: failed to clean temporary directory (HTTP $$http_code)."; \
		if [ -s /tmp/curl_response.txt ]; then cat /tmp/curl_response.txt; fi; \
		echo "Continuing with upload."; \
	fi; \
	rm -f /tmp/curl_response.txt; \
	echo ""; \
	echo "Checking for duplicate packages in repository..."; \
	response=$$(curl -k -sS -X GET -u "$${$(T_USER_VAR)}" -H "Content-Type: application/json" "$(T_HOST)/repos/${T_SUBREPO}/packages"); \
	if [ -z "$$response" ]; then \
		echo "Warning: could not fetch repository package list."; \
		echo "Continuing with upload."; \
	else \
		duplicate_found=false; \
		metadata_failed=false; \
		for file in $$package_files; do \
			if ! pkg_name=$$($(DEBIAN_METADATA_CMD) --file "$$file" --field Package 2>&1); then \
				echo "ERROR: cannot read Package metadata from $$file"; \
				echo "$$pkg_name"; \
				metadata_failed=true; \
				continue; \
			fi; \
			if ! pkg_version=$$($(DEBIAN_METADATA_CMD) --file "$$file" --field Version 2>&1); then \
				echo "ERROR: cannot read Version metadata from $$file"; \
				echo "$$pkg_version"; \
				metadata_failed=true; \
				continue; \
			fi; \
			if [ -n "$$pkg_name" ] && [ -n "$$pkg_version" ]; then \
				if echo "$$response" | grep -q "\"$$pkg_name\" \"$$pkg_version\""; then \
					echo "ERROR: Package $$pkg_name version $$pkg_version already exists in repository"; \
					duplicate_found=true; \
				fi; \
			fi; \
		done; \
		if [ "$$metadata_failed" = "true" ]; then \
			echo ""; \
			echo "ERROR: package metadata check failed. Aborting upload."; \
			exit 1; \
		elif [ "$$duplicate_found" = "true" ]; then \
			echo ""; \
			echo "ERROR: duplicate package(s) found in repository. Aborting upload."; \
			echo "Please increment the version number and rebuild."; \
			exit 1; \
		else \
			echo "No duplicate packages found."; \
		fi; \
	fi; \
	upload_success=true; \
	uploaded_files=""; \
	for file in $$package_files; do \
		printf "%s" "Uploading $$(basename $$file) to temporary directory..."; \
		http_code=$$(curl -k -sS -w "%{http_code}" -o /tmp/curl_response.txt -X POST -u "$${$(T_USER_VAR)}" -F file=@$$file "$(T_HOST)/files/${T_SUBREPO}"); \
		if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
			echo " done (HTTP $$http_code)"; \
			uploaded_files="$$uploaded_files$$file "; \
		else \
			echo " failed (HTTP $$http_code)"; \
			if [ -s /tmp/curl_response.txt ]; then cat /tmp/curl_response.txt; fi; \
			echo ""; \
			upload_success=false; \
			break; \
		fi; \
	done; \
	rm -f /tmp/curl_response.txt; \
	if [ "$$upload_success" = "false" ]; then \
		echo ""; \
		echo "Upload failed. Cleaning up temporary files..."; \
		for file in $$uploaded_files; do \
			filename=$$(basename $$file); \
			printf "%s" "   Deleting $$filename from temporary directory..."; \
			if delete_error=$$(curl -k -sS -X DELETE -u "$${$(T_USER_VAR)}" "$(T_HOST)/files/${T_SUBREPO}/$$filename" 2>&1 >/dev/null); then \
				echo " done"; \
			else \
				echo " failed"; \
				if [ -n "$$delete_error" ]; then echo "$$delete_error"; fi; \
			fi; \
		done; \
		echo ""; \
		echo "ERROR: Debian package upload failed. Process aborted."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "All files uploaded successfully to temporary directory."; \
	echo ""; \
	echo "Pushing files from temporary directory to repository..."; \
	http_code=$$(curl -k -sS -w "%{http_code}" -o /tmp/curl_response.txt -X POST -u "$${$(T_USER_VAR)}" "$(T_HOST)/repos/${T_SUBREPO}/file/${T_SUBREPO}"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Files pushed to repository successfully (HTTP $$http_code)"; \
	else \
		echo "Failed to push files to repository (HTTP $$http_code)"; \
		if [ -s /tmp/curl_response.txt ]; then cat /tmp/curl_response.txt; fi; \
		echo ""; \
		echo "WARNING: files remain in temporary directory ${T_SUBREPO}."; \
		rm -f /tmp/curl_response.txt; \
		exit 1; \
	fi; \
	rm -f /tmp/curl_response.txt; \
	echo ""; \
	echo "Creating snapshot ${T_SNAPSHOT}..."; \
	http_code=$$(curl -k -sS -w "%{http_code}" -o /tmp/curl_response.txt -X POST -u "$${$(T_USER_VAR)}" -H "Content-Type: application/json" -d "{\"Name\": \"${T_SNAPSHOT}\", \"Description\": \"Snapshot created by Makefile. \"}" "$(T_HOST)/repos/${T_SUBREPO}/snapshots"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Snapshot created successfully (HTTP $$http_code)"; \
	else \
		echo "Failed to create snapshot (HTTP $$http_code)"; \
		if [ -s /tmp/curl_response.txt ]; then cat /tmp/curl_response.txt; fi; \
		rm -f /tmp/curl_response.txt; \
		exit 1; \
	fi; \
	rm -f /tmp/curl_response.txt; \
	echo ""; \
	echo "Publishing snapshot ${T_SNAPSHOT}..."; \
	http_code=$$(curl -k -sS -w "%{http_code}" -o /tmp/curl_response.txt -X PUT -u "$${$(T_USER_VAR)}" -H "Content-Type: application/json" -d "{ \"Snapshots\": [{\"Component\": \"main\", \"Name\": \"${T_SNAPSHOT}\"}],\"SigningOptions\": {\"Skip\": false}}" "$(T_HOST)/publish/:/${T_SUBREPO}"); \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Snapshot published successfully (HTTP $$http_code)"; \
	else \
		echo "Failed to publish snapshot (HTTP $$http_code)"; \
		if [ -s /tmp/curl_response.txt ]; then cat /tmp/curl_response.txt; fi; \
		rm -f /tmp/curl_response.txt; \
		exit 1; \
	fi; \
	rm -f /tmp/curl_response.txt; \
	echo ""; \
	echo "Debian package deployment completed successfully."; \
	echo ""
endef

define func_list_local_debs
	@echo ">> Local Debian Packages"
	@printf "  %15s : %s\n" "Directories" "$(DEBIAN_LOCAL_PACKAGE_DIRS)"
	@printf "  %15s : %s\n" "Services" "$(DEBIAN_SERVICES)"
	@echo ""
	@found=false; \
	for dir in $(DEBIAN_LOCAL_PACKAGE_DIRS); do \
		if [ -d "$$dir" ] && find "$$dir" -maxdepth 1 -name "*.deb" -print -quit | grep -q .; then \
			found=true; \
			find "$$dir" -maxdepth 1 -name "*.deb" -exec sh -c 'printf "%-50s %-15s %-10s\n" "$$(basename "{}")" "$$(ls -lh "{}" | awk "{print \$$5}")" "$$(stat -f "%Sm" -t "%Y-%m-%d" "{}")"' \; | sort; \
		fi; \
	done; \
	if [ "$$found" != "true" ]; then \
		echo "(none)"; \
	fi
	@echo ""
endef

define func_list_remote_debs
	$(call func_check_variable,T_HOST)
	$(call func_check_variable,T_USER_VAR)
	$(call func_check_variable,T_SUBREPO)

	@echo ">> Remote Debian Repository Packages"
	@printf "  %15s : %s\n" "Site" "$(DEBIAN_SITE)"
	@printf "  %15s : %s\n" "Repo Host" "$(T_HOST)"
	@printf "  %15s : %s\n" "Subrepo" "$(T_SUBREPO)"
	@echo ""
	@response=$$(curl -k -sS -X GET -u "$${$(T_USER_VAR)}" -H "Content-Type: application/json" "$(T_HOST)/repos/$(T_SUBREPO)/packages"); \
	if [ -z "$$response" ]; then \
		echo "(empty response from server)"; \
		if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
	elif command -v jq >/dev/null; then \
		if echo "$$response" | jq -e 'type == "array"' >/dev/null; then \
			count=$$(echo "$$response" | jq 'length'); \
			echo "$$response" | jq -r 'if type == "array" and length > 0 then (map(split(" ") | {pkg: .[1], ver: .[2], arch: (.[0] | ltrimstr("P")), hash: .[3], verparts: (.[2] | split(".") | map(tonumber))}) | sort_by([.pkg, .verparts]) | ["PACKAGE", "VERSION", "ARCH", "HASH"] as $$headers | ($$headers | @tsv), (["--------", "-------", "----", "----"] | @tsv), (.[] | [.pkg, .ver, .arch, .hash] | @tsv)) else "(no packages found)" end' \
			| column -t -s $$'\t'; \
			echo ""; \
			echo "Total: $$count package(s)"; \
		else \
			echo "Invalid JSON response:"; \
			echo "$$response"; \
			if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		fi; \
	else \
		echo "jq is not installed; showing raw response:"; \
		echo ""; \
		echo "$$response" | python3 -m json.tool || echo "$$response"; \
	fi
	@echo ""
endef
