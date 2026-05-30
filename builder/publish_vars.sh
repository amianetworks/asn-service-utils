#!/usr/bin/env bash
# Print and validate release credential variables without exposing values.

set -euo pipefail

command_name="${1:-}"
[ -n "$command_name" ] || {
    echo "publish_vars ERROR: command is required" >&2
    exit 2
}
shift

kind=""
site=""
endpoint_name=""
endpoint_value=""
profile_name=""
auth_var=""
credential_var=""
used_by=""
profile_row="yes"

usage() {
    cat <<'EOF'
usage: service-utils/builder/publish_vars.sh COMMAND [options]

Commands:
  print   Print redacted inventory rows for one publish site.
  check   Validate one publish site credential and endpoint.

Options:
  --kind docker|debian
  --site SITE
  --endpoint-name VAR
  --endpoint VALUE
  --profile PROFILE
  --profile-row yes|no
  --auth-var VAR
  --credential-var VAR
  --used-by TEXT
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --kind) shift; kind="${1:-}" ;;
        --site) shift; site="${1:-}" ;;
        --endpoint-name) shift; endpoint_name="${1:-}" ;;
        --endpoint) shift; endpoint_value="${1:-}" ;;
        --profile) shift; profile_name="${1:-}" ;;
        --profile-row) shift; profile_row="${1:-}" ;;
        --auth-var) shift; auth_var="${1:-}" ;;
        --credential-var) shift; credential_var="${1:-}" ;;
        --used-by) shift; used_by="${1:-}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "publish_vars ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

credential_value() {
    if [ -n "$credential_var" ]; then
        printf '%s' "${!credential_var:-}"
    fi
}

kind_label() {
    case "$kind" in
        docker) echo "Docker" ;;
        debian) echo "Debian" ;;
        *) echo "$kind" ;;
    esac
}

validate_args() {
    [ -n "$kind" ] || { echo "publish_vars ERROR: --kind is required" >&2; exit 2; }
    [ -n "$site" ] || { echo "publish_vars ERROR: --site is required" >&2; exit 2; }
    [ -n "$endpoint_name" ] || { echo "publish_vars ERROR: --endpoint-name is required" >&2; exit 2; }
    [ -n "$credential_var" ] || { echo "publish_vars ERROR: --credential-var is required" >&2; exit 2; }
    case "$profile_row" in
        yes|no) ;;
        *) echo "publish_vars ERROR: --profile-row must be yes or no" >&2; exit 2 ;;
    esac
}

cmd_print() {
    validate_args
    local status effective_value
    effective_value="$(credential_value)"

    status="SET"
    [ -n "$endpoint_value" ] || status="MISSING"
    printf "%-44s %-11s %-7s %s\n" "$endpoint_name" "$status" "no" "$used_by"

    status="SET"
    if [ "$profile_row" = "yes" ]; then
        [ -n "$profile_name" ] || status="MISSING"
        printf "%-44s %-11s %-7s %s\n" "RELEASE_SECRET_PROFILE_$site" "$status" "no" "$auth_var"
    fi

    status="SET"
    if [ -z "$effective_value" ]; then
        status="MISSING"
    elif ! printf '%s' "$effective_value" | grep -q ':'; then
        status="INVALID"
    fi
    printf "%-44s %-11s %-7s %s\n" "$auth_var" "$status" "yes" "$credential_var, $used_by"
}

cmd_check() {
    validate_args
    local label effective_value
    label="$(kind_label)"
    effective_value="$(credential_value)"

    if [ -z "$endpoint_value" ]; then
        if [ "$kind" = "docker" ]; then
            echo "ERROR: Docker registry $site is not configured."
        else
            echo "ERROR: Debian repo $site is not configured."
        fi
        echo "Required: $endpoint_name."
        exit 1
    fi

    if [ -z "$effective_value" ]; then
        echo "ERROR: $label credential for $site is not configured."
        echo "Required: $auth_var (exported as $credential_var)."
        exit 1
    fi

    if ! printf '%s' "$effective_value" | grep -q ':'; then
        echo "ERROR: $label credential for $site must use user:password format."
        echo "Fix: $auth_var."
        exit 1
    fi

    printf "  %-24s : %s\n" "$label $site" "credential set ($auth_var)"
}

case "$command_name" in
    print) cmd_print ;;
    check) cmd_check ;;
    --help|-h|help) usage ;;
    *) echo "publish_vars ERROR: unsupported command: $command_name" >&2; usage >&2; exit 2 ;;
esac
