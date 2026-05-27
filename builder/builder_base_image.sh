#!/usr/bin/env bash
# Build and validate the local ASN service builder base image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

command_name="${1:-}"
[ -n "$command_name" ] || {
    echo "builder_base_image ERROR: command is required" >&2
    exit 2
}
shift

image=""
dockerfile=""
context_dir="$PROJECT_ROOT"
ssh_key="${PRIVATE_GIT_SSH_KEY_FILE:-}"
api_version="${ASN_SERVICE_API_VERSION:-}"
framework_version="${DEP_VERSION_ASN:-}"
go_version="${DEP_VERSION_GO:-}"
cache_packages="${SERVICE_GO_CACHE_PACKAGES:-./...}"
input_files="go.mod go.sum service-utils/builder/service.plugin.builder.base.dockerfile service-utils/builder/service.plugin.builder.mk service-utils/builder/ASN_VERSION"
platform="${SERVICE_BUILD_DOCKER_PLATFORM:-linux/amd64}"
workdir="${SERVICE_BUILD_WORKDIR:-/asn-service}"

usage() {
    cat <<'EOF'
usage: service-utils/builder/builder_base_image.sh COMMAND [options]

Commands:
  prepare   Build and label the local builder base image.
  check     Validate the local builder base image labels and offline Go cache.
  hashes    Print service_go_mod_hash and builder_input_hash values.

Options:
  --image REF
  --dockerfile FILE
  --context DIR
  --ssh-key FILE
  --api-version VERSION
  --framework-version VERSION
  --go-version VERSION
  --cache-packages "PKG ..."
  --input-files "FILE ..."
  --platform PLATFORM
  --workdir PATH
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image) shift; image="${1:-}" ;;
        --dockerfile) shift; dockerfile="${1:-}" ;;
        --context) shift; context_dir="${1:-}" ;;
        --ssh-key) shift; ssh_key="${1:-}" ;;
        --api-version) shift; api_version="${1:-}" ;;
        --framework-version) shift; framework_version="${1:-}" ;;
        --go-version) shift; go_version="${1:-}" ;;
        --cache-packages) shift; cache_packages="${1:-}" ;;
        --input-files) shift; input_files="${1:-}" ;;
        --platform) shift; platform="${1:-}" ;;
        --workdir) shift; workdir="${1:-}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "builder_base_image ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

context_dir="$(cd "$context_dir" && pwd -P)"

require_common() {
    [ -n "$image" ] || { echo "builder_base_image ERROR: --image is required" >&2; exit 2; }
    [ -n "$api_version" ] || { echo "builder_base_image ERROR: --api-version is required" >&2; exit 2; }
    [ -n "$framework_version" ] || { echo "builder_base_image ERROR: --framework-version is required" >&2; exit 2; }
    [ -n "$go_version" ] || { echo "builder_base_image ERROR: --go-version is required" >&2; exit 2; }
    [ -f "$context_dir/go.mod" ] || { echo "builder_base_image ERROR: missing go.mod in $context_dir" >&2; exit 1; }
}

service_go_mod_hash() {
    (cd "$context_dir" && shasum -a 256 go.mod | awk '{ print $1 }')
}

builder_input_hash() {
    (
        cd "$context_dir"
        {
            printf 'ASN_SERVICE_API_VERSION=%s\n' "$api_version"
            printf 'DEP_VERSION_ASN=%s\n' "$framework_version"
            printf 'DEP_VERSION_GO=%s\n' "$go_version"
            printf 'SERVICE_GO_CACHE_PACKAGES=%s\n' "$cache_packages"
            for file in $input_files; do
                if [ -f "$file" ]; then
                    printf 'file:%s\n' "$file"
                    shasum -a 256 "$file"
                else
                    printf 'missing:%s\n' "$file"
                fi
            done
        } | shasum -a 256 | awk '{ print $1 }'
    )
}

cmd_hashes() {
    require_common
    printf 'service_go_mod_hash=%s\n' "$(service_go_mod_hash)"
    printf 'builder_input_hash=%s\n' "$(builder_input_hash)"
}

cmd_prepare() {
    require_common
    [ -n "$dockerfile" ] || { echo "builder_base_image ERROR: --dockerfile is required" >&2; exit 2; }
    [ -n "$ssh_key" ] || { echo "builder_base_image ERROR: --ssh-key or PRIVATE_GIT_SSH_KEY_FILE is required" >&2; exit 1; }
    [ -r "$ssh_key" ] || { echo "builder_base_image ERROR: SSH key is not readable: $ssh_key" >&2; exit 1; }

    local go_mod_hash inputs_hash
    go_mod_hash="$(service_go_mod_hash)"
    inputs_hash="$(builder_input_hash)"

    DOCKER_BUILDKIT=1 docker buildx build \
        --progress=plain \
        --platform "$platform" \
        --load \
        --build-arg "GO_VERSION=$go_version" \
        -f "$dockerfile" \
        --secret "id=sshkey,src=$ssh_key" \
        --label "asn.service_api=$api_version" \
        --label "asn.framework=$framework_version" \
        --label "asn.go=$go_version" \
        --label "asn.service_go_mod=$go_mod_hash" \
        --label "asn.builder_inputs=$inputs_hash" \
        -t "$image" "$context_dir"
}

print_check_failure() {
    local inspect_id="$1" api="$2" framework="$3" image_go="$4" go_mod="$5" builder_inputs="$6" expected_go_mod="$7" expected_builder_inputs="$8"

    echo ">> Builder Version and Base Image Check: [FAIL]"
    printf "  %-15s : %s\n" "Base Image" "$image"
    printf "  %-15s : %s\n" "ID" "${inspect_id#sha256:}"
    if [ "$api" = "$api_version" ]; then
        printf "  %-15s : %s (expected as ASN_SERVICE_API_VERSION).\n" "API Version" "${api:-unknown}"
    else
        printf "  %-15s : %s (expected %s as ASN_SERVICE_API_VERSION). FAIL\n" "API Version" "${api:-unknown}" "$api_version"
    fi
    if [ "$framework" = "$framework_version" ]; then
        printf "  %-15s : %s (expected from service-utils)\n" "ASN Version" "${framework:-unknown}"
    else
        printf "  %-15s : %s (expected %s from service-utils). FAIL\n" "ASN Version" "${framework:-unknown}" "$framework_version"
    fi
    if [ "$image_go" = "$go_version" ]; then
        printf "  %-15s : %s (expected from service-utils)\n" "Go Version" "${image_go:-unknown}"
    else
        printf "  %-15s : %s (expected %s from service-utils). FAIL\n" "Go Version" "${image_go:-unknown}" "$go_version"
    fi
    if [ "$go_mod" = "$expected_go_mod" ]; then
        printf "  %-15s : %s (expected from service go.mod).\n" "Service go.mod" "${go_mod:-unknown}"
    else
        printf "  %-15s : %s (expected %s from service go.mod). FAIL\n" "Service go.mod" "${go_mod:-missing}" "$expected_go_mod"
    fi
    if [ "$builder_inputs" = "$expected_builder_inputs" ]; then
        printf "  %-15s : %s (expected from builder inputs).\n" "Builder Inputs" "${builder_inputs:-unknown}"
    else
        printf "  %-15s : %s (expected %s from builder inputs). FAIL\n" "Builder Inputs" "${builder_inputs:-missing}" "$expected_builder_inputs"
    fi
    echo "Local builder base image check failed. Run make prepare."
}

cmd_check() {
    require_common

    local docker_info image_id inspect_err inspect_id inspect_status
    if ! docker_info="$(docker info 2>&1)"; then
        echo ">> Builder Version and Base Image Check: [FAIL]"
        printf "  %-15s : unavailable\n" "Docker"
        echo "Local builder base image check failed: Docker daemon is not reachable."
        printf '%s\n' "$docker_info" | sed -n '1,10p' | sed 's/^/  Docker Error             /'
        exit 1
    fi

    image_id="$(docker images --no-trunc --format '{{.Repository}}:{{.Tag}} {{.ID}}' | awk -v image="$image" '$1 == image { print $2; exit }')"
    if [ -z "$image_id" ]; then
        echo ">> Builder Version and Base Image Check: [FAIL]"
        printf "  %-15s : %s (missing)\n" "Base Image" "$image"
        echo "Local builder base image check failed: run make prepare before make build-plugin."
        exit 1
    fi

    inspect_err="$(mktemp "${TMPDIR:-/tmp}/builder-image-inspect.XXXXXX")"
    set +e
    inspect_id="$(docker image inspect "$image_id" --format '{{.Id}}' 2>"$inspect_err")"
    inspect_status=$?
    set -e
    if [ "$inspect_status" -ne 0 ]; then
        echo ">> Builder Version and Base Image Check: [FAIL]"
        if grep -qi "No such image" "$inspect_err"; then
            printf "  %-15s : %s (listed, unusable)\n" "Base Image" "$image"
            echo "Local builder base image check failed: stale Docker image ID; run make prepare."
        else
            printf "  %-15s : %s (inspect failed)\n" "Base Image" "$image"
            echo "Local builder base image check failed: docker image inspect failed."
            sed 's/^/  Docker Error             /' "$inspect_err"
        fi
        rm -f "$inspect_err"
        exit 1
    fi
    rm -f "$inspect_err"

    local api framework image_go go_mod builder_inputs expected_go_mod expected_builder_inputs failed
    api="$(docker image inspect "$image_id" --format '{{ index .Config.Labels "asn.service_api" }}')"
    framework="$(docker image inspect "$image_id" --format '{{ index .Config.Labels "asn.framework" }}')"
    image_go="$(docker image inspect "$image_id" --format '{{ index .Config.Labels "asn.go" }}')"
    go_mod="$(docker image inspect "$image_id" --format '{{ index .Config.Labels "asn.service_go_mod" }}')"
    builder_inputs="$(docker image inspect "$image_id" --format '{{ index .Config.Labels "asn.builder_inputs" }}')"
    expected_go_mod="$(service_go_mod_hash)"
    expected_builder_inputs="$(builder_input_hash)"

    failed=0
    [ "$api" = "$api_version" ] || failed=1
    [ "$framework" = "$framework_version" ] || failed=1
    [ "$image_go" = "$go_version" ] || failed=1
    [ "$go_mod" = "$expected_go_mod" ] || failed=1
    [ "$builder_inputs" = "$expected_builder_inputs" ] || failed=1
    if [ "$failed" -ne 0 ]; then
        print_check_failure "$inspect_id" "$api" "$framework" "$image_go" "$go_mod" "$builder_inputs" "$expected_go_mod" "$expected_builder_inputs"
        exit 1
    fi

    local cache_probe cache_probe_status
    set +e
    cache_probe="$(docker run --rm --platform "$platform" \
        --mount "type=bind,source=$context_dir,target=$workdir,readonly" \
        --workdir "$workdir" \
        --env "SERVICE_GO_CACHE_PACKAGES=$cache_packages" \
        "$image" sh -lc 'GOPROXY=off GOSUMDB=off go list -mod=readonly -deps $SERVICE_GO_CACHE_PACKAGES >/dev/null' 2>&1)"
    cache_probe_status=$?
    set -e
    if [ "$cache_probe_status" -ne 0 ]; then
        echo ">> Builder Version and Base Image Check: [FAIL]"
        printf "  %-15s : %s\n" "Base Image" "$image"
        printf "  %-15s : %s\n" "Packages" "$cache_packages"
        echo "Local builder base image check failed: warmed Go module cache does not satisfy offline package resolution."
        printf '%s\n' "$cache_probe" | sed -n '1,20p' | sed 's/^/  Go Error                 /'
        echo "Run make prepare after confirming private module access."
        exit 1
    fi

    echo ">> Builder Version and Base Image Check: [PASS]"
    printf "  %15s : %s\n" "Base Image" "$image"
    printf "  %15s : %s\n" "ID" "${inspect_id#sha256:}"
    printf "  %15s : %s (expected as ASN_SERVICE_API_VERSION).\n" "API Version" "$api"
    printf "  %15s : %s (expected from service-utils)\n" "ASN Version" "$framework"
    printf "  %15s : %s (expected from service-utils)\n" "Go Version" "$image_go"
    printf "  %15s : %s (expected from service go.mod).\n" "Service go.mod" "$go_mod"
    printf "  %15s : %s (expected from builder inputs).\n" "Builder Inputs" "$builder_inputs"
    printf "  %15s : %s\n" "Offline Cache" "PASS"
}

case "$command_name" in
    prepare) cmd_prepare ;;
    check) cmd_check ;;
    hashes) cmd_hashes ;;
    --help|-h|help) usage ;;
    *) echo "builder_base_image ERROR: unsupported command: $command_name" >&2; usage >&2; exit 2 ;;
esac
