# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Build artifact base image for ASN service projects.

ARG GO_VERSION=1.26.4

FROM golang:${GO_VERSION} AS go-toolchain

FROM ubuntu:24.04

WORKDIR /asn-service
ARG GO_VERSION

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,id=asn-artifact-builder-base-apt-cache-ubuntu24.04,target=/var/cache/apt,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      dpkg-dev \
      git \
      gnupg2 \
      openssh-client \
      protobuf-compiler \
      wget && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install Go from the official toolchain image instead of downloading from
# go.dev during the builder-image build.
COPY --from=go-toolchain /usr/local/go /etc/go
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

COPY go.* ./
RUN --mount=type=secret,id=sshkey \
    go mod download all

# Keep the base image source-free. Build targets run later with the service
# checkout bind-mounted by the artifact build executor.
WORKDIR /
RUN rm -rf /asn-service

# Default
CMD ["bash"]
