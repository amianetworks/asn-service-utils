# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

# Build base build image for ASN Service Plugins

FROM asn-service-builder-base:latest

WORKDIR /asn-service

# -Dependencies should have been installed in the base image.
# -dpkg-dev should have been installed.
# -Golang should have been installed.
#RUN apt update && \
#    apt install -y  dpkg-dev

# Only set the ENV for the new build.
ENV PATH="${PATH}:/etc/go/bin"
ENV GOPROXY="https://goproxy.io,direct"
#ENV GOPATH=/go
#ENV GOCACHE=${GOPATH}/.cache
#ENV GOMODCACHE=${GOPATH}/pkg/mod

# Clean up the $WORKDIR
RUN rm -rf /asn-service/*

# Copy project files
COPY . .


# Allow MAKE_TARGET to be passed in
ARG MAKE_TARGET=build.targets

# Run make specified targets: $(MAKE_TARGETS)
RUN make -f make/internal.mk ${MAKE_TARGET}

# Move the build dir to /
RUN mv build /

CMD ["bash"]
