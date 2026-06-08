#!/usr/bin/env bash
# Stage service-served documentation for package and image artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

release_mode="${BUILD_MODE:-dev}"
build_manifest="$PROJECT_ROOT/build/Manifest.yaml"
version_build_override=""
stage_dir="$PROJECT_ROOT/build/docs"
report_file=""
service_name="${SERVICE_NAME:-service}"
service_title="${SERVICE:-$service_name}"
version_key="${SERVICE_DOCS_VERSION_KEY:-}"
version_label="${SERVICE_DOCS_VERSION_LABEL:-}"
source_key="${SERVICE_DOCS_SOURCE_KEY:-}"
served_key="${SERVICE_DOCS_SERVED_KEY:-}"
runtime_root_key="${SERVICE_DOCS_RUNTIME_ROOT_KEY:-}"
runtime_root="${SERVICE_DOCS_RUNTIME_ROOT:-}"
docs_manifest="${SERVICE_DOCS_STAGE_MANIFEST:-$PROJECT_ROOT/docs/service-docs.tsv}"
index_links="${SERVICE_DOCS_INDEX_LINKS:-}"
routes="${SERVICE_DOCS_ROUTES:-}"
required_files="${SERVICE_DOCS_STAGE_REQUIRED_FILES:-}"
package_channel=""
docker_image_intent=""
documentation_channel=""
rollback_requirement=""
artifact_source="${SERVICE_DOCS_ARTIFACT_SOURCE:-local-build}"
published_manifest="${SERVICE_DOCS_PUBLISHED_MANIFEST:-not selected}"
release_intent="${SERVICE_DOCS_RELEASE_INTENT:-not provided}"
rollback_plan="${SERVICE_DOCS_ROLLBACK_PLAN:-not provided}"

usage() {
    cat <<'EOF'
usage: service-utils/builder/stage_docs.sh [options]

Options:
  --mode DEV|PRO
  --manifest FILE
  --version-build VERSION
  --stage-dir DIR
  --report-file FILE
  --service-name NAME
  --service-title TITLE
  --version-key KEY
  --version-label LABEL
  --source-key KEY
  --served-key KEY
  --runtime-root-key KEY
  --runtime-root PATH
  --docs-manifest FILE
  --index-links "PATH=Label_with_underscores ..."
  --routes "/docs/ /docs/api/ ..."
  --required-files "PATH ..."
  --package-channel TEXT
  --docker-image-intent TEXT
  --documentation-channel TEXT
  --rollback-requirement TEXT
  --artifact-source TEXT
  --published-manifest TEXT
  --release-intent TEXT
  --rollback-plan TEXT
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            shift
            [ "$#" -gt 0 ] || { echo "service-docs-stage ERROR: --mode requires DEV or PRO" >&2; exit 1; }
            release_mode="$1"
            ;;
        --manifest)
            shift
            [ "$#" -gt 0 ] || { echo "service-docs-stage ERROR: --manifest requires a path" >&2; exit 1; }
            build_manifest="$1"
            ;;
        --version-build)
            shift
            [ "$#" -gt 0 ] || { echo "service-docs-stage ERROR: --version-build requires a value" >&2; exit 1; }
            version_build_override="$1"
            ;;
        --stage-dir)
            shift
            [ "$#" -gt 0 ] || { echo "service-docs-stage ERROR: --stage-dir requires a path" >&2; exit 1; }
            stage_dir="$1"
            ;;
        --report-file)
            shift
            [ "$#" -gt 0 ] || { echo "service-docs-stage ERROR: --report-file requires a path" >&2; exit 1; }
            report_file="$1"
            ;;
        --service-name) shift; service_name="${1:-}" ;;
        --service-title) shift; service_title="${1:-}" ;;
        --version-key) shift; version_key="${1:-}" ;;
        --version-label) shift; version_label="${1:-}" ;;
        --source-key) shift; source_key="${1:-}" ;;
        --served-key) shift; served_key="${1:-}" ;;
        --runtime-root-key) shift; runtime_root_key="${1:-}" ;;
        --runtime-root) shift; runtime_root="${1:-}" ;;
        --docs-manifest) shift; docs_manifest="${1:-}" ;;
        --index-links) shift; index_links="${1:-}" ;;
        --routes) shift; routes="${1:-}" ;;
        --required-files) shift; required_files="${1:-}" ;;
        --package-channel) shift; package_channel="${1:-}" ;;
        --docker-image-intent) shift; docker_image_intent="${1:-}" ;;
        --documentation-channel) shift; documentation_channel="${1:-}" ;;
        --rollback-requirement) shift; rollback_requirement="${1:-}" ;;
        --artifact-source) shift; artifact_source="${1:-}" ;;
        --published-manifest) shift; published_manifest="${1:-}" ;;
        --release-intent) shift; release_intent="${1:-}" ;;
        --rollback-plan) shift; rollback_plan="${1:-}" ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) echo "service-docs-stage ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

mode_upper="$(printf '%s' "$release_mode" | tr '[:lower:]' '[:upper:]')"
case "$mode_upper" in
    DEV|PRO) ;;
    *) echo "service-docs-stage ERROR: --mode requires DEV or PRO" >&2; exit 1 ;;
esac
mode_lower="$(printf '%s' "$mode_upper" | tr '[:upper:]' '[:lower:]')"

[ -n "$version_key" ] || version_key="${service_name}_version_build"
[ -n "$version_label" ] || version_label="$service_title Version Build"
[ -n "$source_key" ] || source_key="${service_name}_source_commit"
[ -n "$served_key" ] || served_key="docs_served_by_service"
[ -n "$runtime_root_key" ] || runtime_root_key="docs_runtime_root"
[ -n "$runtime_root" ] || runtime_root="/var/www/$service_name"

if [ -z "$package_channel" ]; then
    case "$mode_lower" in
        pro) package_channel="stable apt subrepo after selected publish intent" ;;
        *) package_channel="dev apt subrepo after selected publish intent" ;;
    esac
fi
[ -n "$docker_image_intent" ] || docker_image_intent="Exact version tag selected by release mode; latest is a PRO publish concern."
[ -n "$documentation_channel" ] || documentation_channel="Release docs tree inside the exact selected package and Docker image."
if [ -z "$rollback_requirement" ]; then
    case "$mode_lower" in
        pro) rollback_requirement="Required before customer/operator release: previous known-good version, packages, images, and data compatibility notes." ;;
        *) rollback_requirement="Required before shared DEV handoff when published artifacts are used; local-build validation records no remote rollback action." ;;
    esac
fi

case "$build_manifest" in
    /*) build_manifest_path="$build_manifest" ;;
    *) build_manifest_path="$PROJECT_ROOT/$build_manifest" ;;
esac

build_manifest_value() {
    local key_path="$1"
    [ -f "$build_manifest_path" ] || return 1
    awk -v key_path="$key_path" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            return value
        }
        BEGIN { split(key_path, want, ".") }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        /^[^[:space:]][^:]*:[[:space:]]*$/ {
            top = $0
            sub(/:.*/, "", top)
            next
        }
        /^[^[:space:]][^:]*:/ {
            key = $0
            sub(/:.*/, "", key)
            value = $0
            sub(/^[^:]*:/, "", value)
            if (want[1] == key && want[2] == "") {
                print trim(value)
                found = 1
                exit
            }
            next
        }
        /^[[:space:]]+[^[:space:]][^:]*:/ {
            key = $0
            sub(/^[[:space:]]+/, "", key)
            sub(/:.*/, "", key)
            value = $0
            sub(/^[[:space:]]+[^:]*:/, "", value)
            if (want[1] == top && want[2] == key) {
                print trim(value)
                found = 1
                exit
            }
        }
        END { exit found ? 0 : 1 }
    ' "$build_manifest_path"
}

version_build() {
    local value manifest_mode
    if [ -n "$version_build_override" ]; then
        printf '%s\n' "$version_build_override"
        return 0
    fi
    if [ ! -s "$build_manifest_path" ]; then
        echo "service-docs-stage ERROR: missing build manifest: ${build_manifest_path#$PROJECT_ROOT/}" >&2
        echo "Run 'make build-plugin' or 'make build' first." >&2
        exit 1
    fi
    value="$(build_manifest_value version_build || true)"
    [ -n "$value" ] || {
        echo "service-docs-stage ERROR: build manifest does not contain version_build: ${build_manifest_path#$PROJECT_ROOT/}" >&2
        exit 1
    }
    manifest_mode="$(build_manifest_value build_mode || true)"
    if [ -n "$manifest_mode" ] && [ "$manifest_mode" != "$mode_lower" ]; then
        echo "service-docs-stage ERROR: build manifest mode is '$manifest_mode', expected '$mode_lower': ${build_manifest_path#$PROJECT_ROOT/}" >&2
        exit 1
    fi
    printf '%s\n' "$value"
}

abs_path() {
    local path="$1"
    local dir base
    [ -n "$path" ] || return 1
    if [ -d "$path" ]; then
        (cd "$path" && pwd -P)
        return
    fi
    case "$path" in
        /*) ;;
        *) path="$PWD/$path" ;;
    esac
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    while [ ! -d "$dir" ]; do
        base="$(basename "$dir")/$base"
        dir="$(dirname "$dir")"
    done
    dir="$(cd "$dir" && pwd -P)"
    printf '%s/%s\n' "$dir" "$base"
}

path_is_under() {
    local child="$1"
    local parent="$2"
    [ -n "$child" ] && [ -n "$parent" ] || return 1
    [ "$child" = "$parent" ] && return 0
    case "$child" in
        "$parent"/*) return 0 ;;
        *) return 1 ;;
    esac
}

prepare_managed_dir() {
    local label="$1"
    local raw="$2"
    local target project_root workspace_root build_root cache_root result_root

    case "$raw" in
        ""|"/")
            echo "service-docs-stage ERROR: refusing unsafe $label directory: ${raw:-<empty>}" >&2
            return 1
            ;;
    esac

    target="$(abs_path "$raw")" || {
        echo "service-docs-stage ERROR: unable to resolve $label directory: $raw" >&2
        return 1
    }
    project_root="$(abs_path "$PROJECT_ROOT")"
    workspace_root="$(abs_path "$PROJECT_ROOT/..")"
    build_root="$(abs_path "$PROJECT_ROOT/build")"
    cache_root="$(abs_path "$PROJECT_ROOT/.cache")"
    result_root=""
    if [ -n "${WORKFLOW_RESULT_DIR:-}" ]; then
        result_root="$(abs_path "$WORKFLOW_RESULT_DIR")"
    fi

    if [ "$target" = "$project_root" ] ||
        [ "$target" = "$workspace_root" ] ||
        [ "$target" = "$build_root" ] ||
        [ "$target" = "$cache_root" ] ||
        { [ -n "$result_root" ] && [ "$target" = "$result_root" ]; }; then
        echo "service-docs-stage ERROR: refusing unsafe $label directory: $target" >&2
        return 1
    fi

    if path_is_under "$project_root" "$target"; then
        echo "service-docs-stage ERROR: refusing ancestor $label directory: $target" >&2
        return 1
    fi

    if path_is_under "$target" "$project_root"; then
        if path_is_under "$target" "$build_root"; then
            printf '%s\n' "$target"
            return 0
        fi
        if path_is_under "$target" "$cache_root"; then
            printf '%s\n' "$target"
            return 0
        fi
        if [ -n "$result_root" ] && path_is_under "$target" "$result_root"; then
            printf '%s\n' "$target"
            return 0
        fi
        echo "service-docs-stage ERROR: refusing $label directory inside product source: $target" >&2
        return 1
    fi

    printf '%s\n' "$target"
}

relpath() {
    local path="$1"
    case "$path" in
        "$PROJECT_ROOT"/*) printf '%s\n' "${path#$PROJECT_ROOT/}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

label_text() {
    local value="$1"
    value="${value//_/ }"
    printf '%s\n' "$value"
}

copy_if_exists() {
    local src="$1"
    local dst="$2"
    case "$src" in
        workflow|workflow/*)
            echo "service-docs-stage ERROR: workflow files are not service-served docs inputs: $src" >&2
            exit 1
            ;;
    esac
    if [ ! -e "$PROJECT_ROOT/$src" ]; then
        echo "service-docs-stage ERROR: missing docs source: $src" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$dst")"
    if [ -d "$PROJECT_ROOT/$src" ]; then
        mkdir -p "$dst"
        cp -R "$PROJECT_ROOT/$src"/. "$dst/"
    else
        cp "$PROJECT_ROOT/$src" "$dst"
    fi
}

docs_manifest_entries() {
    local manifest="$1"
    local src dst extra
    [ -n "$manifest" ] || return 0
    if [ ! -f "$manifest" ]; then
        echo "service-docs-stage ERROR: missing docs staging manifest: ${manifest#$PROJECT_ROOT/}" >&2
        exit 1
    fi
    while read -r src dst extra; do
        case "$src" in
            ""|\#*) continue ;;
        esac
        if [ -z "$dst" ] || [ -n "${extra:-}" ]; then
            echo "service-docs-stage ERROR: invalid docs staging manifest row: $src ${dst:-} ${extra:-}" >&2
            exit 1
        fi
        printf '%s:%s\n' "$src" "$dst"
    done < "$manifest"
}

write_main_index() {
    local link path label
    cat > "$stage_dir/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>$service_title $version Documentation</title>
</head>
<body>
  <h1>$service_title $version Documentation</h1>
  <p>Release mode: $mode_upper</p>
  <p>Source commit: $commit</p>
  <ul>
EOF
    if [ -n "$index_links" ]; then
        for link in $index_links; do
            path="${link%%=*}"
            label="${link#*=}"
            printf '    <li><a href="%s">%s</a></li>\n' "$path" "$(label_text "$label")" >> "$stage_dir/index.html"
        done
    else
        find "$stage_dir" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r dir; do
            path="$(basename "$dir")"
            printf '    <li><a href="%s/">%s/</a></li>\n' "$path" "$path" >> "$stage_dir/index.html"
        done
        find "$stage_dir" -mindepth 1 -maxdepth 1 -type f ! -name index.html | sort | while IFS= read -r file; do
            path="$(basename "$file")"
            printf '    <li><a href="%s">%s</a></li>\n' "$path" "$path" >> "$stage_dir/index.html"
        done
    fi
    cat >> "$stage_dir/index.html" <<'EOF'
  </ul>
</body>
</html>
EOF
}

write_section_indexes() {
    find "$stage_dir" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r dir; do
        local name
        name="$(basename "$dir")"
        [ "$name" != "release" ] || continue
        [ ! -f "$dir/index.html" ] || continue
        {
            printf '<!doctype html>\n'
            printf '<html lang="en">\n'
            printf '<head><meta charset="utf-8"><title>%s %s</title></head>\n' "$service_title" "$name"
            printf '<body>\n'
            printf '  <h1>%s %s</h1>\n' "$service_title" "$name"
            printf '  <ul>\n'
            find "$dir" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r sub; do
                printf '    <li><a href="%s/">%s/</a></li>\n' "$(basename "$sub")" "$(basename "$sub")"
            done
            find "$dir" -mindepth 1 -maxdepth 1 -type f ! -name index.html | sort | while IFS= read -r file; do
                printf '    <li><a href="%s">%s</a></li>\n' "$(basename "$file")" "$(basename "$file")"
            done
            printf '  </ul>\n'
            printf '</body>\n'
            printf '</html>\n'
        } > "$dir/index.html"
    done
}

write_release_manifest() {
    {
        printf 'release_mode: %s\n' "$mode_upper"
        printf '%s: %s\n' "$version_key" "$version"
        printf 'build_manifest: %s\n' "${build_manifest_path#$PROJECT_ROOT/}"
        printf '%s: %s\n' "$source_key" "$commit"
        printf 'generated_at: %s\n' "$generated_at"
        printf '%s: true\n' "$served_key"
        printf '%s: %s\n' "$runtime_root_key" "$runtime_root"
        printf 'docs_routes:\n'
        if [ -n "$routes" ]; then
            for route in $routes; do
                printf '  - %s\n' "$route"
            done
        else
            printf '  - /docs/\n'
        fi
    } > "$stage_dir/release/ReleaseManifest.yaml"
}

write_release_notes() {
    cat > "$stage_dir/release/ReleaseNotes.md" <<EOF
# $service_title Release Notes

Release Mode: $mode_upper
${version_label:-Version Build}: $version
Source Commit: $commit
Artifact Source: $artifact_source
Published Artifact Manifest: $published_manifest
Package Channel: ${package_channel:-not configured}
Docker Image Intent: ${docker_image_intent:-not configured}
Documentation Channel: ${documentation_channel:-service-served docs inside the selected package/image artifacts}
Release Intent: $release_intent
Rollback Plan: $rollback_plan

## Artifact Inventory

| Area | Evidence | Release Intent |
|---|---|---|
| Build artifacts | P2 build inventory or published artifact manifest | Built artifacts must match the release version. |
| Debian packages | Package lane or published apt metadata | Package names, versions, checksums, and subrepo must match the selected release mode. |
| Docker images | Docker lane or published registry metadata | Image coordinates and digests must match the selected release mode. |
| Documentation | Release manifest and docs checksums | Service-served docs must match the release version and selected audience. |

## Release And Rollback

- Publishing, package repository access, registry pushes, optional docs download upload, deployment, live credentials, and deployment phases require explicit user request.
- Release readiness requires final artifact identity, rollback guidance, and release intent before customer/operator handoff.
- ${rollback_requirement:-No additional rollback requirement configured.}
EOF
}

write_checksums() {
    checksum_file="$stage_dir/release/DocsChecksums.tsv"
    if shasum_path="$(command -v shasum 2>&1)"; then
        : "$shasum_path"
        checksum_cmd=(shasum -a 256)
    elif sha256sum_path="$(command -v sha256sum 2>&1)"; then
        : "$sha256sum_path"
        checksum_cmd=(sha256sum)
    else
        echo "service-docs-stage ERROR: shasum or sha256sum is required to stage docs" >&2
        exit 1
    fi
    {
        printf 'Path\tSHA256\n'
        find "$stage_dir" -type f | sort | while IFS= read -r file; do
            case "$file" in
                "$checksum_file") continue ;;
            esac
            sum="$("${checksum_cmd[@]}" "$file" | awk '{ print $1 }')"
            printf '%s\t%s\n' "${file#$stage_dir/}" "$sum"
        done
    } > "$checksum_file"
}

write_report() {
    local file status
    [ -n "$report_file" ] || return 0
    mkdir -p "$(dirname "$report_file")"
    {
        echo "# Service Docs Package"
        echo
        echo "Generated At: $generated_at"
        echo "Release Mode: $mode_upper"
        echo "Stage Directory: \`$(relpath "$stage_dir")\`"
        echo
        printf '| Check | Status | Evidence | Note |\n'
        printf '|---|---|---|---|\n'
        printf '| Docs root | PASS | `%s` | Service package/image docs tree staged. |\n' "$(relpath "$stage_dir")"
        for file in $required_files; do
            status=FAIL
            [ -s "$stage_dir/$file" ] && status=PASS
            printf '| Required docs file | %s | `%s` | Configured docs staging requirement. |\n' "$status" "$(relpath "$stage_dir/$file")"
        done
        printf '| Checksums | PASS | `%s` | Docs package checksum manifest generated. |\n' "$(relpath "$checksum_file")"
    } > "$report_file"
}

validate_required_files() {
    local file missing=0
    for file in $required_files; do
        if [ ! -s "$stage_dir/$file" ]; then
            echo "service-docs-stage ERROR: missing required staged docs file: $file" >&2
            missing=1
        fi
    done
    [ "$missing" -eq 0 ]
}

case "$docs_manifest" in
    ""|/*) ;;
    *) docs_manifest="$PROJECT_ROOT/$docs_manifest" ;;
esac

stage_dir="$(prepare_managed_dir "docs stage" "$stage_dir")"
rm -rf "$stage_dir"
mkdir -p "$stage_dir/release"

docs_entries_file="$(mktemp "${TMPDIR:-/tmp}/service-docs-stage-entries.XXXXXX")"
docs_manifest_entries "$docs_manifest" > "$docs_entries_file"
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    src="${entry%%:*}"
    dst="${entry#*:}"
    if [ -z "$src" ] || [ -z "$dst" ] || [ "$src" = "$dst" ]; then
        echo "service-docs-stage ERROR: invalid docs staging manifest entry: $entry" >&2
        rm -f "$docs_entries_file"
        exit 1
    fi
    copy_if_exists "$src" "$stage_dir/$dst"
done < "$docs_entries_file"
rm -f "$docs_entries_file"

version="$(version_build)"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
commit="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD || echo unknown)"

write_section_indexes
write_main_index
write_release_manifest
write_release_notes
write_checksums
write_report

echo "Service docs staged: $stage_dir"

validate_required_files
