# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Shared read-only Docker image listing targets for ASN framework and services.

DOCKER_LIST_LIMIT ?= 20
DOCKER_LIST_LOCAL_LABEL ?= Services
DOCKER_LIST_COMPAT ?= deprecated
DOCKER_LIST_REQUIRE_REMOTE_AUTH ?= yes
DOCKER_SUBREPO ?=

.PHONY: list-docker list-docker-local list-docker-cn list-docker-us list-docker-% docker-list docker-list-%

list-docker:
	@$(MAKE) -s .list-docker-local
	@if [ -z "$(strip $(DOCKER_REGISTRY_SITES))" ]; then \
		echo "No Docker registry sites configured."; \
		echo ""; \
	else \
		for site in $(DOCKER_REGISTRY_SITES); do \
			$(MAKE) -s .list-docker-site SITE=$$site; \
		done; \
	fi

list-docker-local:
	@$(MAKE) -s .list-docker-local

list-docker-cn:
	@$(MAKE) -s .list-docker-local
	@$(MAKE) -s .list-docker-site SITE=CN

list-docker-us:
	@$(MAKE) -s .list-docker-local
	@$(MAKE) -s .list-docker-site SITE=US

list-docker-%:
	@$(MAKE) -s .list-docker-site SITE=$(call uppercase,$*)

docker-list:
	@if [ "$(DOCKER_LIST_COMPAT)" = "alias" ]; then \
		$(MAKE) -s list-docker; \
	else \
		echo "Target '$@' is deprecated."; \
		echo "Use 'make list-docker-cn', 'make list-docker-us', or 'make list-docker'."; \
		exit 1; \
	fi

docker-list-%:
	@if [ "$(DOCKER_LIST_COMPAT)" = "alias" ]; then \
		$(MAKE) -s list-docker-$*; \
	else \
		echo "Target '$@' is deprecated."; \
		echo "Use 'make list-docker-cn', 'make list-docker-us', or 'make list-docker'."; \
		exit 1; \
	fi

.list-docker-local:
	@echo ">> Local Docker Images"
	@printf "  %15s : %s\n" "$(DOCKER_LIST_LOCAL_LABEL)" "$(DOCKER_IMAGES)"
	@echo ""
	@if ! docker info >/dev/null 2>&1; then \
		echo "Docker daemon is not running."; \
		echo ""; \
	else \
		for image in $(DOCKER_IMAGES); do \
			printf "Image: %s\n" "$$image"; \
			echo ""; \
			if docker images --format '{{.Repository}}' | awk -v image="$$image" '$$1 == image { found=1 } END { exit !found }'; then \
				printf "%-40s %-20s %-15s\n" "REPOSITORY" "TAG" "IMAGE ID"; \
				printf "%-40s %-20s %-15s\n" "----------" "---" "--------"; \
				docker images --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}' | awk -F'\t' -v image="$$image" '$$1 == image {printf "%-40s %-20s %-15s\n", $$1, $$2, $$3}'; \
			else \
				echo "(no local images)"; \
			fi; \
			echo ""; \
		done; \
	fi

.list-docker-site:
	$(eval DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval REGISTRY := $(DOCKER_REGISTRY_$(DOCKER_SITE)))
	$(eval REGISTRY_USER_VAR := DOCKER_REGISTRY_$(DOCKER_SITE)_USER)
	$(eval REGISTRY_USER_SET := $(if $(strip $(DOCKER_REGISTRY_$(DOCKER_SITE)_USER)),yes,no))
	@echo ">> Remote Docker Registry Images"
	@printf "  %15s : %s\n" "Site" "$(DOCKER_SITE)"
	@printf "  %15s : %s\n" "Registry" "$(REGISTRY)"
	@printf "  %15s : %s\n" "Subrepo" "$(if $(DOCKER_SUBREPO),$(DOCKER_SUBREPO),(none))"
	@echo ""
	@if [ -z "$(REGISTRY)" ]; then \
		echo "Docker registry $(DOCKER_SITE) is not configured."; \
		if [ "$(DOCKER_LIST_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		echo ""; \
	elif [ "$(REGISTRY_USER_SET)" != "yes" ]; then \
		echo "Docker registry credentials are not configured for $(DOCKER_SITE)."; \
		echo "Set DOCKER_REGISTRY_$(DOCKER_SITE)_USER='user:password' to list remote tags."; \
		if [ "$(DOCKER_LIST_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		echo ""; \
	else \
		repo_prefix=""; \
		if [ -n "$(DOCKER_SUBREPO)" ]; then repo_prefix="$(DOCKER_SUBREPO)/"; fi; \
		for image in $(DOCKER_IMAGES); do \
			echo "Image: $$image"; \
			echo ""; \
			response=$$(curl -s -u "$${$(REGISTRY_USER_VAR)}" "https://$(REGISTRY)/v2/$${repo_prefix}$$image/tags/list" 2>/dev/null); \
			if [ -z "$$response" ]; then \
				echo "(empty response from registry)"; \
			elif command -v jq >/dev/null 2>&1; then \
				if echo "$$response" | jq -e . >/dev/null 2>&1; then \
					count=$$(echo "$$response" | jq '.tags | length'); \
					if [ "$$count" = "0" ] || [ "$$count" = "null" ]; then \
						echo "(no tags found)"; \
					else \
						printf "%-30s\n" "TAG"; \
						printf "%-30s\n" "---"; \
						if [ "$(DOCKER_LIST_LIMIT)" = "0" ]; then \
							echo "$$response" | jq -r '.tags | map(select(. != null)) | sort_by(split(".") | map(tonumber? // .)) | reverse | .[]' 2>/dev/null || echo "$$response" | jq -r '.tags[]'; \
							echo ""; \
							echo "Total: $$count tag(s)"; \
						else \
							echo "$$response" | jq -r --argjson limit "$(DOCKER_LIST_LIMIT)" '.tags | map(select(. != null)) | sort_by(split(".") | map(tonumber? // .)) | reverse | .[:$$limit] | .[]' 2>/dev/null || echo "$$response" | jq -r '.tags[]'; \
							echo ""; \
							echo "Showing: up to $(DOCKER_LIST_LIMIT) of $$count tag(s)"; \
						fi; \
					fi; \
				else \
					echo "Invalid JSON response:"; \
					echo "$$response"; \
				fi; \
			else \
				echo "jq is not installed; showing raw response:"; \
				echo ""; \
				echo "$$response" | python3 -m json.tool 2>/dev/null || echo "$$response"; \
			fi; \
			echo ""; \
		done; \
	fi
