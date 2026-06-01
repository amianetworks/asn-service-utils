# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Shared release preflight and push-plan targets.
#
# These targets intentionally do not push, upload, publish snapshots, deploy, or
# print credentials. They validate and display the effective Docker/Debian
# destination topology so P6/P7 operators can catch bad local setup before
# running approval-gated publish or deployment commands.

RELEASE_CONFIG_CHECK_DOCKER_LOGIN ?= yes

.PHONY: \
	.check-push-config .check-push-common .check-push-docker-config .check-push-debian-config \
	.check-push-docker-site .check-push-debian-site \
	plan-push plan-push-docker plan-push-debian \
	.plan-push-docker-site .plan-push-debian-site

.check-push-config:
	@status_file="$$(mktemp "$${TMPDIR:-/tmp}/check-push-config.XXXXXX")"; \
	trap 'rm -f "$$status_file"' EXIT; \
	for target in .check-push-common .check-push-docker-config .check-push-debian-config; do \
		$(MAKE) -s "$$target" PUSH_CONFIG_STATUS_FILE="$$status_file" || printf '%s\n' "$$?" >> "$$status_file"; \
	done; \
	if [ -s "$$status_file" ]; then \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then cat "$$status_file" >> "$(PUSH_CONFIG_STATUS_FILE)"; else exit 1; fi; \
	else \
		printf ">> Publish Readiness: [PASS]\n"; \
	fi; \

.check-push-common:
	@printf ">> Publish Readiness\n"; \
	printf "  %24s : %s\n" "Private Git key" "$(if $(strip $(PRIVATE_GIT_SSH_KEY_FILE)),set,not set)"; \
	common_status=0; \
	if [ -z "$(PRIVATE_GIT_SSH_KEY_FILE)" ]; then \
		echo "ERROR: PRIVATE_GIT_SSH_KEY_FILE is not set."; \
		common_status=1; \
	elif [ ! -r "$(PRIVATE_GIT_SSH_KEY_FILE)" ]; then \
		echo "ERROR: PRIVATE_GIT_SSH_KEY_FILE does not point to a readable file."; \
		common_status=1; \
	else \
		printf "  %24s : %s\n" "Private Git key check" "readable"; \
	fi; \
	if [ "$$common_status" -ne 0 ]; then \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then printf '%s\n' "$$common_status" >> "$(PUSH_CONFIG_STATUS_FILE)"; else exit "$$common_status"; fi; \
	fi; \
	echo ""

.check-push-docker-config:
	@if [ -z "$(strip $(DOCKER_REGISTRIES))" ]; then \
		echo "ERROR: DOCKER_REGISTRIES is empty."; \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then printf '%s\n' 1 >> "$(PUSH_CONFIG_STATUS_FILE)"; exit 0; else exit 1; fi; \
	fi
	@printf ">> Docker Destinations\n"; \
	printf "  %24s : %s\n" "Selected registries" "$(DOCKER_REGISTRIES)"
	@status_file="$$(mktemp "$${TMPDIR:-/tmp}/check-push-docker.XXXXXX")"; \
	trap 'rm -f "$$status_file"' EXIT; \
	for site in $(DOCKER_REGISTRIES); do \
		$(MAKE) -s .check-push-docker-site SITE=$$site PUSH_CONFIG_STATUS_FILE="$$status_file"; \
	done; \
	if [ -s "$$status_file" ]; then \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then cat "$$status_file" >> "$(PUSH_CONFIG_STATUS_FILE)"; else exit 1; fi; \
	fi

.check-push-debian-config:
	@if [ -z "$(strip $(DEBIAN_REPOSITORIES))" ]; then \
		echo "ERROR: DEBIAN_REPOSITORIES is empty."; \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then printf '%s\n' 1 >> "$(PUSH_CONFIG_STATUS_FILE)"; exit 0; else exit 1; fi; \
	fi
	@printf ">> Debian Destinations\n"; \
	printf "  %24s : %s\n" "Selected repositories" "$(DEBIAN_REPOSITORIES)"; \
	printf "  %24s : %s\n" "Release channel" "$(DEBIAN_RELEASE_CHANNEL)"
	@status_file="$$(mktemp "$${TMPDIR:-/tmp}/check-push-debian.XXXXXX")"; \
	trap 'rm -f "$$status_file"' EXIT; \
	for site in $(DEBIAN_REPOSITORIES); do \
		$(MAKE) -s .check-push-debian-site SITE=$$site PUSH_CONFIG_STATUS_FILE="$$status_file"; \
	done; \
	if [ -s "$$status_file" ]; then \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then cat "$$status_file" >> "$(PUSH_CONFIG_STATUS_FILE)"; else exit 1; fi; \
	fi
	@if [ -z "$(strip $(DEBIAN_REPO_HOST_US))$(strip $(DEBIAN_REPO_PATH_US))" ]; then \
		printf "  %24s : %s\n" "Debian US" "disabled until host/path are configured"; \
		if [ -n "$(strip $(DEBIAN_REPO_USER_US))" ]; then \
			echo "WARN: DEBIAN_REPO_USER_US is set while Debian US is disabled."; \
		fi; \
	fi
	@echo ""

.check-push-docker-site:
	$(eval RELEASE_DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval RELEASE_DOCKER_REGISTRY := $(DOCKER_REGISTRY_$(RELEASE_DOCKER_SITE)))
	$(eval RELEASE_DOCKER_AUTH := $(DOCKER_REGISTRY_$(RELEASE_DOCKER_SITE)_USER))
	$(eval RELEASE_DOCKER_AUTH_VAR := RELEASE_SECRET_AUTH_$(RELEASE_SECRET_PROFILE_$(RELEASE_DOCKER_SITE))_DOCKER)
	$(eval RELEASE_DOCKER_AUTH_SET := $(if $(strip $(RELEASE_DOCKER_AUTH)),yes,no))
	$(eval RELEASE_DOCKER_AUTH_FORMAT := $(if $(findstring :,$(RELEASE_DOCKER_AUTH)),user:password,invalid))
	@printf "  %24s : %s\n" "Docker site" "$(RELEASE_DOCKER_SITE)"; \
	printf "  %24s : %s\n" "Registry" "$(if $(RELEASE_DOCKER_REGISTRY),$(RELEASE_DOCKER_REGISTRY),not configured)"; \
	printf "  %24s : %s\n" "Credential var" "$(RELEASE_DOCKER_AUTH_VAR)"; \
	printf "  %24s : %s\n" "Credential set" "$(RELEASE_DOCKER_AUTH_SET)"; \
	site_status=0; \
	if [ -z "$(RELEASE_DOCKER_REGISTRY)" ]; then \
		echo "ERROR: Docker registry $(RELEASE_DOCKER_SITE) is not configured."; \
		site_status=1; \
	fi; \
	if [ "$(RELEASE_DOCKER_AUTH_SET)" = "yes" ]; then \
		printf "  %24s : %s\n" "Credential format" "$(RELEASE_DOCKER_AUTH_FORMAT)"; \
		if [ "$(RELEASE_DOCKER_AUTH_FORMAT)" != "user:password" ]; then \
			echo "ERROR: Docker credential for $(RELEASE_DOCKER_SITE) must use user:password format."; \
			site_status=1; \
		fi; \
	else \
		echo "ERROR: Docker credential for $(RELEASE_DOCKER_SITE) is not configured."; \
		site_status=1; \
	fi; \
	if [ "$$site_status" -eq 0 ] && [ "$(RELEASE_CONFIG_CHECK_DOCKER_LOGIN)" = "yes" ]; then \
		docker_config="$${HOME}/.docker/config.json"; \
		docker_config_has_registry() { \
			cfg="$$1"; \
			registry="$$2"; \
			if command -v jq >/dev/null 2>&1; then \
				jq -e --arg registry "$$registry" '.auths? | type == "object" and has($$registry)' "$$cfg" >/dev/null 2>&1; \
			elif command -v python3 >/dev/null 2>&1; then \
				python3 -c 'import json, sys; data=json.load(open(sys.argv[1], encoding="utf-8")); sys.exit(0 if sys.argv[2] in data.get("auths", {}) else 1)' "$$cfg" "$$registry"; \
			else \
				echo "ERROR: jq or python3 is required to validate Docker login config."; \
				return 2; \
			fi; \
		}; \
		if [ ! -f "$$docker_config" ]; then \
			echo "ERROR: Docker login config is missing: $$docker_config"; \
			site_status=1; \
		elif docker_config_has_registry "$$docker_config" "$(RELEASE_DOCKER_REGISTRY)"; then \
			printf "  %24s : %s\n" "Docker login" "present"; \
		else \
			echo "ERROR: Docker login for $(RELEASE_DOCKER_SITE) is missing: $(RELEASE_DOCKER_REGISTRY)."; \
			site_status=1; \
		fi; \
	fi; \
	if [ "$$site_status" -ne 0 ]; then \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then printf '%s\n' "$$site_status" >> "$(PUSH_CONFIG_STATUS_FILE)"; else exit "$$site_status"; fi; \
	fi; \
	echo ""

.check-push-debian-site:
	$(eval RELEASE_DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval RELEASE_DEBIAN_HOST := $(DEBIAN_REPO_HOST_$(RELEASE_DEBIAN_SITE)))
	$(eval RELEASE_DEBIAN_PATH := $(DEBIAN_REPO_PATH_$(RELEASE_DEBIAN_SITE)))
	$(eval RELEASE_DEBIAN_USER := $(DEBIAN_REPO_USER_$(RELEASE_DEBIAN_SITE)))
	$(eval RELEASE_DEBIAN_SUBREPO := $(strip $(DEBIAN_RELEASE_CHANNEL)))
	$(eval RELEASE_DEBIAN_AUTH_VAR := RELEASE_SECRET_AUTH_$(RELEASE_SECRET_PROFILE_$(RELEASE_DEBIAN_SITE))_DEBIAN)
	$(eval RELEASE_DEBIAN_USER_SET := $(if $(strip $(RELEASE_DEBIAN_USER)),yes,no))
	$(eval RELEASE_DEBIAN_AUTH_FORMAT := $(if $(findstring :,$(RELEASE_DEBIAN_USER)),user:password,invalid))
	@printf "  %24s : %s\n" "Debian site" "$(RELEASE_DEBIAN_SITE)"; \
	printf "  %24s : %s\n" "Repo host" "$(if $(RELEASE_DEBIAN_HOST),$(RELEASE_DEBIAN_HOST),not configured)"; \
	printf "  %24s : %s\n" "Repo path" "$(if $(RELEASE_DEBIAN_PATH),$(RELEASE_DEBIAN_PATH),not configured)"; \
	printf "  %24s : %s\n" "Subrepo" "$(if $(RELEASE_DEBIAN_SUBREPO),$(RELEASE_DEBIAN_SUBREPO),not configured)"; \
	printf "  %24s : %s\n" "Credential var" "$(RELEASE_DEBIAN_AUTH_VAR)"; \
	printf "  %24s : %s\n" "Credential set" "$(RELEASE_DEBIAN_USER_SET)"; \
	site_status=0; \
	if [ -z "$(RELEASE_DEBIAN_HOST)" ]; then \
		echo "ERROR: Debian repo $(RELEASE_DEBIAN_SITE) host is not configured."; \
		site_status=1; \
	fi; \
	if [ -z "$(RELEASE_DEBIAN_PATH)" ]; then \
		echo "ERROR: Debian repo $(RELEASE_DEBIAN_SITE) path is not configured."; \
		site_status=1; \
	fi; \
	if [ -z "$(RELEASE_DEBIAN_SUBREPO)" ] || [ "$(RELEASE_DEBIAN_SUBREPO)" = "unknown" ]; then \
		echo "ERROR: DEBIAN_RELEASE_CHANNEL is not configured."; \
		site_status=1; \
	fi; \
	if [ "$(RELEASE_DEBIAN_USER_SET)" = "yes" ]; then \
		printf "  %24s : %s\n" "Credential format" "$(RELEASE_DEBIAN_AUTH_FORMAT)"; \
		if [ "$(RELEASE_DEBIAN_AUTH_FORMAT)" != "user:password" ]; then \
			echo "ERROR: Debian credential for $(RELEASE_DEBIAN_SITE) must use user:password format."; \
			site_status=1; \
		fi; \
	else \
		echo "ERROR: Debian credential for $(RELEASE_DEBIAN_SITE) is not configured."; \
		site_status=1; \
	fi; \
	if [ "$$site_status" -ne 0 ]; then \
		if [ -n "$(PUSH_CONFIG_STATUS_FILE)" ]; then printf '%s\n' "$$site_status" >> "$(PUSH_CONFIG_STATUS_FILE)"; else exit "$$site_status"; fi; \
	fi; \
	echo ""

plan-push:
	@set -e; \
	plan_status=0; \
	aggregate_status_file="$$(mktemp "$${TMPDIR:-/tmp}/plan-push.XXXXXX")"; \
	trap 'rm -f "$$aggregate_status_file"' EXIT; \
	$(MAKE) -s .check-push-config PUSH_CONFIG_STATUS_FILE="$$aggregate_status_file"; \
	$(MAKE) -s plan-push-docker PUSH_PLAN_SKIP_CONFIG=yes PUSH_PLAN_STATUS_FILE="$$aggregate_status_file"; \
	$(MAKE) -s plan-push-debian PUSH_PLAN_SKIP_CONFIG=yes PUSH_PLAN_STATUS_FILE="$$aggregate_status_file"; \
	if [ -s "$$aggregate_status_file" ]; then plan_status=1; fi; \
	exit "$$plan_status"

plan-push-docker:
	@set -e; \
	plan_status=0; \
	if [ "$(PUSH_PLAN_SKIP_CONFIG)" != "yes" ]; then \
		config_status_file="$$(mktemp "$${TMPDIR:-/tmp}/plan-push-docker-config.XXXXXX")"; \
		trap 'rm -f "$$config_status_file"' EXIT; \
		$(MAKE) -s .check-push-common PUSH_CONFIG_STATUS_FILE="$$config_status_file"; \
		$(MAKE) -s .check-push-docker-config PUSH_CONFIG_STATUS_FILE="$$config_status_file"; \
		if [ -s "$$config_status_file" ]; then plan_status=1; fi; \
	fi; \
	if [ -z "$(strip $(DOCKER_REGISTRIES))" ]; then \
		echo "ERROR: DOCKER_REGISTRIES is empty."; \
		plan_status=1; \
	fi; \
	plan_version="$(DOCKER_PUSH_VERSION)"; \
	manifest_version=""; \
	plan_version_error=""; \
	if manifest_version="$$( $(BUILD_MANIFEST_CMD) require-lane --lane docker $(BUILD_MANIFEST_COMMON_ARGS) 2>&1 )"; then \
		if [ -z "$$plan_version" ]; then \
			plan_version="$$manifest_version"; \
		elif [ "$$plan_version" != "$$manifest_version" ]; then \
			plan_version_error="selected docker version '$$plan_version' does not match manifest docker lane '$$manifest_version'"; \
			plan_status=1; \
		fi; \
	else \
		plan_version_error="$$manifest_version"; \
		[ -n "$$plan_version" ] || plan_version="(manifest docker lane unavailable)"; \
		plan_status=1; \
	fi; \
	site_status_file="$$(mktemp "$${TMPDIR:-/tmp}/plan-push-docker.XXXXXX")"; \
	artifact_refs_file="$$(mktemp "$${TMPDIR:-/tmp}/plan-push-docker-artifacts.XXXXXX")"; \
	trap 'rm -f "$$site_status_file" "$$artifact_refs_file"' EXIT; \
	artifact_error=""; \
	if [ -z "$$plan_version_error" ]; then \
		if ! artifact_error="$$( $(BUILD_MANIFEST_CMD) artifacts --lane docker $(BUILD_MANIFEST_COMMON_ARGS) > "$$artifact_refs_file" 2>&1 )"; then \
			plan_version_error="$$artifact_error"; \
			plan_status=1; \
		elif [ ! -s "$$artifact_refs_file" ]; then \
			plan_version_error="manifest docker lane has no artifacts"; \
			plan_status=1; \
		fi; \
	fi; \
	artifact_refs="$$(tr '\n' ' ' < "$$artifact_refs_file" | sed 's/[[:space:]]*$$//')"; \
	printf ">> Docker Publish Plan\n"; \
	printf "  %24s : %s\n" "Selected registries" "$(DOCKER_REGISTRIES)"; \
	printf "  %24s : %s\n" "Images" "$${artifact_refs:-"(manifest unavailable)"}"; \
	printf "  %24s : %s\n" "Version tag" "$$plan_version"; \
	printf "  %24s : %s\n" "Latest tag" "$(DOCKER_PUSH_LATEST)"; \
	printf "  %24s : %s\n" "No-upload guarantee" "no docker tag/push is executed"; \
	if [ -n "$$plan_version_error" ]; then printf "%s\n" "$$plan_version_error" | sed "s/^/  Manifest: /"; fi; \
	for site in $(DOCKER_REGISTRIES); do \
		$(MAKE) -s .plan-push-docker-site SITE=$$site DOCKER_PUSH_PLAN_VERSION="$$plan_version" DOCKER_PUSH_PLAN_ARTIFACTS_FILE="$$artifact_refs_file" PUSH_PLAN_STATUS_FILE="$$site_status_file"; \
	done; \
	if [ -s "$$site_status_file" ]; then plan_status=1; fi; \
	if [ "$$plan_status" -ne 0 ]; then \
		echo "ERROR: Docker publish plan is not release-ready."; \
		if [ -n "$(PUSH_PLAN_STATUS_FILE)" ]; then printf '%s\n' "$$plan_status" >> "$(PUSH_PLAN_STATUS_FILE)"; else exit "$$plan_status"; fi; \
	fi

.plan-push-docker-site:
	$(eval PUSH_PLAN_DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval PUSH_PLAN_DOCKER_REGISTRY := $(DOCKER_REGISTRY_$(PUSH_PLAN_DOCKER_SITE)))
	$(eval PUSH_PLAN_DOCKER_PREFIX := $(if $(DOCKER_SUBREPO),$(PUSH_PLAN_DOCKER_REGISTRY)/$(DOCKER_SUBREPO),$(PUSH_PLAN_DOCKER_REGISTRY)))
	@printf "  %24s : %s\n" "Docker site" "$(PUSH_PLAN_DOCKER_SITE)"; \
	printf "  %24s : %s\n" "Registry" "$(if $(PUSH_PLAN_DOCKER_REGISTRY),$(PUSH_PLAN_DOCKER_REGISTRY),not configured)"; \
	site_status=0; \
	if [ -z "$(PUSH_PLAN_DOCKER_REGISTRY)" ]; then site_status=1; fi; \
	plan_version="$(DOCKER_PUSH_PLAN_VERSION)"; \
	artifact_refs_file="$(DOCKER_PUSH_PLAN_ARTIFACTS_FILE)"; \
	if [ ! -s "$$artifact_refs_file" ]; then \
		printf "  %24s : %s\n" "Would push" "(manifest docker artifacts unavailable)"; \
		site_status=1; \
	else \
		while IFS= read -r ref || [ -n "$$ref" ]; do \
			[ -n "$$ref" ] || continue; \
			image="$${ref%:*}"; \
			image_tag="$${ref##*:}"; \
			if [ "$$image" = "$$ref" ] || [ -z "$$image" ] || [ -z "$$image_tag" ]; then \
				printf "  %24s : %s\n" "Would push" "$$ref (invalid manifest image ref)"; \
				site_status=1; \
				continue; \
			fi; \
			if [ -z "$(PUSH_PLAN_DOCKER_REGISTRY)" ]; then \
				printf "  %24s : %s\n" "Would push" "$$ref (destination unavailable)"; \
				continue; \
			fi; \
			printf "  %24s : %s\n" "Would push" "$(PUSH_PLAN_DOCKER_PREFIX)/$$image:$$image_tag"; \
			if [ "$(DOCKER_PUSH_LATEST)" = "yes" ]; then \
				printf "  %24s : %s\n" "Would push" "$(PUSH_PLAN_DOCKER_PREFIX)/$$image:latest"; \
			fi; \
		done < "$$artifact_refs_file"; \
	fi; \
	echo ""; \
	if [ "$$site_status" -ne 0 ]; then \
		if [ -n "$(PUSH_PLAN_STATUS_FILE)" ]; then printf '%s\n' "$$site_status" >> "$(PUSH_PLAN_STATUS_FILE)"; else exit "$$site_status"; fi; \
	fi

plan-push-debian:
	@set -e; \
	plan_status=0; \
	if [ "$(PUSH_PLAN_SKIP_CONFIG)" != "yes" ]; then \
		config_status_file="$$(mktemp "$${TMPDIR:-/tmp}/plan-push-debian-config.XXXXXX")"; \
		trap 'rm -f "$$config_status_file"' EXIT; \
		$(MAKE) -s .check-push-common PUSH_CONFIG_STATUS_FILE="$$config_status_file"; \
		$(MAKE) -s .check-push-debian-config PUSH_CONFIG_STATUS_FILE="$$config_status_file"; \
		if [ -s "$$config_status_file" ]; then plan_status=1; fi; \
	fi; \
	if [ -z "$(strip $(DEBIAN_REPOSITORIES))" ]; then \
		echo "ERROR: DEBIAN_REPOSITORIES is empty."; \
		plan_status=1; \
	fi; \
	plan_version="$(DEBIAN_PUSH_VERSION)"; \
	manifest_version=""; \
	plan_version_error=""; \
	if manifest_version="$$( $(BUILD_MANIFEST_CMD) require-lane --lane debian $(BUILD_MANIFEST_COMMON_ARGS) 2>&1 )"; then \
		if [ -z "$$plan_version" ]; then \
			plan_version="$$manifest_version"; \
		elif [ "$$plan_version" != "$$manifest_version" ]; then \
			plan_version_error="selected debian version '$$plan_version' does not match manifest debian lane '$$manifest_version'"; \
			plan_status=1; \
		fi; \
	else \
		plan_version_error="$$manifest_version"; \
		[ -n "$$plan_version" ] || plan_version="(manifest debian lane unavailable)"; \
		plan_status=1; \
	fi; \
	site_status_file="$$(mktemp "$${TMPDIR:-/tmp}/plan-push-debian.XXXXXX")"; \
	package_refs_file="$$(mktemp "$${TMPDIR:-/tmp}/plan-push-debian-artifacts.XXXXXX")"; \
	trap 'rm -f "$$site_status_file" "$$package_refs_file"' EXIT; \
	artifact_error=""; \
	if [ -z "$$plan_version_error" ]; then \
		if ! artifact_error="$$( $(BUILD_MANIFEST_CMD) artifacts --lane debian $(BUILD_MANIFEST_COMMON_ARGS) > "$$package_refs_file" 2>&1 )"; then \
			plan_version_error="$$artifact_error"; \
			plan_status=1; \
		elif [ ! -s "$$package_refs_file" ]; then \
			plan_version_error="manifest debian lane has no artifacts"; \
			plan_status=1; \
		fi; \
	fi; \
	package_refs="$$(tr '\n' ' ' < "$$package_refs_file" | sed 's/[[:space:]]*$$//')"; \
	printf ">> Debian Publish Plan\n"; \
	printf "  %24s : %s\n" "Selected repositories" "$(DEBIAN_REPOSITORIES)"; \
	printf "  %24s : %s\n" "Release channel" "$(DEBIAN_RELEASE_CHANNEL)"; \
	printf "  %24s : %s\n" "Package version" "$$plan_version"; \
	printf "  %24s : %s\n" "Packages" "$${package_refs:-"(manifest unavailable)"}"; \
	printf "  %24s : %s\n" "No-upload guarantee" "no curl upload/publish is executed"; \
	if [ -n "$$plan_version_error" ]; then printf "%s\n" "$$plan_version_error" | sed "s/^/  Manifest: /"; fi; \
	for site in $(DEBIAN_REPOSITORIES); do \
		$(MAKE) -s .plan-push-debian-site SITE=$$site DEBIAN_PUSH_PLAN_VERSION="$$plan_version" DEBIAN_PUSH_PLAN_ARTIFACTS_FILE="$$package_refs_file" PUSH_PLAN_STATUS_FILE="$$site_status_file"; \
	done; \
	if [ -s "$$site_status_file" ]; then plan_status=1; fi; \
	if [ "$$plan_status" -ne 0 ]; then \
		echo "ERROR: Debian publish plan is not release-ready."; \
		if [ -n "$(PUSH_PLAN_STATUS_FILE)" ]; then printf '%s\n' "$$plan_status" >> "$(PUSH_PLAN_STATUS_FILE)"; else exit "$$plan_status"; fi; \
	fi

.plan-push-debian-site:
	$(eval PUSH_PLAN_DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval PUSH_PLAN_DEBIAN_HOST := $(DEBIAN_REPO_HOST_$(PUSH_PLAN_DEBIAN_SITE)))
	$(eval PUSH_PLAN_DEBIAN_PATH := $(DEBIAN_REPO_PATH_$(PUSH_PLAN_DEBIAN_SITE)))
	$(eval PUSH_PLAN_DEBIAN_SUBREPO := $(strip $(DEBIAN_RELEASE_CHANNEL)))
	@printf "  %24s : %s\n" "Debian site" "$(PUSH_PLAN_DEBIAN_SITE)"; \
	printf "  %24s : %s\n" "Repo host" "$(if $(PUSH_PLAN_DEBIAN_HOST),$(PUSH_PLAN_DEBIAN_HOST),not configured)"; \
	printf "  %24s : %s\n" "Repo path" "$(if $(PUSH_PLAN_DEBIAN_PATH),$(PUSH_PLAN_DEBIAN_PATH),not configured)"; \
	printf "  %24s : %s\n" "Subrepo" "$(if $(PUSH_PLAN_DEBIAN_SUBREPO),$(PUSH_PLAN_DEBIAN_SUBREPO),not configured)"; \
	site_status=0; \
	if [ -z "$(PUSH_PLAN_DEBIAN_HOST)" ] || [ -z "$(PUSH_PLAN_DEBIAN_PATH)" ] || [ -z "$(PUSH_PLAN_DEBIAN_SUBREPO)" ] || [ "$(PUSH_PLAN_DEBIAN_SUBREPO)" = "unknown" ]; then site_status=1; fi; \
	package_refs_file="$(DEBIAN_PUSH_PLAN_ARTIFACTS_FILE)"; \
	if [ ! -s "$$package_refs_file" ]; then \
		printf "  %24s : %s\n" "Would upload" "(manifest debian artifacts unavailable)"; \
		site_status=1; \
	else \
		while IFS= read -r file || [ -n "$$file" ]; do \
			[ -n "$$file" ] || continue; \
			printf "  %24s : %s\n" "Would upload" "$$file"; \
		done < "$$package_refs_file"; \
	fi; \
	echo ""; \
	if [ "$$site_status" -ne 0 ]; then \
		if [ -n "$(PUSH_PLAN_STATUS_FILE)" ]; then printf '%s\n' "$$site_status" >> "$(PUSH_PLAN_STATUS_FILE)"; else exit "$$site_status"; fi; \
	fi
