# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Shared Docker registry targets for ASN framework and services.

DOCKER_PUSH_CHECK_TARGETS ?=
DOCKER_PUSH_VERSION ?= $(VERSION_BUILD)
DOCKER_PUSH_LATEST ?= no
DOCKER_REQUIRE_REGISTRY_USER ?= yes
DOCKER_REQUIRE_LOGIN_CONFIG ?= yes
DOCKER_CLEAN_DEPS ?=
DOCKER_CLEAN_UNTAGGED ?= no
DOCKER_LIST_LIMIT ?= 20
DOCKER_LIST_LOCAL_LABEL ?= Services
DOCKER_LIST_REQUIRE_REMOTE_AUTH ?= yes
DOCKER_SUBREPO ?=

# The list/push recipes read credentials through shell variables such as
# $${DOCKER_REGISTRY_CN_USER} so curl invocations do not contain make-expanded
# secret values. Export the selected site variables because projects often
# derive them from RELEASE_SECRET_* values in config.mk or ignored local.mk.
docker_registry_uppercase = $(shell echo $(1) | tr a-z A-Z)
DOCKER_REGISTRY_USER_EXPORTS := $(foreach site,$(DOCKER_REGISTRY_SITES),DOCKER_REGISTRY_$(call docker_registry_uppercase,$(site))_USER)
export $(DOCKER_REGISTRY_USER_EXPORTS)

.PHONY: \
	check-push-docker-sites \
	push-docker push-docker-cn push-docker-us push-docker-% \
	list-docker list-docker-local list-docker-cn list-docker-us list-docker-% \
	clean-docker

push-docker: $(DOCKER_PUSH_CHECK_TARGETS) check-push-docker-sites
	@for site in $(DOCKER_REGISTRY_SITES); do \
		$(MAKE) -s .push-docker-site SITE=$$site; \
	done

# Site-specific targets are thin selectors. The aggregate target owns all
# validation and push behavior, so site shortcuts cannot drift from it.
push-docker-cn: $(DOCKER_PUSH_CHECK_TARGETS)
	@$(MAKE) -s push-docker DOCKER_REGISTRY_SITES=CN

push-docker-us: $(DOCKER_PUSH_CHECK_TARGETS)
	@$(MAKE) -s push-docker DOCKER_REGISTRY_SITES=US

push-docker-%: $(DOCKER_PUSH_CHECK_TARGETS)
	@$(MAKE) -s push-docker DOCKER_REGISTRY_SITES=$(call uppercase,$*)

check-push-docker-sites:
	@if [ -z "$(strip $(DOCKER_REGISTRY_SITES))" ]; then \
		echo "ERROR: DOCKER_REGISTRY_SITES is empty."; \
		exit 1; \
	fi
	@for site in $(DOCKER_REGISTRY_SITES); do \
		$(MAKE) -s .check-docker-registry-site SITE=$$site; \
	done
	@echo "Docker publish site preflight passed: $(DOCKER_REGISTRY_SITES)"
	@echo ""

.check-docker-registry-site:
	$(eval DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval REGISTRY_USER_SET := $(if $(strip $(DOCKER_REGISTRY_$(DOCKER_SITE)_USER)),yes,no))
	$(eval REGISTRY_USER_FORMAT := $(if $(findstring :,$(DOCKER_REGISTRY_$(DOCKER_SITE)_USER)),user:password,invalid))
	@if [ -z "$(DOCKER_REGISTRY_$(DOCKER_SITE))" ]; then \
		echo "ERROR: Docker registry $(DOCKER_SITE) is not configured."; \
		echo "Required: DOCKER_REGISTRY_$(DOCKER_SITE)."; \
		exit 1; \
	fi
	@if [ "$(DOCKER_REQUIRE_REGISTRY_USER)" = "yes" ] && [ "$(REGISTRY_USER_SET)" != "yes" ]; then \
		echo "ERROR: Docker registry $(DOCKER_SITE) is not fully configured."; \
		echo "Required: DOCKER_REGISTRY_$(DOCKER_SITE) and DOCKER_REGISTRY_$(DOCKER_SITE)_USER."; \
		exit 1; \
	fi
	@if [ "$(REGISTRY_USER_SET)" = "yes" ] && [ "$(REGISTRY_USER_FORMAT)" != "user:password" ]; then \
		echo "ERROR: Docker registry credential for $(DOCKER_SITE) must use user:password format."; \
		exit 1; \
	fi
	@if [ "$(DOCKER_REQUIRE_LOGIN_CONFIG)" = "yes" ]; then \
		docker_config="$${HOME}/.docker/config.json"; \
		if [ ! -f "$$docker_config" ]; then \
			echo "ERROR: Docker login config is missing: $$docker_config"; \
			exit 1; \
		fi; \
		if ! grep -q "$(DOCKER_REGISTRY_$(DOCKER_SITE))" "$$docker_config"; then \
			echo "ERROR: Docker registry $(DOCKER_SITE) is not logged in: $(DOCKER_REGISTRY_$(DOCKER_SITE))"; \
			exit 1; \
		fi; \
	fi

.push-docker-site:
	$(eval DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval REGISTRY := $(DOCKER_REGISTRY_$(DOCKER_SITE)))
	@echo ">> Docker Publish Target"
	@printf "  %15s : %s\n" "Site" "$(DOCKER_SITE)"
	@printf "  %15s : %s\n" "Registry" "$(REGISTRY)"
	@printf "  %15s : %s\n" "Subrepo" "$(if $(DOCKER_SUBREPO),$(DOCKER_SUBREPO),(none))"
	@printf "  %15s : %s\n" "Version Tag" "$(DOCKER_PUSH_VERSION)"
	@printf "  %15s : %s\n" "Latest Tag" "$(DOCKER_PUSH_LATEST)"
	@echo ""
	@for image in $(DOCKER_IMAGES); do \
		if ! inspect_error="$$(docker image inspect "$$image:$(DOCKER_PUSH_VERSION)" 2>&1 >/dev/null)"; then \
			echo "ERROR: local image $$image:$(DOCKER_PUSH_VERSION) is missing. Run make build-docker first."; \
			if [ -n "$$inspect_error" ]; then echo "$$inspect_error"; fi; \
			exit 1; \
		fi; \
	done
	@for image in $(DOCKER_IMAGES); do \
		$(MAKE) -s .push-docker-image IMAGE=$$image IMAGE_TAG=$(DOCKER_PUSH_VERSION) REGISTRY=$(REGISTRY); \
	done
	@if [ "$(DOCKER_PUSH_LATEST)" = "yes" ]; then \
		for image in $(DOCKER_IMAGES); do \
			$(MAKE) -s .push-docker-image IMAGE=$$image IMAGE_TAG=latest REGISTRY=$(REGISTRY) SOURCE_TAG=$(DOCKER_PUSH_VERSION); \
		done; \
	fi

.push-docker-image:
	$(eval SOURCE_IMAGE_TAG := $(if $(SOURCE_TAG),$(SOURCE_TAG),$(IMAGE_TAG)))
	$(eval REGISTRY_IMAGE_PREFIX := $(if $(DOCKER_SUBREPO),$(REGISTRY)/$(DOCKER_SUBREPO),$(REGISTRY)))
	@echo ""
	@printf "%s" "Tagging image $(IMAGE):$(SOURCE_IMAGE_TAG) to registry: $(REGISTRY_IMAGE_PREFIX)/$(IMAGE):$(IMAGE_TAG)"
	@docker tag $(IMAGE):$(SOURCE_IMAGE_TAG) $(REGISTRY_IMAGE_PREFIX)/$(IMAGE):$(IMAGE_TAG)
	@echo " ...Done."
	@echo "Pushing image $(IMAGE):$(IMAGE_TAG) to registry: $(REGISTRY)"
	@docker push $(REGISTRY_IMAGE_PREFIX)/$(IMAGE):$(IMAGE_TAG)
	@echo "Pushed."

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

clean-docker: $(DOCKER_CLEAN_DEPS)
	@echo "Removing untagged Docker images..."; \
	docker image prune -f
	@if [ "$(DOCKER_CLEAN_UNTAGGED)" = "yes" ]; then \
		echo "DOCKER_CLEAN_UNTAGGED=yes; skipped older tagged image cleanup."; \
	else \
		echo "- Cleaning older docker images for repositories: $(DOCKER_IMAGES)"; \
		echo ""; \
		for image in $(DOCKER_IMAGES); do \
			echo "> $$image"; \
			ids=$$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' \
				| awk -v prefix="^$$image:" '$$1 ~ prefix { if (!seen[$$2]++) print $$2 }'); \
			if [ -z "$$ids" ]; then \
				echo "(none)"; \
			else \
				keep=$$(printf "%s\n" $$ids | head -n 1); \
				remove=$$(printf "%s\n" $$ids | tail -n +2); \
				echo "Kept image ID: $$keep"; \
				if [ -n "$$remove" ]; then \
					echo "$$remove" | xargs docker rmi -f; \
				else \
					echo "No older images to remove."; \
				fi; \
			fi; \
			echo ""; \
		done; \
	fi

list-docker-local:
	@$(MAKE) -s .list-docker-local

# Site-specific list targets mirror the push selector model: they only set the
# configured site list, while `list-docker` owns local and remote list behavior.
list-docker-cn:
	@$(MAKE) -s list-docker DOCKER_REGISTRY_SITES=CN

list-docker-us:
	@$(MAKE) -s list-docker DOCKER_REGISTRY_SITES=US

list-docker-%:
	@echo "ERROR: unsupported Docker list target: list-docker-$*."
	@echo "Supported targets: list-docker, list-docker-local, list-docker-cn, list-docker-us."
	@exit 2

.list-docker-local:
	@echo ">> Local Docker Images"
	@printf "  %15s : %s\n" "$(DOCKER_LIST_LOCAL_LABEL)" "$(DOCKER_IMAGES)"
	@echo ""
	@if ! docker_error="$$(docker info 2>&1 >/dev/null)"; then \
		echo "Docker daemon is not running or not reachable."; \
		if [ -n "$$docker_error" ]; then echo "$$docker_error"; fi; \
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
	$(eval REGISTRY_USER_FORMAT := $(if $(findstring :,$(DOCKER_REGISTRY_$(DOCKER_SITE)_USER)),user:password,invalid))
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
	elif [ "$(REGISTRY_USER_FORMAT)" != "user:password" ]; then \
		echo "Docker registry credential for $(DOCKER_SITE) must use user:password format."; \
		if [ "$(DOCKER_LIST_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
		echo ""; \
	else \
		repo_prefix=""; \
		if [ -n "$(DOCKER_SUBREPO)" ]; then repo_prefix="$(DOCKER_SUBREPO)/"; fi; \
		for image in $(DOCKER_IMAGES); do \
			echo "Image: $$image"; \
			echo ""; \
			response=$$(curl -sS -u "$${$(REGISTRY_USER_VAR)}" "https://$(REGISTRY)/v2/$${repo_prefix}$$image/tags/list"); \
			if [ -z "$$response" ]; then \
				echo "(empty response from registry)"; \
				if [ "$(DOCKER_LIST_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
			elif command -v jq >/dev/null; then \
				if echo "$$response" | jq -e . >/dev/null; then \
					if echo "$$response" | jq -e '.errors? // empty' >/dev/null; then \
						echo "Registry error response:"; \
						echo "$$response" | jq .; \
						if [ "$(DOCKER_LIST_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
					elif ! echo "$$response" | jq -e 'has("tags")' >/dev/null; then \
						echo "Unexpected registry response:"; \
						echo "$$response" | jq .; \
						if [ "$(DOCKER_LIST_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
					else \
						count=$$(echo "$$response" | jq '.tags | length'); \
						if [ "$$count" = "0" ] || [ "$$count" = "null" ]; then \
							echo "(no tags found)"; \
						else \
							printf "%-30s\n" "TAG"; \
							printf "%-30s\n" "---"; \
							if [ "$(DOCKER_LIST_LIMIT)" = "0" ]; then \
								echo "$$response" | jq -r '.tags | map(select(. != null)) | sort_by(split(".") | map(tonumber? // .)) | reverse | .[]' || echo "$$response" | jq -r '.tags[]'; \
								echo ""; \
								echo "Total: $$count tag(s)"; \
							else \
								echo "$$response" | jq -r --argjson limit "$(DOCKER_LIST_LIMIT)" '.tags | map(select(. != null)) | sort_by(split(".") | map(tonumber? // .)) | reverse | .[:$$limit] | .[]' || echo "$$response" | jq -r '.tags[]'; \
								echo ""; \
								echo "Showing: up to $(DOCKER_LIST_LIMIT) of $$count tag(s)"; \
							fi; \
						fi; \
					fi; \
				else \
					echo "Invalid JSON response:"; \
					echo "$$response"; \
					if [ "$(DOCKER_LIST_REQUIRE_REMOTE_AUTH)" = "yes" ]; then exit 1; fi; \
				fi; \
			else \
				echo "jq is not installed; showing raw response:"; \
				echo ""; \
				echo "$$response" | python3 -m json.tool || echo "$$response"; \
			fi; \
			echo ""; \
		done; \
	fi
