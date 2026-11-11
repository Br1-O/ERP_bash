#!/usr/bin/env bash
#
# Router HTTP para socat.
# Se ejecuta una vez por conexión: lee la petición de stdin y escribe la
# respuesta en stdout.

set -u

ROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${ROUTER_DIR}/.." && pwd)"
export ERP_ROOT_DIR="${APP_DIR}"
export ERP_DB_PATH="${ERP_DB_PATH:-${APP_DIR}/shared/data/erp_licores.db}"

cd "${APP_DIR}" || exit 1

# shellcheck disable=SC1091
source "${APP_DIR}/config.sh"

is_api_path() {
    [[ "${1:-}" == /api/* ]]
}

assets_route() {
    case "$1" in
        /assets/app.css) http_send_file "${APP_DIR}/frontend/assets/app.css" "text/css; charset=UTF-8" ;;
        /assets/app.js) http_send_file "${APP_DIR}/frontend/assets/app.js" "application/javascript; charset=UTF-8" ;;
        /favicon.ico) http_send 204 "image/x-icon" "" ;;
        *) return 1 ;;
    esac
    return 0
}

current_alerts_count() {
    local count
    count=$(db_scalar "SELECT (SELECT COUNT(*) FROM Inputs WHERE stock <= min_stock_threshold) +
                              (SELECT COUNT(*) FROM Products WHERE active = 1 AND stock <= min_production_threshold);" 2>/dev/null || printf '0')
    [[ "${count}" =~ ^[0-9]+$ ]] || count=0
    printf '%s' "${count}"
}

require_api_session() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_send_json '{"ok":false,"error":"Sesión expirada o inválida."}' 401
        return 1
    fi
    return 0
}

handle_login_get() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if api_load_session "${token}"; then
        http_redirect "/dashboard"
        return
    fi

    local html error
    error="${HTTP_QUERY_PARAMS[error]:-}"
    html=$(view_login_page "${error}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_login_post() {
    local username password html
    username=$(json_body_param "username" "")
    password=$(json_body_param "password" "")

    if api_authenticate "${username}" "${password}"; then
        http_add_header "$(api_session_cookie "${AUTH_TOKEN}")"
        http_redirect "/dashboard"
        return
    fi

    html=$(view_login_page "${AUTH_ERROR}" "${username}")
    http_send 401 "text/html; charset=UTF-8" "${html}"
}

handle_logout() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    api_logout_session "${token}"
    http_add_header "$(api_logout_cookie)"
    http_redirect "/login"
}

handle_dashboard() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi

    local tab="${1:-resumen}"
    case "${tab}" in
        resumen|stock|catalogo|agenda) ;;
        *) tab="resumen" ;;
    esac

    local alerts data html
    alerts=$(current_alerts_count)
    data=$(analytics_dashboard_json)
    html=$(view_dashboard_page "${AUTH_USER}" "${AUTH_ROLE}" "${tab}" "${alerts}" "${data}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_api_session_required() {
    require_api_session || return 1
    return 0
}

handle_api_sales() {
    handle_api_session_required || return

    if [[ "${HTTP_CONTENT_TYPE}" != *application/json* && "${HTTP_CONTENT_TYPE}" != *application/x-www-form-urlencoded* ]]; then
        http_json_error "Formato de datos no soportado." 400
        return
    fi

    local customer_id payment_method
    customer_id=$(json_body_param "customer_id" "0")
    payment_method=$(json_body_param "payment_method" "Efectivo")

    local -a product_ids=()
    local -a quantities=()
    if ! json_body_parse_items product_ids quantities; then
        http_json_error "Debe incluir al menos un ítem de venta." 400
        return
    fi

    if api_register_sale "${customer_id}" "${payment_method}" product_ids quantities; then
        http_send_json "{\"ok\":true,\"sale_id\":$(json_number "${SALE_ID}"),\"total\":$(json_number "${SALE_TOTAL}")}" 201
    else
        local status=400
        [[ "${AUTH_ERROR}" == *"transacción"* ]] && status=500
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_production() {
    handle_api_session_required || return

    local product_id quantity unit_cost notes
    product_id=$(json_body_param "product_id" "0")
    quantity=$(json_body_param "quantity" "0")
    unit_cost=$(json_body_param "unit_cost" "0")
    notes=$(json_body_param "notes" "")

    local -a input_ids=()
    local -a input_quantities=()
    local single_input single_quantity
    single_input=$(json_body_param "input_id" "")
    single_quantity=$(json_body_param "input_quantity" "")
    if [[ -n "${single_input}" && -n "${single_quantity}" ]]; then
        input_ids+=("${single_input}")
        input_quantities+=("${single_quantity}")
    fi

    if api_register_production_batch "${product_id}" "${quantity}" "${unit_cost}" "${notes}" input_ids input_quantities; then
        http_send_json "{\"ok\":true,\"batch_id\":$(json_number "${BATCH_ID}")}" 201
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_api_customer_create() {
    handle_api_session_required || return
    local name type phone email
    name=$(json_body_param "name" "")
    type=$(json_body_param "type" "Minorista")
    phone=$(json_body_param "phone" "")
    email=$(json_body_param "email" "")

    if api_create_customer "${name}" "${type}" "${phone}" "${email}"; then
        http_send_json "{\"ok\":true,\"customer_id\":$(json_number "$(db_last_insert_id)")}" 201
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_api_supplier_create() {
    handle_api_session_required || return
    local name contact phone email address
    name=$(json_body_param "name" "")
    contact=$(json_body_param "contact" "")
    [[ -z "${contact}" ]] && contact=$(json_body_param "contact_person" "")
    phone=$(json_body_param "phone" "")
    email=$(json_body_param "email" "")
    address=$(json_body_param "address" "")

    if api_create_supplier "${name}" "${contact}" "${phone}" "${email}" "${address}"; then
        http_send_json "{\"ok\":true,\"supplier_id\":$(json_number "$(db_last_insert_id)")}" 201
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_api_product_create() {
    handle_api_session_required || return
    local name category_id stock threshold cost price seasonal
    name=$(json_body_param "name" "")
    category_id=$(json_body_param "category_id" "0")
    stock=$(json_body_param "stock" "0")
    threshold=$(json_body_param "min_threshold" "0")
    [[ "${threshold}" == "0" ]] && threshold=$(json_body_param "min_production_threshold" "0")
    cost=$(json_body_param "cost" "0")
    price=$(json_body_param "price" "0")
    seasonal=$(json_body_param "seasonal" "0")
    [[ "${seasonal}" == "0" ]] && seasonal=$(json_body_param "is_seasonal" "0")

    if api_create_product "${name}" "${category_id}" "${stock}" "${threshold}" "${cost}" "${price}" "${seasonal}"; then
        http_send_json "{\"ok\":true,\"product_id\":$(json_number "$(db_last_insert_id)")}" 201
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_api_input_create() {
    handle_api_session_required || return
    local name category_id stock unit cost supplier_id threshold
    name=$(json_body_param "name" "")
    category_id=$(json_body_param "category_id" "0")
    stock=$(json_body_param "stock" "0")
    unit=$(json_body_param "unit" "unidades")
    cost=$(json_body_param "cost" "0")
    supplier_id=$(json_body_param "supplier_id" "0")
    threshold=$(json_body_param "min_threshold" "0")
    [[ "${threshold}" == "0" ]] && threshold=$(json_body_param "min_stock_threshold" "0")

    if api_create_input "${name}" "${category_id}" "${stock}" "${unit}" "${cost}" "${supplier_id}" "${threshold}"; then
        http_send_json "{\"ok\":true,\"input_id\":$(json_number "$(db_last_insert_id)")}" 201
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_api_input_restock() {
    handle_api_session_required || return
    local input_id quantity
    input_id=$(json_body_param "input_id" "0")
    quantity=$(json_body_param "quantity" "0")

    if api_restock_input "${input_id}" "${quantity}"; then
        http_send_json '{"ok":true}' 200
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_request() {
    local method="${HTTP_METHOD^^}"
    local path="${HTTP_PATH}"

    if assets_route "${path}"; then
        return
    fi

    if ! db_singleton_init; then
        if is_api_path "${path}"; then
            http_json_error "Base de datos no disponible: ${DB_LAST_ERROR:-error desconocido}" 500
        else
            local html
            html=$(view_error_page 500 "No se pudo inicializar la base de datos: ${DB_LAST_ERROR:-error desconocido}")
            http_send 500 "text/html; charset=UTF-8" "${html}"
        fi
        return
    fi

    case "${method} ${path}" in
        "GET /") http_redirect "/dashboard" ;;
        "GET /login") handle_login_get ;;
        "POST /login") handle_login_post ;;
        "GET /logout"|"POST /logout") handle_logout ;;

        "GET /dashboard")
            handle_dashboard "$(http_param "tab" "resumen")"
            ;;
        "GET /contactos")
            handle_dashboard "agenda"
            ;;

        "GET /api/health")
            http_send_json "{\"ok\":true,\"database\":$(json_quote "${ERP_DB_PATH}")}" 200
            ;;
        "GET /api/dashboard")
            handle_api_session_required && http_send_json "$(analytics_dashboard_json)" 200
            ;;
        "GET /api/alerts")
            handle_api_session_required && http_send_json "$(analytics_alerts_json)" 200
            ;;
        "GET /api/products")
            handle_api_session_required && http_send_json "$(api_list_products_json)" 200
            ;;
        "GET /api/inputs")
            handle_api_session_required && http_send_json "$(api_list_inputs_json)" 200
            ;;
        "GET /api/contacts")
            handle_api_session_required && http_send_json "$(api_contacts_json "$(http_param "q" "")")" 200
            ;;
        "POST /api/sales")
            handle_api_sales
            ;;
        "POST /api/production")
            handle_api_production
            ;;
        "POST /api/customers")
            handle_api_customer_create
            ;;
        "POST /api/suppliers")
            handle_api_supplier_create
            ;;
        "POST /api/products")
            handle_api_product_create
            ;;
        "POST /api/inputs")
            handle_api_input_create
            ;;
        "POST /api/inputs/restock")
            handle_api_input_restock
            ;;

        "GET /api/"*)
            http_json_error "Recurso de API no encontrado." 404
            ;;
        "POST /api/"*)
            http_json_error "Recurso de API no encontrado." 404
            ;;
        *)
            if is_api_path "${path}"; then
                http_json_error "Método o ruta no permitida." 405
            else
                local html
                html=$(view_error_page 404 "La ruta ${path} no existe en este ERP.")
                http_send 404 "text/html; charset=UTF-8" "${html}"
            fi
            ;;
    esac
}

if ! http_read_request; then
    http_send 400 "text/plain; charset=UTF-8" "Petición HTTP inválida"
    exit 0
fi

handle_request
exit 0
