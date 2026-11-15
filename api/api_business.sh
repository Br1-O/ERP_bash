#!/usr/bin/env bash
#
# Información fiscal/comercial del negocio para facturas y comprobantes.

[[ -n "${_ERP_API_BUSINESS_LOADED:-}" ]] && return 0
declare -g _ERP_API_BUSINESS_LOADED=1

api_business_json() {
    local row id name instagram facebook phone email website updated_at
    row=$(db_query "SELECT id, name, instagram, facebook, phone, email, website, datetime(updated_at)
                    FROM BusinessInfo WHERE id = 1;")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id name instagram facebook phone email website updated_at <<< "${row}"
    printf '{"id":%s,"name":%s,"instagram":%s,"facebook":%s,"phone":%s,"email":%s,"website":%s,"updated_at":%s}' \
        "$(json_number "${id}")" "$(json_quote "${name}")" "$(json_quote "${instagram}")" \
        "$(json_quote "${facebook}")" "$(json_quote "${phone}")" "$(json_quote "${email}")" \
        "$(json_quote "${website}")" "$(json_quote "${updated_at}")"
}

api_business_update() {
    local name="${1:-}" instagram="${2:-}" facebook="${3:-}" phone="${4:-}"
    local email="${5:-}" website="${6:-}"

    AUTH_ERROR=""
    [[ -n "${name}" && ${#name} -le 100 ]] || { AUTH_ERROR="Nombre del negocio inválido."; return 1; }
    [[ ${#instagram} -le 150 ]] || { AUTH_ERROR="Instagram es demasiado largo."; return 1; }
    [[ ${#facebook} -le 150 ]] || { AUTH_ERROR="Facebook es demasiado largo."; return 1; }
    [[ ${#phone} -le 40 ]] || { AUTH_ERROR="Teléfono es demasiado largo."; return 1; }
    [[ ${#email} -le 100 ]] || { AUTH_ERROR="Email es demasiado largo."; return 1; }
    [[ -z "${email}" || "${email}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || {
        AUTH_ERROR="Email inválido."
        return 1
    }
    [[ ${#website} -le 150 ]] || { AUTH_ERROR="Sitio web es demasiado largo."; return 1; }

    if ! db_exec "INSERT INTO BusinessInfo (id, name, instagram, facebook, phone, email, website, updated_at)
                  VALUES (1, $(db_quote "${name}"), $(db_quote "${instagram}"), $(db_quote "${facebook}"),
                          $(db_quote "${phone}"), $(db_quote "${email}"), $(db_quote "${website}"),
                          datetime('now', 'localtime'))
                  ON CONFLICT(id) DO UPDATE SET
                      name = excluded.name,
                      instagram = excluded.instagram,
                      facebook = excluded.facebook,
                      phone = excluded.phone,
                      email = excluded.email,
                      website = excluded.website,
                      updated_at = excluded.updated_at;"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo guardar la información del negocio.}"
        return 1
    fi
    return 0
}
