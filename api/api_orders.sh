#!/usr/bin/env bash
#
# Ventas y pedidos: listado unificado, estados, edición de líneas y stock.

[[ -n "${_ERP_API_ORDERS_LOADED:-}" ]] && return 0
declare -g _ERP_API_ORDERS_LOADED=1

declare -g ORDER_ID=""
declare -g ORDER_CUSTOMER_ID=""
declare -g ORDER_TOTAL=""

_api_orders_stage_expr() {
    local alias="${1:-s}"
    printf "COALESCE(NULLIF(%s.order_stage, ''), CASE WHEN %s.status = 'cancel' THEN 'cancel' WHEN %s.order_type = 'direct' THEN 'delivered' WHEN %s.status = 'finished' THEN 'delivered' ELSE 'pending' END)" "${alias}" "${alias}" "${alias}" "${alias}"
}

api_orders_stage_is_early() {
    case "${1:-}" in
        draft|pending|preparing) return 0 ;;
    esac
    return 1
}

api_orders_stage_is_final() {
    case "${1:-}" in
        confirmed|paid|delivered) return 0 ;;
    esac
    return 1
}

api_orders_stage_status() {
    case "${1:-}" in
        draft|pending|preparing) printf 'pending' ;;
        confirmed|paid|delivered) printf 'finished' ;;
        cancel) printf 'cancel' ;;
        *) return 1 ;;
    esac
}

api_orders_can_transition() {
    local from="${1:-}" to="${2:-}"
    [[ "${from}" == "${to}" ]] && return 0
    case "${from}" in
        draft) [[ "${to}" == "pending" || "${to}" == "preparing" || "${to}" == "confirmed" ]] ;;
        pending) [[ "${to}" == "preparing" || "${to}" == "confirmed" ]] ;;
        preparing) [[ "${to}" == "confirmed" ]] ;;
        confirmed) [[ "${to}" == "paid" || "${to}" == "delivered" ]] ;;
        paid) [[ "${to}" == "delivered" ]] ;;
        *) return 1 ;;
    esac
}

api_orders_int() {
    local value="${1:-}" default="${2:-1}" min="${3:-1}" max="${4:-100}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${default}"
    value=$((10#${value}))
    (( value < min )) && value="${min}"
    (( value > max )) && value="${max}"
    printf '%s' "${value}"
}

api_orders_json() {
    local search="${1:-}" status="${2:-all}"
    local page per_page
    page=$(api_orders_int "${3:-1}" 1 1 100000)
    per_page=$(api_orders_int "${4:-8}" 8 1 50)

    local stage_expr
    stage_expr=$(_api_orders_stage_expr "s")

    local -a where=("1 = 1")
    case "${status}" in
        draft|pending|preparing|confirmed|paid|delivered|cancel) where+=("${stage_expr} = '${status}'") ;;
        finished) where+=("s.status = 'finished'") ;;
    esac
    if [[ -n "${search}" ]]; then
        local like
        like=$(db_quote "%${search}%")
        where+=("(LOWER(COALESCE(c.name, '')) LIKE LOWER(${like}) OR LOWER(COALESCE(s.notes, '')) LIKE LOWER(${like}) OR CAST(s.id AS TEXT) LIKE ${like})")
    fi
    local where_sql="" clause sep=""
    for clause in "${where[@]}"; do
        where_sql+="${sep}${clause}"
        sep=" AND "
    done

    local total pages offset
    total=$(db_scalar "SELECT COUNT(*)
                       FROM Sales s
                       LEFT JOIN Customers c ON c.id = s.customer_id
                       WHERE ${where_sql};" 2>/dev/null || printf '0')
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    pages=$(( (total + per_page - 1) / per_page ))
    if (( pages == 0 )); then
        page=1
    elif (( page > pages )); then
        page="${pages}"
    fi
    offset=$(( (page - 1) * per_page ))

    local rows row id date customer_id customer_name total_amount subtotal discount stage_value
    local payment notes created_by items units stock_applied order_type_value stock_status
    local cancel_reason cancelled_by cancel_authorized_by cancelled_at channel event_id event_name item out=""
    rows=$(db_query "SELECT s.id, datetime(s.timestamp), COALESCE(s.customer_id, 0),
                            COALESCE(c.name, 'Consumidor final'), s.total_amount, s.subtotal_amount,
                            s.discount_amount, ${stage_expr}, s.payment_method, COALESCE(s.notes, ''),
                            s.created_by, COUNT(si.id), COALESCE(SUM(si.quantity), 0),
                            s.stock_applied, s.order_type, s.status,
                            COALESCE(s.cancel_reason, ''), COALESCE(s.cancelled_by, ''),
                            COALESCE(s.cancel_authorized_by, ''), COALESCE(datetime(s.cancelled_at), ''),
                            COALESCE(s.channel, 'LOCAL'), COALESCE(s.event_id, 0), COALESCE(e.name, '')
                     FROM Sales s
                     LEFT JOIN Customers c ON c.id = s.customer_id
                     LEFT JOIN Events e ON e.id = s.event_id
                     LEFT JOIN SaleItems si ON si.sale_id = s.id
                     WHERE ${where_sql}
                     GROUP BY s.id
                     ORDER BY s.timestamp DESC, s.id DESC
                     LIMIT ${per_page} OFFSET ${offset};")

    while IFS='|' read -r id date customer_id customer_name total_amount subtotal discount stage_value payment notes created_by items units stock_applied order_type_value stock_status cancel_reason cancelled_by cancel_authorized_by cancelled_at channel event_id event_name; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%s,"date":%s,"customer_id":%s,"customer":%s,"total":%s,"subtotal":%s,"discount":%s,"status":%s,"stock_status":%s,"payment_method":%s,"notes":%s,"created_by":%s,"items":%s,"units":%s,"stock_applied":%s,"order_type":%s,"cancel_reason":%s,"cancelled_by":%s,"cancel_authorized_by":%s,"cancelled_at":%s,"channel":%s,"event_id":%s,"event_name":%s}' \
            "$(json_number "${id}")" "$(json_quote "${date}")" "$(json_number "${customer_id}")" \
            "$(json_quote "${customer_name}")" "$(json_number "${total_amount}")" \
            "$(json_number "${subtotal}")" "$(json_number "${discount}")" \
            "$(json_quote "${stage_value}")" "$(json_quote "${stock_status}")" \
            "$(json_quote "${payment}")" "$(json_quote "${notes}")" "$(json_quote "${created_by}")" \
            "$(json_number "${items}")" "$(json_number "${units}")" "$(json_number "${stock_applied}")" \
            "$(json_quote "${order_type_value}")" "$(json_quote "${cancel_reason}")" \
            "$(json_quote "${cancelled_by}")" "$(json_quote "${cancel_authorized_by}")" \
            "$(json_quote "${cancelled_at}")" "$(json_quote "${channel}")" \
            "$(json_number "${event_id}")" "$(json_quote "${event_name}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '{"items":[%s],"total":%s,"page":%s,"per_page":%s,"pages":%s}' \
        "${out}" "${total}" "${page}" "${per_page}" "${pages}"
}

api_order_detail_json() {
    local order_id="${1:-0}"
    [[ "${order_id}" =~ ^[0-9]+$ ]] || return 1

    local stage_expr
    stage_expr=$(_api_orders_stage_expr "s")

    local row id date customer_id customer_name customer_type customer_phone customer_email
    local subtotal discount_type discount_value discount_total total payment notes stage_value
    local created_by stock_applied order_type_value stock_status cancel_reason cancelled_by
    local cancel_authorized_by cancelled_at channel event_id event_name
    row=$(db_query "SELECT s.id, datetime(s.timestamp), COALESCE(s.customer_id, 0),
                           COALESCE(c.name, 'Consumidor final'), COALESCE(c.type, ''),
                           COALESCE(c.phone, ''), COALESCE(c.email, ''),
                           s.subtotal_amount, s.discount_type, s.discount_value, s.discount_amount,
                           s.total_amount, s.payment_method, COALESCE(s.notes, ''), ${stage_expr},
                           s.created_by, s.stock_applied, s.order_type, s.status,
                           COALESCE(s.cancel_reason, ''), COALESCE(s.cancelled_by, ''),
                           COALESCE(s.cancel_authorized_by, ''), COALESCE(datetime(s.cancelled_at), ''),
                           COALESCE(s.channel, 'LOCAL'), COALESCE(s.event_id, 0), COALESCE(e.name, '')
                    FROM Sales s
                    LEFT JOIN Customers c ON c.id = s.customer_id
                    LEFT JOIN Events e ON e.id = s.event_id
                    WHERE s.id = ${order_id};")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id date customer_id customer_name customer_type customer_phone customer_email \
        subtotal discount_type discount_value discount_total total payment notes stage_value \
        created_by stock_applied order_type_value stock_status cancel_reason cancelled_by \
        cancel_authorized_by cancelled_at channel event_id event_name <<< "${row}"

    local item_rows item_out="" iid product_id product_name is_combo quantity unit_price item_total
    item_rows=$(db_query "SELECT si.id, si.product_id, p.name, p.is_combo, si.quantity,
                                 si.unit_price, si.quantity * si.unit_price
                          FROM SaleItems si
                          JOIN Products p ON p.id = si.product_id
                          WHERE si.sale_id = ${order_id}
                          ORDER BY si.id;")
    while IFS='|' read -r iid product_id product_name is_combo quantity unit_price item_total; do
        [[ -z "${iid}" ]] && continue
        item_out+="${item_out:+,}$(printf '{"id":%s,"product_id":%s,"product_name":%s,"is_combo":%s,"quantity":%s,"unit_price":%s,"subtotal":%s}' \
            "$(json_number "${iid}")" "$(json_number "${product_id}")" "$(json_quote "${product_name}")" \
            "$(json_number "${is_combo}")" "$(json_number "${quantity}")" \
            "$(json_number "${unit_price}")" "$(json_number "${item_total}")")"
    done <<< "${item_rows}"

    printf '{"id":%s,"date":%s,"customer_id":%s,"customer":%s,"customer_type":%s,"customer_phone":%s,"customer_email":%s,"subtotal":%s,"discount_type":%s,"discount_value":%s,"discount":%s,"total":%s,"payment_method":%s,"notes":%s,"status":%s,"stock_status":%s,"created_by":%s,"stock_applied":%s,"order_type":%s,"cancel_reason":%s,"cancelled_by":%s,"cancel_authorized_by":%s,"cancelled_at":%s,"channel":%s,"event_id":%s,"event_name":%s,"items":[%s]}' \
        "$(json_number "${id}")" "$(json_quote "${date}")" "$(json_number "${customer_id}")" \
        "$(json_quote "${customer_name}")" "$(json_quote "${customer_type}")" \
        "$(json_quote "${customer_phone}")" "$(json_quote "${customer_email}")" \
        "$(json_number "${subtotal}")" "$(json_quote "${discount_type}")" \
        "$(json_number "${discount_value}")" "$(json_number "${discount_total}")" \
        "$(json_number "${total}")" "$(json_quote "${payment}")" "$(json_quote "${notes}")" \
        "$(json_quote "${stage_value}")" "$(json_quote "${stock_status}")" \
        "$(json_quote "${created_by}")" "$(json_number "${stock_applied}")" \
        "$(json_quote "${order_type_value}")" "$(json_quote "${cancel_reason}")" \
        "$(json_quote "${cancelled_by}")" "$(json_quote "${cancel_authorized_by}")" \
        "$(json_quote "${cancelled_at}")" "$(json_quote "${channel}")" \
        "$(json_number "${event_id}")" "$(json_quote "${event_name}")" "${item_out}"
}

_api_orders_upsert_customer() {
    local customer_id="$1" name="$2" type="$3" phone="$4" email="$5" save="$6"
    ORDER_CUSTOMER_ID=""

    [[ "${customer_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Cliente inválido."; return 1; }
    [[ "${type}" == "Mayorista" || "${type}" == "Minorista" ]] || { AUTH_ERROR="Tipo de cliente inválido."; return 1; }
    [[ -z "${email}" || "${email}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || {
        AUTH_ERROR="Email de cliente inválido."
        return 1
    }
    [[ ${#name} -le 80 ]] || { AUTH_ERROR="Nombre de cliente inválido."; return 1; }

    if (( customer_id > 0 )); then
        local exists
        exists=$(db_scalar "SELECT COUNT(*) FROM Customers WHERE id = ${customer_id} AND active = 1;" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="El cliente no existe."; return 1; }
        if (( save == 1 )) && [[ -n "${name}" ]]; then
            if ! db_exec "UPDATE Customers
                          SET name = $(db_quote "${name}"), type = $(db_quote "${type}"),
                              phone = $(db_quote "${phone}"), email = $(db_quote "${email}")
                          WHERE id = ${customer_id};"; then
                AUTH_ERROR="${DB_LAST_ERROR:-No se pudo actualizar el cliente.}"
                return 1
            fi
        fi
        ORDER_CUSTOMER_ID="${customer_id}"
        return 0
    fi

    if (( save == 1 )) && [[ -n "${name}" ]]; then
        if ! db_exec "INSERT INTO Customers (name, type, phone, email)
                      VALUES ($(db_quote "${name}"), $(db_quote "${type}"),
                              $(db_quote "${phone}"), $(db_quote "${email}"));"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el cliente.}"
            return 1
        fi
        ORDER_CUSTOMER_ID=$(db_last_insert_id)
        return 0
    fi

    ORDER_CUSTOMER_ID="NULL"
    return 0
}

_api_orders_insert_items() {
    local order_id="$1"
    local -n _item_product_ids=$2
    local -n _item_quantities=$3
    local -n _item_unit_prices=$4

    (( ${#_item_product_ids[@]} > 0 )) || { AUTH_ERROR="El pedido debe incluir al menos un producto."; return 1; }

    local i product_id quantity price product_name product_active product_price is_combo price_cents price_db combo_components
    for (( i = 0; i < ${#_item_product_ids[@]}; i++ )); do
        product_id="${_item_product_ids[$i]}"
        quantity="${_item_quantities[$i]:-0}"
        price="${_item_unit_prices[$i]:-}"

        [[ "${product_id}" =~ ^[0-9]+$ ]] && (( product_id > 0 )) || { AUTH_ERROR="Producto inválido en el pedido."; return 1; }
        [[ "${quantity}" =~ ^[0-9]+$ ]] && (( quantity > 0 )) || { AUTH_ERROR="Cantidad inválida en el pedido."; return 1; }

        local row
        row=$(db_query "SELECT name, active, price, is_combo FROM Products WHERE id = ${product_id};")
        [[ -z "${row}" ]] && { AUTH_ERROR="El producto ${product_id} no existe."; return 1; }
        IFS='|' read -r product_name product_active product_price is_combo <<< "${row}"
        (( product_active == 1 )) || { AUTH_ERROR="El producto '${product_name}' está inactivo."; return 1; }

        if (( is_combo == 1 )); then
            combo_components=$(db_scalar "SELECT COUNT(*)
                                          FROM ComboItems ci
                                          JOIN Products cp ON cp.id = ci.component_product_id
                                          WHERE ci.combo_product_id = ${product_id} AND cp.active = 1;" 2>/dev/null || printf '0')
            (( ${combo_components:-0} > 0 )) || { AUTH_ERROR="El combo '${product_name}' no tiene componentes activos."; return 1; }
        fi

        if [[ -n "${price}" ]]; then
            price_cents=$(billing_money_to_cents "${price}") || { AUTH_ERROR="Precio inválido para '${product_name}'."; return 1; }
        else
            price_cents=$(billing_money_to_cents "${product_price}") || { AUTH_ERROR="Precio inválido para '${product_name}'."; return 1; }
        fi
        (( price_cents >= 0 )) || { AUTH_ERROR="El precio no puede ser negativo."; return 1; }
        price_db=$(billing_cents_to_decimal "${price_cents}")

        if ! db_exec "INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
                      VALUES (${order_id}, ${product_id}, ${quantity}, ${price_db});"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudo agregar '${product_name}' al pedido.}"
            return 1
        fi
    done
    return 0
}

_api_orders_recalculate() {
    local order_id="$1" discount_type="$2" discount_value="$3"
    local subtotal_raw subtotal_cents

    subtotal_raw=$(db_scalar "SELECT printf('%.2f', COALESCE(SUM(quantity * unit_price), 0))
                              FROM SaleItems WHERE sale_id = ${order_id};" 2>/dev/null || printf '0.00')
    subtotal_cents=$(billing_money_to_cents "${subtotal_raw}") || subtotal_cents=0
    if ! billing_apply_strategy "${discount_type}" "${discount_value}" "${subtotal_cents}"; then
        AUTH_ERROR="${BILLING_ERROR:-No se pudo aplicar el descuento.}"
        return 1
    fi

    local safe_subtotal safe_discount safe_total
    safe_subtotal=$(billing_cents_to_decimal "${BILLING_SUBTOTAL_CENTS}")
    safe_discount=$(billing_cents_to_decimal "${BILLING_DISCOUNT_CENTS}")
    safe_total=$(billing_cents_to_decimal "${BILLING_TOTAL_CENTS}")

    if ! db_exec "UPDATE Sales
                  SET subtotal_amount = ${safe_subtotal},
                      discount_type = $(db_quote "${discount_type}"),
                      discount_value = ${BILLING_DISCOUNT_VALUE_DB},
                      discount_amount = ${safe_discount},
                      total_amount = ${safe_total}
                  WHERE id = ${order_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudieron recalcular los totales del pedido.}"
        return 1
    fi
    ORDER_TOTAL="${safe_total}"
    return 0
}

api_order_create() {
    local customer_id="${1:-0}" customer_name="${2:-}" customer_type="${3:-Minorista}"
    local customer_phone="${4:-}" customer_email="${5:-}" payment_method="${6:-Efectivo}"
    local notes="${7:-}" discount_type="${8:-none}" discount_value="${9:-0}"
    local status="${10:-pending}" save_customer="${11:-1}"
    local -n _order_product_ids=${12}
    local -n _order_quantities=${13}
    local -n _order_unit_prices=${14}
    local event_id="${15:-0}"

    AUTH_ERROR=""
    ORDER_ID=""
    ORDER_CUSTOMER_ID=""
    ORDER_TOTAL=""

    [[ "${event_id}" =~ ^[0-9]+$ ]] || event_id=0
    if (( event_id > 0 )); then
        local event_status
        event_status=$(db_scalar "SELECT status FROM Events WHERE id = ${event_id};" 2>/dev/null || true)
        [[ "${event_status}" == "active" ]] || { AUTH_ERROR="El evento no existe o no está activo."; return 1; }
    fi

    case "${payment_method}" in
        Efectivo|Transferencia|Tarjeta) ;;
        *) AUTH_ERROR="Método de pago inválido."; return 1 ;;
    esac

    local initial_stage
    case "${status}" in
        draft|pending|preparing|confirmed|paid|delivered) initial_stage="${status}" ;;
        finished) initial_stage="delivered" ;;
        *) AUTH_ERROR="Estado inicial de pedido inválido."; return 1 ;;
    esac
    [[ "${save_customer}" == "1" ]] || save_customer=0

    local safe_event="NULL" order_channel="LOCAL"
    if (( event_id > 0 )); then
        safe_event="${event_id}"
        order_channel="FERIA"
    fi

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! _api_orders_upsert_customer "${customer_id}" "${customer_name}" "${customer_type}" \
        "${customer_phone}" "${customer_email}" "${save_customer}"; then
        tx_rollback
        return 1
    fi

    if ! db_exec "INSERT INTO Sales (timestamp, customer_id, subtotal_amount, discount_type,
                                    discount_value, discount_amount, total_amount, payment_method,
                                    status, notes, created_by, stock_applied, order_type, order_stage,
                                    event_id, channel)
                  VALUES (datetime('now', 'localtime'), ${ORDER_CUSTOMER_ID}, 0, 'none', 0, 0, 0,
                          $(db_quote "${payment_method}"), 'pending', $(db_quote "${notes}"),
                          $(db_quote "${AUTH_USER:-sistema}"), 0, 'order', $(db_quote "${initial_stage}"),
                          ${safe_event}, $(db_quote "${order_channel}"));"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el pedido.}"
        tx_rollback
        return 1
    fi
    ORDER_ID=$(db_last_insert_id)
    [[ -n "${ORDER_ID}" ]] || { AUTH_ERROR="No se obtuvo el identificador del pedido."; tx_rollback; return 1; }

    if ! _api_orders_insert_items "${ORDER_ID}" _order_product_ids _order_quantities _order_unit_prices; then
        tx_rollback
        return 1
    fi
    if ! _api_orders_recalculate "${ORDER_ID}" "${discount_type}" "${discount_value}"; then
        tx_rollback
        return 1
    fi

    if [[ "${initial_stage}" == "confirmed" || "${initial_stage}" == "paid" || "${initial_stage}" == "delivered" ]]; then
        if ! db_exec "UPDATE Sales SET status = 'finished' WHERE id = ${ORDER_ID};"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudo finalizar el pedido. Verifique el stock.}"
            tx_rollback
            return 1
        fi
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar el pedido."
        tx_rollback
        return 1
    fi
    return 0
}

api_order_update() {
    local order_id="${1:-0}" customer_id="${2:--1}" payment_method="${3:-__KEEP__}"
    local notes="${4:-__KEEP__}" discount_type="${5:-__KEEP__}" discount_value="${6:-__KEEP__}"
    local status="${7:-__KEEP__}" items_provided="${8:-0}"
    local -n _order_product_ids=${9}
    local -n _order_quantities=${10}
    local -n _order_unit_prices=${11}

    AUTH_ERROR=""
    ORDER_ID="${order_id}"
    ORDER_TOTAL=""

    [[ "${order_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Pedido inválido."; return 1; }

    local stage_expr
    stage_expr=$(_api_orders_stage_expr "s")
    local row current_customer current_payment current_notes current_discount_type
    local current_discount_value current_stage current_status stock_applied order_type
    row=$(db_query "SELECT COALESCE(s.customer_id, 0), s.payment_method, COALESCE(s.notes, ''),
                           s.discount_type, s.discount_value, ${stage_expr}, s.status,
                           s.stock_applied, s.order_type
                    FROM Sales s WHERE s.id = ${order_id};")
    [[ -z "${row}" ]] && { AUTH_ERROR="El pedido no existe."; return 2; }
    IFS='|' read -r current_customer current_payment current_notes current_discount_type \
        current_discount_value current_stage current_status stock_applied order_type <<< "${row}"
    [[ "${order_type}" == "order" ]] || { AUTH_ERROR="El registro no es un pedido de cliente."; return 2; }

    if ! api_orders_stage_is_early "${current_stage}"; then
        AUTH_ERROR="Los pedidos confirmados, pagados o entregados son inmutables. Use la anulación con motivo y PIN."
        return 1
    fi

    [[ "${customer_id}" == "-1" ]] && customer_id="${current_customer}"
    [[ "${payment_method}" == "__KEEP__" ]] && payment_method="${current_payment}"
    [[ "${notes}" == "__KEEP__" ]] && notes="${current_notes}"
    [[ "${discount_type}" == "__KEEP__" ]] && discount_type="${current_discount_type}"
    [[ "${discount_value}" == "__KEEP__" ]] && discount_value="${current_discount_value}"
    [[ "${status}" == "__KEEP__" ]] && status="${current_stage}"

    case "${payment_method}" in
        Efectivo|Transferencia|Tarjeta) ;;
        *) AUTH_ERROR="Método de pago inválido."; return 1 ;;
    esac

    local next_stage
    case "${status}" in
        cancel) AUTH_ERROR="Use la anulación con motivo y PIN."; return 1 ;;
        finished) next_stage="delivered" ;;
        draft|pending|preparing|confirmed|paid|delivered) next_stage="${status}" ;;
        *) AUTH_ERROR="Estado de pedido inválido."; return 1 ;;
    esac
    if ! api_orders_can_transition "${current_stage}" "${next_stage}"; then
        AUTH_ERROR="Transición de estado no permitida: ${current_stage} → ${next_stage}."
        return 1
    fi
    local next_status
    next_status=$(api_orders_stage_status "${next_stage}") || { AUTH_ERROR="Estado de pedido inválido."; return 1; }

    [[ "${customer_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Cliente inválido."; return 1; }
    if (( customer_id > 0 )); then
        local customer_exists
        customer_exists=$(db_scalar "SELECT COUNT(*) FROM Customers WHERE id = ${customer_id} AND active = 1;" 2>/dev/null || printf '0')
        (( ${customer_exists:-0} > 0 )) || { AUTH_ERROR="El cliente no existe."; return 1; }
    fi

    if (( items_provided == 1 )) && (( stock_applied == 1 )); then
        AUTH_ERROR="Reabra el pedido antes de modificar sus productos."
        return 1
    fi

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "UPDATE Sales
                  SET customer_id = $([[ "${customer_id}" == "0" ]] && printf 'NULL' || printf '%s' "${customer_id}"),
                      payment_method = $(db_quote "${payment_method}"),
                      notes = $(db_quote "${notes}")
                  WHERE id = ${order_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo actualizar el pedido.}"
        tx_rollback
        return 1
    fi

    if (( items_provided == 1 )); then
        if ! db_exec "DELETE FROM SaleItems WHERE sale_id = ${order_id};"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudieron reemplazar los productos del pedido.}"
            tx_rollback
            return 1
        fi
        if ! _api_orders_insert_items "${order_id}" _order_product_ids _order_quantities _order_unit_prices; then
            tx_rollback
            return 1
        fi
    fi

    if ! _api_orders_recalculate "${order_id}" "${discount_type}" "${discount_value}"; then
        tx_rollback
        return 1
    fi

    if [[ "${next_stage}" != "${current_stage}" || "${next_status}" != "${current_status}" ]]; then
        if ! db_exec "UPDATE Sales
                         SET order_stage = $(db_quote "${next_stage}"),
                             status = $(db_quote "${next_status}")
                       WHERE id = ${order_id};"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudo cambiar el estado del pedido. Verifique el stock.}"
            tx_rollback
            return 1
        fi
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la actualización del pedido."
        tx_rollback
        return 1
    fi
    return 0
}

api_order_set_status() {
    local order_id="${1:-0}" status="${2:-}"
    AUTH_ERROR=""
    ORDER_ID="${order_id}"

    [[ "${order_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Pedido inválido."; return 1; }
    case "${status}" in
        cancel) AUTH_ERROR="Use la anulación con motivo y PIN."; return 1 ;;
        finished) status="delivered" ;;
        draft|pending|preparing|confirmed|paid|delivered) ;;
        *) AUTH_ERROR="Estado de pedido inválido."; return 1 ;;
    esac

    local stage_expr
    stage_expr=$(_api_orders_stage_expr "s")
    local row order_type current_stage current_status
    row=$(db_query "SELECT s.order_type, ${stage_expr}, s.status FROM Sales s WHERE s.id = ${order_id};")
    [[ -z "${row}" ]] && { AUTH_ERROR="El pedido no existe."; return 2; }
    IFS='|' read -r order_type current_stage current_status <<< "${row}"
    [[ "${order_type}" == "order" ]] || { AUTH_ERROR="El registro no es un pedido de cliente."; return 2; }
    [[ "${status}" != "${current_stage}" ]] || return 0

    if ! api_orders_can_transition "${current_stage}" "${status}"; then
        AUTH_ERROR="Transición de estado no permitida: ${current_stage} → ${status}."
        return 1
    fi
    local next_status
    next_status=$(api_orders_stage_status "${status}") || { AUTH_ERROR="Estado de pedido inválido."; return 1; }

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    if ! db_exec "UPDATE Sales
                     SET order_stage = $(db_quote "${status}"),
                         status = $(db_quote "${next_status}")
                   WHERE id = ${order_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo cambiar el estado del pedido. Verifique el stock.}"
        return 1
    fi
    return 0
}

api_order_delete() {
    local order_id="${1:-0}" reason="${2:-}" pin="${3:-}"
    AUTH_ERROR=""

    [[ "${order_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Pedido inválido."; return 1; }
    local stage_expr
    stage_expr=$(_api_orders_stage_expr "s")
    local row order_type stage_value
    row=$(db_query "SELECT s.order_type, ${stage_expr} FROM Sales s WHERE s.id = ${order_id};")
    [[ -z "${row}" ]] && { AUTH_ERROR="El pedido no existe."; return 2; }
    IFS='|' read -r order_type stage_value <<< "${row}"
    [[ "${order_type}" == "order" ]] || { AUTH_ERROR="El registro no es un pedido de cliente."; return 2; }
    api_orders_stage_is_early "${stage_value}" || {
        AUTH_ERROR="Solo los pedidos en borrador, pendiente o en preparación pueden eliminarse. Use la anulación con motivo y PIN."
        return 1
    }

    api_sales_cancel "${order_id}" "${reason}" "${pin}"
}
