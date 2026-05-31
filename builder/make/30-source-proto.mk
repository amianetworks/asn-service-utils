# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

##----------------------------------------------------------------------------##
## Source maintenance ##
##
## Consuming services may override package/path/tool variables in their own
## config, while service-utils owns the reusable Go source-maintenance recipes.

GOCACHE ?= $(CURDIR)/.cache/go-build
export GOCACHE
GO_TEST_FLAGS ?=
SERVICE_GO_CHECK_PACKAGES ?= ./...
SERVICE_GO_FORMAT_PACKAGES ?= ./...
SERVICE_GOIMPORTS_PATHS ?= .
SERVICE_GOIMPORTS_LOCAL ?= $(PACKAGE)
SERVICE_GOIMPORTS ?= goimports
SERVICE_ERRCHECK ?= errcheck
SERVICE_STATICCHECK ?= go run honnef.co/go/tools/cmd/staticcheck@v0.6.1
SERVICE_GOLANGCI_LINT ?= go run github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.8

go-test:
	@if [ -z "$(PKG)" ]; then \
		echo "ERROR: set PKG=./path/to/package for targeted Go validation."; \
		exit 2; \
	fi
	go test $(GO_TEST_FLAGS) $(PKG)

code-cleanup: deps-tidy code-format code-check

deps-tidy:
	@echo "running [go mod tidy]"
	@go mod tidy
	@echo "deps-tidy completed"

deps-update:
	@echo "WARNING: deps-update performs broad dependency upgrades with go get -u."
	@echo "Run only with explicit approval."
	@echo "running [go mod tidy]"
	@go mod tidy
	@echo "running [go get -u]"
	@go get -u
	@echo "running [go mod tidy]"
	@go mod tidy
	@echo "deps-update completed"

code-format:
	@set -e; \
	goimports_args=(); \
	if [ -n "$(strip $(SERVICE_GOIMPORTS_LOCAL))" ]; then goimports_args=(-local "$(SERVICE_GOIMPORTS_LOCAL)"); fi; \
	$(SERVICE_GOIMPORTS) -w "$${goimports_args[@]}" $(SERVICE_GOIMPORTS_PATHS); \
	go fmt $(SERVICE_GO_FORMAT_PACKAGES)
	@echo "code-format completed"

code-check:
	$(SERVICE_ERRCHECK) $(SERVICE_GO_CHECK_PACKAGES)
	go vet $(SERVICE_GO_CHECK_PACKAGES)
	$(SERVICE_STATICCHECK) $(SERVICE_GO_CHECK_PACKAGES)
	$(SERVICE_GOLANGCI_LINT) run
	@echo "code-check completed"

code-inspect: code-format code-check
	@echo "code-inspect completed"

##----------------------------------------------------------------------------##
## Protobuf generation ##
##
## Consuming services own PROTO_SOURCE_FILES. The shared builder owns the common
## generated-file/spec/state defaults, pinned tool staging, version checks,
## incremental stamp, and generation loop. Each PROTO_GEN_SPECS item is
## source-glob:generated-output-dir, where the output dir is relative to
## PROTO_OUT.

PROTOC_VERSION ?= libprotoc 34.1
PROTOC_RELEASE_VERSION ?= $(lastword $(PROTOC_VERSION))
PROTOC_GEN_GO_VERSION ?= v1.36.11
PROTOC_GEN_GO_GRPC_VERSION ?= v1.6.0
PROTO_TOOLS_DIR ?= .cache/proto-tools
PROTO_TOOLS_BIN := $(abspath $(PROTO_TOOLS_DIR)/bin)
PROTOC_LOCAL := $(PROTO_TOOLS_BIN)/protoc
PROTOC_RELEASE_DIR := $(abspath $(PROTO_TOOLS_DIR)/protoc-$(PROTOC_RELEASE_VERSION))
PROTOC_INCLUDE := $(PROTOC_RELEASE_DIR)/include
PROTOC_DOWNLOAD_BASE_URL ?= https://github.com/protocolbuffers/protobuf/releases/download/v$(PROTOC_RELEASE_VERSION)
PROTOC_AUTO_DOWNLOAD ?= 1
PROTO_OUT ?= .
PROTO_GEN_ENV := PATH="$(PROTO_TOOLS_BIN):$$PATH"
PROTO_GEN_STAMP ?= $(PROTO_TOOLS_DIR)/proto-gen.stamp
PROTO_GEN_FORCE ?= 0
PROTO_GEN_DEFAULT_OUT := $(abspath .)
PROTO_SOURCE_FILES ?=
PROTO_GENERATED_FILES ?= $(patsubst %.proto,%.pb.go,$(PROTO_SOURCE_FILES))
PROTO_GEN_SPECS ?= $(foreach source,$(PROTO_SOURCE_FILES),$(source):$(patsubst %/,%,$(dir $(source))))
PROTO_GEN_STATE_FILES ?= Makefile make/config.mk $(BUILD_ENV_MAKEFILE) $(wildcard $(SERVICE_UTILS_DIR)/builder/make/*.mk) $(SERVICE_UTILS_DIR)/builder/proto_tools.sh $(PROTO_SOURCE_FILES) $(PROTO_GENERATED_FILES)
PROTOC_DEFAULTED := $(if $(filter undefined,$(origin PROTOC)),1,0)
PROTOC ?= $(PROTOC_LOCAL)

proto-tools:
	@$(PROTO_GEN_ENV) $(PROTO_TOOLS_CMD) tools \
		--protoc-version "$(PROTOC_VERSION)" \
		--protoc-release-version "$(PROTOC_RELEASE_VERSION)" \
		--protoc-gen-go-version "$(PROTOC_GEN_GO_VERSION)" \
		--protoc-gen-go-grpc-version "$(PROTOC_GEN_GO_GRPC_VERSION)" \
		--tools-dir "$(PROTO_TOOLS_DIR)" \
		--download-base-url "$(PROTOC_DOWNLOAD_BASE_URL)" \
		--auto-download "$(PROTOC_AUTO_DOWNLOAD)" \
		--protoc-defaulted "$(PROTOC_DEFAULTED)" \
		--protoc "$(PROTOC)"

proto-tools-check:
	@$(PROTO_GEN_ENV) $(PROTO_TOOLS_CMD) tools-check \
		--protoc-version "$(PROTOC_VERSION)" \
		--protoc-release-version "$(PROTOC_RELEASE_VERSION)" \
		--protoc-gen-go-version "$(PROTOC_GEN_GO_VERSION)" \
		--protoc-gen-go-grpc-version "$(PROTOC_GEN_GO_GRPC_VERSION)" \
		--tools-dir "$(PROTO_TOOLS_DIR)" \
		--download-base-url "$(PROTOC_DOWNLOAD_BASE_URL)" \
		--auto-download "$(PROTOC_AUTO_DOWNLOAD)" \
		--protoc-defaulted "$(PROTOC_DEFAULTED)" \
		--protoc "$(PROTOC)"

proto-gen:
	@$(PROTO_GEN_ENV) $(PROTO_TOOLS_CMD) gen \
		--protoc-version "$(PROTOC_VERSION)" \
		--protoc-release-version "$(PROTOC_RELEASE_VERSION)" \
		--protoc-gen-go-version "$(PROTOC_GEN_GO_VERSION)" \
		--protoc-gen-go-grpc-version "$(PROTOC_GEN_GO_GRPC_VERSION)" \
		--tools-dir "$(PROTO_TOOLS_DIR)" \
		--download-base-url "$(PROTOC_DOWNLOAD_BASE_URL)" \
		--auto-download "$(PROTOC_AUTO_DOWNLOAD)" \
		--protoc-defaulted "$(PROTOC_DEFAULTED)" \
		--protoc "$(PROTOC)" \
		--proto-out "$(PROTO_OUT)" \
		--default-out "$(PROTO_GEN_DEFAULT_OUT)" \
		--stamp "$(PROTO_GEN_STAMP)" \
		--force "$(PROTO_GEN_FORCE)" \
		--specs "$(PROTO_GEN_SPECS)" \
		--state-files "$(PROTO_GEN_STATE_FILES)"

proto-gen-force: PROTO_GEN_FORCE=1
proto-gen-force: proto-gen
