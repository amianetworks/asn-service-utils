#!/usr/bin/env bash
# Check and assemble generic Debian package staging trees.

set -euo pipefail

command_name="${1:-}"
[ -n "$command_name" ] || {
    echo "debian_package ERROR: command is required" >&2
    exit 2
}
shift

service_name=""
service_config=""
service_control=""
debian_files=""
debian_path="build/debian"
version_build="${VERSION_BUILD:-}"
depends_version="${DEP_VERSION_ASN:-}"
deb_file=""
metadata_field=""

usage() {
    cat <<'EOF'
usage: service-utils/builder/debian_package.sh COMMAND [options]

Commands:
  check   Validate package control/config files and configured input files.
  build   Stage files, generate control metadata, and run dpkg-deb.
  metadata
          Print one control metadata field from a .deb package.

Options:
  --service NAME
  --config FILE
  --control FILE
  --files "SRC:DEST ..."
  --debian-path DIR
  --version-build VERSION
  --depends-version VERSION
  --file FILE
  --field FIELD
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --service) shift; service_name="${1:-}" ;;
        --config) shift; service_config="${1:-}" ;;
        --control) shift; service_control="${1:-}" ;;
        --files) shift; debian_files="${1:-}" ;;
        --debian-path) shift; debian_path="${1:-}" ;;
        --version-build) shift; version_build="${1:-}" ;;
        --depends-version) shift; depends_version="${1:-}" ;;
        --file) shift; deb_file="${1:-}" ;;
        --field) shift; metadata_field="${1:-}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "debian_package ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

require_common() {
    [ -n "$service_name" ] || { echo "debian_package ERROR: --service is required" >&2; exit 2; }
    [ -n "$service_config" ] || service_config="debian/deb.$service_name.config"
    [ -n "$service_control" ] || service_control="debian/deb.$service_name.control"
    if [ ! -f "$service_config" ]; then
        echo "Missing config: $service_config"
        exit 1
    fi
    if [ ! -f "$service_control" ]; then
        echo "Missing control: $service_control"
        exit 1
    fi
}

check_inputs() {
    local missing=0 pair src seen_missing=""
    for pair in $debian_files; do
        src="${pair%%:*}"
        if [ ! -e "$src" ]; then
            case " $seen_missing " in
                *" $src "*) continue ;;
            esac
            seen_missing="$seen_missing $src"
            echo "Missing Debian input: $src"
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        echo "Build plugin artifacts before running make build-debian."
        exit 1
    fi
}

cmd_check() {
    require_common
    check_inputs
    printf "  %-24s : inputs present\n" "$service_name"
}

copy_if_present() {
    local src="$1" dest="$2" mode="$3"
    [ -f "$src" ] || return 0
    cp "$src" "$dest"
    chmod "$mode" "$dest"
}

cmd_build() {
    require_common
    [ -n "$version_build" ] || { echo "debian_package ERROR: --version-build is required" >&2; exit 2; }

    local deb_svc_dir service_file conffiles pair src dst package_file
    deb_svc_dir="$debian_path/$service_name"

    check_inputs

    echo "DEBIAN_PATH: $deb_svc_dir"
    mkdir -p "$deb_svc_dir/DEBIAN"

    sed -e "s/@VERSION@/$version_build/" \
        -e "s/@DEPENDS@/$depends_version/" \
        -e "s/@SERVICE@/$service_name/" \
        "$service_control" > "$deb_svc_dir/DEBIAN/control"

    copy_if_present "debian/deb.$service_name.postinst" "$deb_svc_dir/DEBIAN/postinst" 755
    copy_if_present "debian/deb.$service_name.postrm" "$deb_svc_dir/DEBIAN/postrm" 755
    copy_if_present "debian/deb.$service_name.preinst" "$deb_svc_dir/DEBIAN/preinst" 755
    copy_if_present "debian/deb.$service_name.prerm" "$deb_svc_dir/DEBIAN/prerm" 755

    service_file="debian/deb.$service_name.service"
    if [ -f "$service_file" ]; then
        mkdir -p "$deb_svc_dir/lib/systemd/system"
        cp "$service_file" "$deb_svc_dir/lib/systemd/system/$service_name.service"
    fi

    conffiles="debian/conffiles.$service_name"
    if [ -f "$conffiles" ]; then
        echo "Copying service-specific conffiles for $service_name..."
        cp "$conffiles" "$deb_svc_dir/DEBIAN/conffiles"
        chmod 644 "$deb_svc_dir/DEBIAN/conffiles"
    else
        echo "No conffiles found for $service_name, skipping"
    fi

    for pair in $debian_files; do
        src="${pair%%:*}"
        dst="${pair#*:}"
        case "$dst" in
            ""|"."|".."|/*|../*|*/../*|*/..)
                echo "debian_package ERROR: unsafe Debian file destination: $dst" >&2
                exit 2
                ;;
        esac
        deb_root_abs="$(cd "$deb_svc_dir" && pwd -P)"
        dst_parent="$deb_svc_dir/$dst"
        mkdir -p "$dst_parent"
        dst_parent_abs="$(cd "$dst_parent" && pwd -P)"
        case "$dst_parent_abs/" in
            "$deb_root_abs"/*) ;;
            *)
                echo "debian_package ERROR: Debian file destination escapes package root: $dst" >&2
                exit 2
                ;;
        esac
        echo "Processing file: $src -> $dst_parent_abs"
        cp "$src" "$dst_parent_abs/" || { echo "Failed to copy $src"; exit 1; }
    done
    echo "Prepared to packing .deb."

    package_file="${deb_svc_dir}_${version_build}_amd64.deb"
    dpkg-deb --build "$deb_svc_dir" "$package_file"
    echo "Packed: $package_file."
}

extract_deb_control() {
    local file="$1"
    local tmp_dir control_member archive_file extract_dir control_file status

    command -v ar >/dev/null || {
        echo "debian_package ERROR: ar is required when dpkg-deb is unavailable" >&2
        return 1
    }

    control_member="$(ar t "$file" | awk '/^control\.tar($|\.)/ { print; exit }')"
    if [ -z "$control_member" ]; then
        echo "debian_package ERROR: no control.tar member found in $file" >&2
        return 1
    fi

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/debian-package.XXXXXX")"
    archive_file="$tmp_dir/$control_member"
    extract_dir="$tmp_dir/control"
    mkdir -p "$extract_dir"

    if ! ar p "$file" "$control_member" > "$archive_file"; then
        rm -rf "$tmp_dir"
        echo "debian_package ERROR: failed to extract $control_member from $file" >&2
        return 1
    fi

    status=0
    case "$control_member" in
        control.tar)
            tar -xf "$archive_file" -C "$extract_dir" || status=$?
            ;;
        control.tar.gz)
            gzip -dc "$archive_file" | tar -xf - -C "$extract_dir" || status=$?
            ;;
        control.tar.xz)
            command -v xz >/dev/null || { echo "debian_package ERROR: xz is required for $control_member" >&2; status=1; }
            [ "$status" -ne 0 ] || xz -dc "$archive_file" | tar -xf - -C "$extract_dir" || status=$?
            ;;
        control.tar.zst)
            command -v zstd >/dev/null || { echo "debian_package ERROR: zstd is required for $control_member" >&2; status=1; }
            [ "$status" -ne 0 ] || zstd -dc "$archive_file" | tar -xf - -C "$extract_dir" || status=$?
            ;;
        control.tar.bz2)
            command -v bzip2 >/dev/null || { echo "debian_package ERROR: bzip2 is required for $control_member" >&2; status=1; }
            [ "$status" -ne 0 ] || bzip2 -dc "$archive_file" | tar -xf - -C "$extract_dir" || status=$?
            ;;
        *)
            echo "debian_package ERROR: unsupported Debian control archive: $control_member" >&2
            status=1
            ;;
    esac

    if [ "$status" -ne 0 ]; then
        rm -rf "$tmp_dir"
        return "$status"
    fi

    control_file="$(find "$extract_dir" -type f -name control -print -quit)"
    if [ -z "$control_file" ]; then
        rm -rf "$tmp_dir"
        echo "debian_package ERROR: control file not found in $file" >&2
        return 1
    fi

    cat "$control_file"
    rm -rf "$tmp_dir"
}

cmd_metadata() {
    [ -n "$deb_file" ] || { echo "debian_package ERROR: --file is required" >&2; exit 2; }
    [ -n "$metadata_field" ] || { echo "debian_package ERROR: --field is required" >&2; exit 2; }
    [ -f "$deb_file" ] || { echo "debian_package ERROR: package file not found: $deb_file" >&2; exit 1; }

    if command -v dpkg-deb >/dev/null; then
        dpkg-deb -f "$deb_file" "$metadata_field"
        return
    fi

    extract_deb_control "$deb_file" | awk -v key="$metadata_field" '
        $0 ~ "^" key ":" {
            sub("^[^:]+:[[:space:]]*", "")
            print
            found = 1
            exit
        }
        END {
            if (!found) exit 1
        }
    '
}

case "$command_name" in
    check) cmd_check ;;
    build) cmd_build ;;
    metadata) cmd_metadata ;;
    --help|-h|help) usage ;;
    *) echo "debian_package ERROR: unsupported command: $command_name" >&2; usage >&2; exit 2 ;;
esac
