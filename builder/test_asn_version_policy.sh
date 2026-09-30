#!/usr/bin/env bash
# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

# Contract tests for the API-line version policy check.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
policy=(bash "$SCRIPT_DIR/asn_version_policy.sh")

fail() {
    echo "test_asn_version_policy ERROR: $*" >&2
    exit 1
}

ok=(
    --asn-service-api-version 26.11.0
    --asn-runtime-version-pro 26.11.3
    --asn-runtime-version-dev 26.11.104
    --builder-go-version-pro 1.26.5
    --builder-go-version-dev 1.26.5
    --runtime-mode pro
)
# The check must not depend on the caller's environment.
unset ASN_SERVICE_API_VERSION ASN_RUNTIME_VERSION_PRO ASN_RUNTIME_VERSION_DEV \
    ASN_BUILDER_GO_VERSION_PRO ASN_BUILDER_GO_VERSION_DEV ASN_RUNTIME_MODE

"${policy[@]}" "${ok[@]}" || fail "a policy-conforming identity should pass"

# Later options override the conforming ones.
expect_fail() {
    local want="$1" out status
    shift
    set +e
    out="$("${policy[@]}" "${ok[@]}" "$@" 2>&1)"
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "should fail: $want"
    printf '%s\n' "$out" | grep -Fq "$want" || fail "output missing '$want': $out"
}

expect_fail "has patch 1; asn-service-api is released only as X.Y.0" --asn-service-api-version 26.11.1
expect_fail "is not X.Y.Z" --asn-service-api-version v26.11.0
expect_fail "ASN_RUNTIME_VERSION_PRO 26.10.11 is not on API line 26.11" --asn-runtime-version-pro 26.10.11
expect_fail "ASN_RUNTIME_VERSION_DEV 26.12.100 is not on API line 26.11" --asn-runtime-version-dev 26.12.100
expect_fail "differs from ASN_BUILDER_GO_VERSION_DEV 1.26.6" --builder-go-version-dev 1.26.6
expect_fail "ASN_RUNTIME_MODE must be pro or dev" --runtime-mode stable

# A line that has only one lane yet: the empty lane is allowed unless selected.
"${policy[@]}" "${ok[@]}" --asn-runtime-version-pro "" --builder-go-version-pro "" --runtime-mode dev ||
    fail "an empty PRO lane must pass when DEV is selected"
"${policy[@]}" "${ok[@]}" --asn-runtime-version-dev "" --builder-go-version-dev "" ||
    fail "an empty DEV lane must pass when PRO is selected"
expect_fail "ASN_RUNTIME_VERSION_PRO is not set, but ASN_RUNTIME_MODE=pro selects it" \
    --asn-runtime-version-pro "" --builder-go-version-pro ""
expect_fail "ASN_RUNTIME_VERSION_DEV is not set, but ASN_RUNTIME_MODE=dev selects it" \
    --asn-runtime-version-dev "" --builder-go-version-dev "" --runtime-mode dev
# An empty lane is not compared for Go, but a set lane needs its Go version.
"${policy[@]}" "${ok[@]}" --asn-runtime-version-dev "" --builder-go-version-dev 1.26.6 ||
    fail "Go versions must not be compared when a lane is empty"
expect_fail "ASN_BUILDER_GO_VERSION_DEV is not set for ASN_RUNTIME_VERSION_DEV 26.11.104" \
    --builder-go-version-dev ""
# A set but unselected lane must still be on the line.
expect_fail "ASN_RUNTIME_VERSION_DEV 26.10.116 is not on API line 26.11" --asn-runtime-version-dev 26.10.116

# Environment inputs, as builder/asn.mk exports them.
ASN_SERVICE_API_VERSION=26.11.0 ASN_RUNTIME_VERSION_PRO=26.11.3 ASN_RUNTIME_VERSION_DEV=26.11.104 \
    ASN_BUILDER_GO_VERSION_PRO=1.26.5 ASN_BUILDER_GO_VERSION_DEV=1.26.5 "${policy[@]}" ||
    fail "environment inputs should pass"

# Every violation is reported in one run.
set +e
out="$("${policy[@]}" "${ok[@]}" --asn-service-api-version 26.11.2 \
    --asn-runtime-version-pro 26.10.1 --builder-go-version-dev 1.26.6 2>&1)"
set -e
for want in "has patch 2" "ASN_RUNTIME_VERSION_PRO 26.10.1" "differs from ASN_BUILDER_GO_VERSION_DEV"; do
    printf '%s\n' "$out" | grep -Fq "$want" || fail "multi-violation output missing '$want': $out"
done

echo "asn_version_policy contract tests passed"
