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
    local url token pending pending_count fallback uuids applied snapshot bytes message
    local -a phases=()
    SYNC_ERROR=""
    SYNC_MESSAGE=""
    SYNC_OK=0

    url=$(local_repo_get_sync_url)
    token=$(local_repo_get_sync_token)
    if [[ -z "${url}" ]]; then
        SYNC_ERROR="Configure primero la URL del endpoint PostgreSQL."
        return 1
    fi

    # Fase 1: push de eventos locales pendientes.
    pending_count=$(local_repo_pending_event_count)
    if (( pending_count > 0 )); then
        pending=$(local_repo_pending_events_json) || {
            SYNC_ERROR="No se pudo construir el lote de eventos pendientes."
            return 1
        }
        fallback=$(local_repo_pending_event_uuids_json) || fallback='[]'

        if ! pg_repo_push_events "${pending}" "${url}" "${token}"; then
            message=$(api_sync_sanitize_message "${PG_REPO_MESSAGE:-No se pudieron enviar los eventos locales.}")
            SYNC_ERROR="Fase 1 (push): ${message}"
            local_repo_record_sync "error" "${PG_REPO_ENDPOINT:-${url}}" "${SYNC_ERROR}" 0 || true
            return 1
        fi

        uuids=$(local_repo_processed_uuids_json "${PG_REPO_RESPONSE}" "${fallback}")
        if ! local_repo_mark_events_synced_json "${uuids}"; then
            if ! local_repo_mark_events_synced_json "${fallback}"; then
                SYNC_ERROR="Fase 1 (push): no se pudo marcar los eventos como sincronizados."
                local_repo_record_sync "error" "${PG_REPO_ENDPOINT:-${url}}" "${SYNC_ERROR}" 0 || true
                return 1
            fi
        fi
        phases+=("Push: ${pending_count} eventos")
    else
        phases+=("Push: 0 eventos")
    fi

    # Fase 2: pull de eventos e-commerce posteriores al último cursor remoto.
    local since_id
    since_id=$(local_repo_last_remote_journal_id)
    if ! pg_repo_pull_events "${since_id}" "${url}" "${token}"; then
        message=$(api_sync_sanitize_message "${PG_REPO_MESSAGE:-No se pudieron obtener los eventos remotos.}")
        SYNC_ERROR="Fase 2 (pull): ${message}"
        local_repo_record_sync "error" "${PG_REPO_ENDPOINT:-${url}}" "${SYNC_ERROR}" 0 || true
        return 1
    fi

    if ! applied=$(local_repo_apply_remote_events "${PG_REPO_RESPONSE}"); then
        message=$(api_sync_sanitize_message "${LOCAL_REPO_PULL_ERROR:-No se pudieron aplicar los eventos remotos.}")
        SYNC_ERROR="Fase 2 (pull): ${message}"
        local_repo_record_sync "error" "${PG_REPO_ENDPOINT:-${url}}" "${SYNC_ERROR}" 0 || true
        return 1
    fi
    phases+=("Pull: ${applied:-0} eventos")

    # Fase 3: snapshot consolidado de respaldo.
    snapshot=$(local_repo_snapshot_json) || {
        SYNC_ERROR="Fase 3 (snapshot): no se pudo construir el snapshot de la base local."
        local_repo_record_sync "error" "${PG_REPO_ENDPOINT:-${url}}" "${SYNC_ERROR}" 0 || true
        return 1
    }
    local previous_lc="${LC_ALL:-}"
    LC_ALL=C
    bytes=${#snapshot}
    LC_ALL="${previous_lc}"

    if ! pg_repo_push "${snapshot}" "${url}" "${token}"; then
        message=$(api_sync_sanitize_message "${PG_REPO_MESSAGE:-No se pudo enviar el snapshot de respaldo.}")
        SYNC_ERROR="Fase 3 (snapshot): ${message}"
        local_repo_record_sync "error" "${PG_REPO_ENDPOINT:-${url}}" "${SYNC_ERROR}" "${bytes}" || true
        return 1
    fi
    phases+=("Snapshot: ${bytes} bytes")

    SYNC_OK=1
    message=$(api_sync_sanitize_message "${phases[*]}")
    SYNC_MESSAGE="${message}"
    local_repo_record_sync "ok" "${PG_REPO_ENDPOINT}" "${message}" "${bytes}" || true
    return 0
}
