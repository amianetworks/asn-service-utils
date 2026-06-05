# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

.PHONY: init_service_utils update_service_utils

SERVICE_UTILS_REF ?= workflow/$(ASN_SERVICE_API_VERSION)

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
		git_ssh_command=""; \
		if [ -n "$$PRIVATE_GIT_SSH_KEY_FILE" ]; then git_ssh_command="ssh -i $$PRIVATE_GIT_SSH_KEY_FILE -o IdentitiesOnly=yes"; fi; \
		if [ -n "$$git_ssh_command" ]; then \
			GIT_SSH_COMMAND="$$git_ssh_command" git submodule sync --recursive $(SERVICE_UTILS_DIR); \
			GIT_SSH_COMMAND="$$git_ssh_command" git submodule update --init --recursive --force --checkout $(SERVICE_UTILS_DIR); \
		else \
			git submodule sync --recursive $(SERVICE_UTILS_DIR); \
			git submodule update --init --recursive --force --checkout $(SERVICE_UTILS_DIR); \
		fi; \
		if git -C "$(SERVICE_UTILS_DIR)" config --bool core.sparseCheckout | grep -qx true; then \
			echo "ERROR: service-utils uses sparse checkout; disable sparse checkout, then rerun 'make init'."; \
			exit 1; \
		fi; \
		git -C "$(SERVICE_UTILS_DIR)" checkout -f HEAD -- .; \
	fi

update_service_utils: init_service_utils
	@if [ -z "$(ASN_SERVICE_API_VERSION)" ]; then \
		echo "ERROR: ASN_SERVICE_API_VERSION is not set."; \
		exit 1; \
	fi
	@if [ -z "$(SERVICE_UTILS_REF)" ]; then \
		echo "ERROR: SERVICE_UTILS_REF is not set."; \
		exit 1; \
	fi
	@expected="$(SERVICE_UTILS_REF)"; \
	current_is_branch=false; \
	if current=$$(git -C "$(SERVICE_UTILS_DIR)" symbolic-ref --quiet --short HEAD 2>&1); then current_is_branch=true; \
	elif current=$$(git -C "$(SERVICE_UTILS_DIR)" describe --tags --exact-match 2>&1); then :; \
	else current=$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD); fi; \
	git_ssh_command=""; \
	if [ -n "$$PRIVATE_GIT_SSH_KEY_FILE" ]; then git_ssh_command="ssh -i $$PRIVATE_GIT_SSH_KEY_FILE -o IdentitiesOnly=yes"; fi; \
	cd $(SERVICE_UTILS_DIR) && \
	if [ -n "$$git_ssh_command" ]; then GIT_SSH_COMMAND="$$git_ssh_command" git fetch --prune origin; else git fetch --prune origin; fi && \
	if [ "$$current" = "$$expected" ]; then \
		if [ "$$current_is_branch" = "true" ] && git show-ref --verify --quiet "refs/remotes/origin/$$expected"; then \
			if [ -n "$$git_ssh_command" ]; then GIT_SSH_COMMAND="$$git_ssh_command" git pull --ff-only origin "$$expected"; else git pull --ff-only origin "$$expected"; fi; \
		else \
			echo "service-utils ref $$current already selected (tag, no pull needed)."; \
		fi; \
	else \
		echo "Selecting service-utils ref $$expected"; \
		if git show-ref --verify --quiet "refs/remotes/origin/$$expected"; then \
				if git show-ref --verify --quiet "refs/heads/$$expected"; then \
					git checkout "$$expected"; \
					if [ -n "$$git_ssh_command" ]; then GIT_SSH_COMMAND="$$git_ssh_command" git pull --ff-only origin "$$expected"; else git pull --ff-only origin "$$expected"; fi; \
				else \
					git checkout -b "$$expected" "origin/$$expected"; \
				fi; \
		elif git show-ref --verify --quiet "refs/tags/$$expected"; then \
			git checkout "$$expected"; \
		else \
			echo "ERROR: service-utils ref $$expected was not found as an origin branch or tag."; \
			exit 1; \
		fi; \
	fi
