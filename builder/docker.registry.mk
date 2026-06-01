# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Shared Docker registry targets for ASN framework and services.

DOCKER_PUSH_VERSION ?= $(VERSION_BUILD)
DOCKER_PUSH_LATEST ?= no
DOCKER_REQUIRE_REGISTRY_USER ?= yes
DOCKER_REQUIRE_LOGIN_CONFIG ?= yes
DOCKER_CLEAN_DEPS ?=
DOCKER_CLEAN_UNTAGGED ?= no
DOCKER_CLEAN_GLOBAL_PRUNE ?= no
DOCKER_CLEAN_TAGGED ?= no
DOCKER_CHECK_REMOTE_TAGS ?= yes
DOCKER_ALLOW_TAG_OVERWRITE ?= no
DOCKER_LIST_LIMIT ?= 20
DOCKER_LIST_LOCAL_LABEL ?= Services
DOCKER_LIST_REQUIRE_REMOTE_AUTH ?= yes
DOCKER_SUBREPO ?=
DOCKER_CURL_TIMEOUT_FLAGS ?= --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 2 --retry-connrefused

# The list/push recipes read credentials through shell variables such as
# $${DOCKER_REGISTRY_CN_USER} so curl invocations do not contain make-expanded
# secret values. Export the selected registry variables because projects often
# derive them from RELEASE_SECRET_* values in make/config.mk or ignored make/local.mk.
docker_registry_uppercase = $(call uppercase,$(1))
DOCKER_REGISTRY_USER_EXPORTS := $(foreach site,$(DOCKER_REGISTRIES),DOCKER_REGISTRY_$(call docker_registry_uppercase,$(site))_USER)
export $(DOCKER_REGISTRY_USER_EXPORTS)

.PHONY: \
	check-push-docker-sites \
	push-docker push-docker-cn push-docker-us push-docker-% \
	list-docker list-docker-local list-docker-cn list-docker-us list-docker-% \
	clean-docker

push-docker: .check-docker-release-mode .check-docker-publish-images check-push-docker-sites
	@for site in $(DOCKER_REGISTRIES); do \
		$(MAKE) -s .push-docker-site SITE=$$site; \
	done

# Site-specific targets are thin selectors. The aggregate target owns all
# validation and push behavior, so site shortcuts cannot drift from it.
push-docker-cn: .check-docker-release-mode .check-docker-publish-images
	@$(MAKE) -s push-docker DOCKER_REGISTRIES=CN

push-docker-us: .check-docker-release-mode .check-docker-publish-images
	@$(MAKE) -s push-docker DOCKER_REGISTRIES=US

push-docker-%: .check-docker-release-mode .check-docker-publish-images
	@$(MAKE) -s push-docker DOCKER_REGISTRIES=$(call uppercase,$*)

check-push-docker-sites:
	@if [ -z "$(strip $(DOCKER_REGISTRIES))" ]; then \
		echo ">> Docker Site Preflight: [FAIL]"; \
		printf "  %15s : %s\n" "Selected registries" "<empty>"; \
		echo "ERROR: DOCKER_REGISTRIES is empty."; \
		exit 1; \
	fi
	@set +e; \
	echo ">> Docker Site Preflight"; \
	printf "  %15s : %s\n" "Selected registries" "$(DOCKER_REGISTRIES)"; \
	failed=0; \
	for site in $(DOCKER_REGISTRIES); do \
		output="$$( $(MAKE) -s .check-docker-registry-site SITE=$$site 2>&1 )"; \
		status="$$?"; \
		if [ "$$status" -ne 0 ]; then \
			if [ -n "$$output" ]; then \
				printf "%s\n" "$$output" | sed '/^make\[[0-9][0-9]*\]: \*\*\*/d;/^make: \*\*\*/d'; \
			fi; \
			failed=1; \
		fi; \
	done; \
	if [ "$$failed" -ne 0 ]; then \
		echo ">> Docker Site Preflight: [FAIL]"; \
		exit 1; \
	fi; \
	echo ">> Docker Site Preflight: [PASS]"
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
			exit 1; \
		fi; \
		if ! docker_config_has_registry "$$docker_config" "$(DOCKER_REGISTRY_$(DOCKER_SITE))"; then \
			echo "ERROR: Docker registry $(DOCKER_SITE) is not logged in: $(DOCKER_REGISTRY_$(DOCKER_SITE))"; \
			exit 1; \
		fi; \
	fi

.push-docker-site:
	$(eval DOCKER_SITE := $(call uppercase,$(SITE)))
	$(eval REGISTRY := $(DOCKER_REGISTRY_$(DOCKER_SITE)))
	@set -e; \
	push_version="$(DOCKER_PUSH_VERSION)"; \
	if [ -z "$$push_version" ]; then \
		push_version="$$($(BUILD_MANIFEST_CMD) require-lane --lane docker $(BUILD_MANIFEST_COMMON_ARGS))"; \
	fi; \
	registry="$(REGISTRY)"; \
	registry_prefix="$$registry"; \
	if [ -n "$(DOCKER_SUBREPO)" ]; then registry_prefix="$$registry/$(DOCKER_SUBREPO)"; fi; \
	curl_config_file=""; \
	if [ "$(DOCKER_CHECK_REMOTE_TAGS)" = "yes" ] && [ "$(DOCKER_ALLOW_TAG_OVERWRITE)" != "yes" ]; then \
		registry_auth="$${DOCKER_REGISTRY_$(DOCKER_SITE)_USER:-}"; \
		if [ -z "$$registry_auth" ]; then \
			echo "ERROR: Docker remote tag check requires DOCKER_REGISTRY_$(DOCKER_SITE)_USER."; \
			exit 1; \
		fi; \
		curl_config_file="$$(mktemp "$${TMPDIR:-/tmp}/docker-push-curl-config.XXXXXX")"; \
		chmod 600 "$$curl_config_file"; \
		printf 'user = "%s"\n' "$$registry_auth" > "$$curl_config_file"; \
		trap 'rm -f "$$curl_config_file"' EXIT; \
		trap 'rm -f "$$curl_config_file"; exit 130' INT; \
		trap 'rm -f "$$curl_config_file"; exit 143' TERM; \
	fi; \
	validate_docker_ref() { \
		label="$$1"; \
		ref="$$2"; \
		case "$$ref" in ""|*[^A-Za-z0-9._:/-]*) echo "ERROR: invalid Docker $$label: $$ref"; exit 2 ;; esac; \
	}; \
	remote_docker_tag_exists() { \
		repo_path="$$1"; \
		tag="$$2"; \
		response_file="$$(mktemp "$${TMPDIR:-/tmp}/docker-remote-tag.XXXXXX")"; \
		http_code="$$(curl $(DOCKER_CURL_TIMEOUT_FLAGS) -sS -o "$$response_file" -w '%{http_code}' --config "$$curl_config_file" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' "https://$$registry/v2/$$repo_path/manifests/$$tag")" || { \
			echo "ERROR: Docker registry tag probe failed for $$registry/$$repo_path:$$tag"; \
			rm -f "$$response_file"; \
			return 2; \
		}; \
		case "$$http_code" in \
			200|201|202) rm -f "$$response_file"; return 0 ;; \
			404) rm -f "$$response_file"; return 1 ;; \
			*) \
				echo "ERROR: Docker registry returned HTTP $$http_code while checking $$registry/$$repo_path:$$tag"; \
				if [ -s "$$response_file" ]; then sed 's/^/Registry response: /' "$$response_file"; fi; \
				rm -f "$$response_file"; \
				return 2 ;; \
		esac; \
	}; \
	assert_remote_docker_tag_absent() { \
		repo_path="$$1"; \
		tag="$$2"; \
		ref="$$3"; \
		if [ "$(DOCKER_CHECK_REMOTE_TAGS)" != "yes" ] || [ "$(DOCKER_ALLOW_TAG_OVERWRITE)" = "yes" ] || [ "$$tag" = "latest" ]; then \
			return 0; \
		fi; \
		set +e; \
		remote_docker_tag_exists "$$repo_path" "$$tag"; \
		status="$$?"; \
		set -e; \
		if [ "$$status" = "0" ]; then \
			echo "ERROR: Docker remote tag already exists: $$ref"; \
			echo "Set DOCKER_ALLOW_TAG_OVERWRITE=yes only with explicit release approval."; \
			exit 1; \
		fi; \
		if [ "$$status" -gt 1 ]; then exit "$$status"; fi; \
	}; \
	publish_docker_ref() { \
		image="$$1"; \
		target_tag="$$2"; \
		source_tag="$$3"; \
		source_ref="$$image:$$source_tag"; \
		target_ref="$$registry_prefix/$$image:$$target_tag"; \
		repo_path="$$image"; \
		if [ -n "$(DOCKER_SUBREPO)" ]; then repo_path="$(DOCKER_SUBREPO)/$$image"; fi; \
		validate_docker_ref "source ref" "$$source_ref"; \
		validate_docker_ref "target ref" "$$target_ref"; \
		assert_remote_docker_tag_absent "$$repo_path" "$$target_tag" "$$target_ref"; \
		echo ""; \
		printf "%s" "Tagging image $$source_ref to registry: $$target_ref"; \
		docker tag "$$source_ref" "$$target_ref"; \
		echo " ...Done."; \
		echo "Pushing image $$target_ref"; \
		docker push "$$target_ref"; \
		echo "Pushed."; \
	}; \
	validate_docker_ref "registry prefix" "$$registry_prefix"; \
	validate_docker_ref "version tag" "$$push_version"; \
	echo ">> Docker Publish Target"; \
	printf "  %15s : %s\n" "Site" "$(DOCKER_SITE)"; \
	printf "  %15s : %s\n" "Registry" "$(REGISTRY)"; \
	printf "  %15s : %s\n" "Subrepo" "$(if $(DOCKER_SUBREPO),$(DOCKER_SUBREPO),(none))"; \
	printf "  %15s : %s\n" "Version Tag" "$$push_version"; \
	printf "  %15s : %s\n" "Latest Tag" "$(DOCKER_PUSH_LATEST)"; \
		echo ""; \
		artifact_refs="$$( $(BUILD_MANIFEST_CMD) artifacts --lane docker $(BUILD_MANIFEST_COMMON_ARGS) )"; \
		if [ -z "$$artifact_refs" ]; then \
			echo "ERROR: manifest docker lane has no image artifacts."; \
			exit 1; \
		fi; \
		for ref in $$artifact_refs; do \
			image="$${ref%:*}"; \
			source_tag="$${ref##*:}"; \
			if [ "$$image" = "$$ref" ] || [ -z "$$image" ] || [ -z "$$source_tag" ]; then \
				echo "ERROR: invalid manifest Docker image ref: $$ref"; \
				exit 2; \
			fi; \
			publish_docker_ref "$$image" "$$push_version" "$$source_tag"; \
		done; \
		if [ "$(DOCKER_PUSH_LATEST)" = "yes" ]; then \
			for ref in $$artifact_refs; do \
				image="$${ref%:*}"; \
				source_tag="$${ref##*:}"; \
				publish_docker_ref "$$image" "latest" "$$source_tag"; \
			done; \
		fi; \
	if [ -n "$$curl_config_file" ]; then rm -f "$$curl_config_file"; trap - EXIT INT TERM; fi

.push-docker-image:
	$(eval SOURCE_IMAGE_TAG := $(if $(SOURCE_TAG),$(SOURCE_TAG),$(IMAGE_TAG)))
	$(eval REGISTRY_IMAGE_PREFIX := $(if $(DOCKER_SUBREPO),$(REGISTRY)/$(DOCKER_SUBREPO),$(REGISTRY)))
	@set -e; \
	source_ref="$(IMAGE):$(SOURCE_IMAGE_TAG)"; \
	target_ref="$(REGISTRY_IMAGE_PREFIX)/$(IMAGE):$(IMAGE_TAG)"; \
	case "$$source_ref" in ""|*[^A-Za-z0-9._:/-]*) echo "ERROR: invalid Docker source ref: $$source_ref"; exit 2 ;; esac; \
	case "$$target_ref" in ""|*[^A-Za-z0-9._:/-]*) echo "ERROR: invalid Docker target ref: $$target_ref"; exit 2 ;; esac
	@echo ""
	@printf "%s" "Tagging image $(IMAGE):$(SOURCE_IMAGE_TAG) to registry: $(REGISTRY_IMAGE_PREFIX)/$(IMAGE):$(IMAGE_TAG)"
	@docker tag "$(IMAGE):$(SOURCE_IMAGE_TAG)" "$(REGISTRY_IMAGE_PREFIX)/$(IMAGE):$(IMAGE_TAG)"
	@echo " ...Done."
	@echo "Pushing image $(IMAGE):$(IMAGE_TAG) to registry: $(REGISTRY)"
	@docker push "$(REGISTRY_IMAGE_PREFIX)/$(IMAGE):$(IMAGE_TAG)"
	@echo "Pushed."

list-docker:
	@$(MAKE) -s .list-docker-local
	@if [ -z "$(strip $(DOCKER_REGISTRIES))" ]; then \
		echo "No Docker registries configured."; \
		echo ""; \
	else \
		for site in $(DOCKER_REGISTRIES); do \
			$(MAKE) -s .list-docker-site SITE=$$site; \
		done; \
	fi

clean-docker: $(DOCKER_CLEAN_DEPS)
	@if [ "$(DOCKER_CLEAN_GLOBAL_PRUNE)" = "yes" ]; then \
		echo "Removing untagged Docker images by explicit request..."; \
		docker image prune -f; \
	else \
		echo "Skipped global Docker image prune. Set DOCKER_CLEAN_GLOBAL_PRUNE=yes to opt in."; \
	fi
	@if [ "$(DOCKER_CLEAN_TAGGED)" != "yes" ]; then \
		echo "Skipped older tagged image cleanup. Set DOCKER_CLEAN_TAGGED=yes to opt in."; \
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
	@$(MAKE) -s list-docker DOCKER_REGISTRIES=CN

list-docker-us:
	@$(MAKE) -s list-docker DOCKER_REGISTRIES=US

list-docker-%:
	@echo "ERROR: unsupported Docker list target: list-docker-$*."
	@echo "Supported targets: list-docker, list-docker-local, list-docker-cn, list-docker-us."
	@exit 2

.list-docker-local:
	@echo ">> Local Docker Images"
	@printf "  %15s : %s\n" "$(DOCKER_LIST_LOCAL_LABEL)" "$(DOCKER_IMAGES)"
	@echo ""
	@docker_info_output=$$(mktemp); \
	if ! docker info > "$$docker_info_output" 2>&1; then \
		echo "Docker daemon is not running or not reachable."; \
		if [ -s "$$docker_info_output" ]; then cat "$$docker_info_output"; fi; \
		rm -f "$$docker_info_output"; \
		echo ""; \
	else \
		rm -f "$$docker_info_output"; \
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
			curl_config_file="$$(mktemp "$${TMPDIR:-/tmp}/docker-curl-config.XXXXXX")"; \
			chmod 600 "$$curl_config_file"; \
			printf 'user = "%s"\n' "$${$(REGISTRY_USER_VAR)}" > "$$curl_config_file"; \
			trap 'rm -f "$$curl_config_file"' EXIT; \
			trap 'rm -f "$$curl_config_file"; exit 130' INT; \
			trap 'rm -f "$$curl_config_file"; exit 143' TERM; \
			repo_prefix=""; \
			if [ -n "$(DOCKER_SUBREPO)" ]; then repo_prefix="$(DOCKER_SUBREPO)/"; fi; \
			for image in $(DOCKER_IMAGES); do \
				echo "Image: $$image"; \
				echo ""; \
				response=$$(curl $(DOCKER_CURL_TIMEOUT_FLAGS) -sS --config "$$curl_config_file" "https://$(REGISTRY)/v2/$${repo_prefix}$$image/tags/list"); \
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
			rm -f "$$curl_config_file"; \
			trap - EXIT INT TERM; \
		fi
