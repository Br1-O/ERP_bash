#!/usr/bin/env bash
#
# Capa de negocio: autenticación y sesiones.

[[ -n "${_ERP_API_AUTH_LOADED:-}" ]] && return 0
declare -g _ERP_API_AUTH_LOADED=1

declare -g AUTH_USER=""
declare -g AUTH_ROLE=""
declare -g AUTH_TOKEN=""
declare -g AUTH_ERROR=""

api_hash_password() {
    local password="${1:-}"
    local salt="${2:-}"
    printf '%s' "${salt}:${password}" | sha256sum | awk '{print $1}'
}

api_generate_session_token() {
    printf '%s|%s|%s|%s|%s' "${RANDOM}" "${RANDOM}" "$(date +%s%N)" "${BASHPID}" "${AUTH_USER:-anon}" \
        | sha256sum | awk '{print $1}'
}

api_user_exists() {
    local username="${1:-}"
    local count
    count=$(db_scalar "SELECT COUNT(*) FROM Users WHERE username = $(db_quote "${username}");" 2>/dev/null || printf '0')
    (( ${count:-0} > 0 ))
}

api_create_user() {
    local username="${1:-}"
    local password="${2:-}"
    local role="${3:-vendedor}"

    AUTH_ERROR=""

    if [[ -z "${username}" || ! "${username}" =~ ^[A-Za-zÁÉÍÓÚáéíóúÑñ0-9._-]{3,50}$ ]]; then
        AUTH_ERROR="El usuario debe tener entre 3 y 50 caracteres válidos."
        return 1
    fi

    if [[ ${#password} -lt 6 ]]; then
        AUTH_ERROR="La contraseña debe tener al menos 6 caracteres."
        return 1
    fi

    if api_user_exists "${username}"; then
        AUTH_ERROR="El nombre de usuario ya está registrado."
        return 2
    fi

    local salt hash
    salt=$(printf '%s|%s|%s' "$(date +%s%N)" "${RANDOM}" "${username}" | sha256sum | cut -c1-12)
    hash=$(api_hash_password "${password}" "${salt}")

    db_set_context_user "${username}"
    db_exec "INSERT INTO Users (username, password_hash, salt, role)
             VALUES ($(db_quote "${username}"), $(db_quote "${hash}"), $(db_quote "${salt}"), $(db_quote "${role}"));"
}

api_authenticate() {
    local username="${1:-}"
    local password="${2:-}"

    AUTH_USER=""
    AUTH_ROLE=""
    AUTH_TOKEN=""
    AUTH_ERROR=""

    if [[ -z "${username}" || -z "${password}" ]]; then
        AUTH_ERROR="Usuario y contraseña son obligatorios."
        return 1
    fi

    local row salt stored_hash username_db role
    row=$(db_query "SELECT username, password_hash, salt, role FROM Users WHERE username = $(db_quote "${username}") LIMIT 1;")
    if [[ -z "${row}" ]]; then
        AUTH_ERROR="Credenciales inválidas."
        return 1
    fi

    IFS='|' read -r username_db stored_hash salt role <<< "${row}"
    if [[ "$(api_hash_password "${password}" "${salt}")" != "${stored_hash}" ]]; then
        AUTH_ERROR="Credenciales inválidas."
        return 1
    fi

    AUTH_USER="${username_db}"
    AUTH_ROLE="${role:-vendedor}"
    AUTH_TOKEN=$(api_generate_session_token)

    db_exec "DELETE FROM Sessions WHERE expires_at <= strftime('%s', 'now');" >/dev/null 2>&1 || true
    db_exec "INSERT INTO Sessions (token, username, expires_at)
             VALUES ($(db_quote "${AUTH_TOKEN}"), $(db_quote "${AUTH_USER}"), strftime('%s', 'now') + 28800);" || {
        AUTH_ERROR="No se pudo crear la sesión."
        return 1
    }

    db_set_context_user "${AUTH_USER}" >/dev/null 2>&1 || true
    return 0
}

api_load_session() {
    local token="${1:-}"
    AUTH_USER=""
    AUTH_ROLE=""
    AUTH_TOKEN=""

    [[ -z "${token}" ]] && return 1

    local row username role
    row=$(db_query "SELECT s.username, u.role
                    FROM Sessions s
                    JOIN Users u ON u.username = s.username
                    WHERE s.token = $(db_quote "${token}")
                      AND s.expires_at > strftime('%s', 'now')
                    LIMIT 1;")
    [[ -z "${row}" ]] && return 1

    IFS='|' read -r username role <<< "${row}"
    AUTH_USER="${username}"
    AUTH_ROLE="${role:-vendedor}"
    AUTH_TOKEN="${token}"
    return 0
}

api_logout_session() {
    local token="${1:-}"
    [[ -z "${token}" ]] && return 0
    db_exec "DELETE FROM Sessions WHERE token = $(db_quote "${token}");" >/dev/null 2>&1 || true
}

api_session_cookie() {
    local token="${1:-}"
    printf 'Set-Cookie: erp_session=%s; Path=/; HttpOnly; SameSite=Lax; Max-Age=28800' "${token}"
}

api_logout_cookie() {
    printf 'Set-Cookie: erp_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0'
}

api_user_initials() {
    local name="${1:-Usuario}"
    local first="${name:0:1}"
    printf '%s' "${first^^}"
}
