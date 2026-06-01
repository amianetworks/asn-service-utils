# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Variable checks ##

.check_vars:
	@echo ">> Variable Inventory"; \
	echo "Secret values are redacted."; \
	echo ""; \
	printf "%-44s %-11s %-7s %s\n" "Variable" "Status" "Secret" "Used by"; \
	printf "%-44s %-11s %-7s %s\n" "--------" "------" "------" "-------"; \
	private_key="$${PRIVATE_GIT_SSH_KEY_FILE:-}"; \
	if [ -z "$$private_key" ]; then status="MISSING"; elif [ ! -r "$$private_key" ]; then status="UNREADABLE"; else status="SET"; fi; \
	printf "%-44s %-11s %-7s %s\n" "PRIVATE_GIT_SSH_KEY_FILE" "$$status" "yes" "init"; \
	if [ -z "$(strip $(DOCKER_REGISTRIES))" ]; then status="MISSING"; else status="SET"; fi; \
	printf "%-44s %-11s %-7s %s\n" "DOCKER_REGISTRIES" "$$status" "no" "plan-push-docker, push-docker"; \
	if [ -z "$(strip $(DEBIAN_REPOSITORIES))" ]; then status="MISSING"; else status="SET"; fi; \
	printf "%-44s %-11s %-7s %s\n" "DEBIAN_REPOSITORIES" "$$status" "no" "plan-push-debian, push-debian"
	@for site in $(sort $(DOCKER_REGISTRIES) $(DEBIAN_REPOSITORIES)); do \
		$(MAKE) -s .print-publish-profile-var SITE=$$site; \
	done
	@for site in $(DOCKER_REGISTRIES); do \
		$(MAKE) -s .print-docker-push-var SITE=$$site; \
	done
	@for site in $(DEBIAN_REPOSITORIES); do \
		$(MAKE) -s .print-debian-push-var SITE=$$site; \
	done
	@echo ""; \
	echo "Variable inventory completed without printing secret values."

.print-publish-profile-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	@status="SET"; \
	if [ -z "$(strip $(VAR_PROFILE))" ]; then status="MISSING"; fi; \
	printf "%-44s %-11s %-7s %s\n" "RELEASE_SECRET_PROFILE_$(VAR_SITE)" "$$status" "no" "publish credential selection"

.print-docker-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DOCKER)
	$(eval VAR_REGISTRY := $(DOCKER_REGISTRY_$(VAR_SITE)))
	@$(PUBLISH_VARS_CMD) print --kind docker --site "$(VAR_SITE)" --endpoint-name "DOCKER_REGISTRY_$(VAR_SITE)" --endpoint "$(VAR_REGISTRY)" --profile "$(VAR_PROFILE)" --profile-row no --auth-var "$(VAR_AUTH_VAR)" --credential-var "DOCKER_REGISTRY_$(VAR_SITE)_USER" --used-by "push-docker-$(call lowercase,$(VAR_SITE))"

.print-debian-push-var:
	$(eval VAR_SITE := $(call uppercase,$(SITE)))
	$(eval VAR_PROFILE := $(RELEASE_SECRET_PROFILE_$(VAR_SITE)))
	$(eval VAR_AUTH_VAR := RELEASE_SECRET_AUTH_$(VAR_PROFILE)_DEBIAN)
	$(eval VAR_HOST := $(DEBIAN_REPO_HOST_$(VAR_SITE)))
	@$(PUBLISH_VARS_CMD) print --kind debian --site "$(VAR_SITE)" --endpoint-name "DEBIAN_REPO_HOST_$(VAR_SITE)" --endpoint "$(VAR_HOST)" --profile "$(VAR_PROFILE)" --profile-row no --auth-var "$(VAR_AUTH_VAR)" --credential-var "DEBIAN_REPO_USER_$(VAR_SITE)" --used-by "push-debian-$(call lowercase,$(VAR_SITE))"

.check_build_vars:
	@failed=0; \
	tmp="$$(mktemp "$${TMPDIR:-/tmp}/check-private-key.XXXXXX")"; \
	trap 'rm -f "$$tmp"' EXIT; \
	check_file_var() { \
		name="$$1"; value="$$2"; required="$$3"; secret="$$4"; \
		display="$$value"; \
		if [ "$$secret" = "yes" ] && [ -n "$$value" ]; then display="<set>"; fi; \
		if [ -z "$$value" ]; then \
			display="<empty>"; \
			if [ "$$required" = "yes" ]; then failed=1; fi; \
		elif [ ! -r "$$value" ]; then \
			display="$$display (unreadable)"; \
			failed=1; \
		fi; \
		printf "  %24s : %s\n" "$$name" "$$display" >> "$$tmp"; \
	}; \
	check_file_var "PRIVATE_GIT_SSH_KEY_FILE" "$${PRIVATE_GIT_SSH_KEY_FILE:-}" "yes" "yes"; \
	if [ "$$failed" -ne 0 ]; then \
		echo ">> Build Variable Check: [FAIL]"; \
		cat "$$tmp"; \
		echo ""; \
		echo "Build variable check failed. Set PRIVATE_GIT_SSH_KEY_FILE to a readable private Git SSH key using one of the methods below."; \
		echo ""; \
		echo "Private Git SSH key file"; \
		echo "  Method 1: export it from ignored make/local.mk:"; \
		echo "    export PRIVATE_GIT_SSH_KEY_FILE := /path/to/private_git_key"; \
		echo "  Method 2: export it from ~/.zshrc or ~/.bashrc:"; \
		echo "    export PRIVATE_GIT_SSH_KEY_FILE=/path/to/private_git_key"; \
		exit 1; \
	fi; \
	echo ">> Build Variable Check: [PASS]"; \
	cat "$$tmp"

check-vars: .check_vars

check-build:
	@$(BUILD_MANIFEST_CMD) check-build \
		--service "$(SERVICE)" \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
		--asn-version "$(ASN_VERSION)" \
		--dep-version-asn "$(DEP_VERSION_ASN)" \
		$(BUILD_MANIFEST_ARGS)

check-version:
	@$(BUILD_MANIFEST_CMD) check-version \
		--service "$(SERVICE)" \
		--version "$(VERSION)" \
		--mode "$(BUILD_MODE)" \
		--build "$(BUILD)" \
		--dev-start "$(BUILD_DEV)" \
		--dev-file "$(DEV_BUILD_FILE)" \
		--manifest "$(BUILD_MANIFEST_FILE)" \
		--asn-service-api-version "$(ASN_SERVICE_API_VERSION)" \
		--asn-version "$(ASN_VERSION)" \
		--dep-version-asn "$(DEP_VERSION_ASN)" \
		--go-version "$(GO_VERSION)" \
		--dep-version-go "$(DEP_VERSION_GO)" \
		$(BUILD_MANIFEST_ARGS)

check-go-mod:
	@failed=0; compared=0; skipped=0; \
	root_requires=$$(mktemp); utils_requires=$$(mktemp); \
	if [ ! -f go.mod ]; then \
		echo ">> Go Module Compatibility: [FAIL]"; \
		echo "            Missing root go.mod."; \
		rm -f "$$root_requires" "$$utils_requires"; \
		exit 1; \
	fi; \
	if [ ! -f "$(SERVICE_UTILS_DIR)/go.mod" ]; then \
		echo ">> Go Module Compatibility: [FAIL]"; \
		echo "            Missing $(SERVICE_UTILS_DIR)/go.mod."; \
		rm -f "$$root_requires" "$$utils_requires"; \
		exit 1; \
	fi; \
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
			printf "            %-48s Root: %s, service-utils: %s. FAIL\n" "$$module" "$$actual" "$$expected"; \
			failed=1; \
		else \
			compared=$$(expr $$compared + 1); \
		fi; \
	done < "$$utils_requires"; \
	rm -f "$$root_requires" "$$utils_requires"; \
	if [ "$$failed" -ne 0 ]; then \
		echo ""; \
		echo ">> Go Module Compatibility: [FAIL]"; \
		echo "            Shared package versions must match between root go.mod and service-utils/go.mod."; \
		exit 1; \
	fi; \
	echo ">> Go Module Compatibility: [PASS]"; \
	printf "  %15s : %s matched\n" "Shared packages" "$$compared"; \
	printf "  %15s : %s ignored\n" "Utils-only mods" "$$skipped"
	@echo ""
