# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Shared Debian repository targets for ASN framework and services.

DEBIAN_PUSH_CHECK_TARGETS ?=
DEBIAN_INTERNAL_PUSH_CHECK_TARGETS ?= $(DEBIAN_PUSH_CHECK_TARGETS)
DEBIAN_PUSH_VERSION ?= $(VERSION_BUILD)
DEBIAN_REPO_SITES ?= $(DEBIAN_REPOS)
DEBIAN_RELEASE_CHANNEL ?= $(RELEASE_CHANNEL)
DEBIAN_TARGET_HINT ?= 'make push-debian-cn', 'make push-debian-us', or 'make push-debian'
DEBIAN_PACKAGE_DIR ?= $(DEBIAN_PATH)
DEBIAN_LOCAL_PACKAGE_DIRS ?= $(DEBIAN_PACKAGE_DIR)
DEBIAN_PACKAGE_FILES ?=
DEBIAN_REQUIRE_REMOTE_AUTH ?= yes
DEBIAN_METADATA_CMD ?= $(DEBIAN_PACKAGE_CMD) metadata
DEBIAN_ALLOW_INSECURE_TLS ?= no
DEBIAN_INSECURE_TLS_APPROVED ?= no
DEBIAN_CURL_TLS_FLAGS ?= $(if $(filter yes,$(DEBIAN_ALLOW_INSECURE_TLS)),-k,)
DEBIAN_CURL_TIMEOUT_FLAGS ?= --connect-timeout 10 --max-time 300
DEBIAN_CURL_RETRY_FLAGS ?= --retry 2 --retry-delay 2 --retry-connrefused
DEBIAN_CURL_READ_FLAGS ?= $(DEBIAN_CURL_TLS_FLAGS) $(DEBIAN_CURL_TIMEOUT_FLAGS) $(DEBIAN_CURL_RETRY_FLAGS)
DEBIAN_CURL_MUTATION_FLAGS ?= $(DEBIAN_CURL_TLS_FLAGS) $(DEBIAN_CURL_TIMEOUT_FLAGS)
SERVICE_UTILS_RECURSIVE_MAKE ?= $(MAKE)

# The list/push recipes read credentials through shell variables such as
# $${DEBIAN_REPO_USER_CN} so curl invocations do not contain make-expanded
# secret values. Export the selected site variables because projects often
# derive them from RELEASE_SECRET_* values in make/config.mk or ignored make/local.mk.
debian_registry_uppercase = $(call uppercase,$(1))
DEBIAN_REPO_USER_EXPORTS := $(foreach site,$(DEBIAN_REPO_SITES),DEBIAN_REPO_USER_$(call debian_registry_uppercase,$(site)))
export $(DEBIAN_REPO_USER_EXPORTS)

func_check_variable = $(if $(value $(1)),,$(error $(1) is not set))

define func_check_debian_curl_tls_flags
	@for flag in $(DEBIAN_CURL_TLS_FLAGS); do \
		case "$$flag" in \
			-k|--insecure) \
				if [ "$(DEBIAN_ALLOW_INSECURE_TLS)" != "yes" ]; then \
					echo "ERROR: insecure Debian curl TLS flag '$$flag' requires DEBIAN_ALLOW_INSECURE_TLS=yes."; \
					exit 1; \
				elif [ "$(DEBIAN_INSECURE_TLS_APPROVED)" != "yes" ]; then \
					echo "ERROR: insecure Debian curl TLS flag '$$flag' requires DEBIAN_INSECURE_TLS_APPROVED=yes plus explicit release approval."; \
					exit 1; \
				fi ;; \
		esac; \
	done
endef

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
		echo ">> Debian Site Preflight: [FAIL]"; \
		printf "  %15s : %s\n" "Selected sites" "<empty>"; \
		echo "ERROR: DEBIAN_REPO_SITES is empty."; \
		exit 1; \
	fi
	@set +e; \
	echo ">> Debian Site Preflight"; \
	printf "  %15s : %s\n" "Selected sites" "$(DEBIAN_REPO_SITES)"; \
	failed=0; \
	for site in $(DEBIAN_REPO_SITES); do \
		output="$$( $(SERVICE_UTILS_RECURSIVE_MAKE) -s .check-debian-repo SITE=$$site 2>&1 )"; \
		status="$$?"; \
		if [ "$$status" -ne 0 ]; then \
			if [ -n "$$output" ]; then \
				printf "%s\n" "$$output" | sed '/^make\[[0-9][0-9]*\]: \*\*\*/d;/^make: \*\*\*/d'; \
			fi; \
			failed=1; \
		fi; \
	done; \
	if [ "$$failed" -ne 0 ]; then \
		echo ">> Debian Site Preflight: [FAIL]"; \
		exit 1; \
	fi; \
	echo ">> Debian Site Preflight: [PASS]"
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
	@if ! printf '%s\n' "$(DEBIAN_REPO_HOST_$(DEBIAN_SITE))" | grep -Eq '^https://'; then \
		echo "ERROR: Debian repo $(DEBIAN_SITE) must use https:// when credentials are configured."; \
		exit 1; \
	fi
	@if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ] && [ "$(DEBIAN_USER_SET)" != "yes" ]; then \
		echo "ERROR: Debian repo $(DEBIAN_SITE) is not fully configured."; \
			echo "Required: DEBIAN_REPO_HOST_$(DEBIAN_SITE), DEBIAN_REPO_USER_$(DEBIAN_SITE)."; \
			exit 1; \
		fi
	@if ! command -v jq >/dev/null; then \
		echo "ERROR: jq is required before Debian repository mutation."; \
		exit 1; \
	fi
	@if [ "$(DEBIAN_USER_SET)" = "yes" ] && [ "$(DEBIAN_USER_FORMAT)" != "user:password" ]; then \
		echo "ERROR: Debian repo credential for $(DEBIAN_SITE) must use user:password format."; \
		exit 1; \
	fi
	@if [ "$(DEBIAN_ALLOW_INSECURE_TLS)" = "yes" ]; then \
		if [ "$(DEBIAN_INSECURE_TLS_APPROVED)" != "yes" ]; then \
			echo "ERROR: DEBIAN_ALLOW_INSECURE_TLS=yes disables TLS verification and requires DEBIAN_INSECURE_TLS_APPROVED=yes plus explicit release approval."; \
			exit 1; \
		fi; \
		echo "WARN: DEBIAN_ALLOW_INSECURE_TLS=yes approved for this command; TLS certificate verification is disabled."; \
	fi

.push-debian-site: $(DEBIAN_INTERNAL_PUSH_CHECK_TARGETS)
	$(eval DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval DEBIAN_CHANNEL := $(if $(strip $(DEBIAN_RELEASE_CHANNEL)),$(call uppercase,$(DEBIAN_RELEASE_CHANNEL)),$(DEBIAN_SITE)))
	$(eval T_HOST := $(if ${DEBIAN_REPO_HOST_$(DEBIAN_SITE)},${DEBIAN_REPO_HOST_$(DEBIAN_SITE)},__UNCONFIGURED__))
	$(eval T_USER_VAR := DEBIAN_REPO_USER_$(DEBIAN_SITE))
	$(eval T_USER_SET := $(if $(strip $(DEBIAN_REPO_USER_$(DEBIAN_SITE))),yes,no))
	$(eval T_USER_FORMAT := $(if $(findstring :,$(DEBIAN_REPO_USER_$(DEBIAN_SITE))),user:password,invalid))
	$(eval T_SUBREPO := $(if ${DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL)},${DEBIAN_REPO_SUBREPO_$(DEBIAN_CHANNEL)},__UNCONFIGURED__))
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
	@printf "  %15s : %s\n" "Version" "$(if $(strip $(DEBIAN_PUSH_VERSION)),$(DEBIAN_PUSH_VERSION),(manifest debian lane))"
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
	$(call func_check_debian_curl_tls_flags)

	@selected_version="$(DEBIAN_PUSH_VERSION)"; \
	if [ -z "$$selected_version" ]; then \
		selected_version="$$($(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS))"; \
	fi; \
	printf "  %15s : %s\n" "Effective Version" "$$selected_version"; \
	echo ""; \
	package_files="$(DEBIAN_PACKAGE_FILES)"; \
	if [ -z "$$package_files" ]; then \
		if [ -d "$(DEBIAN_PACKAGE_DIR)" ]; then \
			for svc in $(DEBIAN_SERVICES); do \
				files=$$(find "$(DEBIAN_PACKAGE_DIR)" -maxdepth 1 -type f -name "$${svc}_$${selected_version}_amd64.deb" -print | sort); \
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
			case " $(DEBIAN_SERVICES) " in \
				*" $$pkg_name "*) : ;; \
				*) echo "ERROR: package $$pkg_name from $$file is not in DEBIAN_SERVICES: $(DEBIAN_SERVICES)"; metadata_failed=true ;; \
			esac; \
			if [ "$$pkg_version" != "$$selected_version" ]; then \
				echo "ERROR: package $$pkg_name from $$file has version $$pkg_version, expected $$selected_version."; \
				metadata_failed=true; \
			fi; \
		done; \
		if [ "$$metadata_failed" = "true" ]; then \
			echo ""; \
			echo "ERROR: package identity check failed before any remote repository mutation."; \
			exit 1; \
			fi; \
			echo ""; \
			snapshot="$(T_SUBREPO)-$${selected_version}-$$(date +%Y%m%d%H%M%S)-$$$$"; \
			if ! command -v jq >/dev/null; then \
				echo "ERROR: jq is required to parse repository package lists before any remote mutation."; \
				exit 1; \
			fi; \
			curl_response_file="$$(mktemp "$${TMPDIR:-/tmp}/debian-push-response.XXXXXX")"; \
			curl_config_file="$$(mktemp "$${TMPDIR:-/tmp}/debian-curl-config.XXXXXX")"; \
		chmod 600 "$$curl_config_file"; \
		repo_credential="$${$(T_USER_VAR)}"; \
		printf 'user = "%s"\n' "$$repo_credential" > "$$curl_config_file"; \
		trap 'rm -f "$$curl_response_file" "$$curl_config_file"' EXIT; \
		trap 'rm -f "$$curl_response_file" "$$curl_config_file"; exit 130' INT; \
			trap 'rm -f "$$curl_response_file" "$$curl_config_file"; exit 143' TERM; \
			echo "Cleaning temporary upload directory..."; \
			: > "$$curl_response_file"; \
			if ! http_code=$$(curl $(DEBIAN_CURL_MUTATION_FLAGS) -sS -w "%{http_code}" -o "$$curl_response_file" -X DELETE --config "$$curl_config_file" "$(T_HOST)/files/${T_SUBREPO}"); then \
				echo "ERROR: failed to clean temporary directory (curl transport failure); refusing to upload into an unknown remote staging state."; \
				if [ -s "$$curl_response_file" ]; then cat "$$curl_response_file"; fi; \
				exit 1; \
			fi; \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Temporary directory cleaned successfully (HTTP $$http_code)"; \
	elif [ "$$http_code" -eq 404 ]; then \
		echo "Temporary directory does not exist (HTTP $$http_code); it will be created."; \
	else \
		echo "ERROR: failed to clean temporary directory (HTTP $$http_code); refusing to upload into an unknown remote staging state."; \
		if [ -s "$$curl_response_file" ]; then cat "$$curl_response_file"; fi; \
		exit 1; \
	fi; \
	echo ""; \
	echo "Checking for duplicate packages in repository..."; \
	: > "$$curl_response_file"; \
	if ! http_code=$$(curl $(DEBIAN_CURL_READ_FLAGS) -sS -w "%{http_code}" -o "$$curl_response_file" -X GET --config "$$curl_config_file" -H "Content-Type: application/json" "$(T_HOST)/repos/${T_SUBREPO}/packages"); then \
			echo "ERROR: could not fetch repository package list; refusing to upload without duplicate protection."; \
			if [ -s "$$curl_response_file" ]; then cat "$$curl_response_file"; fi; \
			exit 1; \
		fi; \
		response="$$(cat "$$curl_response_file")"; \
	if [ "$$http_code" -lt 200 ] || [ "$$http_code" -ge 300 ]; then \
		echo "ERROR: could not fetch repository package list (HTTP $$http_code); refusing to upload without duplicate protection."; \
		if [ -n "$$response" ]; then echo "$$response"; fi; \
		exit 1; \
	fi; \
	if [ -z "$$response" ]; then \
		echo "ERROR: repository package list response is empty; refusing to upload without duplicate protection."; \
		exit 1; \
	elif ! printf "%s" "$$response" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null; then \
		echo "ERROR: repository package list response has an unexpected format; refusing to upload without duplicate protection."; \
		exit 1; \
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
				if printf "%s" "$$response" | jq -e --arg pkg "$$pkg_name" --arg ver "$$pkg_version" 'any(.[]; (split(" ") as $$parts | ($$parts | length) >= 3 and $$parts[1] == $$pkg and $$parts[2] == $$ver))' >/dev/null; then \
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
				printf "%s" "Uploading $$(basename "$$file") to temporary directory..."; \
				: > "$$curl_response_file"; \
				if ! http_code=$$(curl $(DEBIAN_CURL_MUTATION_FLAGS) -sS -w "%{http_code}" -o "$$curl_response_file" -X POST --config "$$curl_config_file" -F file=@"$$file" "$(T_HOST)/files/${T_SUBREPO}"); then \
					http_code="000"; \
				fi; \
		if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
			echo " done (HTTP $$http_code)"; \
			uploaded_files="$$uploaded_files$$file "; \
			else \
				echo " failed (HTTP $$http_code)"; \
				if [ -s "$$curl_response_file" ]; then cat "$$curl_response_file"; fi; \
				echo ""; \
				upload_success=false; \
				break; \
			fi; \
		done; \
	if [ "$$upload_success" = "false" ]; then \
		echo ""; \
		echo "Upload failed. Cleaning up temporary files..."; \
			for file in $$uploaded_files; do \
				filename=$$(basename "$$file"); \
				printf "%s" "   Deleting $$filename from temporary directory..."; \
				delete_output=$$(mktemp); \
				delete_status=0; \
				delete_http_code=$$(curl $(DEBIAN_CURL_MUTATION_FLAGS) -sS -w "%{http_code}" -o "$$delete_output" -X DELETE --config "$$curl_config_file" "$(T_HOST)/files/${T_SUBREPO}/$$filename" 2>>"$$delete_output") || delete_status=$$?; \
				if [ "$$delete_status" = "0" ] && { { [ "$$delete_http_code" -ge 200 ] && [ "$$delete_http_code" -lt 300 ]; } || [ "$$delete_http_code" -eq 404 ]; }; then \
					echo " done (HTTP $$delete_http_code)"; \
				else \
					echo " failed"; \
					if [ -n "$$delete_http_code" ]; then echo "HTTP $$delete_http_code"; fi; \
					if [ -s "$$delete_output" ]; then cat "$$delete_output"; fi; \
				fi; \
			rm -f "$$delete_output"; \
		done; \
		echo ""; \
		echo "ERROR: Debian package upload failed. Process aborted."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "All files uploaded successfully to temporary directory."; \
		echo ""; \
			echo "Pushing files from temporary directory to repository..."; \
			: > "$$curl_response_file"; \
			if ! http_code=$$(curl $(DEBIAN_CURL_MUTATION_FLAGS) -sS -w "%{http_code}" -o "$$curl_response_file" -X POST --config "$$curl_config_file" "$(T_HOST)/repos/${T_SUBREPO}/file/${T_SUBREPO}"); then \
				http_code="000"; \
			fi; \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Files pushed to repository successfully (HTTP $$http_code)"; \
		else \
			echo "Failed to push files to repository (HTTP $$http_code)"; \
			if [ -s "$$curl_response_file" ]; then cat "$$curl_response_file"; fi; \
			echo ""; \
			echo "WARNING: files remain in temporary directory ${T_SUBREPO}."; \
			exit 1; \
		fi; \
		echo ""; \
			echo "Creating snapshot $$snapshot..."; \
			: > "$$curl_response_file"; \
			if ! http_code=$$(curl $(DEBIAN_CURL_MUTATION_FLAGS) -sS -w "%{http_code}" -o "$$curl_response_file" -X POST --config "$$curl_config_file" -H "Content-Type: application/json" -d "{\"Name\": \"$$snapshot\", \"Description\": \"Snapshot created by Makefile. \"}" "$(T_HOST)/repos/${T_SUBREPO}/snapshots"); then \
				http_code="000"; \
			fi; \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Snapshot created successfully (HTTP $$http_code)"; \
		else \
			echo "Failed to create snapshot (HTTP $$http_code)"; \
			if [ -s "$$curl_response_file" ]; then cat "$$curl_response_file"; fi; \
			exit 1; \
		fi; \
		echo ""; \
			echo "Publishing snapshot $$snapshot..."; \
			: > "$$curl_response_file"; \
			if ! http_code=$$(curl $(DEBIAN_CURL_MUTATION_FLAGS) -sS -w "%{http_code}" -o "$$curl_response_file" -X PUT --config "$$curl_config_file" -H "Content-Type: application/json" -d "{ \"Snapshots\": [{\"Component\": \"main\", \"Name\": \"$$snapshot\"}],\"SigningOptions\": {\"Skip\": false}}" "$(T_HOST)/publish/:/${T_SUBREPO}"); then \
				http_code="000"; \
			fi; \
	if [ "$$http_code" -ge 200 ] && [ "$$http_code" -lt 300 ]; then \
		echo "Snapshot published successfully (HTTP $$http_code)"; \
		else \
			echo "Failed to publish snapshot (HTTP $$http_code)"; \
			if [ -s "$$curl_response_file" ]; then cat "$$curl_response_file"; fi; \
			exit 1; \
		fi; \
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
	$(call func_check_debian_curl_tls_flags)

	@echo ">> Remote Debian Repository Packages"
	@printf "  %15s : %s\n" "Site" "$(DEBIAN_SITE)"
	@printf "  %15s : %s\n" "Repo Host" "$(T_HOST)"
	@printf "  %15s : %s\n" "Subrepo" "$(T_SUBREPO)"
	@echo ""
	@curl_config_file="$$(mktemp "$${TMPDIR:-/tmp}/debian-curl-config.XXXXXX")"; \
	chmod 600 "$$curl_config_file"; \
	repo_credential="$${$(T_USER_VAR)}"; \
	printf 'user = "%s"\n' "$$repo_credential" > "$$curl_config_file"; \
	trap 'rm -f "$$curl_config_file"' EXIT; \
	trap 'rm -f "$$curl_config_file"; exit 130' INT; \
	trap 'rm -f "$$curl_config_file"; exit 143' TERM; \
	response=$$(curl $(DEBIAN_CURL_READ_FLAGS) -sS -X GET --config "$$curl_config_file" -H "Content-Type: application/json" "$(T_HOST)/repos/$(T_SUBREPO)/packages" 2>&1); \
	curl_status=$$?; \
	rm -f "$$curl_config_file"; \
	trap - EXIT INT TERM; \
	if [ "$$curl_status" -ne 0 ]; then \
		echo "$$response"; \
		if [ "$(DEBIAN_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit "$$curl_status"; fi; \
		echo ""; \
		exit 0; \
	fi; \
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
