# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Build base build image for ASN Service Plugins

FROM ubuntu:24.04

WORKDIR /asn-service
ARG GO_VERSION

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,id=asn-service-builder-base-apt-cache-ubuntu24.04,target=/var/cache/apt,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
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

COPY go.* ./
RUN --mount=type=secret,id=sshkey \
    go mod download

# Keep the base image source-free. Build targets run later with the service
# checkout bind-mounted by service-build-once-docker-run.
WORKDIR /
RUN rm -rf /asn-service

# Default 
CMD ["bash"]
