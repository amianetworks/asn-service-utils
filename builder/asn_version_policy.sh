#!/usr/bin/env bash
# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Enforce the API-line version policy (asn-service-api README "Versioning";
# ASN workflow/design/VersionCompatibility.md, "Enforcement at Build Time"):
#   - asn-service-api is released only as X.Y.0;
#   - every runtime lane that is set (ASN_RUNTIME_VERSION_PRO / _DEV) is on the
#     API's X.Y, and the lane ASN_RUNTIME_MODE selects is set;
#   - PRO and DEV build with the same Go toolchain;
#   - the project's own version is X.Y.n on the API line: VERSION is the API's
#     X.Y, a PRO build number stays below 100 and a DEV build number starts at
#     100 (ASN workflow/alpha/ASN.ControllerUpgrade.md CU-D1). This holds for
#     ASN and for every service built with this builder.
# A lane may be empty: when a line starts, the lane that has no build on it yet
# is cleared by ASN `make set-version` rather than left on the previous line.
# Every violation is reported before failing, so one run shows the whole fix.
#
# Inputs default to the variables builder/asn.mk exports; options override them.
# This is ASN policy, so it lives here rather than in the neutral AM Workflow
# build_manifest.sh (which owns BUILD_MANIFEST_CMD).

set -euo pipefail

api="${ASN_SERVICE_API_VERSION:-}"
runtime_pro="${ASN_RUNTIME_VERSION_PRO:-}"
runtime_dev="${ASN_RUNTIME_VERSION_DEV:-}"
go_pro="${ASN_BUILDER_GO_VERSION_PRO:-}"
go_dev="${ASN_BUILDER_GO_VERSION_DEV:-}"
mode="${ASN_RUNTIME_MODE:-pro}"
version="${VERSION:-}"
build_mode="${BUILD_MODE:-}"
build="${BUILD:-}"
build_dev="${BUILD_DEV:-}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --asn-service-api-version) shift; api="${1:-}" ;;
        --asn-runtime-version-pro) shift; runtime_pro="${1:-}" ;;
        --asn-runtime-version-dev) shift; runtime_dev="${1:-}" ;;
        --builder-go-version-pro) shift; go_pro="${1:-}" ;;
        --builder-go-version-dev) shift; go_dev="${1:-}" ;;
        --runtime-mode) shift; mode="${1:-}" ;;
        --version) shift; version="${1:-}" ;;
        --build-mode) shift; build_mode="${1:-}" ;;
        --build) shift; build="${1:-}" ;;
        --build-dev) shift; build_dev="${1:-}" ;;
        *) echo "asn_version_policy ERROR: unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# line prints X.Y of an X.Y[.Z...] version, or nothing.
line() {
    printf '%s\n' "$1" | awk -F. 'NF >= 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print $1 "." $2 }'
}

errors=""
add() { errors="${errors}$1"$'\n'; }

if ! printf '%s\n' "$api" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    add "ASN_SERVICE_API_VERSION '$api' is not X.Y.Z"
elif [ "${api##*.}" != "0" ]; then
    add "ASN_SERVICE_API_VERSION $api has patch ${api##*.}; asn-service-api is released only as X.Y.0"
fi
api_line="$(line "$api")"

case "$mode" in
    pro|dev) ;;
    *) add "ASN_RUNTIME_MODE must be pro or dev, got '$mode'" ;;
esac

# check_lane NAME RUNTIME GO_NAME GO: a set lane must be on the API line and
# carry its Go version; the selected lane must be set.
check_lane() {
    local lane="$1" runtime="$2" go="$3" upper
    upper="$(printf '%s' "$lane" | tr '[:lower:]' '[:upper:]')"
    if [ -z "$runtime" ]; then
        if [ "$lane" = "$mode" ]; then
            add "ASN_RUNTIME_VERSION_$upper is not set, but ASN_RUNTIME_MODE=$mode selects it; line $api_line has no $upper runtime yet"
        fi
        return
    fi
    if [ -n "$api_line" ] && [ "$(line "$runtime")" != "$api_line" ]; then
        add "ASN_RUNTIME_VERSION_$upper $runtime is not on API line $api_line (ASN_SERVICE_API_VERSION $api)"
    fi
    [ -n "$go" ] || add "ASN_BUILDER_GO_VERSION_$upper is not set for ASN_RUNTIME_VERSION_$upper $runtime"
}
check_lane pro "$runtime_pro" "$go_pro"
check_lane dev "$runtime_dev" "$go_dev"

if [ -n "$runtime_pro" ] && [ -n "$runtime_dev" ] && [ -n "$go_pro" ] && [ -n "$go_dev" ] &&
    [ "$go_pro" != "$go_dev" ]; then
    add "ASN_BUILDER_GO_VERSION_PRO $go_pro differs from ASN_BUILDER_GO_VERSION_DEV $go_dev; one line builds PRO and DEV with one toolchain"
fi

# The project's version X.Y.n: X.Y is the API line; n < 100 is PRO, n >= 100
# is DEV. BUILD and BUILD_DEV are the last builds of each lane, so the next
# build is one higher.
if [ -z "$version" ]; then
    add "VERSION is not set; it must be the API line $api_line"
elif ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+$'; then
    add "VERSION '$version' is not X.Y; the version is X.Y.n with X.Y the API line $api_line"
elif [ -n "$api_line" ] && [ "$version" != "$api_line" ]; then
    add "VERSION $version is not the API line $api_line (ASN_SERVICE_API_VERSION $api); the version is X.Y.n on the API line"
fi
case "$build_mode" in
    pro)
        if ! printf '%s\n' "$build" | grep -Eq '^[0-9]+$'; then
            add "BUILD '$build' is not a number"
        elif [ "$build" -ge 99 ]; then
            add "BUILD $build leaves no PRO build below 100 on $version; PRO builds are $version.0 to $version.99"
        fi
        ;;
    dev)
        if ! printf '%s\n' "$build_dev" | grep -Eq '^[0-9]+$'; then
            add "BUILD_DEV '$build_dev' is not a number"
        elif [ "$build_dev" -lt 99 ]; then
            add "BUILD_DEV $build_dev would build DEV below 100; DEV builds start at $version.100 (set BUILD_DEV to 99 or more)"
        fi
        ;;
    *) add "BUILD_MODE must be pro or dev, got '$build_mode'" ;;
esac

if [ -n "$errors" ]; then
    printf '%s' "$errors" | sed 's/^/check-version ERROR: /' >&2
    exit 1
fi
