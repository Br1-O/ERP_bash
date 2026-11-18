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
    local path="$1" component_dir component_file extension
    case "${path}" in
        /assets/app.css) http_send_file "${APP_DIR}/frontend/assets/app.css" "text/css; charset=UTF-8" ;;
        /assets/app.js) http_send_file "${APP_DIR}/frontend/assets/app.js" "application/javascript; charset=UTF-8" ;;
        /assets/components.js) http_send_file "${APP_DIR}/frontend/assets/components.js" "application/javascript; charset=UTF-8" ;;
        /assets/billing.js) http_send_file "${APP_DIR}/frontend/assets/billing.js" "application/javascript; charset=UTF-8" ;;
        /assets/insights.js) http_send_file "${APP_DIR}/frontend/assets/insights.js" "application/javascript; charset=UTF-8" ;;
        /favicon.ico) http_send 204 "image/x-icon" "" ;;
        *)
            if [[ "${path}" =~ ^/components/([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+)\.(js|css|html)$ ]]; then
                component_dir="${BASH_REMATCH[1]}"
                component_file="${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
                extension="${BASH_REMATCH[3]}"
                case "${extension}" in
                    js) http_send_file "${APP_DIR}/frontend/components/${component_dir}/${component_file}" "application/javascript; charset=UTF-8" ;;
                    css) http_send_file "${APP_DIR}/frontend/components/${component_dir}/${component_file}" "text/css; charset=UTF-8" ;;
                    html) http_send_file "${APP_DIR}/frontend/components/${component_dir}/${component_file}" "text/html; charset=UTF-8" ;;
                esac
                return 0
            fi
            return 1
            ;;
    esac
    return 0
}

current_alerts_count() {
    local count stock_expr
    stock_expr=$(_analytics_available_stock_sql "p")
    count=$(db_scalar "SELECT (SELECT COUNT(*) FROM Inputs WHERE active = 1 AND stock <= min_stock_threshold) +
                              (SELECT COUNT(*) FROM Products p WHERE p.active = 1 AND (${stock_expr}) <= p.min_production_threshold);" 2>/dev/null || printf '0')
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
        http_redirect "$(api_default_route)"
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
        http_redirect "$(api_default_route)"
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

    if ! api_can_view_metrics; then
        http_redirect "/ventas"
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

handle_insights_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    if ! api_can_view_metrics; then
        http_redirect "/ventas"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_insights_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_inventory_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    if ! api_can_manage_stock; then
        http_redirect "/ventas"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_inventory_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_purchases_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    if ! api_can_manage_stock; then
        http_redirect "/ventas"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_purchases_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_orders_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_orders_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_audit_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_audit_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_settings_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_settings_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_users_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    if ! api_is_admin; then
        http_redirect "$(api_default_route)"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_users_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_contacts_page() {
    local token="${HTTP_COOKIES[erp_session]:-}"
    if ! api_load_session "${token}"; then
        http_redirect "/login"
        return
    fi
    local alerts html
    alerts=$(current_alerts_count)
    html=$(view_contacts_page "${AUTH_USER}" "${AUTH_ROLE}" "${alerts}")
    http_send 200 "text/html; charset=UTF-8" "${html}"
}

handle_api_session_required() {
    require_api_session || return 1
    return 0
}

handle_api_admin_required() {
    handle_api_session_required || return 1
    if [[ "${AUTH_ROLE}" != "admin" ]]; then
        http_json_error "Solo un administrador puede realizar esta acción." 403
        return 1
    fi
    return 0
}

handle_api_metrics_required() {
    handle_api_session_required || return 1
    if ! api_can_view_metrics; then
        http_json_error "No tiene permiso para consultar métricas." 403
        return 1
    fi
    return 0
}

handle_api_stock_required() {
    handle_api_session_required || return 1
    if ! api_can_manage_stock; then
        http_json_error "No tiene permiso para modificar stock, productos o compras." 403
        return 1
    fi
    return 0
}

handle_api_sync_status() {
    handle_api_admin_required || return
    http_send_json "$(api_sync_status_json)" 200
}

handle_api_sync_config() {
    handle_api_admin_required || return

    if [[ "${HTTP_CONTENT_TYPE}" != *application/json* && "${HTTP_CONTENT_TYPE}" != *application/x-www-form-urlencoded* ]]; then
        http_json_error "Formato de datos no soportado." 400
        return
    fi

    local url token clear_token
    url=$(json_body_param "url" "")
    token=$(json_body_param "token" "")
    clear_token=$(json_body_param "clear_token" "0")

    if api_sync_save_config "${url}" "${token}" "${clear_token}"; then
        http_send_json "{\"ok\":true,\"message\":\"Configuración de sincronización guardada.\"}" 200
    else
        http_json_error "${SYNC_ERROR}" 400
    fi
}

handle_api_sync_push() {
    handle_api_admin_required || return

    if api_sync_push; then
        http_send_json "{\"ok\":true,\"message\":$(json_quote "${SYNC_MESSAGE}")}" 200
    else
        local status=502
        [[ "${SYNC_ERROR}" == *"Configure"* ]] && status=400
        http_json_error "${SYNC_ERROR}" "${status}"
    fi
}

handle_api_sales() {
    handle_api_session_required || return

    if [[ "${HTTP_CONTENT_TYPE}" != *application/json* && "${HTTP_CONTENT_TYPE}" != *application/x-www-form-urlencoded* ]]; then
        http_json_error "Formato de datos no soportado." 400
        return
    fi

    local customer_id payment_method discount_type discount_value
    customer_id=$(json_body_param "customer_id" "0")
    payment_method=$(json_body_param "payment_method" "Efectivo")
    discount_type=$(json_body_param "discount_type" "none")
    discount_value=$(json_body_param "discount_value" "0")

    local -a product_ids=()
    local -a quantities=()
    if ! json_body_parse_items product_ids quantities; then
        http_json_error "Debe incluir al menos un ítem de venta." 400
        return
    fi

    if api_register_sale "${customer_id}" "${payment_method}" product_ids quantities \
        "${discount_type}" "${discount_value}"; then
        http_send_json "{\"ok\":true,\"sale_id\":$(json_number "${SALE_ID}"),\"subtotal\":$(json_number "${SALE_SUBTOTAL}"),\"discount\":$(json_number "${SALE_DISCOUNT}"),\"total\":$(json_number "${SALE_TOTAL}")}" 201
    else
        local status=400
        [[ "${AUTH_ERROR}" == *"transacción"* ]] && status=500
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_production() {
    handle_api_stock_required || return

    local product_id quantity unit_cost notes
    product_id=$(json_body_param "product_id" "0")
    quantity=$(json_body_param "quantity" "0")
    unit_cost=$(json_body_param "unit_cost" "0")
    notes=$(json_body_param "notes" "")

    local -a input_ids=()
    local -a input_quantities=()
    local -a input_costs=()
    json_body_parse_input_items input_ids input_quantities input_costs || true

    if (( ${#input_ids[@]} == 0 )); then
        local single_input single_quantity
        single_input=$(json_body_param "input_id" "")
        single_quantity=$(json_body_param "input_quantity" "")
        if [[ -n "${single_input}" && -n "${single_quantity}" ]]; then
            input_ids+=("${single_input}")
            input_quantities+=("${single_quantity}")
        fi
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
    handle_api_stock_required || return
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

handle_api_customer_update() {
    local customer_id="$1"
    handle_api_session_required || return
    local name type phone email
    name=$(json_body_param "name" "")
    type=$(json_body_param "type" "Minorista")
    phone=$(json_body_param "phone" "")
    email=$(json_body_param "email" "")

    if api_update_customer "${customer_id}" "${name}" "${type}" "${phone}" "${email}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_customer_delete() {
    local customer_id="$1"
    handle_api_session_required || return
    if api_delete_customer "${customer_id}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_supplier_update() {
    local supplier_id="$1"
    handle_api_stock_required || return
    local name contact phone email address
    name=$(json_body_param "name" "")
    contact=$(json_body_param "contact" "")
    [[ -z "${contact}" ]] && contact=$(json_body_param "contact_person" "")
    phone=$(json_body_param "phone" "")
    email=$(json_body_param "email" "")
    address=$(json_body_param "address" "")

    if api_update_supplier "${supplier_id}" "${name}" "${contact}" "${phone}" "${email}" "${address}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_supplier_delete() {
    local supplier_id="$1"
    handle_api_stock_required || return
    if api_delete_supplier "${supplier_id}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_product_create() {
    handle_api_stock_required || return
    local name category_id stock threshold cost price seasonal consume is_combo
    local recipe_description steps_text
    name=$(json_body_param "name" "")
    category_id=$(json_body_param "category_id" "0")
    stock=$(json_body_param "stock" "0")
    threshold=$(json_body_param "min_threshold" "0")
    [[ "${threshold}" == "0" ]] && threshold=$(json_body_param "min_production_threshold" "0")
    cost=$(json_body_param "cost" "0")
    price=$(json_body_param "price" "0")
    seasonal=$(json_body_param "seasonal" "0")
    [[ "${seasonal}" == "0" ]] && seasonal=$(json_body_param "is_seasonal" "0")
    consume=$(json_body_param "consume_recipe" "0")
    is_combo=$(json_body_param "is_combo" "0")
    recipe_description=$(json_body_param "recipe_description" "")
    steps_text=$(json_body_param "steps_text" "")

    local -a recipe_ids=()
    local -a recipe_qtys=()
    local -a recipe_costs=()
    json_body_parse_input_items recipe_ids recipe_qtys recipe_costs || true

    local -a component_ids=()
    local -a component_qtys=()
    json_body_parse_component_items component_ids component_qtys || true

    if api_inv_create_product "${name}" "${category_id}" "${stock}" "${threshold}" "${cost}" "${price}" "${seasonal}" "${consume}" "${is_combo}" "${recipe_description}" "${steps_text}" recipe_ids recipe_qtys component_ids component_qtys; then
        http_send_json "{\"ok\":true,\"product_id\":$(json_number "${INV_PRODUCT_ID}")}" 201
    else
        local rc=$? status=400
        (( rc == 2 )) && status=409
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_product_update() {
    local product_id="$1"
    handle_api_stock_required || return
    local name category_id threshold cost price seasonal active is_combo
    local recipe_description steps_text
    name=$(json_body_param "name" "")
    category_id=$(json_body_param "category_id" "0")
    threshold=$(json_body_param "min_threshold" "0")
    [[ "${threshold}" == "0" ]] && threshold=$(json_body_param "min_production_threshold" "0")
    cost=$(json_body_param "cost" "0")
    price=$(json_body_param "price" "0")
    seasonal=$(json_body_param "seasonal" "0")
    [[ "${seasonal}" == "0" ]] && seasonal=$(json_body_param "is_seasonal" "0")
    active=$(json_body_param "active" "1")
    is_combo=$(json_body_param "is_combo" "0")
    recipe_description=$(json_body_param "recipe_description" "")
    steps_text=$(json_body_param "steps_text" "")

    local update_recipe=0 update_combo=0
    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        [[ "${HTTP_BODY}" == *\"items\"* || "${HTTP_BODY}" == *\"steps_text\"* || "${HTTP_BODY}" == *\"recipe_description\"* ]] && update_recipe=1
        [[ "${HTTP_BODY}" == *\"components\"* ]] && update_combo=1
    else
        [[ -n "$(http_param "items_count" "")" || -n "$(http_param "steps_text" "")" || -n "$(http_param "recipe_description" "")" ]] && update_recipe=1
        [[ -n "$(http_param "components_count" "")" ]] && update_combo=1
    fi

    local -a recipe_ids=()
    local -a recipe_qtys=()
    local -a recipe_costs=()
    if (( update_recipe == 1 )); then
        json_body_parse_input_items recipe_ids recipe_qtys recipe_costs || true
    fi

    local -a component_ids=()
    local -a component_qtys=()
    if (( update_combo == 1 )); then
        json_body_parse_component_items component_ids component_qtys || true
    fi

    if api_inv_update_product "${product_id}" "${name}" "${category_id}" "${threshold}" \
        "${cost}" "${price}" "${seasonal}" "${active}" "${update_recipe}" "${is_combo}" \
        "${recipe_description}" "${steps_text}" "${update_combo}" \
        recipe_ids recipe_qtys component_ids component_qtys; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status=400
        (( rc == 2 )) && status=409
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_product_delete() {
    local product_id="$1"
    handle_api_stock_required || return
    if api_inv_delete_product "${product_id}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status=400
        (( rc == 2 )) && status=404
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_product_stock() {
    local product_id="$1"
    handle_api_stock_required || return
    local quantity mode consume
    quantity=$(json_body_param "quantity" "0")
    mode=$(json_body_param "mode" "add")
    consume=$(json_body_param "consume_recipe" "0")

    local -a input_ids=()
    local -a quantities=()
    local -a unit_costs=()
    json_body_parse_input_items input_ids quantities unit_costs || true

    if api_inv_adjust_product_stock "${product_id}" "${quantity}" "${mode}" "${consume}" input_ids quantities; then
        local stock
        stock=$(db_scalar "SELECT stock FROM Products WHERE id = ${product_id};")
        http_send_json "{\"ok\":true,\"stock\":$(json_number "${stock}")}" 200
    else
        local rc=$? status=400
        (( rc == 2 )) && status=404
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_input_update() {
    local input_id="$1"
    handle_api_stock_required || return
    local name category_id unit cost supplier_id threshold active stock
    name=$(json_body_param "name" "")
    category_id=$(json_body_param "category_id" "0")
    unit=$(json_body_param "unit" "unidades")
    cost=$(json_body_param "cost" "0")
    supplier_id=$(json_body_param "supplier_id" "0")
    threshold=$(json_body_param "min_threshold" "0")
    [[ "${threshold}" == "0" ]] && threshold=$(json_body_param "min_stock_threshold" "0")
    active=$(json_body_param "active" "1")
    stock=$(json_body_param "stock" "")

    if api_inv_update_input "${input_id}" "${name}" "${category_id}" "${unit}" "${cost}" \
        "${supplier_id}" "${threshold}" "${active}" "${stock}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status=400
        (( rc == 2 )) && status=409
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_input_delete() {
    local input_id="$1"
    handle_api_stock_required || return
    if api_inv_delete_input "${input_id}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status=400
        (( rc == 2 )) && status=404
        http_json_error "${AUTH_ERROR}" "${status}"
    fi
}

handle_api_inventory_products() {
    handle_api_session_required || return
    local q category state page per_page
    q=$(http_param "q" "")
    category=$(http_param "category" "0")
    state=$(http_param "state" "active")
    page=$(http_param "page" "1")
    per_page=$(http_param "per_page" "8")
    http_send_json "$(api_inv_products_json "${q}" "${category}" "${state}" "${page}" "${per_page}")" 200
}

handle_api_inventory_inputs() {
    handle_api_session_required || return
    local q supplier state page per_page
    q=$(http_param "q" "")
    supplier=$(http_param "supplier" "0")
    state=$(http_param "state" "active")
    page=$(http_param "page" "1")
    per_page=$(http_param "per_page" "8")
    http_send_json "$(api_inv_inputs_json "${q}" "${supplier}" "${state}" "${page}" "${per_page}")" 200
}

handle_api_inventory_meta() {
    handle_api_session_required || return
    http_send_json "$(api_inv_meta_json)" 200
}

handle_api_product_detail() {
    local product_id="$1"
    handle_api_session_required || return
    local payload
    if payload=$(api_inv_product_detail_json "${product_id}"); then
        http_send_json "${payload}" 200
    else
        http_json_error "Producto no encontrado." 404
    fi
}

handle_api_input_detail() {
    local input_id="$1"
    handle_api_session_required || return
    local payload
    if payload=$(api_inv_input_detail_json "${input_id}"); then
        http_send_json "${payload}" 200
    else
        http_json_error "Insumo no encontrado." 404
    fi
}

handle_api_supplier_detail() {
    local supplier_id="$1"
    handle_api_session_required || return
    local payload
    if payload=$(api_inv_supplier_detail_json "${supplier_id}"); then
        http_send_json "${payload}" 200
    else
        http_json_error "Proveedor no encontrado." 404
    fi
}

handle_api_customer_detail() {
    local customer_id="$1"
    handle_api_session_required || return
    local payload
    if payload=$(api_customer_detail_json "${customer_id}"); then
        http_send_json "${payload}" 200
    else
        http_json_error "Cliente no encontrado." 404
    fi
}

handle_api_user_detail() {
    local username
    username=$(http_param "username" "")
    handle_api_session_required || return
    local payload
    if payload=$(api_user_detail_json "${username}"); then
        http_send_json "${payload}" 200
    else
        http_json_error "Usuario no encontrado." 404
    fi
}

handle_api_purchases_list() {
    handle_api_session_required || return
    local q supplier status page per_page
    q=$(http_param "q" "")
    supplier=$(http_param "supplier" "0")
    status=$(http_param "status" "all")
    page=$(http_param "page" "1")
    per_page=$(http_param "per_page" "8")
    http_send_json "$(api_purchases_json "${q}" "${supplier}" "${status}" "${page}" "${per_page}")" 200
}

handle_api_purchase_detail() {
    local purchase_id="$1"
    handle_api_session_required || return
    local payload
    if payload=$(api_purchase_detail_json "${purchase_id}"); then
        http_send_json "${payload}" 200
    else
        http_json_error "Compra no encontrada." 404
    fi
}

handle_api_purchase_create() {
    handle_api_stock_required || return
    local supplier_id notes status
    supplier_id=$(json_body_param "supplier_id" "0")
    notes=$(json_body_param "notes" "")
    status=$(json_body_param "status" "pending")

    local -a input_ids=()
    local -a quantities=()
    local -a unit_costs=()
    json_body_parse_input_items input_ids quantities unit_costs || true

    if api_purchase_create "${supplier_id}" "${notes}" "${status}" input_ids quantities unit_costs; then
        http_send_json "{\"ok\":true,\"purchase_id\":$(json_number "${PURCHASE_ID}")}" 201
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_api_purchase_update() {
    local purchase_id="$1"
    handle_api_stock_required || return
    local supplier_id notes
    supplier_id=$(json_body_param "supplier_id" "-1")
    notes=$(json_body_param "notes" "__KEEP__")

    local items_provided=0
    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        [[ "${HTTP_BODY}" == *\"items\"* ]] && items_provided=1
    else
        [[ -n "$(http_param "items_count" "")" ]] && items_provided=1
    fi

    local -a input_ids=()
    local -a quantities=()
    local -a unit_costs=()
    if (( items_provided == 1 )); then
        json_body_parse_input_items input_ids quantities unit_costs || true
    fi

    if api_purchase_update "${purchase_id}" "${supplier_id}" "${notes}" "${items_provided}" \
        input_ids quantities unit_costs; then
        http_send_json "{\"ok\":true,\"purchase_id\":$(json_number "${purchase_id}")}" 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_purchase_status() {
    local purchase_id="$1"
    handle_api_stock_required || return
    local status
    status=$(json_body_param "status" "")
    if api_purchase_set_status "${purchase_id}" "${status}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_purchase_delete() {
    local purchase_id="$1"
    handle_api_stock_required || return
    if api_purchase_delete "${purchase_id}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_orders_list() {
    handle_api_session_required || return
    local q status page per_page
    q=$(http_param "q" "")
    status=$(http_param "status" "all")
    page=$(http_param "page" "1")
    per_page=$(http_param "per_page" "8")
    http_send_json "$(api_orders_json "${q}" "${status}" "${page}" "${per_page}")" 200
}

handle_api_audit_list() {
    handle_api_session_required || return
    local q page per_page
    q=$(http_param "q" "")
    page=$(http_param "page" "1")
    per_page=$(http_param "per_page" "20")
    http_send_json "$(api_audit_json "${q}" "${page}" "${per_page}")" 200
}

handle_api_order_detail() {
    local order_id="$1"
    handle_api_session_required || return
    local payload
    if payload=$(api_order_detail_json "${order_id}"); then
        http_send_json "${payload}" 200
    else
        http_json_error "Registro no encontrado." 404
    fi
}

handle_api_order_create() {
    handle_api_session_required || return
    local customer_id customer_name customer_type customer_phone customer_email
    local payment_method notes discount_type discount_value status save_customer
    customer_id=$(json_body_param "customer_id" "0")
    customer_name=$(json_body_param "customer_name" "")
    customer_type=$(json_body_param "customer_type" "Minorista")
    customer_phone=$(json_body_param "customer_phone" "")
    customer_email=$(json_body_param "customer_email" "")
    payment_method=$(json_body_param "payment_method" "Efectivo")
    notes=$(json_body_param "notes" "")
    discount_type=$(json_body_param "discount_type" "none")
    discount_value=$(json_body_param "discount_value" "0")
    status=$(json_body_param "status" "pending")
    save_customer=$(json_body_param "save_customer" "1")

    local -a product_ids=()
    local -a quantities=()
    local -a unit_prices=()
    if ! json_body_parse_order_items product_ids quantities unit_prices; then
        http_json_error "El pedido debe incluir al menos un producto." 400
        return
    fi

    if api_order_create "${customer_id}" "${customer_name}" "${customer_type}" \
        "${customer_phone}" "${customer_email}" "${payment_method}" "${notes}" \
        "${discount_type}" "${discount_value}" "${status}" "${save_customer}" \
        product_ids quantities unit_prices; then
        http_send_json "{\"ok\":true,\"order_id\":$(json_number "${ORDER_ID}"),\"total\":$(json_number "${ORDER_TOTAL}")}" 201
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_order_update() {
    local order_id="$1"
    handle_api_session_required || return
    local customer_id payment_method notes discount_type discount_value status
    customer_id=$(json_body_param "customer_id" "-1")
    payment_method=$(json_body_param "payment_method" "__KEEP__")
    notes=$(json_body_param "notes" "__KEEP__")
    discount_type=$(json_body_param "discount_type" "__KEEP__")
    discount_value=$(json_body_param "discount_value" "__KEEP__")
    status=$(json_body_param "status" "__KEEP__")

    local items_provided=0
    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        [[ "${HTTP_BODY}" == *\"items\"* ]] && items_provided=1
    else
        [[ -n "$(http_param "items_count" "")" ]] && items_provided=1
    fi

    local -a product_ids=()
    local -a quantities=()
    local -a unit_prices=()
    if (( items_provided == 1 )); then
        json_body_parse_order_items product_ids quantities unit_prices || true
    fi

    if api_order_update "${order_id}" "${customer_id}" "${payment_method}" "${notes}" \
        "${discount_type}" "${discount_value}" "${status}" "${items_provided}" \
        product_ids quantities unit_prices; then
        http_send_json "{\"ok\":true,\"order_id\":$(json_number "${ORDER_ID}"),\"total\":$(json_number "${ORDER_TOTAL}")}" 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_order_status() {
    local order_id="$1"
    handle_api_session_required || return
    local status
    status=$(json_body_param "status" "")
    if api_order_set_status "${order_id}" "${status}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_order_delete() {
    local order_id="$1"
    handle_api_session_required || return
    local reason pin
    reason=$(json_body_param "reason" "")
    pin=$(json_body_param "pin" "")
    if api_order_delete "${order_id}" "${reason}" "${pin}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_sales_cancel() {
    local sale_id="$1"
    handle_api_session_required || return
    local reason pin
    reason=$(json_body_param "reason" "")
    pin=$(json_body_param "pin" "")
    if api_sales_cancel "${sale_id}" "${reason}" "${pin}"; then
        http_send_json "{\"ok\":true,\"sale_id\":$(json_number "${sale_id}"),\"authorized_by\":$(json_quote "${AUTH_AUTHORIZED_BY}")}" 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=409
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_order_cancel() {
    local order_id="$1"
    handle_api_session_required || return
    local reason pin
    reason=$(json_body_param "reason" "")
    pin=$(json_body_param "pin" "")
    if api_sales_cancel "${order_id}" "${reason}" "${pin}"; then
        http_send_json "{\"ok\":true,\"order_id\":$(json_number "${order_id}"),\"authorized_by\":$(json_quote "${AUTH_AUTHORIZED_BY}")}" 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=409
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_users_list() {
    handle_api_admin_required || return
    http_send_json "$(api_users_list_json)" 200
}

handle_api_user_create() {
    handle_api_admin_required || return
    local username password role can_view can_manage pin
    username=$(json_body_param "username" "")
    password=$(json_body_param "password" "")
    role=$(json_body_param "role" "vendedor")
    can_view=$(json_body_param "can_view_metrics" "0")
    can_manage=$(json_body_param "can_manage_stock" "0")
    pin=$(json_body_param "pin" "")

    if [[ "${role}" == "admin" ]]; then
        http_json_error "No se pueden crear cuentas administradoras desde esta pantalla." 403
        return
    fi
    if api_create_user "${username}" "${password}" "${role}" "${can_view}" "${can_manage}" "${pin}"; then
        http_send_json '{"ok":true}' 201
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=409
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_user_update() {
    local username="$1"
    handle_api_admin_required || return
    local role active can_view can_manage pin
    role=$(json_body_param "role" "vendedor")
    active=$(json_body_param "active" "1")
    can_view=$(json_body_param "can_view_metrics" "0")
    can_manage=$(json_body_param "can_manage_stock" "0")
    pin=$(json_body_param "pin" "")

    if api_admin_update_user "${username}" "${role}" "${active}" "${can_view}" "${can_manage}" "${pin}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_user_pin() {
    local username="$1"
    handle_api_admin_required || return
    local pin
    pin=$(json_body_param "pin" "")
    if api_user_set_pin "${username}" "${pin}"; then
        http_send_json '{"ok":true}' 200
    else
        local rc=$? status_code=400
        (( rc == 2 )) && status_code=404
        http_json_error "${AUTH_ERROR}" "${status_code}"
    fi
}

handle_api_business_get() {
    handle_api_session_required || return
    local payload
    if payload=$(api_business_json); then
        http_send_json "${payload}" 200
    else
        http_json_error "No se encontró la información del negocio." 404
    fi
}

handle_api_business_update() {
    handle_api_admin_required || return
    local name instagram facebook phone email website
    name=$(json_body_param "name" "")
    instagram=$(json_body_param "instagram" "")
    facebook=$(json_body_param "facebook" "")
    phone=$(json_body_param "phone" "")
    email=$(json_body_param "email" "")
    website=$(json_body_param "website" "")

    if api_business_update "${name}" "${instagram}" "${facebook}" "${phone}" "${email}" "${website}"; then
        http_send_json '{"ok":true}' 200
    else
        http_json_error "${AUTH_ERROR}" 400
    fi
}

handle_api_invoice_purchase() {
    local purchase_id="$1"
    handle_api_session_required || return
    local payload rc
    payload=$(api_invoice_purchase_json "${purchase_id}")
    rc=$?
    if (( rc == 0 )); then
        http_send_json "${payload}" 200
    elif (( rc == 2 )); then
        http_json_error "Solo se pueden facturar compras finalizadas." 409
    else
        http_json_error "Compra no encontrada." 404
    fi
}

handle_api_invoice_order() {
    local order_id="$1"
    handle_api_session_required || return
    local payload rc
    payload=$(api_invoice_order_json "${order_id}")
    rc=$?
    if (( rc == 0 )); then
        http_send_json "${payload}" 200
    elif (( rc == 2 )); then
        http_json_error "Solo se pueden facturar pedidos finalizados." 409
    else
        http_json_error "Pedido no encontrado." 404
    fi
}

handle_api_invoice_sale() {
    local sale_id="$1"
    handle_api_session_required || return
    local payload rc
    payload=$(api_invoice_sale_json "${sale_id}")
    rc=$?
    if (( rc == 0 )); then
        http_send_json "${payload}" 200
    elif (( rc == 2 )); then
        http_json_error "Solo se pueden facturar ventas finalizadas." 409
    else
        http_json_error "Venta no encontrada." 404
    fi
}

handle_api_recommendations() {
    handle_api_stock_required || return
    http_send_json "$(api_recommendations_json)" 200
}

handle_api_input_create() {
    handle_api_stock_required || return
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
    handle_api_stock_required || return
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

    if [[ "${method}" == "GET" && "${path}" =~ ^/api/products/([0-9]+)$ ]]; then
        handle_api_product_detail "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/products/([0-9]+)$ ]]; then
        handle_api_product_update "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "DELETE" && "${path}" =~ ^/api/products/([0-9]+)$ ]]; then
        handle_api_product_delete "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "POST" && "${path}" =~ ^/api/products/([0-9]+)/stock$ ]]; then
        handle_api_product_stock "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/inputs/([0-9]+)$ ]]; then
        handle_api_input_detail "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/inputs/([0-9]+)$ ]]; then
        handle_api_input_update "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "DELETE" && "${path}" =~ ^/api/inputs/([0-9]+)$ ]]; then
        handle_api_input_delete "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/suppliers/([0-9]+)$ ]]; then
        handle_api_supplier_detail "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/suppliers/([0-9]+)$ ]]; then
        handle_api_supplier_update "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "DELETE" && "${path}" =~ ^/api/suppliers/([0-9]+)$ ]]; then
        handle_api_supplier_delete "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/customers/([0-9]+)$ ]]; then
        handle_api_customer_detail "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/customers/([0-9]+)$ ]]; then
        handle_api_customer_update "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "DELETE" && "${path}" =~ ^/api/customers/([0-9]+)$ ]]; then
        handle_api_customer_delete "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" == "/api/users" ]]; then
        if [[ -n "$(http_param "username" "")" ]]; then
            handle_api_user_detail
        else
            handle_api_users_list
        fi
        return
    fi
    if [[ "${method}" == "POST" && "${path}" == "/api/users" ]]; then
        handle_api_user_create
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/purchases/([0-9]+)$ ]]; then
        handle_api_purchase_detail "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/purchases/([0-9]+)$ ]]; then
        handle_api_purchase_update "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "DELETE" && "${path}" =~ ^/api/purchases/([0-9]+)$ ]]; then
        handle_api_purchase_delete "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/purchases/([0-9]+)/status$ ]]; then
        handle_api_purchase_status "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/orders/([0-9]+)$ ]]; then
        handle_api_order_detail "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/orders/([0-9]+)$ ]]; then
        handle_api_order_update "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "DELETE" && "${path}" =~ ^/api/orders/([0-9]+)$ ]]; then
        handle_api_order_delete "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/orders/([0-9]+)/status$ ]]; then
        handle_api_order_status "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "POST" && "${path}" =~ ^/api/sales/([0-9]+)/cancel$ ]]; then
        handle_api_sales_cancel "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "POST" && "${path}" =~ ^/api/orders/([0-9]+)/cancel$ ]]; then
        handle_api_order_cancel "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/users/([A-Za-z0-9._-]+)/pin$ ]]; then
        handle_api_user_pin "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" =~ ^/api/users/([A-Za-z0-9._-]+)$ ]]; then
        handle_api_user_update "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/invoices/purchases/([0-9]+)$ ]]; then
        handle_api_invoice_purchase "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/invoices/orders/([0-9]+)$ ]]; then
        handle_api_invoice_order "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "GET" && "${path}" =~ ^/api/invoices/sales/([0-9]+)$ ]]; then
        handle_api_invoice_sale "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${method}" == "PUT" && "${path}" == "/api/business-info" ]]; then
        handle_api_business_update
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
        "GET /inteligencia")
            handle_insights_page
            ;;
        "GET /inventario")
            handle_inventory_page
            ;;
        "GET /compras")
            handle_purchases_page
            ;;
        "GET /ventas")
            handle_orders_page
            ;;
        "GET /auditoria")
            handle_audit_page
            ;;
        "GET /configuracion")
            handle_settings_page
            ;;
        "GET /contactos")
            handle_contacts_page
            ;;
        "GET /usuarios")
            handle_users_page
            ;;

        "GET /api/health")
            http_send_json "{\"ok\":true,\"database\":$(json_quote "${ERP_DB_PATH}")}" 200
            ;;
        "GET /api/dashboard")
            handle_api_metrics_required && http_send_json "$(analytics_dashboard_json)" 200
            ;;
        "GET /api/analytics/basket")
            handle_api_metrics_required && http_send_json "$(analytics_basket_full_json)" 200
            ;;
        "GET /api/sync/status")
            handle_api_sync_status
            ;;
        "POST /api/sync/config")
            handle_api_sync_config
            ;;
        "POST /api/sync/push")
            handle_api_sync_push
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
        "GET /api/inventory/products")
            handle_api_inventory_products
            ;;
        "GET /api/inventory/inputs")
            handle_api_inventory_inputs
            ;;
        "GET /api/inventory/meta")
            handle_api_inventory_meta
            ;;
        "GET /api/purchases")
            handle_api_purchases_list
            ;;
        "GET /api/orders")
            handle_api_orders_list
            ;;
        "GET /api/audit")
            handle_api_audit_list
            ;;
        "POST /api/orders")
            handle_api_order_create
            ;;
        "GET /api/business-info")
            handle_api_business_get
            ;;
        "GET /api/recommendations")
            handle_api_recommendations
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
        "POST /api/purchases")
            handle_api_purchase_create
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
db_close
exit 0
