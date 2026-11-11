#!/usr/bin/env bash
#
# Utilidades mínimas de JSON sin dependencias externas.

[[ -n "${_ERP_JSON_LOADED:-}" ]] && return 0
declare -g _ERP_JSON_LOADED=1

json_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/}"
    value="${value//$'\t'/\\t}"
    printf '%s' "${value}"
}

json_quote() {
    printf '"%s"' "$(json_escape "${1:-}")"
}

json_number() {
    local value="${1:-0}"
    if [[ "${value}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

json_bool() {
    if [[ "${1:-0}" == "1" || "${1:-0}" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}
