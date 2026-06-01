# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

.PHONY: init_service_utils update_service_utils

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
	@expected="v$(ASN_SERVICE_API_VERSION)"; \
	if current=$$(git -C "$(SERVICE_UTILS_DIR)" symbolic-ref --quiet --short HEAD 2>&1); then :; \
	elif current=$$(git -C "$(SERVICE_UTILS_DIR)" describe --tags --exact-match 2>&1); then :; \
	else current=$$(git -C "$(SERVICE_UTILS_DIR)" rev-parse --short HEAD); fi; \
	git_ssh_command=""; \
	if [ -n "$$PRIVATE_GIT_SSH_KEY_FILE" ]; then git_ssh_command="ssh -i $$PRIVATE_GIT_SSH_KEY_FILE -o IdentitiesOnly=yes"; fi; \
	cd $(SERVICE_UTILS_DIR) && \
	if [ -n "$$git_ssh_command" ]; then GIT_SSH_COMMAND="$$git_ssh_command" git fetch --prune origin; else git fetch --prune origin; fi && \
	if [ "$$current" = "$$expected" ]; then \
		if git show-ref --verify --quiet refs/remotes/origin/v$(ASN_SERVICE_API_VERSION); then \
			if [ -n "$$git_ssh_command" ]; then GIT_SSH_COMMAND="$$git_ssh_command" git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); else git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); fi; \
		else \
			echo "service-utils ref $$current already selected (tag, no pull needed)."; \
		fi; \
	else \
		echo "Selecting service-utils ref $$expected"; \
		if git show-ref --verify --quiet refs/remotes/origin/v$(ASN_SERVICE_API_VERSION); then \
				if git show-ref --verify --quiet refs/heads/v$(ASN_SERVICE_API_VERSION); then \
					git checkout v$(ASN_SERVICE_API_VERSION); \
					if [ -n "$$git_ssh_command" ]; then GIT_SSH_COMMAND="$$git_ssh_command" git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); else git pull --ff-only origin v$(ASN_SERVICE_API_VERSION); fi; \
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
