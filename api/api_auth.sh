#!/usr/bin/env bash
#
# Capa de negocio: autenticación y sesiones.

[[ -n "${_ERP_API_AUTH_LOADED:-}" ]] && return 0
declare -g _ERP_API_AUTH_LOADED=1

declare -g AUTH_USER=""
declare -g AUTH_ROLE=""
declare -g AUTH_TOKEN=""
declare -g AUTH_ERROR=""
declare -g AUTH_CAN_VIEW_METRICS=0
declare -g AUTH_CAN_MANAGE_STOCK=0
declare -g AUTH_AUTHORIZED_BY=""

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

api_validate_pin() {
    local pin="${1:-}"
    [[ ${#pin} -ge 4 && ${#pin} -le 20 && "${pin}" != *[[:space:]]* ]]
}

api_generate_salt() {
    printf '%s|%s|%s' "$(date +%s%N)" "${RANDOM}" "${1:-user}" | sha256sum | cut -c1-12
}

api_user_role_exists() {
    case "${1:-}" in
        admin|supervisor|vendedor) return 0 ;;
    esac
    return 1
}

api_is_admin() {
    [[ "${AUTH_ROLE:-}" == "admin" ]]
}

api_can_view_metrics() {
    api_is_admin && return 0
    [[ "${AUTH_ROLE:-}" == "supervisor" && "${AUTH_CAN_VIEW_METRICS:-0}" == "1" ]]
}

api_can_manage_stock() {
    api_is_admin && return 0
    [[ "${AUTH_ROLE:-}" == "supervisor" && "${AUTH_CAN_MANAGE_STOCK:-0}" == "1" ]]
}

api_default_route() {
    if api_can_view_metrics; then
        printf '/dashboard'
    else
        printf '/ventas'
    fi
}

api_create_user() {
    local username="${1:-}"
    local password="${2:-}"
    local role="${3:-vendedor}"
    local can_view_metrics="${4:-0}"
    local can_manage_stock="${5:-0}"
    local pin="${6:-}"

    AUTH_ERROR=""

    if [[ -z "${username}" || ! "${username}" =~ ^[A-Za-zÁÉÍÓÚáéíóúÑñ0-9._-]{3,50}$ ]]; then
        AUTH_ERROR="El usuario debe tener entre 3 y 50 caracteres válidos."
        return 1
    fi

    if [[ ${#password} -lt 6 ]]; then
        AUTH_ERROR="La contraseña debe tener al menos 6 caracteres."
        return 1
    fi

    if ! api_user_role_exists "${role}"; then
        AUTH_ERROR="Rol de usuario inválido."
        return 1
    fi

    if [[ "${role}" == "vendedor" ]]; then
        can_view_metrics=0
        can_manage_stock=0
        pin=""
    elif [[ "${role}" == "admin" ]]; then
        can_view_metrics=1
        can_manage_stock=1
    elif [[ -z "${pin}" ]]; then
        AUTH_ERROR="Un supervisor debe tener un PIN de autorización."
        return 1
    fi

    if [[ -n "${pin}" ]] && ! api_validate_pin "${pin}"; then
        AUTH_ERROR="El PIN debe tener entre 4 y 20 caracteres, sin espacios."
        return 1
    fi

    if api_user_exists "${username}"; then
        AUTH_ERROR="El nombre de usuario ya está registrado."
        return 2
    fi

    local salt hash pin_salt="" pin_hash=""
    salt=$(api_generate_salt "${username}")
    hash=$(api_hash_password "${password}" "${salt}")
    if [[ -n "${pin}" ]]; then
        pin_salt=$(api_generate_salt "pin-${username}")
        pin_hash=$(api_hash_password "${pin}" "${pin_salt}")
    fi

    db_set_context_user "${AUTH_USER:-${username}}" >/dev/null 2>&1 || true
    db_exec "INSERT INTO Users (username, password_hash, salt, role, pin_hash, pin_salt,
                               can_view_metrics, can_manage_stock, active)
             VALUES ($(db_quote "${username}"), $(db_quote "${hash}"), $(db_quote "${salt}"),
                     $(db_quote "${role}"), $([[ -n "${pin_hash}" ]] && db_quote "${pin_hash}" || printf 'NULL'),
                     $([[ -n "${pin_salt}" ]] && db_quote "${pin_salt}" || printf 'NULL'),
                     ${can_view_metrics}, ${can_manage_stock}, 1);"
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

    local row salt stored_hash username_db role can_view can_manage active
    row=$(db_query "SELECT username, password_hash, salt, role, can_view_metrics, can_manage_stock, active
                    FROM Users WHERE username = $(db_quote "${username}") LIMIT 1;")
    if [[ -z "${row}" ]]; then
        AUTH_ERROR="Credenciales inválidas."
        return 1
    fi

    IFS='|' read -r username_db stored_hash salt role can_view can_manage active <<< "${row}"
    if [[ "$(api_hash_password "${password}" "${salt}")" != "${stored_hash}" ]]; then
        AUTH_ERROR="Credenciales inválidas."
        return 1
    fi
    if [[ "${active:-0}" != "1" ]]; then
        AUTH_ERROR="La cuenta está desactivada."
        return 1
    fi

    AUTH_USER="${username_db}"
    AUTH_ROLE="${role:-vendedor}"
    AUTH_CAN_VIEW_METRICS="${can_view:-0}"
    AUTH_CAN_MANAGE_STOCK="${can_manage:-0}"
    if [[ "${AUTH_ROLE}" == "admin" ]]; then
        AUTH_CAN_VIEW_METRICS=1
        AUTH_CAN_MANAGE_STOCK=1
    fi
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

    local row username role can_view can_manage active
    row=$(db_query "SELECT s.username, u.role, u.can_view_metrics, u.can_manage_stock, u.active
                    FROM Sessions s
                    JOIN Users u ON u.username = s.username
                    WHERE s.token = $(db_quote "${token}")
                      AND s.expires_at > strftime('%s', 'now')
                    LIMIT 1;")
    [[ -z "${row}" ]] && return 1

    IFS='|' read -r username role can_view can_manage active <<< "${row}"
    [[ "${active:-0}" == "1" ]] || return 1
    AUTH_USER="${username}"
    AUTH_ROLE="${role:-vendedor}"
    AUTH_CAN_VIEW_METRICS="${can_view:-0}"
    AUTH_CAN_MANAGE_STOCK="${can_manage:-0}"
    if [[ "${AUTH_ROLE}" == "admin" ]]; then
        AUTH_CAN_VIEW_METRICS=1
        AUTH_CAN_MANAGE_STOCK=1
    fi
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

api_verify_authorization_pin() {
    local pin="${1:-}"
    AUTH_AUTHORIZED_BY=""
    AUTH_ERROR=""

    if ! api_validate_pin "${pin}"; then
        AUTH_ERROR="Ingrese un PIN de administrador o supervisor válido."
        return 1
    fi

    local rows username pin_hash pin_salt
    rows=$(db_query "SELECT username, COALESCE(pin_hash, ''), COALESCE(pin_salt, '')
                     FROM Users
                     WHERE active = 1
                       AND role IN ('admin', 'supervisor')
                       AND pin_hash IS NOT NULL
                       AND pin_hash <> '';")
    while IFS='|' read -r username pin_hash pin_salt; do
        [[ -z "${username}" || -z "${pin_hash}" || -z "${pin_salt}" ]] && continue
        if [[ "$(api_hash_password "${pin}" "${pin_salt}")" == "${pin_hash}" ]]; then
            AUTH_AUTHORIZED_BY="${username}"
            return 0
        fi
    done <<< "${rows}"

    AUTH_ERROR="PIN de autorización inválido."
    return 1
}

api_users_list_json() {
    local rows row id username role active can_view can_manage has_pin created_at item out=""
    rows=$(db_query "SELECT id, username, role, active, can_view_metrics, can_manage_stock,
                            CASE WHEN pin_hash IS NULL OR pin_hash = '' THEN 0 ELSE 1 END,
                            datetime(created_at)
                     FROM Users
                     ORDER BY CASE role WHEN 'admin' THEN 0 WHEN 'supervisor' THEN 1 ELSE 2 END,
                              username;")
    while IFS='|' read -r id username role active can_view can_manage has_pin created_at; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%s,"username":%s,"role":%s,"active":%s,"can_view_metrics":%s,"can_manage_stock":%s,"has_pin":%s,"created_at":%s}'             "$(json_number "${id}")" "$(json_quote "${username}")" "$(json_quote "${role}")"             "$(json_number "${active}")" "$(json_number "${can_view}")"             "$(json_number "${can_manage}")" "$(json_number "${has_pin}")"             "$(json_quote "${created_at}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"
    printf '{"items":[%s]}' "${out}"
}

api_user_set_pin() {
    local username="${1:-}" pin="${2:-}"
    AUTH_ERROR=""

    local role
    role=$(db_scalar "SELECT role FROM Users WHERE username = $(db_quote "${username}");" 2>/dev/null || printf '')
    [[ -n "${role}" ]] || { AUTH_ERROR="Usuario no encontrado."; return 2; }
    [[ "${role}" == "admin" || "${role}" == "supervisor" ]] || {
        AUTH_ERROR="Solo administradores y supervisores pueden tener PIN."
        return 1
    }
    if ! api_validate_pin "${pin}"; then
        AUTH_ERROR="El PIN debe tener entre 4 y 20 caracteres, sin espacios."
        return 1
    fi

    local pin_salt pin_hash
    pin_salt=$(api_generate_salt "pin-${username}")
    pin_hash=$(api_hash_password "${pin}" "${pin_salt}")
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    db_exec "UPDATE Users
                SET pin_hash = $(db_quote "${pin_hash}"),
                    pin_salt = $(db_quote "${pin_salt}")
              WHERE username = $(db_quote "${username}");"
}

api_admin_update_user() {
    local username="${1:-}" role="${2:-}" active="${3:-1}"
    local can_view="${4:-0}" can_manage="${5:-0}" pin="${6:-}"
    AUTH_ERROR=""

    local current_role
    current_role=$(db_scalar "SELECT role FROM Users WHERE username = $(db_quote "${username}");" 2>/dev/null || printf '')
    [[ -n "${current_role}" ]] || { AUTH_ERROR="Usuario no encontrado."; return 2; }

    if [[ "${current_role}" == "admin" ]]; then
        if [[ "${role}" != "admin" || "${active}" != "1" || "${can_view}" != "1" || "${can_manage}" != "1" ]]; then
            AUTH_ERROR="La cuenta administradora solo permite cambiar su PIN."
            return 1
        fi
        if [[ -n "${pin}" ]]; then
            api_user_set_pin "${username}" "${pin}" || return $?
        fi
        return 0
    fi

    if ! api_user_role_exists "${role}" || [[ "${role}" == "admin" ]]; then
        AUTH_ERROR="Solo se pueden administrar vendedores y supervisores."
        return 1
    fi
    [[ "${active}" == "1" ]] || active=0
    [[ "${can_view}" == "1" ]] || can_view=0
    [[ "${can_manage}" == "1" ]] || can_manage=0
    if [[ "${role}" == "vendedor" ]]; then
        can_view=0
        can_manage=0
        pin=""
    fi

    if [[ -n "${pin}" ]] && ! api_validate_pin "${pin}"; then
        AUTH_ERROR="El PIN debe tener entre 4 y 20 caracteres, sin espacios."
        return 1
    fi
    if [[ "${role}" == "supervisor" && -z "${pin}" ]]; then
        local existing_pin
        existing_pin=$(db_scalar "SELECT COUNT(*) FROM Users WHERE username = $(db_quote "${username}") AND pin_hash IS NOT NULL AND pin_hash <> '';" 2>/dev/null || printf '0')
        (( ${existing_pin:-0} > 0 )) || {
            AUTH_ERROR="Un supervisor debe tener un PIN de autorización."
            return 1
        }
    fi

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    local pin_sql=""
    if [[ -n "${pin}" ]]; then
        local pin_salt pin_hash
        pin_salt=$(api_generate_salt "pin-${username}")
        pin_hash=$(api_hash_password "${pin}" "${pin_salt}")
        pin_sql=", pin_hash = $(db_quote "${pin_hash}"), pin_salt = $(db_quote "${pin_salt}")"
    elif [[ "${role}" == "vendedor" ]]; then
        pin_sql=", pin_hash = NULL, pin_salt = NULL"
    fi

    if ! db_exec "UPDATE Users
                     SET role = $(db_quote "${role}"),
                         active = ${active},
                         can_view_metrics = ${can_view},
                         can_manage_stock = ${can_manage}
                         ${pin_sql}
                   WHERE username = $(db_quote "${username}");"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo actualizar el usuario.}"
        return 1
    fi
    if [[ "${active}" == "0" ]]; then
        db_exec "DELETE FROM Sessions WHERE username = $(db_quote "${username}");" >/dev/null 2>&1 || true
    fi
    return 0
}

api_user_detail_json() {
    local username="${1:-}"
    [[ -n "${username}" ]] || return 1

    local row id username_db role created_at
    row=$(db_query "SELECT id, username, role, datetime(created_at)
                    FROM Users
                    WHERE username = $(db_quote "${username}")
                    LIMIT 1;")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id username_db role created_at <<< "${row}"

    printf '{"id":%s,"username":%s,"role":%s,"created_at":%s}' \
        "$(json_number "${id}")" "$(json_quote "${username_db}")" \
        "$(json_quote "${role}")" "$(json_quote "${created_at}")"
}
