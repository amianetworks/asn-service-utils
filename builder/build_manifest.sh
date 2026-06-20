#!/usr/bin/env bash
# Own the local artifact build identity and build/Manifest.yaml contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

command_name="${1:-}"
[ -n "$command_name" ] || {
    echo "build_manifest ERROR: command is required" >&2
    exit 2
}
shift

build_mode="${BUILD_MODE:-dev}"
version="${VERSION:-}"
maintainer_build="${BUILD:-}"
dev_start="${BUILD_DEV:-100}"
dev_file="$PROJECT_ROOT/.DEV_BUILD_FILE"
dev_lock_dir="$PROJECT_ROOT/.DEV_BUILD_FILE.lock"
manifest_file="$PROJECT_ROOT/build/Manifest.yaml"
version_build="${VERSION_BUILD:-}"
lane=""
docs_dir="$PROJECT_ROOT/build/docs"
debian_dir="$PROJECT_ROOT/build/debian"
debian_packages="${DEBIAN_PACKAGES:-}"
debian_required_artifacts="${DEBIAN_REQUIRED_ARTIFACTS:-}"
docker_images="${DOCKER_IMAGES:-}"
artifact_matrix_entries="${BUILD_MANIFEST_ARTIFACT_MATRIX:-}"
manifest_schema="${BUILD_MANIFEST_SCHEMA:-artifact.build.manifest.v1}"
source_key="${BUILD_MANIFEST_SOURCE_KEY:-source_commit}"
source_label="${BUILD_MANIFEST_SOURCE_LABEL:-service}"
plugin_required_artifacts="${SERVICE_PLUGIN_REQUIRED_ARTIFACTS:-}"
plugin_required_globs="${SERVICE_PLUGIN_REQUIRED_GLOBS:-}"
plugin_optional_artifacts="${SERVICE_PLUGIN_OPTIONAL_ARTIFACTS:-}"
plugin_optional_globs="${SERVICE_PLUGIN_OPTIONAL_GLOBS:-}"
docs_required_artifacts="${SERVICE_DOCS_REQUIRED_ARTIFACTS:-}"
docs_version_file="${SERVICE_DOCS_VERSION_FILE:-}"
docs_version_key="${SERVICE_DOCS_VERSION_KEY:-version_build}"
service_utils_dir="${SERVICE_UTILS_DIR:-service-utils}"
asn_service_api_version="${ASN_SERVICE_API_VERSION:-}"
asn_runtime_version="${ASN_RUNTIME_VERSION:-}"
go_version="${GO_VERSION:-}"
asn_builder_go_version="${ASN_BUILDER_GO_VERSION:-}"
service_utils_ref=""
service_name=""
project_id="${PROJECT_ID:-}"
manifest_commit_lane="docker"

usage() {
    cat <<'EOF'
usage: service-utils/builder/build_manifest.sh COMMAND [options]

Commands:
  next-plugin-version   Print the version_build that build-plugin should stamp.
  reserve-plugin-version
                        Reserve and print the DEV version_build for build-plugin.
  clear-reserved-plugin-version
                        Clear a matching DEV build reservation after failed build.
  commit-plugin         Validate plugin artifacts, then write build/Manifest.yaml.
  commit-lane           Refresh build/Manifest.yaml after docs/debian/docker succeeds.
  require-lane          Require manifest mode, version, and lane PASS.
  artifacts             Print manifest artifact paths for a committed lane.
  active-version-build  Print current manifest version_build when it matches mode/version.
  value                 Print a manifest value, such as version_build.
  check-build           Print the active and next local build identity.
  check-version         Print the local version identity.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode|--build-mode) shift; build_mode="${1:-}" ;;
        --version) shift; version="${1:-}" ;;
        --build) shift; maintainer_build="${1:-}" ;;
        --dev-start) shift; dev_start="${1:-}" ;;
        --dev-file) shift; dev_file="${1:-}" ;;
        --manifest) shift; manifest_file="${1:-}" ;;
        --version-build) shift; version_build="${1:-}" ;;
        --lane) shift; lane="${1:-}" ;;
        --docs-dir) shift; docs_dir="${1:-}" ;;
        --debian-dir) shift; debian_dir="${1:-}" ;;
        --debian-packages) shift; debian_packages="${1:-}" ;;
        --debian-required-artifacts) shift; debian_required_artifacts="${1:-}" ;;
        --docker-images) shift; docker_images="${1:-}" ;;
        --artifact-matrix) shift; artifact_matrix_entries="${1:-}" ;;
        --schema) shift; manifest_schema="${1:-}" ;;
        --source-key) shift; source_key="${1:-}" ;;
        --source-label) shift; source_label="${1:-}" ;;
        --project) shift; project_id="${1:-}" ;;
        --plugin-required-artifacts) shift; plugin_required_artifacts="${1:-}" ;;
        --plugin-required-globs) shift; plugin_required_globs="${1:-}" ;;
        --plugin-optional-artifacts) shift; plugin_optional_artifacts="${1:-}" ;;
        --plugin-optional-globs) shift; plugin_optional_globs="${1:-}" ;;
        --docs-required-artifacts) shift; docs_required_artifacts="${1:-}" ;;
        --docs-version-file) shift; docs_version_file="${1:-}" ;;
        --docs-version-key) shift; docs_version_key="${1:-}" ;;
        --service-utils-dir) shift; service_utils_dir="${1:-}" ;;
        --service) shift; service_name="${1:-}" ;;
        --asn-service-api-version) shift; asn_service_api_version="${1:-}" ;;
        --asn-runtime-version) shift; asn_runtime_version="${1:-}" ;;
        --go-version) shift; go_version="${1:-}" ;;
        --builder-go-version) shift; asn_builder_go_version="${1:-}" ;;
        --service-utils-ref) shift; service_utils_ref="${1:-}" ;;
        --key) shift; key_path="${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "build_manifest ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

project_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        ./*) printf '%s/%s\n' "$PROJECT_ROOT" "${1#./}" ;;
        *) printf '%s/%s\n' "$PROJECT_ROOT" "$1" ;;
    esac
}

dev_file="$(project_path "$dev_file")"
dev_lock_dir="$(project_path "$dev_lock_dir")"
manifest_file="$(project_path "$manifest_file")"
docs_dir="$(project_path "$docs_dir")"
debian_dir="$(project_path "$debian_dir")"
service_utils_dir="$(project_path "$service_utils_dir")"

mode_lower="$(printf '%s' "$build_mode" | tr '[:upper:]' '[:lower:]')"
case "$mode_lower" in
    dev|pro) ;;
    *) echo "build_manifest ERROR: unsupported BUILD_MODE: $build_mode" >&2; exit 2 ;;
esac

relpath() {
    local path="$1"
    case "$path" in
        "$PROJECT_ROOT") printf '.\n' ;;
        "$PROJECT_ROOT"/*) printf '%s\n' "${path#$PROJECT_ROOT/}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

yaml_value() {
    local file="$1"
    local key_path="$2"
    [ -s "$file" ] || return 1
    awk -v key_path="$key_path" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            return value
        }
        BEGIN { split(key_path, want, "."); depth = 0 }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            match($0, /^[ ]*/)
            indent = RLENGTH
            key = $0
            sub(/^[ ]*/, "", key)
            sub(/:.*/, "", key)
            value = $0
            sub(/^[ ]*[^:]*:[ ]*/, "", value)
            level = int(indent / 2) + 1
            stack[level] = key
            for (i = level + 1; i <= 10; i++) delete stack[i]
            if (key == "-" || index($0, ":") == 0) next
            path = stack[1]
            for (i = 2; i <= level; i++) {
                if (stack[i] != "") path = path "." stack[i]
            }
            if (path == key_path && value != "") {
                print trim(value)
                found = 1
                exit
            }
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

replace_placeholders() {
    local value="$1"
    value="${value//@SERVICE@/$service_name}"
    value="${value//@PROJECT@/$project_id}"
    value="${value//@BUILD_MODE@/$mode_lower}"
    value="${value//@MANIFEST@/$(relpath "$manifest_file")}"
    value="${value//@BUILT_VERSION@/$display_built_version}"
    value="${value//@NEXT_BUILD@/$display_next_build}"
    value="${value//@VERSION_BUILD@/$display_version_build}"
    value="${value//@ASN_SERVICE_API_VERSION@/$asn_service_api_version}"
    value="${value//@ASN_RUNTIME_VERSION@/$asn_runtime_version}"
    value="${value//@GO_VERSION@/${go_version:-$asn_builder_go_version}}"
    value="${value//@ASN_BUILDER_GO_VERSION@/$asn_builder_go_version}"
    printf '%s\n' "$value"
}

render_rows() {
    local rows="$1"
    local line label value
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|"#"*) continue ;;
        esac
        label="${line%%=*}"
        value="${line#*=}"
        if [ "$label" = "$line" ]; then
            continue
        fi
        label="$(printf '%s' "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        value="$(replace_placeholders "$value")"
        printf "  %15s : %s\n" "$label" "$value"
    done <<EOF
$rows
EOF
}

set_check_display_values() {
    active=""
    manifest_mode=""
    manifest_check_error=""
    if [ -s "$manifest_file" ]; then
        manifest_mode="$(yaml_value "$manifest_file" build_mode || true)"
        if active="$(assert_manifest_identity 2>&1)"; then
            :
        else
            manifest_check_error="$active"
            active="$(yaml_value "$manifest_file" version_build || true)"
        fi
    fi
    next="$(next_plugin_version)"
    active_matches=no
    if [ -z "$manifest_check_error" ] && [ -n "$active" ] && [ "$manifest_mode" = "$mode_lower" ]; then
        case "$active" in
            "$version".*) active_matches=yes ;;
        esac
        if [ "$mode_lower" = "pro" ] && [ "$active" != "$version.$maintainer_build" ]; then
            active_matches=no
        fi
    fi
    display_built_version="<none>"
    if [ "$active_matches" = "yes" ]; then
        display_built_version="$active"
    elif [ -n "$manifest_check_error" ]; then
        display_built_version="<stale>"
    fi
    display_next_build="$next"
    display_version_build="$next"
    if [ -n "$manifest_check_error" ]; then
        display_version_build="<stale>"
    elif [ -n "$active" ] && [ "$manifest_mode" = "$mode_lower" ]; then
        display_version_build="$active"
    fi
}

has_glob() {
    local pattern="$1"
    local matches
    matches="$(compgen -G "$pattern" || true)"
    [ -n "$matches" ]
}

git_ref_or_unknown() {
    local repo="$1"
    local label="$2"
    local ref
    if ref="$(git -C "$repo" rev-parse --short HEAD 2>&1)"; then
        printf '%s\n' "$ref"
    else
        printf 'build_manifest WARN: could not resolve %s git ref: %s\n' "$label" "$ref" >&2
        printf 'unknown\n'
    fi
}

have_command() {
    local name="$1"
    local found
    found="$(command -v "$name" 2>&1)" || return 1
    [ -n "$found" ]
}

lane_rank() {
    case "$1" in
        plugin) printf '1\n' ;;
        docs) printf '2\n' ;;
        debian) printf '3\n' ;;
        docker) printf '4\n' ;;
        *) echo "build_manifest ERROR: unsupported lane: $1" >&2; exit 2 ;;
    esac
}

lane_is_committed() {
    local requested="$1"
    local requested_rank commit_rank
    requested_rank="$(lane_rank "$requested")"
    commit_rank="$(lane_rank "$manifest_commit_lane")"
    [ "$requested_rank" -le "$commit_rank" ]
}

dev_build_file_value() {
    local key="$1"
    if [ -s "$dev_file" ]; then
        awk -F= -v key="$key" '$1 == key { print $2; found=1 } END { exit found ? 0 : 1 }' "$dev_file"
    fi
}

normalize_dev_build_number() {
    local value="$1"
    case "$value" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$value"
}

last_dev_build() {
    local value reserved
    value="$(dev_build_file_value LAST_DEV_BUILD || true)"
    value="$(normalize_dev_build_number "$value" || printf '%s\n' "$dev_start")"
    reserved="$(dev_build_file_value RESERVED_DEV_BUILD || true)"
    if reserved="$(normalize_dev_build_number "$reserved")"; then
        if [ "$reserved" -gt "$value" ]; then
            value="$reserved"
        fi
    fi
    if [ "$value" -lt "$dev_start" ]; then
        value="$dev_start"
    fi
    printf '%s\n' "$value"
}

release_dev_build_lock() {
    [ "$mode_lower" = "dev" ] || return 0
    local release_error
    if ! release_error="$(rmdir "$dev_lock_dir" 2>&1)"; then
        : "$release_error"
    fi
}

acquire_dev_build_lock() {
    [ "$mode_lower" = "dev" ] || return 0
    local waited=0
    local lock_error=""
    while ! lock_error="$(mkdir "$dev_lock_dir" 2>&1)"; do
        if [ "$waited" -ge 60 ]; then
            echo "build_manifest ERROR: timed out waiting for DEV build lock: $(relpath "$dev_lock_dir")" >&2
            [ -n "$lock_error" ] && printf '%s\n' "$lock_error" >&2
            exit 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    trap release_dev_build_lock EXIT HUP INT TERM
}

next_plugin_version() {
    [ -n "$version" ] || { echo "build_manifest ERROR: --version is required" >&2; exit 2; }
    case "$mode_lower" in
        dev)
            local last candidate
            last="$(last_dev_build)"
            candidate=$((last + 1))
            printf '%s.%s\n' "$version" "$candidate"
            ;;
        pro)
            [ -n "$maintainer_build" ] || { echo "build_manifest ERROR: --build is required for pro mode" >&2; exit 2; }
            printf '%s.%s\n' "$version" "$maintainer_build"
            ;;
    esac
}

write_dev_build_file() {
    local last="$1"
    local reserved="${2:-}"
    local tmp

    mkdir -p "$(dirname "$dev_file")"
    tmp="$(mktemp "${TMPDIR:-/tmp}/service-dev-build.XXXXXX")"
    {
        printf 'LAST_DEV_BUILD=%s\n' "$last"
        if [ -n "$reserved" ]; then
            printf 'RESERVED_DEV_BUILD=%s\n' "$reserved"
        fi
    } > "$tmp"
    mv "$tmp" "$dev_file"
}

reserve_plugin_version() {
    if [ "$mode_lower" != "dev" ]; then
        next_plugin_version
        return
    fi

    acquire_dev_build_lock
    local reserved build_number
    reserved="$(next_plugin_version)"
    build_number="$(build_number_from_version "$reserved")"
    case "$build_number" in
        ''|*[!0-9]*) echo "build_manifest ERROR: invalid DEV version_build: $reserved" >&2; exit 1 ;;
    esac
    local current_last
    current_last="$(dev_build_file_value LAST_DEV_BUILD || true)"
    current_last="$(normalize_dev_build_number "$current_last" || printf '%s\n' "$dev_start")"
    write_dev_build_file "$current_last" "$build_number"
    printf '%s\n' "$reserved"
}

build_number_from_version() {
    local value="$1"
    printf '%s\n' "${value##*.}"
}

assert_manifest_identity() {
    [ -s "$manifest_file" ] || {
        echo "build_manifest ERROR: missing build manifest: $(relpath "$manifest_file")" >&2
        echo "Run 'make build-plugin' or 'make build' first." >&2
        exit 1
    }
    local manifest_mode manifest_version manifest_source current_source expected
    manifest_mode="$(yaml_value "$manifest_file" build_mode || true)"
    manifest_version="$(yaml_value "$manifest_file" version_build || true)"
    [ "$manifest_mode" = "$mode_lower" ] || {
        echo "build_manifest ERROR: manifest build_mode is '$manifest_mode', expected '$mode_lower': $(relpath "$manifest_file")" >&2
        exit 1
    }
    [ -n "$manifest_version" ] || {
        echo "build_manifest ERROR: manifest is missing version_build: $(relpath "$manifest_file")" >&2
        exit 1
    }
    [ -n "$version" ] || { echo "build_manifest ERROR: --version is required for manifest validation" >&2; exit 2; }
    case "$manifest_version" in
        "$version".*) ;;
        *)
            echo "build_manifest ERROR: manifest version_build is '$manifest_version', expected current VERSION '$version.*'." >&2
            exit 1
            ;;
    esac
    if [ "$mode_lower" = "pro" ]; then
        [ -n "$maintainer_build" ] || { echo "build_manifest ERROR: --build is required for pro manifest validation" >&2; exit 2; }
        expected="$version.$maintainer_build"
        [ "$manifest_version" = "$expected" ] || {
            echo "build_manifest ERROR: PRO manifest version_build is '$manifest_version', expected '$expected'." >&2
            exit 1
        }
    fi
    manifest_source="$(yaml_value "$manifest_file" "source.$source_key" || true)"
    current_source="$(git_ref_or_unknown "$PROJECT_ROOT" "$source_label")"
    if [ -n "$manifest_source" ] && [ "$manifest_source" != "unknown" ] && [ "$current_source" != "unknown" ] && [ "$manifest_source" != "$current_source" ]; then
        echo "build_manifest ERROR: manifest source $source_key is '$manifest_source', expected current '$current_source': $(relpath "$manifest_file")" >&2
        echo "Run 'make build-plugin' before reusing downstream artifacts." >&2
        exit 1
    fi
    printf '%s\n' "$manifest_version"
}

active_version_build() {
    [ -s "$manifest_file" ] || return 0
    local manifest_mode manifest_version
    manifest_mode="$(yaml_value "$manifest_file" build_mode || true)"
    manifest_version="$(yaml_value "$manifest_file" version_build || true)"
    [ "$manifest_mode" = "$mode_lower" ] || return 0
    [ -n "$manifest_version" ] || return 0
    if [ -n "$version" ]; then
        case "$manifest_version" in
            "$version".*) ;;
            *) return 0 ;;
        esac
    fi
    if [ "$mode_lower" = "pro" ] && [ -n "$version" ] && [ -n "$maintainer_build" ]; then
        [ "$manifest_version" = "$version.$maintainer_build" ] || return 0
    fi
    printf '%s\n' "$manifest_version"
}

add_existing_file() {
    local out_file="$1"
    local path="$2"
    [ -f "$path" ] || return 1
    printf '%s\n' "$(relpath "$path")" >> "$out_file"
}

expand_manifest_tokens() {
    local value="$1"
    value="${value//@VERSION_BUILD@/$version_build}"
    printf '%s\n' "$value"
}

collect_configured_artifacts() {
    local out_file="$1"
    local files="$2"
    local globs="$3"
    local file pattern matches match
    for file in $files; do
        file="$(project_path "$(expand_manifest_tokens "$file")")"
        add_existing_file "$out_file" "$file" || true
    done
    for pattern in $globs; do
        pattern="$(project_path "$(expand_manifest_tokens "$pattern")")"
        matches="$(compgen -G "$pattern" || true)"
        [ -n "$matches" ] || continue
        while IFS= read -r match; do
            [ -n "$match" ] || continue
            add_existing_file "$out_file" "$match" || true
        done <<< "$matches"
    done
}

configured_files_status() {
    local files="$1"
    local file
    for file in $files; do
        file="$(project_path "$(expand_manifest_tokens "$file")")"
        [ -f "$file" ] || { printf 'MISSING\n'; return; }
    done
    printf 'PASS\n'
}

configured_globs_status() {
    local globs="$1"
    local pattern
    for pattern in $globs; do
        pattern="$(project_path "$(expand_manifest_tokens "$pattern")")"
        has_glob "$pattern" || { printf 'MISSING\n'; return; }
    done
    printf 'PASS\n'
}

collect_plugin_artifacts() {
    local out_file="$1"
    : > "$out_file"
    collect_configured_artifacts "$out_file" "$plugin_required_artifacts $plugin_optional_artifacts" "$plugin_required_globs $plugin_optional_globs"
    sort -u "$out_file" -o "$out_file"
}

plugin_lane_status() {
    local artifacts="$1"
    collect_plugin_artifacts "$artifacts"
    [ -n "$plugin_required_artifacts$plugin_required_globs" ] || { printf 'MISSING\n'; return; }
    [ "$(configured_files_status "$plugin_required_artifacts")" = "PASS" ] || { printf 'MISSING\n'; return; }
    [ "$(configured_globs_status "$plugin_required_globs")" = "PASS" ] || { printf 'MISSING\n'; return; }
    printf 'PASS\n'
}

collect_docs_artifacts() {
    local out_file="$1"
    : > "$out_file"
    collect_configured_artifacts "$out_file" "$docs_required_artifacts" ""
    sort -u "$out_file" -o "$out_file"
}

docs_lane_status() {
    local artifacts="$1"
    local docs_version docs_version_path
    collect_docs_artifacts "$artifacts"
    [ -n "$docs_required_artifacts" ] || { printf 'MISSING\n'; return; }
    [ "$(configured_files_status "$docs_required_artifacts")" = "PASS" ] || { printf 'MISSING\n'; return; }
    [ -n "$docs_version_file" ] || { printf 'MISSING\n'; return; }
    docs_version_path="$(project_path "$(expand_manifest_tokens "$docs_version_file")")"
    docs_version="$(yaml_value "$docs_version_path" "$docs_version_key" || true)"
    [ "$docs_version" = "$version_build" ] || { printf 'MISSING\n'; return; }
    printf 'PASS\n'
}

collect_debian_artifacts() {
    local out_file="$1"
    : > "$out_file"
    if [ -n "$debian_required_artifacts" ]; then
        collect_configured_artifacts "$out_file" "$debian_required_artifacts" ""
        sort -u "$out_file" -o "$out_file"
        return
    fi
    local package file
    for package in $debian_packages; do
        file="$debian_dir/${package}_${version_build}_amd64.deb"
        add_existing_file "$out_file" "$file" || true
    done
    sort -u "$out_file" -o "$out_file"
}

debian_lane_status() {
    local artifacts="$1"
    collect_debian_artifacts "$artifacts"
    if [ -n "$debian_required_artifacts" ]; then
        [ "$(configured_files_status "$debian_required_artifacts")" = "PASS" ] || { printf 'MISSING\n'; return; }
        printf 'PASS\n'
        return
    fi
    local package file
    [ -n "$debian_packages" ] || { printf 'MISSING\n'; return; }
    for package in $debian_packages; do
        file="$debian_dir/${package}_${version_build}_amd64.deb"
        [ -f "$file" ] || { printf 'MISSING\n'; return; }
    done
    printf 'PASS\n'
}

collect_docker_artifacts() {
    local out_file="$1"
    : > "$out_file"
    have_command docker || return 0
    local image ref inspect_output
    for image in $docker_images; do
        ref="$image:$version_build"
        if inspect_output="$(docker image inspect "$ref" 2>&1)"; then
            printf '%s\n' "$ref" >> "$out_file"
        fi
        : "${inspect_output:-}"
    done
    sort -u "$out_file" -o "$out_file"
}

docker_lane_status() {
    local artifacts="$1"
    collect_docker_artifacts "$artifacts"
    [ -n "$docker_images" ] || { printf 'MISSING\n'; return; }
    have_command docker || { printf 'MISSING\n'; return; }
    local image inspect_output
    for image in $docker_images; do
        inspect_output="$(docker image inspect "$image:$version_build" 2>&1)" || {
            : "$inspect_output"
            printf 'MISSING\n'
            return
        }
    done
    printf 'PASS\n'
}

write_artifact_block() {
    local out="$1"
    local artifacts="$2"
    local indent="$3"
    if [ -s "$artifacts" ]; then
        printf '%sartifacts:\n' "$indent" >> "$out"
        while IFS= read -r path; do
            printf '%s  - path: %s\n' "$indent" "$(yaml_quote "$path")" >> "$out"
        done < "$artifacts"
    else
        printf '%sartifacts: []\n' "$indent" >> "$out"
    fi
}

write_manifest() {
    [ -n "$version_build" ] || { echo "build_manifest ERROR: --version-build is required" >&2; exit 2; }
    mkdir -p "$(dirname "$manifest_file")"
    local tmpdir out generated_at source_commit plugin_artifacts docs_artifacts debian_artifacts docker_artifacts
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/artifact-build-manifest.XXXXXX")"
    out="$tmpdir/Manifest.yaml"
    plugin_artifacts="$tmpdir/plugin.txt"
    docs_artifacts="$tmpdir/docs.txt"
    debian_artifacts="$tmpdir/debian.txt"
    docker_artifacts="$tmpdir/docker.txt"
    generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    source_commit="$(git_ref_or_unknown "$PROJECT_ROOT" "$source_label")"
    [ -n "$service_utils_ref" ] || service_utils_ref="$(git_ref_or_unknown "$service_utils_dir" "service-utils")"
    [ -n "$asn_service_api_version" ] || asn_service_api_version="$(yaml_value "$manifest_file" source.asn_service_api_version || true)"
    [ -n "$asn_runtime_version" ] || asn_runtime_version="$(yaml_value "$manifest_file" source.asn_runtime_version || true)"
    [ -n "$go_version" ] || go_version="$(yaml_value "$manifest_file" source.go_version || true)"
    [ -n "$asn_builder_go_version" ] || asn_builder_go_version="$(yaml_value "$manifest_file" source.asn_builder_go_version || true)"

    plugin_status="$(plugin_lane_status "$plugin_artifacts")"
    if lane_is_committed docs; then
        docs_status="$(docs_lane_status "$docs_artifacts")"
    else
        : > "$docs_artifacts"
        docs_status="MISSING"
    fi
    if lane_is_committed debian; then
        debian_status="$(debian_lane_status "$debian_artifacts")"
    else
        : > "$debian_artifacts"
        debian_status="MISSING"
    fi
    if lane_is_committed docker; then
        docker_status="$(docker_lane_status "$docker_artifacts")"
    else
        : > "$docker_artifacts"
        docker_status="MISSING"
    fi

    {
        printf 'schema: %s\n' "$(yaml_quote "$manifest_schema")"
        printf 'build_mode: %s\n' "$(yaml_quote "$mode_lower")"
        printf 'version_build: %s\n' "$(yaml_quote "$version_build")"
        printf 'generated_at: %s\n' "$(yaml_quote "$generated_at")"
        printf 'source:\n'
        printf '  %s: %s\n' "$source_key" "$(yaml_quote "$source_commit")"
        printf '  asn_service_api_version: %s\n' "$(yaml_quote "$asn_service_api_version")"
        printf '  asn_runtime_version: %s\n' "$(yaml_quote "$asn_runtime_version")"
        printf '  go_version: %s\n' "$(yaml_quote "$go_version")"
        printf '  asn_builder_go_version: %s\n' "$(yaml_quote "$asn_builder_go_version")"
        printf '  service_utils_ref: %s\n' "$(yaml_quote "$service_utils_ref")"
        printf 'lanes:\n'
        printf '  plugin:\n'
        printf '    status: %s\n' "$(yaml_quote "$plugin_status")"
    } > "$out"
    write_artifact_block "$out" "$plugin_artifacts" "    "
    {
        printf '  docs:\n'
        printf '    status: %s\n' "$(yaml_quote "$docs_status")"
    } >> "$out"
    write_artifact_block "$out" "$docs_artifacts" "    "
    {
        printf '  debian:\n'
        printf '    status: %s\n' "$(yaml_quote "$debian_status")"
    } >> "$out"
    write_artifact_block "$out" "$debian_artifacts" "    "
    {
        printf '  docker:\n'
        printf '    status: %s\n' "$(yaml_quote "$docker_status")"
    } >> "$out"
    write_artifact_block "$out" "$docker_artifacts" "    "

    mv "$out" "$manifest_file"
    rm -rf "$tmpdir"
}

lane_status_from_manifest() {
    local lane_name="$1"
    yaml_value "$manifest_file" "lanes.$lane_name.status" || true
}

lane_artifacts_from_manifest() {
    local lane_name="$1"
    [ -s "$manifest_file" ] || return 0
    awk -v lane_name="$lane_name" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        function unquote(value) {
            value = trim(value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
                gsub(/\\"/, "\"", value)
                gsub(/\\\\/, "\\", value)
            }
            return value
        }
        /^[^[:space:]][^:]*:/ {
            top = $0
            sub(/:.*/, "", top)
            in_lanes = (top == "lanes")
            in_lane = 0
            in_artifacts = 0
            next
        }
        in_lanes && /^  [^[:space:]][^:]*:/ {
            lane = $0
            sub(/^  /, "", lane)
            sub(/:.*/, "", lane)
            in_lane = (lane == lane_name)
            in_artifacts = 0
            next
        }
        in_lanes && in_lane && /^    artifacts:/ {
            in_artifacts = 1
            next
        }
        in_lanes && in_lane && in_artifacts && /^      - path:/ {
            value = $0
            sub(/^      - path:[[:space:]]*/, "", value)
            print unquote(value)
            next
        }
        in_lanes && in_lane && in_artifacts && /^    [^[:space:]][^:]*:/ {
            in_artifacts = 0
        }
    ' "$manifest_file"
}

require_lane() {
    [ -n "$lane" ] || { echo "build_manifest ERROR: --lane is required" >&2; exit 2; }
    lane_rank "$lane" >/dev/null
    version_build="$(assert_manifest_identity)"
    local status
    status="$(lane_status_from_manifest "$lane")"
    [ "$status" = "PASS" ] || {
        echo "build_manifest ERROR: manifest lane '$lane' is '$status', expected PASS: $(relpath "$manifest_file")" >&2
        exit 1
    }
    printf '%s\n' "$version_build"
}

lane_artifacts() {
    [ -n "$lane" ] || { echo "build_manifest ERROR: --lane is required" >&2; exit 2; }
    require_lane >/dev/null
    lane_artifacts_from_manifest "$lane"
}

commit_dev_build_file() {
    [ "$mode_lower" = "dev" ] || return 0
    local build_number current_last current_reserved keep_reserved new_last
    build_number="$(build_number_from_version "$version_build")"
    case "$build_number" in
        ''|*[!0-9]*) echo "build_manifest ERROR: invalid DEV version_build: $version_build" >&2; exit 1 ;;
    esac
    acquire_dev_build_lock
    current_last="$(dev_build_file_value LAST_DEV_BUILD || true)"
    current_last="$(normalize_dev_build_number "$current_last" || printf '0\n')"
    current_reserved="$(dev_build_file_value RESERVED_DEV_BUILD || true)"
    current_reserved="$(normalize_dev_build_number "$current_reserved" || true)"
    new_last="$build_number"
    if [ "$current_last" -gt "$new_last" ]; then
        new_last="$current_last"
    fi
    keep_reserved=""
    if [ -n "$current_reserved" ] && [ "$current_reserved" -gt "$new_last" ]; then
        keep_reserved="$current_reserved"
    fi
    write_dev_build_file "$new_last" "$keep_reserved"
}

clear_reserved_plugin_version() {
    [ "$mode_lower" = "dev" ] || return 0
    [ -n "$version_build" ] || { echo "build_manifest ERROR: --version-build is required" >&2; exit 2; }
    local build_number current_last current_reserved
    build_number="$(build_number_from_version "$version_build")"
    case "$build_number" in
        ''|*[!0-9]*) echo "build_manifest ERROR: invalid DEV version_build: $version_build" >&2; exit 1 ;;
    esac
    acquire_dev_build_lock
    current_last="$(dev_build_file_value LAST_DEV_BUILD || true)"
    current_last="$(normalize_dev_build_number "$current_last" || printf '%s\n' "$dev_start")"
    current_reserved="$(dev_build_file_value RESERVED_DEV_BUILD || true)"
    current_reserved="$(normalize_dev_build_number "$current_reserved" || true)"
    if [ "$current_reserved" = "$build_number" ]; then
        write_dev_build_file "$current_last"
    fi
}

case "$command_name" in
    next-plugin-version)
        next_plugin_version
        ;;
    reserve-plugin-version)
        reserve_plugin_version
        ;;
    clear-reserved-plugin-version)
        clear_reserved_plugin_version
        ;;
    commit-plugin)
        [ -n "$version_build" ] || version_build="$(next_plugin_version)"
        tmp_check="$(mktemp "${TMPDIR:-/tmp}/service-plugin-artifacts.XXXXXX")"
        plugin_status="$(plugin_lane_status "$tmp_check")"
        rm -f "$tmp_check"
        [ "$plugin_status" = "PASS" ] || {
            echo "build_manifest ERROR: plugin artifacts are incomplete; not updating $(relpath "$manifest_file") or $(relpath "$dev_file")." >&2
            exit 1
        }
        manifest_commit_lane="plugin"
        write_manifest
        commit_dev_build_file
        printf '%s\n' "$version_build"
        ;;
    commit-lane)
        [ -n "$lane" ] || { echo "build_manifest ERROR: --lane is required" >&2; exit 2; }
        [ -n "$version_build" ] || version_build="$(assert_manifest_identity)"
        manifest_commit_lane="$lane"
        write_manifest
        require_lane_output="$(require_lane)"
        : "$require_lane_output"
        printf '%s\n' "$version_build"
        ;;
    require-lane)
        require_lane
        ;;
    artifacts)
        lane_artifacts
        ;;
    active-version-build)
        active_version_build
        ;;
    value)
        key_path="${key_path:-}"
        [ -n "$key_path" ] || { echo "build_manifest ERROR: value requires --key" >&2; exit 2; }
        yaml_value "$manifest_file" "$key_path"
        ;;
    check-build)
        set_check_display_values
        rows="${CHECK_BUILD_ROWS:-}"
        if [ -z "$rows" ]; then
            rows="$(cat <<'EOF'
Service=@SERVICE@
Build Mode=@BUILD_MODE@
Manifest=@MANIFEST@
Built Version=@BUILT_VERSION@
Next Build=@NEXT_BUILD@
EOF
)"
        fi
        if [ -n "${CHECK_BUILD_EXTRA_ROWS:-}" ]; then
            rows="${rows}"$'\n'"${CHECK_BUILD_EXTRA_ROWS}"
        fi
        printf ">> Build Identity\n"
        render_rows "$rows"
        if [ -n "$manifest_check_error" ]; then
            printf '\n'
            printf '%s\n' "$manifest_check_error" | sed 's/^/  Manifest: /'
            exit 1
        fi
        printf '\n'
        ;;
    check-version)
        set_check_display_values
        rows="${CHECK_VERSION_ROWS:-}"
        if [ -z "$rows" ]; then
            rows="$(cat <<'EOF'
Service=@SERVICE@
Version Build=@VERSION_BUILD@
ASN Service API=@ASN_SERVICE_API_VERSION@
ASN Runtime=@ASN_RUNTIME_VERSION@
Go Toolchain=@GO_VERSION@
EOF
)"
        fi
        if [ -n "${CHECK_VERSION_EXTRA_ROWS:-}" ]; then
            rows="${rows}"$'\n'"${CHECK_VERSION_EXTRA_ROWS}"
        fi
        printf ">> Version Identity\n"
        render_rows "$rows"
        printf '\n'
        ;;
    *)
        echo "build_manifest ERROR: unsupported command: $command_name" >&2
        usage >&2
        exit 2
        ;;
esac
