# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Build base build image for ASN Service Plugins

FROM ubuntu:24.04

WORKDIR /asn-service
ARG GO_VERSION

## Install critical dependencies in one layer with noninteractive mode
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y build-essential wget git ca-certificates gnupg2 protobuf-compiler

## Install dpkg-dev
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y dpkg-dev

# Install Go
RUN test -n "$GO_VERSION" && \
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
    tar -C /etc -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm -f go${GO_VERSION}.linux-amd64.tar.gz
ENV PATH="${PATH}:/etc/go/bin"
RUN go version | grep -q "go${GO_VERSION} "
#ENV GOPROXY="https://goproxy.io,direct"
#ENV GOPATH=/go
#ENV GOCACHE=${GOPATH}/.cache
#ENV GOMODCACHE=${GOPATH}/pkg/mod

# Configure SSH for private GitHub repositories
ENV GOPRIVATE="github.com/amianetworks/*"
RUN git config --global --add url."git@github.com:".insteadOf "https://github.com/" && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    echo "Host *\n  IdentityFile /run/secrets/sshkey\n  StrictHostKeyChecking no" > /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Copy project files
COPY . .

# Download all modules declared by the service so later plugin builds do not
# depend on ad hoc network access for service-specific Go dependencies.
RUN --mount=type=secret,id=sshkey \
    --mount=type=cache,target=/root/go/pkg/mod \
    go mod download

# Run build.so once to get all Go packages downloaded.
RUN --mount=type=secret,id=sshkey \
    --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    make -f make/internal.mk build.so

# Clean up the workdir for later builds.
WORKDIR /
RUN rm -rf /asn-service

# Default 
CMD ["bash"]
