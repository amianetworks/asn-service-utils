# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Shared release preflight and push-plan targets.
#
# These targets intentionally do not push, upload, publish snapshots, deploy, or
# print credentials. They validate and display the effective Docker/Debian
# destination topology so P6/P7 operators can catch bad local setup before
# running approval-gated publish or deployment commands.

RELEASE_CONFIG_STRICT ?= no
RELEASE_CONFIG_CHECK_DOCKER_LOGIN ?= yes
PUSH_PLAN_CHECK_LOCAL_IMAGES ?= no
PUSH_PLAN_STRICT ?= yes

.PHONY: \
	check-release-config check-release-config-strict .check-release-config \
	.check-release-docker-site .check-release-debian-site \
	plan-push plan-push-preview plan-push-readiness plan-push-docker plan-push-debian \
	.plan-push-docker-site .plan-push-debian-site

check-release-config:
	@$(MAKE) -s .check-release-config RELEASE_CONFIG_STRICT=$(RELEASE_CONFIG_STRICT)

check-release-config-strict:
	@$(MAKE) -s .check-release-config RELEASE_CONFIG_STRICT=yes

.check-release-config:
	@printf "## Release Config Check\n"; \
	printf "  %-24s : %s\n" "Strict" "$(RELEASE_CONFIG_STRICT)"; \
	printf "  %-24s : %s\n" "Private Git key" "$(if $(strip $(PRIVATE_GIT_SSH_KEY_FILE)),set,not set)"; \
	if [ -z "$(PRIVATE_GIT_SSH_KEY_FILE)" ]; then \
		if [ "$(RELEASE_CONFIG_STRICT)" = "yes" ]; then \
			echo "ERROR: PRIVATE_GIT_SSH_KEY_FILE is not set."; \
			exit 1; \
		fi; \
		echo "WARN: PRIVATE_GIT_SSH_KEY_FILE is not set."; \
	elif [ ! -r "$(PRIVATE_GIT_SSH_KEY_FILE)" ]; then \
		if [ "$(RELEASE_CONFIG_STRICT)" = "yes" ]; then \
			echo "ERROR: PRIVATE_GIT_SSH_KEY_FILE does not point to a readable file."; \
			exit 1; \
		fi; \
		echo "WARN: PRIVATE_GIT_SSH_KEY_FILE does not point to a readable file."; \
	else \
		printf "  %-24s : %s\n" "Private Git key check" "readable"; \
	fi; \
	echo ""
	@if [ -z "$(strip $(DOCKER_REGISTRY_SITES))" ]; then \
		echo "ERROR: DOCKER_REGISTRY_SITES is empty."; \
		exit 1; \
	fi
	@printf "## Docker Release Destinations\n"; \
	printf "  %-24s : %s\n" "Selected sites" "$(DOCKER_REGISTRY_SITES)"
	@for site in $(DOCKER_REGISTRY_SITES); do \
		$(MAKE) -s .check-release-docker-site SITE=$$site RELEASE_CONFIG_STRICT=$(RELEASE_CONFIG_STRICT) || exit $$?; \
	done
	@if [ -z "$(strip $(DEBIAN_REPO_SITES))" ]; then \
		echo "ERROR: DEBIAN_REPO_SITES is empty."; \
		exit 1; \
	fi
	@printf "## Debian Release Destinations\n"; \
	printf "  %-24s : %s\n" "Selected sites" "$(DEBIAN_REPO_SITES)"; \
	printf "  %-24s : %s\n" "Release channel" "$(DEBIAN_RELEASE_CHANNEL)"
	@for site in $(DEBIAN_REPO_SITES); do \
		$(MAKE) -s .check-release-debian-site SITE=$$site RELEASE_CONFIG_STRICT=$(RELEASE_CONFIG_STRICT) || exit $$?; \
	done
	@if [ -z "$(strip $(DEBIAN_REPO_HOST_US))$(strip $(DEBIAN_REPO_PATH_US))" ]; then \
		printf "  %-24s : %s\n" "Debian US" "disabled until host/path are configured"; \
		if [ -n "$(strip $(DEBIAN_REPO_USER_US))" ]; then \
			echo "WARN: DEBIAN_REPO_USER_US is set while Debian US is disabled."; \
		fi; \
	fi
	@printf "\nRelease config check completed without printing secret values.\n"

.check-release-docker-site:
	$(eval RELEASE_DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval RELEASE_DOCKER_REGISTRY := $(DOCKER_REGISTRY_$(RELEASE_DOCKER_SITE)))
	$(eval RELEASE_DOCKER_AUTH := $(DOCKER_REGISTRY_$(RELEASE_DOCKER_SITE)_USER))
	$(eval RELEASE_DOCKER_AUTH_VAR := RELEASE_SECRET_AUTH_$(RELEASE_SECRET_PROFILE_$(RELEASE_DOCKER_SITE))_DOCKER)
	$(eval RELEASE_DOCKER_AUTH_SET := $(if $(strip $(RELEASE_DOCKER_AUTH)),yes,no))
	$(eval RELEASE_DOCKER_AUTH_FORMAT := $(if $(findstring :,$(RELEASE_DOCKER_AUTH)),user:password,invalid))
	@printf "  %-24s : %s\n" "Docker site" "$(RELEASE_DOCKER_SITE)"; \
	printf "  %-24s : %s\n" "Registry" "$(if $(RELEASE_DOCKER_REGISTRY),$(RELEASE_DOCKER_REGISTRY),not configured)"; \
	printf "  %-24s : %s\n" "Credential var" "$(RELEASE_DOCKER_AUTH_VAR)"; \
	printf "  %-24s : %s\n" "Credential set" "$(RELEASE_DOCKER_AUTH_SET)"; \
	if [ -z "$(RELEASE_DOCKER_REGISTRY)" ]; then \
		echo "ERROR: Docker registry $(RELEASE_DOCKER_SITE) is not configured."; \
		exit 1; \
	fi; \
	if [ "$(RELEASE_DOCKER_AUTH_SET)" = "yes" ]; then \
		printf "  %-24s : %s\n" "Credential format" "$(RELEASE_DOCKER_AUTH_FORMAT)"; \
		if [ "$(RELEASE_DOCKER_AUTH_FORMAT)" != "user:password" ]; then \
			echo "ERROR: Docker credential for $(RELEASE_DOCKER_SITE) must use user:password format."; \
			exit 1; \
		fi; \
	elif [ "$(RELEASE_CONFIG_STRICT)" = "yes" ]; then \
		echo "ERROR: Docker credential for $(RELEASE_DOCKER_SITE) is not configured."; \
		exit 1; \
	else \
		echo "WARN: Docker credential for $(RELEASE_DOCKER_SITE) is not configured."; \
	fi; \
	if [ "$(RELEASE_CONFIG_CHECK_DOCKER_LOGIN)" = "yes" ]; then \
		docker_config="$${HOME}/.docker/config.json"; \
		if [ ! -f "$$docker_config" ]; then \
			if [ "$(RELEASE_CONFIG_STRICT)" = "yes" ]; then \
				echo "ERROR: Docker login config is missing: $$docker_config"; \
				exit 1; \
			else \
				echo "WARN: Docker login config is missing: $$docker_config"; \
			fi; \
		elif grep -Fq "$(RELEASE_DOCKER_REGISTRY)" "$$docker_config"; then \
			printf "  %-24s : %s\n" "Docker login" "present"; \
		elif [ "$(RELEASE_CONFIG_STRICT)" = "yes" ]; then \
			echo "ERROR: Docker login for $(RELEASE_DOCKER_SITE) is missing: $(RELEASE_DOCKER_REGISTRY)."; \
			exit 1; \
		else \
			echo "WARN: Docker login for $(RELEASE_DOCKER_SITE) was not found in ~/.docker/config.json."; \
		fi; \
	fi; \
	echo ""

.check-release-debian-site:
	$(eval RELEASE_DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval RELEASE_DEBIAN_CHANNEL := $(if $(strip $(DEBIAN_RELEASE_CHANNEL)),$(call uppercase,$(DEBIAN_RELEASE_CHANNEL)),$(RELEASE_DEBIAN_SITE)))
	$(eval RELEASE_DEBIAN_HOST := $(DEBIAN_REPO_HOST_$(RELEASE_DEBIAN_SITE)))
	$(eval RELEASE_DEBIAN_PATH := $(DEBIAN_REPO_PATH_$(RELEASE_DEBIAN_SITE)))
	$(eval RELEASE_DEBIAN_USER := $(DEBIAN_REPO_USER_$(RELEASE_DEBIAN_SITE)))
	$(eval RELEASE_DEBIAN_SUBREPO := $(DEBIAN_REPO_SUBREPO_$(RELEASE_DEBIAN_CHANNEL)))
	$(eval RELEASE_DEBIAN_AUTH_VAR := RELEASE_SECRET_AUTH_$(RELEASE_SECRET_PROFILE_$(RELEASE_DEBIAN_SITE))_DEBIAN)
	$(eval RELEASE_DEBIAN_USER_SET := $(if $(strip $(RELEASE_DEBIAN_USER)),yes,no))
	$(eval RELEASE_DEBIAN_AUTH_FORMAT := $(if $(findstring :,$(RELEASE_DEBIAN_USER)),user:password,invalid))
	@printf "  %-24s : %s\n" "Debian site" "$(RELEASE_DEBIAN_SITE)"; \
	printf "  %-24s : %s\n" "Repo host" "$(if $(RELEASE_DEBIAN_HOST),$(RELEASE_DEBIAN_HOST),not configured)"; \
	printf "  %-24s : %s\n" "Repo path" "$(if $(RELEASE_DEBIAN_PATH),$(RELEASE_DEBIAN_PATH),not configured)"; \
	printf "  %-24s : %s\n" "Subrepo" "$(if $(RELEASE_DEBIAN_SUBREPO),$(RELEASE_DEBIAN_SUBREPO),not configured)"; \
	printf "  %-24s : %s\n" "Credential var" "$(RELEASE_DEBIAN_AUTH_VAR)"; \
	printf "  %-24s : %s\n" "Credential set" "$(RELEASE_DEBIAN_USER_SET)"; \
	if [ -z "$(RELEASE_DEBIAN_HOST)" ]; then \
		echo "ERROR: Debian repo $(RELEASE_DEBIAN_SITE) host is not configured."; \
		exit 1; \
	fi; \
	if [ -z "$(RELEASE_DEBIAN_PATH)" ]; then \
		echo "ERROR: Debian repo $(RELEASE_DEBIAN_SITE) path is not configured."; \
		exit 1; \
	fi; \
	if [ -z "$(RELEASE_DEBIAN_SUBREPO)" ]; then \
		echo "ERROR: Debian repo subrelease $(RELEASE_DEBIAN_CHANNEL) is not configured."; \
		exit 1; \
	fi; \
	if [ "$(RELEASE_DEBIAN_USER_SET)" = "yes" ]; then \
		printf "  %-24s : %s\n" "Credential format" "$(RELEASE_DEBIAN_AUTH_FORMAT)"; \
		if [ "$(RELEASE_DEBIAN_AUTH_FORMAT)" != "user:password" ]; then \
			echo "ERROR: Debian credential for $(RELEASE_DEBIAN_SITE) must use user:password format."; \
			exit 1; \
		fi; \
	elif [ "$(RELEASE_CONFIG_STRICT)" = "yes" ]; then \
		echo "ERROR: Debian credential for $(RELEASE_DEBIAN_SITE) is not configured."; \
		exit 1; \
	else \
		echo "WARN: Debian credential for $(RELEASE_DEBIAN_SITE) is not configured."; \
	fi; \
	echo ""

plan-push:
	@set -e; \
	plan_status=0; \
	$(MAKE) -s plan-push-docker || plan_status=$$?; \
	$(MAKE) -s plan-push-debian || plan_status=$$?; \
	exit "$$plan_status"

# `plan-push` is a readiness gate by default: it still never uploads, but it
# must prove concrete artifact identities and configured destinations. Use the
# preview target only when a non-failing topology printout is useful before
# artifacts exist.
plan-push-preview:
	@$(MAKE) -s plan-push PUSH_PLAN_STRICT=no

plan-push-readiness:
	@$(MAKE) -s plan-push PUSH_PLAN_STRICT=yes PUSH_PLAN_CHECK_LOCAL_IMAGES=yes

plan-push-docker:
	@set -e; \
	plan_status=0; \
	if [ -z "$(strip $(DOCKER_REGISTRY_SITES))" ]; then \
		echo "ERROR: DOCKER_REGISTRY_SITES is empty."; \
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
	printf "## Docker Publish Plan\n"; \
	printf "  %-24s : %s\n" "Selected sites" "$(DOCKER_REGISTRY_SITES)"; \
	printf "  %-24s : %s\n" "Images" "$(DOCKER_IMAGES)"; \
	printf "  %-24s : %s\n" "Version tag" "$$plan_version"; \
	printf "  %-24s : %s\n" "Latest tag" "$(DOCKER_PUSH_LATEST)"; \
	printf "  %-24s : %s\n" "No-upload guarantee" "no docker tag/push is executed"; \
	if [ -n "$$plan_version_error" ]; then printf "%s\n" "$$plan_version_error" | sed "s/^/  Manifest: /"; fi; \
	for site in $(DOCKER_REGISTRY_SITES); do \
		$(MAKE) -s .plan-push-docker-site SITE=$$site DOCKER_PUSH_PLAN_VERSION="$$plan_version" || plan_status=$$?; \
	done; \
	if [ "$(PUSH_PLAN_STRICT)" = "yes" ] && [ "$$plan_status" -ne 0 ]; then \
		echo "ERROR: Docker publish plan is not release-ready."; \
		exit "$$plan_status"; \
	fi

.plan-push-docker-site:
	$(eval PUSH_PLAN_DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval PUSH_PLAN_DOCKER_REGISTRY := $(DOCKER_REGISTRY_$(PUSH_PLAN_DOCKER_SITE)))
	$(eval PUSH_PLAN_DOCKER_PREFIX := $(if $(DOCKER_SUBREPO),$(PUSH_PLAN_DOCKER_REGISTRY)/$(DOCKER_SUBREPO),$(PUSH_PLAN_DOCKER_REGISTRY)))
	@printf "  %-24s : %s\n" "Docker site" "$(PUSH_PLAN_DOCKER_SITE)"; \
	printf "  %-24s : %s\n" "Registry" "$(if $(PUSH_PLAN_DOCKER_REGISTRY),$(PUSH_PLAN_DOCKER_REGISTRY),not configured)"; \
	site_status=0; \
	if [ -z "$(PUSH_PLAN_DOCKER_REGISTRY)" ]; then site_status=1; fi; \
	plan_version="$(DOCKER_PUSH_PLAN_VERSION)"; \
	for image in $(DOCKER_IMAGES); do \
		if [ "$${plan_version#\(}" != "$$plan_version" ]; then \
			printf "  %-24s : %s\n" "Would push" "$$image (version unavailable)"; \
			site_status=1; \
			continue; \
		fi; \
		if [ -z "$(PUSH_PLAN_DOCKER_REGISTRY)" ]; then \
			printf "  %-24s : %s\n" "Would push" "$$image (destination unavailable)"; \
			continue; \
		fi; \
		printf "  %-24s : %s\n" "Would push" "$(PUSH_PLAN_DOCKER_PREFIX)/$$image:$$plan_version"; \
		if [ "$(DOCKER_PUSH_LATEST)" = "yes" ]; then \
			printf "  %-24s : %s\n" "Would push" "$(PUSH_PLAN_DOCKER_PREFIX)/$$image:latest"; \
		fi; \
		if [ "$(PUSH_PLAN_CHECK_LOCAL_IMAGES)" = "yes" ]; then \
			inspect_output=$$(mktemp); \
			if docker image inspect "$$image:$$plan_version" > "$$inspect_output" 2>&1; then \
				printf "  %-24s : %s\n" "$$image:$$plan_version" "local image present"; \
			else \
				printf "  %-24s : %s\n" "$$image:$$plan_version" "local image missing"; \
				if [ -s "$$inspect_output" ]; then sed 's/^/  Docker Error: /' "$$inspect_output"; fi; \
				site_status=1; \
			fi; \
			rm -f "$$inspect_output"; \
		else \
			printf "  %-24s : %s\n" "$$image:$$plan_version" "local image check skipped (set PUSH_PLAN_CHECK_LOCAL_IMAGES=yes)"; \
		fi; \
	done; \
	echo ""; \
	if [ "$(PUSH_PLAN_STRICT)" = "yes" ] && [ "$$site_status" -ne 0 ]; then exit "$$site_status"; fi

plan-push-debian:
	@set -e; \
	plan_status=0; \
	if [ -z "$(strip $(DEBIAN_REPO_SITES))" ]; then \
		echo "ERROR: DEBIAN_REPO_SITES is empty."; \
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
	printf "## Debian Publish Plan\n"; \
	printf "  %-24s : %s\n" "Selected sites" "$(DEBIAN_REPO_SITES)"; \
	printf "  %-24s : %s\n" "Release channel" "$(DEBIAN_RELEASE_CHANNEL)"; \
	printf "  %-24s : %s\n" "Package version" "$$plan_version"; \
	printf "  %-24s : %s\n" "No-upload guarantee" "no curl upload/publish is executed"; \
	if [ -n "$$plan_version_error" ]; then printf "%s\n" "$$plan_version_error" | sed "s/^/  Manifest: /"; fi; \
	for site in $(DEBIAN_REPO_SITES); do \
		$(MAKE) -s .plan-push-debian-site SITE=$$site DEBIAN_PUSH_PLAN_VERSION="$$plan_version" || plan_status=$$?; \
	done; \
	if [ "$(PUSH_PLAN_STRICT)" = "yes" ] && [ "$$plan_status" -ne 0 ]; then \
		echo "ERROR: Debian publish plan is not release-ready."; \
		exit "$$plan_status"; \
	fi

.plan-push-debian-site:
	$(eval PUSH_PLAN_DEBIAN_SITE := $(call uppercase,$(SITE)))
	$(eval PUSH_PLAN_DEBIAN_CHANNEL := $(if $(strip $(DEBIAN_RELEASE_CHANNEL)),$(call uppercase,$(DEBIAN_RELEASE_CHANNEL)),$(PUSH_PLAN_DEBIAN_SITE)))
	$(eval PUSH_PLAN_DEBIAN_HOST := $(DEBIAN_REPO_HOST_$(PUSH_PLAN_DEBIAN_SITE)))
	$(eval PUSH_PLAN_DEBIAN_PATH := $(DEBIAN_REPO_PATH_$(PUSH_PLAN_DEBIAN_SITE)))
	$(eval PUSH_PLAN_DEBIAN_SUBREPO := $(DEBIAN_REPO_SUBREPO_$(PUSH_PLAN_DEBIAN_CHANNEL)))
	@printf "  %-24s : %s\n" "Debian site" "$(PUSH_PLAN_DEBIAN_SITE)"; \
	printf "  %-24s : %s\n" "Repo host" "$(if $(PUSH_PLAN_DEBIAN_HOST),$(PUSH_PLAN_DEBIAN_HOST),not configured)"; \
	printf "  %-24s : %s\n" "Repo path" "$(if $(PUSH_PLAN_DEBIAN_PATH),$(PUSH_PLAN_DEBIAN_PATH),not configured)"; \
	printf "  %-24s : %s\n" "Subrepo" "$(if $(PUSH_PLAN_DEBIAN_SUBREPO),$(PUSH_PLAN_DEBIAN_SUBREPO),not configured)"; \
	site_status=0; \
	if [ -z "$(PUSH_PLAN_DEBIAN_HOST)" ] || [ -z "$(PUSH_PLAN_DEBIAN_PATH)" ] || [ -z "$(PUSH_PLAN_DEBIAN_SUBREPO)" ]; then site_status=1; fi; \
	plan_version="$(DEBIAN_PUSH_PLAN_VERSION)"; \
	package_files="$(DEBIAN_PACKAGE_FILES)"; \
	if [ -z "$$package_files" ] && [ "$${plan_version#\(}" = "$$plan_version" ] && [ -d "$(DEBIAN_PACKAGE_DIR)" ]; then \
		for service in $(DEBIAN_SERVICES); do \
			files=$$(find "$(DEBIAN_PACKAGE_DIR)" -maxdepth 1 -type f -name "$${service}_$${plan_version}_amd64.deb" -print | sort); \
			if [ -n "$$files" ]; then package_files="$$package_files $$files"; fi; \
		done; \
	fi; \
	if [ -z "$$package_files" ]; then \
		printf "  %-24s : %s\n" "Would upload" "(no matching local packages)"; \
		site_status=1; \
	fi; \
	for file in $$package_files; do \
		if [ -f "$$file" ]; then \
			printf "  %-24s : %s\n" "Would upload" "$$file"; \
		else \
			printf "  %-24s : %s\n" "Would upload" "$$file (missing locally)"; \
			site_status=1; \
		fi; \
	done; \
	echo ""; \
	if [ "$(PUSH_PLAN_STRICT)" = "yes" ] && [ "$$site_status" -ne 0 ]; then exit "$$site_status"; fi
