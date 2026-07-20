# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Build artifact base image for ASN service projects.

FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

WORKDIR /asn-service
ARG TARGETARCH

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,id=am-apt-archives-ubuntu-24.04-${TARGETARCH}-asn-builder-tools-v1,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=am-apt-lists-ubuntu-24.04-${TARGETARCH}-asn-builder-tools-v1,target=/var/lib/apt/lists,sharing=locked \
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
    update-ca-certificates

# Install Go
ARG GO_VERSION
RUN test -n "$GO_VERSION" && \
    case "$TARGETARCH" in amd64|arm64) ;; *) echo "unsupported builder architecture: $TARGETARCH" >&2; exit 2 ;; esac && \
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz && \
    tar -C /etc -xzf go${GO_VERSION}.linux-${TARGETARCH}.tar.gz && \
    rm -f go${GO_VERSION}.linux-${TARGETARCH}.tar.gz
ENV PATH="${PATH}:/etc/go/bin"
RUN go version | grep -q "go${GO_VERSION} "
#ENV GOPROXY="https://goproxy.io,direct"
#ENV GOPATH=/go
#ENV GOCACHE=${GOPATH}/.cache
#ENV GOMODCACHE=${GOPATH}/pkg/mod

# Keep the base image source-free. Build targets run later with the service
# checkout bind-mounted by the artifact build executor. The executor supplies
# private-module Git and SSH configuration for the numeric host user only when
# the selected project declares private modules.
WORKDIR /
RUN rm -rf /asn-service

# Default
CMD ["bash"]
