#!/usr/bin/env bash
#
# Sincronización offline-first con PostgreSQL.
#
# El servicio solo conoce la interfaz de repositorio (local y remoto). Cambiar
# SQLite por otro almacenamiento o el endpoint HTTP por otro transporte no
# requiere tocar el router ni la interfaz de usuario.

[[ -n "${_ERP_API_SYNC_LOADED:-}" ]] && return 0
declare -g _ERP_API_SYNC_LOADED=1

declare -g SYNC_ERROR=""
declare -g SYNC_MESSAGE=""
declare -g SYNC_OK=0

api_sync_sanitize_message() {
    local message="${1:-}"
    message="${message//$'\n'/ }"
    message="${message//$'\r'/ }"
    printf '%s' "${message:0:400}"
}

api_sync_status_json() {
    local_repo_sync_status_json
}

api_sync_save_config() {
    local url="${1:-}"
    local token="${2:-}"
    local clear_token="${3:-0}"

    SYNC_ERROR=""
    if ! pg_repo_validate_url "${url}"; then
        SYNC_ERROR="Ingrese una URL http(s) válida."
        return 1
    fi
    if [[ -n "${token}" ]] && ! pg_repo_validate_token "${token}"; then
        SYNC_ERROR="El token contiene caracteres inválidos."
        return 1
    fi

    if ! local_repo_save_sync_url "${url}"; then
        SYNC_ERROR="No se pudo guardar la URL de sincronización."
        return 1
    fi
    if [[ "${clear_token}" == "1" ]]; then
        local_repo_save_sync_token "" || {
            SYNC_ERROR="No se pudo quitar el token de sincronización."
            return 1
        }
    elif [[ -n "${token}" ]]; then
        local_repo_save_sync_token "${token}" || {
            SYNC_ERROR="No se pudo guardar el token de sincronización."
            return 1
        }
    fi
    return 0
}

api_sync_push() {
    local url token payload bytes message
    SYNC_ERROR=""
    SYNC_MESSAGE=""
    SYNC_OK=0

    url=$(local_repo_get_sync_url)
    token=$(local_repo_get_sync_token)
    if [[ -z "${url}" ]]; then
        SYNC_ERROR="Configure primero la URL del endpoint PostgreSQL."
        return 1
    fi

    payload=$(local_repo_snapshot_json) || {
        SYNC_ERROR="No se pudo construir el snapshot de la base local."
        return 1
    }
    local previous_lc="${LC_ALL:-}"
    LC_ALL=C
    bytes=${#payload}
    LC_ALL="${previous_lc}"

    if pg_repo_push "${payload}" "${url}" "${token}"; then
        SYNC_OK=1
        message=$(api_sync_sanitize_message "${PG_REPO_MESSAGE:-Sincronización completada.}")
        SYNC_MESSAGE="${message}"
        local_repo_record_sync "ok" "${PG_REPO_ENDPOINT}" "${message}" "${bytes}" || true
        return 0
    fi

    message=$(api_sync_sanitize_message "${PG_REPO_MESSAGE:-No se pudo sincronizar.}")
    SYNC_ERROR="${message}"
    local_repo_record_sync "error" "${PG_REPO_ENDPOINT:-${url}}" "${message}" "${bytes}" || true
    return 1
}
