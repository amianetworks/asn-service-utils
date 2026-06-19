#!/usr/bin/env bash
# Stage and run the protobuf toolchain for ASN service repositories.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

command_name="${1:-}"
[ -n "$command_name" ] || {
    echo "proto_tools ERROR: command is required" >&2
    exit 2
}
shift

protoc_version="${PROTOC_VERSION:-libprotoc 34.1}"
protoc_release_version="${PROTOC_RELEASE_VERSION:-${protoc_version##* }}"
protoc_gen_go_version="${PROTOC_GEN_GO_VERSION:-v1.36.11}"
protoc_gen_go_grpc_version="${PROTOC_GEN_GO_GRPC_VERSION:-v1.6.0}"
tools_dir="${PROTO_TOOLS_DIR:-.cache/proto-tools}"
download_base_url="${PROTOC_DOWNLOAD_BASE_URL:-}"
auto_download="${PROTOC_AUTO_DOWNLOAD:-1}"
protoc_defaulted="${PROTOC_DEFAULTED:-1}"
protoc_override="${PROTOC:-}"
proto_out="${PROTO_OUT:-.}"
default_out="$PROJECT_ROOT"
stamp_file="${PROTO_GEN_STAMP:-}"
force="${PROTO_GEN_FORCE:-0}"
specs="${PROTO_GEN_SPECS:-}"
state_files="${PROTO_GEN_STATE_FILES:-}"
gateway="${PROTO_GEN_GATEWAY:-0}"
protoc_gen_grpc_gateway_version="${PROTOC_GEN_GRPC_GATEWAY_VERSION:-}"
proto_include_paths="${PROTO_INCLUDE_PATHS:-}"

usage() {
    cat <<'EOF'
usage: service-utils/builder/proto_tools.sh COMMAND [options]

Commands:
  tools        Stage protoc, protoc-gen-go, and protoc-gen-go-grpc.
  tools-check  Verify staged/selected protobuf tools.
  gen          Generate protobuf Go outputs using PROTO_GEN_SPECS.

Options:
  --protoc-version TEXT
  --protoc-release-version VERSION
  --protoc-gen-go-version VERSION
  --protoc-gen-go-grpc-version VERSION
  --tools-dir DIR
  --download-base-url URL
  --auto-download 0|1
  --protoc-defaulted 0|1
  --protoc PATH
  --proto-out DIR
  --default-out DIR
  --stamp FILE
  --force 0|1
  --specs "SRC_GLOB:OUT_DIR ..."
  --state-files "FILE ..."
  --gateway 0|1
  --protoc-gen-grpc-gateway-version VERSION
  --proto-include-paths "DIR ..."
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --protoc-version) shift; protoc_version="${1:-}" ;;
        --protoc-release-version) shift; protoc_release_version="${1:-}" ;;
        --protoc-gen-go-version) shift; protoc_gen_go_version="${1:-}" ;;
        --protoc-gen-go-grpc-version) shift; protoc_gen_go_grpc_version="${1:-}" ;;
        --tools-dir) shift; tools_dir="${1:-}" ;;
        --download-base-url) shift; download_base_url="${1:-}" ;;
        --auto-download) shift; auto_download="${1:-}" ;;
        --protoc-defaulted) shift; protoc_defaulted="${1:-}" ;;
        --protoc) shift; protoc_override="${1:-}" ;;
        --proto-out) shift; proto_out="${1:-}" ;;
        --default-out) shift; default_out="${1:-}" ;;
        --stamp) shift; stamp_file="${1:-}" ;;
        --force) shift; force="${1:-}" ;;
        --specs) shift; specs="${1:-}" ;;
        --state-files) shift; state_files="${1:-}" ;;
        --gateway) shift; gateway="${1:-}" ;;
        --protoc-gen-grpc-gateway-version) shift; protoc_gen_grpc_gateway_version="${1:-}" ;;
        --proto-include-paths) shift; proto_include_paths="${1:-}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "proto_tools ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

tools_dir="$(cd "$PROJECT_ROOT" && mkdir -p "$tools_dir" && cd "$tools_dir" && pwd -P)"
tools_bin="$tools_dir/bin"
protoc_local="$tools_bin/protoc"
release_dir="$tools_dir/protoc-$protoc_release_version"
protoc_include="$release_dir/include"
[ -n "$download_base_url" ] || download_base_url="https://github.com/protocolbuffers/protobuf/releases/download/v$protoc_release_version"
[ -n "$stamp_file" ] || stamp_file="$tools_dir/proto-gen.stamp"
[ -n "$protoc_override" ] || protoc_override="$protoc_local"
PATH="$tools_bin:$PATH"

abs_path() {
    local path="$1"
    if [ -d "$path" ]; then
        (cd "$path" && pwd -P)
    else
        local dir base
        dir="$(dirname "$path")"
        base="$(basename "$path")"
        (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
    fi
}

protoc_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os/$arch" in
        Darwin/arm64) echo osx-aarch_64 ;;
        Darwin/x86_64) echo osx-x86_64 ;;
        Linux/x86_64) echo linux-x86_64 ;;
        *) echo "ERROR: unsupported protoc platform $os/$arch. Install protoc $protoc_version and set PROTOC=/path/to/protoc." >&2; exit 1 ;;
    esac
}

stage_protoc_tree() {
    local tree="$1" source="$2" actual
    [ -x "$tree/bin/protoc" ] || return 1
    actual="$("$tree/bin/protoc" --version 2>&1 || true)"
    [ "$actual" = "$protoc_version" ] || return 1
    cp "$tree/bin/protoc" "$protoc_local"
    chmod +x "$protoc_local"
    if [ -d "$tree/include" ]; then
        rm -rf "$protoc_include"
        mkdir -p "$release_dir"
        cp -R "$tree/include" "$protoc_include"
    fi
    echo "protoc $protoc_version staged from $source"
    return 0
}

stage_host_protoc() {
    local host_bin="$1" host_prefix="$2" source="$3" actual
    [ -x "$host_bin" ] || return 1
    actual="$("$host_bin" --version 2>&1 || true)"
    [ "$actual" = "$protoc_version" ] || return 1
    printf '%s\n' '#!/bin/sh' "exec \"$host_bin\" \"\$@\"" > "$protoc_local"
    chmod +x "$protoc_local"
    if [ -n "$host_prefix" ] && [ -d "$host_prefix/include" ]; then
        rm -rf "$protoc_include"
        mkdir -p "$release_dir"
        cp -R "$host_prefix/include" "$protoc_include"
    fi
    echo "protoc $protoc_version staged from $source"
    return 0
}

ensure_protoc() {
    if [ -x "$protoc_local" ] && [ "$("$protoc_local" --version 2>&1 || true)" = "$protoc_version" ]; then
        echo "protoc $protoc_version already staged"
        return 0
    fi

    local host_protoc host_prefix platform cache_dir archive url
    host_protoc="$(command -v protoc || true)"
    if [ -n "$host_protoc" ] && [ "$(protoc --version 2>&1 || true)" = "$protoc_version" ]; then
        host_prefix="$(cd "$(dirname "$host_protoc")/.." && pwd -P || true)"
        stage_host_protoc "$host_protoc" "$host_prefix" PATH
        return 0
    fi

    if [ "$auto_download" != "1" ]; then
        echo "ERROR: protoc $protoc_version is not staged and PATH does not provide a matching protoc." >&2
        echo "Run make proto-tools with network access, install protoc $protoc_version, or set PROTOC=/path/to/protoc." >&2
        exit 1
    fi

    command -v curl >/dev/null || { echo "ERROR: curl is required to download protoc $protoc_version." >&2; exit 1; }
    command -v unzip >/dev/null || { echo "ERROR: unzip is required to unpack protoc $protoc_version." >&2; exit 1; }
    platform="$(protoc_platform)"
    cache_dir="$release_dir/$platform"
    if stage_protoc_tree "$cache_dir" "download cache"; then
        return 0
    fi

    archive="$(mktemp "${TMPDIR:-/tmp}/protoc-$protoc_release_version.XXXXXX.zip")"
    url="$download_base_url/protoc-$protoc_release_version-$platform.zip"
    echo "downloading protoc $protoc_version from $url"
    curl -fsSL "$url" -o "$archive"
    rm -rf "$cache_dir"
    mkdir -p "$cache_dir"
    unzip -q "$archive" -d "$cache_dir"
    rm -f "$archive"
    stage_protoc_tree "$cache_dir" "download"
}

ensure_tool() {
    local name="$1" module="$2" want="$3" pattern="$4" target host_bin
    target="$tools_bin/$name"
    if [ -x "$target" ] && "$target" --version 2>&1 | grep -Eq "$pattern"; then
        echo "$name $want already staged"
        return 0
    fi
    host_bin="$(command -v "$name" || true)"
    if [ -n "$host_bin" ] && "$host_bin" --version 2>&1 | grep -Eq "$pattern"; then
        if [ "$host_bin" != "$target" ]; then
            cp "$host_bin" "$target"
            chmod +x "$target"
        fi
        echo "$name $want staged from PATH"
        return 0
    fi
    echo "installing $name $want into $tools_bin"
    GOBIN="$tools_bin" go install "$module@$want"
    "$target" --version 2>&1 | grep -Eq "$pattern"
}

cmd_tools() {
    mkdir -p "$tools_bin"
    if [ "$protoc_defaulted" = "1" ]; then
        ensure_protoc
    else
        echo "protoc override selected: $protoc_override"
    fi
    ensure_tool protoc-gen-go google.golang.org/protobuf/cmd/protoc-gen-go "$protoc_gen_go_version" "protoc-gen-go $protoc_gen_go_version$"
    ensure_tool protoc-gen-go-grpc google.golang.org/grpc/cmd/protoc-gen-go-grpc "$protoc_gen_go_grpc_version" "protoc-gen-go-grpc ${protoc_gen_go_grpc_version#v}$"
    if [ "$gateway" = "1" ]; then
        [ -n "$protoc_gen_grpc_gateway_version" ] || { echo "ERROR: PROTO_GEN_GATEWAY=1 requires PROTOC_GEN_GRPC_GATEWAY_VERSION." >&2; exit 1; }
        ensure_tool protoc-gen-grpc-gateway github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway "$protoc_gen_grpc_gateway_version" "Version $protoc_gen_grpc_gateway_version,"
    fi
}

cmd_tools_check() {
    cmd_tools
    local actual
    actual="$("$protoc_override" --version)"
    if [ "$actual" != "$protoc_version" ]; then
        echo "ERROR: $protoc_override version mismatch: got '$actual', want '$protoc_version'." >&2
        echo "Install protoc $protoc_version or override PROTOC_VERSION only after regenerating and reviewing protobuf output." >&2
        exit 1
    fi
    protoc-gen-go --version | grep -Eq "protoc-gen-go $protoc_gen_go_version$"
    protoc-gen-go-grpc --version | grep -Eq "protoc-gen-go-grpc ${protoc_gen_go_grpc_version#v}$"
    if [ "$gateway" = "1" ]; then
        protoc-gen-grpc-gateway --version 2>&1 | grep -Eq "Version $protoc_gen_grpc_gateway_version,"
    fi
    echo "protobuf toolchain check passed"
}

proto_state_hash() {
    (
        cd "$PROJECT_ROOT"
        {
            printf 'PROTOC_VERSION=%s\n' "$protoc_version"
            printf 'PROTOC_GEN_GO_VERSION=%s\n' "$protoc_gen_go_version"
            printf 'PROTOC_GEN_GO_GRPC_VERSION=%s\n' "$protoc_gen_go_grpc_version"
            printf 'PROTO_GEN_GATEWAY=%s\n' "$gateway"
            printf 'PROTOC_GEN_GRPC_GATEWAY_VERSION=%s\n' "$protoc_gen_grpc_gateway_version"
            printf 'PROTO_INCLUDE_PATHS=%s\n' "$proto_include_paths"
            printf 'PROTO_GEN_SPECS=%s\n' "$specs"
            for file in $state_files; do
                [ -e "$file" ] || continue
                printf 'file:%s\n' "$file"
                shasum -a 256 "$file"
            done
        } | shasum -a 256 | awk '{ print $1 }'
    )
}

cmd_gen() {
    [ -n "$specs" ] || { echo "ERROR: PROTO_GEN_SPECS is empty." >&2; exit 1; }

    local proto_out_abs default_out_abs default_output current previous include_args
    proto_out_abs="$(cd "$PROJECT_ROOT" && mkdir -p "$proto_out" && cd "$proto_out" && pwd -P)"
    default_out_abs="$(abs_path "$default_out")"
    default_output=0
    [ "$proto_out_abs" = "$default_out_abs" ] && default_output=1

    if [ "$default_output" = "1" ] && [ "$force" != "1" ] && [ -f "$stamp_file" ]; then
        current="$(proto_state_hash)"
        previous="$(cat "$stamp_file")"
        if [ "$current" = "$previous" ]; then
            echo "proto-gen skipped; generated protobuf output is current."
            exit 0
        fi
    fi

    cmd_tools_check

    (
        cd "$PROJECT_ROOT"
        for spec in $specs; do
            proto_sources="${spec%%:*}"
            generated_dir="${spec#*:}"
            if [ "$proto_sources" = "$spec" ] || [ -z "$generated_dir" ]; then
                echo "ERROR: invalid PROTO_GEN_SPECS item '$spec'; expected source-glob:generated-output-dir." >&2
                exit 1
            fi
            include_args="-I ."
            [ -d "$protoc_include" ] && include_args="$include_args -I $protoc_include"
            # Extra include roots (e.g. vendored google/api annotations for grpc-gateway).
            for inc in $proto_include_paths; do
                include_args="$include_args -I $inc"
            done
            gateway_args=""
            if [ "$gateway" = "1" ]; then
                gateway_args="--grpc-gateway_out=$proto_out_abs --grpc-gateway_opt=paths=source_relative"
            fi
            # Intentionally leave proto_sources/gateway_args unquoted so configured globs/args expand.
            "$protoc_override" $include_args --go_out="$proto_out_abs" --go_opt=paths=source_relative --go-grpc_out=require_unimplemented_servers=false:"$proto_out_abs" --go-grpc_opt=paths=source_relative $gateway_args $proto_sources
            if [ -d "$proto_out_abs/$generated_dir" ]; then
                find "$proto_out_abs/$generated_dir" \( -name '*.pb.go' -o -name '*.pb.gw.go' \) -exec gofmt -w {} +
            fi
        done
    )

    if [ "$default_output" = "1" ]; then
        mkdir -p "$(dirname "$stamp_file")"
        proto_state_hash > "$stamp_file"
    fi
    echo "proto-gen completed"
}

case "$command_name" in
    tools) cmd_tools ;;
    tools-check) cmd_tools_check ;;
    gen) cmd_gen ;;
    --help|-h|help) usage ;;
    *) echo "proto_tools ERROR: unsupported command: $command_name" >&2; usage >&2; exit 2 ;;
esac
