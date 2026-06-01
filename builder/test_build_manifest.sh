#!/usr/bin/env bash
# Contract tests for the local build manifest helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/build_manifest.sh"

fail() {
    echo "test_build_manifest ERROR: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1" text="$2"
    grep -Fq "$text" "$file" || fail "expected '$text' in $file"
}

assert_equals() {
    local got="$1" want="$2" label="$3"
    [ "$got" = "$want" ] || fail "$label: got '$got', want '$want'"
}

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/build-manifest-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

project="$tmpdir/project"
mkdir -p "$project/service-utils/builder" \
    "$project/build/controller" \
    "$project/build/docs/release" \
    "$project/build/debian"
cp "$SOURCE_SCRIPT" "$project/service-utils/builder/build_manifest.sh"

cd "$project"
git init -q
git config user.email "builder-test@example.invalid"
git config user.name "Builder Test"

printf 'module example.invalid/service\n' > go.mod
printf 'plugin\n' > build/controller/svc.so
printf 'config\n' > build/controller/svc.conf
git add .
git commit -q -m "initial test project"

manifest_cmd=(bash service-utils/builder/build_manifest.sh)
common_args=(
    --manifest build/Manifest.yaml
    --mode dev
    --version 1.2
    --build 7
    --debian-dir build/debian
    --debian-services svc
    --docker-images svc-image
    --service-utils-dir service-utils
    --service svc
    --schema service.build.manifest.v1
    --source-key source_commit
    --source-label service
    --plugin-required-artifacts "build/controller/svc.so"
    --plugin-required-globs "build/controller/*.conf"
)
identity_args=(
    --asn-service-api-version 26.7.0
    --asn-version 26.7.0
    --dep-version-asn 26.7.0
    --go-version 1.26.3
    --dep-version-go 1.26.3
    --service-utils-ref utils-ref
)
docs_args=(
    --docs-required-artifacts "build/docs/release/ReleaseManifest.yaml build/docs/release/DocsChecksums.tsv build/docs/index.html"
    --docs-version-file build/docs/release/ReleaseManifest.yaml
    --docs-version-key svc_version_build
)

version="$("${manifest_cmd[@]}" commit-plugin \
    "${common_args[@]}" \
    "${identity_args[@]}" \
    --dev-start 100 \
    --dev-file .DEV_BUILD_FILE \
    --version-build 1.2.101)"
assert_equals "$version" "1.2.101" "commit-plugin version"
assert_contains build/Manifest.yaml 'asn_service_api_version: "26.7.0"'
assert_contains build/Manifest.yaml 'asn_version: "26.7.0"'
assert_contains build/Manifest.yaml 'dep_version_go: "1.26.3"'
assert_contains build/Manifest.yaml 'service_utils_ref: "utils-ref"'
assert_contains build/Manifest.yaml 'status: "PASS"'

cat > build/docs/release/ReleaseManifest.yaml <<'EOF'
svc_version_build: 1.2.101
EOF
printf 'Path\tSHA256\n' > build/docs/release/DocsChecksums.tsv
printf '<!doctype html>\n' > build/docs/index.html

"${manifest_cmd[@]}" commit-lane \
    --lane docs \
    "${common_args[@]}" \
    "${docs_args[@]}" \
    --version-build 1.2.101 >/dev/null
assert_contains build/Manifest.yaml 'asn_service_api_version: "26.7.0"'
assert_contains build/Manifest.yaml 'asn_version: "26.7.0"'
assert_contains build/Manifest.yaml 'dep_version_asn: "26.7.0"'
assert_contains build/Manifest.yaml 'go_version: "1.26.3"'
assert_contains build/Manifest.yaml 'dep_version_go: "1.26.3"'

rm -rf build/docs
required="$("${manifest_cmd[@]}" require-lane --lane docs "${common_args[@]}" "${docs_args[@]}")"
assert_equals "$required" "1.2.101" "require-lane should trust committed docs lane"

artifacts="$("${manifest_cmd[@]}" artifacts --lane docs "${common_args[@]}" "${docs_args[@]}")"
printf '%s\n' "$artifacts" | grep -Fxq "build/docs/release/ReleaseManifest.yaml" || fail "missing docs release manifest artifact"
printf '%s\n' "$artifacts" | grep -Fxq "build/docs/release/DocsChecksums.tsv" || fail "missing docs checksum artifact"
printf '%s\n' "$artifacts" | grep -Fxq "build/docs/index.html" || fail "missing docs index artifact"

printf 'source change\n' > source.txt
git add source.txt
git commit -q -m "change source after manifest"

set +e
check_output="$("${manifest_cmd[@]}" check-build "${common_args[@]}" 2>&1)"
check_status=$?
set -e
[ "$check_status" -ne 0 ] || fail "check-build should fail for stale manifest"
printf '%s\n' "$check_output" | grep -Fq "<stale>" || fail "stale manifest output did not mark built version stale: $check_output"
printf '%s\n' "$check_output" | grep -Fq "manifest source source_commit" || fail "stale manifest output did not explain source mismatch: $check_output"

echo "build_manifest contract tests passed"
