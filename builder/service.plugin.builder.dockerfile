# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Build base build image for ASN Service Plugins

ARG BUILD_ENV_BASE_IMAGE=asn-service-builder-base:local
FROM ${BUILD_ENV_BASE_IMAGE}

WORKDIR /asn-service

# -Dependencies should have been installed in the base image.
# -dpkg-dev should have been installed.
# -Golang should have been installed.
#RUN apt update && \
#    apt install -y  dpkg-dev

# Only set the ENV for the new build.
ENV PATH="${PATH}:/etc/go/bin"
#ENV GOPROXY="https://goproxy.io,direct"
#ENV GOPATH=/go
#ENV GOCACHE=${GOPATH}/.cache
#ENV GOMODCACHE=${GOPATH}/pkg/mod

# Clean up the $WORKDIR
RUN rm -rf /asn-service/*

# Copy project files
COPY . .


# Allow MAKE_TARGET to be passed in
ARG MAKE_TARGET=build.targets
ARG SERVICE_BUILD_MAKEFILE=Makefile
ARG BUILD_MODE=dev
ARG VERSION_BUILD
ENV BUILD_MODE=${BUILD_MODE}
ENV VERSION_BUILD=${VERSION_BUILD}

# Run make specified targets: $(MAKE_TARGETS)
RUN --mount=type=secret,id=sshkey \
    make -f ${SERVICE_BUILD_MAKEFILE} ${MAKE_TARGET} BUILD_MODE="${BUILD_MODE}" VERSION_BUILD="${VERSION_BUILD}"

# Move the build dir to /
RUN mv build /

CMD ["bash"]
