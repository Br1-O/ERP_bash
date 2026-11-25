#!/usr/bin/env bash
#
# Repositorio remoto (PostgreSQL vía endpoint HTTP).
#
# El ERP no abre sockets PostgreSQL directamente: compone una URL de
# sincronización y envía un snapshot JSON idempotente. El endpoint puede ser
# PostgREST, Supabase Edge Function o un servicio propio que haga UPSERT en
# PostgreSQL. Ver docs/SYNC_POSTGRES.sql para el contrato de referencia.

[[ -n "${_ERP_POSTGRES_REPOSITORY_LOADED:-}" ]] && return 0
declare -g _ERP_POSTGRES_REPOSITORY_LOADED=1

declare -g PG_REPO_HTTP_CODE=""
declare -g PG_REPO_MESSAGE=""
declare -g PG_REPO_OK=0
declare -g PG_REPO_ENDPOINT=""
declare -g PG_REPO_RESPONSE=""

pg_repo_validate_url() {
    local url="${1:-}"
    [[ ${#url} -le 500 ]] || return 1
    [[ "${url}" != *$'\n'* && "${url}" != *$'\r'* && "${url}" != *[[:space:]]* ]] || return 1
    [[ "${url}" =~ ^https?://[^[:space:]]+$ ]]
}

pg_repo_validate_token() {
    local token="${1:-}"
    [[ ${#token} -le 500 ]] || return 1
    [[ "${token}" != *$'\n'* && "${token}" != *$'\r'* ]]
}

pg_repo_compose_endpoint() {
    local url="${1:-}"
    local mode="${2:-snapshot}"
    local separator="?"
    [[ "${url}" == *\?* ]] && separator="&"
    printf '%s%ssource=sqlite&schema_version=%s&mode=%s' \
        "${url}" "${separator}" "${ERP_SCHEMA_VERSION}" "${mode}"
}

_pg_repo_request() {
    local method="${1:-POST}" url="${2:-}" token="${3:-}" payload="${4:-}"
    PG_REPO_HTTP_CODE=""
    PG_REPO_MESSAGE=""
    PG_REPO_OK=0
    PG_REPO_ENDPOINT="${url}"
    PG_REPO_RESPONSE=""

    if ! pg_repo_validate_url "${url}"; then
        PG_REPO_MESSAGE="URL de sincronización inválida."
        return 1
    fi
    if ! pg_repo_validate_token "${token}"; then
        PG_REPO_MESSAGE="Token de sincronización inválido."
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        PG_REPO_MESSAGE="curl no está disponible para sincronizar."
        return 1
    fi
    if [[ "${method}" != "GET" && -z "${payload}" ]]; then
        PG_REPO_MESSAGE="No hay datos para sincronizar."
        return 1
    fi

    local -a headers=(
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        -H "X-ERP-Source: aurea-sqlite"
    )
    if [[ -n "${token}" ]]; then
        headers+=(-H "Authorization: Bearer ${token}" -H "apikey: ${token}")
    fi

    local payload_file="" response_file http_code curl_rc raw response
    response_file=$(mktemp "${TMPDIR:-/tmp}/erp-sync-response.XXXXXX") || {
        PG_REPO_MESSAGE="No se pudo preparar la sincronización."
        return 1
    }

    if [[ "${method}" == "GET" ]]; then
        http_code=$(curl --silent --show-error --connect-timeout 4 --max-time 15 \
            --output "${response_file}" --write-out '%{http_code}' \
            "${headers[@]}" "${url}" 2>/dev/null)
    else
        payload_file=$(mktemp "${TMPDIR:-/tmp}/erp-sync-payload.XXXXXX") || {
            rm -f "${response_file}"
            PG_REPO_MESSAGE="No se pudo preparar el snapshot para enviar."
            return 1
        }
        if ! printf '%s' "${payload}" > "${payload_file}"; then
            rm -f "${payload_file}" "${response_file}"
            PG_REPO_MESSAGE="No se pudo escribir el snapshot temporal."
            return 1
        fi
        http_code=$(curl --silent --show-error --connect-timeout 4 --max-time 15 \
            --output "${response_file}" --write-out '%{http_code}' \
            "${headers[@]}" --data-binary "@${payload_file}" "${url}" 2>/dev/null)
    fi
    curl_rc=$?

    raw=$(cat "${response_file}" 2>/dev/null || true)
    rm -f "${payload_file}" "${response_file}"
    PG_REPO_RESPONSE="${raw}"
    response="${raw//$'\n'/ }"
    response="${response//$'\r'/ }"
    response="${response:0:400}"
    PG_REPO_HTTP_CODE="${http_code:-000}"

    if (( curl_rc != 0 )); then
        PG_REPO_MESSAGE="Sin conexión o endpoint inaccesible (curl ${curl_rc})."
        return 1
    fi
    if [[ ! "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
        PG_REPO_MESSAGE="El endpoint respondió HTTP ${http_code}. ${response}"
        return 1
    fi

    PG_REPO_OK=1
    PG_REPO_MESSAGE="${response:-Sincronización aceptada por el endpoint.}"
    return 0
}

pg_repo_push() {
    local payload="${1:-}" url="${2:-}" token="${3:-}"
    local endpoint
    endpoint=$(pg_repo_compose_endpoint "${url}" "snapshot")
    PG_REPO_ENDPOINT="${endpoint}"
    _pg_repo_request "POST" "${endpoint}" "${token}" "${payload}"
}

pg_repo_push_events() {
    local events="${1:-}" url="${2:-}" token="${3:-}"
    local endpoint payload
    endpoint=$(pg_repo_compose_endpoint "${url}" "events")
    PG_REPO_ENDPOINT="${endpoint}"
    payload="{\"source\":\"sqlite\",\"schema_version\":${ERP_SCHEMA_VERSION},\"events\":${events}}"
    _pg_repo_request "POST" "${endpoint}" "${token}" "${payload}"
}

pg_repo_pull_events() {
    local since_id="${1:-0}" url="${2:-}" token="${3:-}"
    local endpoint
    [[ "${since_id}" =~ ^[0-9]+$ ]] || since_id=0
    endpoint="$(pg_repo_compose_endpoint "${url}" "pull")&since_id=${since_id}"
    PG_REPO_ENDPOINT="${endpoint}"
    _pg_repo_request "GET" "${endpoint}" "${token}"
}
