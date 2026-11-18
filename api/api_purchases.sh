#!/usr/bin/env bash

[[ -n "${_ERP_API_PURCHASES_LOADED:-}" ]] && return 0
declare -g _ERP_API_PURCHASES_LOADED=1

declare -g PURCHASE_ID=""

api_purchases_int() {
    local value="${1:-}" default="${2:-1}" min="${3:-1}" max="${4:-100}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${default}"
    value=$((10#${value}))
    (( value < min )) && value="${min}"
    (( value > max )) && value="${max}"
    printf '%s' "${value}"
}

api_purchases_json() {
    local search="${1:-}" supplier_id="${2:-0}" status="${3:-all}"
    local page per_page
    page=$(api_purchases_int "${4:-1}" 1 1 100000)
    per_page=$(api_purchases_int "${5:-8}" 8 1 50)
    [[ "${supplier_id}" =~ ^[0-9]+$ ]] || supplier_id=0

    local -a where=("1 = 1")
    if (( supplier_id > 0 )); then
        where+=("pu.supplier_id = ${supplier_id}")
    fi
    case "${status}" in
        pending|processing|finished) where+=("pu.status = '${status}'") ;;
    esac
    if [[ -n "${search}" ]]; then
        local like
        like=$(db_quote "%${search}%")
        where+=("(LOWER(COALESCE(s.name, '')) LIKE LOWER(${like}) OR LOWER(COALESCE(pu.notes, '')) LIKE LOWER(${like}) OR CAST(pu.id AS TEXT) LIKE ${like})")
    fi
    local where_sql="" clause sep=""
    for clause in "${where[@]}"; do
        where_sql+="${sep}${clause}"
        sep=" AND "
    done

    local total pages offset
    total=$(db_scalar "SELECT COUNT(*) FROM Purchases pu
                       LEFT JOIN Suppliers s ON s.id = pu.supplier_id
                       WHERE ${where_sql};" 2>/dev/null || printf '0')
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    pages=$(( (total + per_page - 1) / per_page ))
    (( page > pages && pages > 0 )) && page="${pages}"
    offset=$(( (page - 1) * per_page ))

    local rows row id timestamp supplier_name supplier_id_value total_amount notes status stock_applied items units item out=""
    rows=$(db_query "SELECT pu.id, datetime(pu.timestamp), COALESCE(s.name, 'Sin proveedor'),
                            COALESCE(pu.supplier_id, 0), pu.total_amount, COALESCE(pu.notes, ''),
                            pu.status, COALESCE(pu.stock_applied, 0), COUNT(pi.id), COALESCE(SUM(pi.quantity), 0)
                     FROM Purchases pu
                     LEFT JOIN Suppliers s ON s.id = pu.supplier_id
                     LEFT JOIN PurchaseItems pi ON pi.purchase_id = pu.id
                     WHERE ${where_sql}
                     GROUP BY pu.id
                     ORDER BY pu.timestamp DESC, pu.id DESC
                     LIMIT ${per_page} OFFSET ${offset};")

    while IFS='|' read -r id timestamp supplier_name supplier_id_value total_amount notes status stock_applied items units; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%s,"date":%s,"supplier":%s,"supplier_id":%s,"total":%s,"notes":%s,"status":%s,"stock_applied":%s,"items":%s,"units":%s}' \
            "$(json_number "${id}")" "$(json_quote "${timestamp}")" "$(json_quote "${supplier_name}")" \
            "$(json_number "${supplier_id_value}")" "$(json_number "${total_amount}")" \
            "$(json_quote "${notes}")" "$(json_quote "${status}")" "$(json_number "${stock_applied}")" \
            "$(json_number "${items}")" "$(json_number "${units}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '{"items":[%s],"total":%s,"page":%s,"per_page":%s,"pages":%s}' \
        "${out}" "${total}" "${page}" "${per_page}" "${pages}"
}

api_purchase_detail_json() {
    local purchase_id="${1:-0}"
    [[ "${purchase_id}" =~ ^[0-9]+$ ]] || return 1

    local row id timestamp supplier_id supplier contact phone email total_amount notes status stock_applied created_by
    row=$(db_query "SELECT pu.id, datetime(pu.timestamp), COALESCE(pu.supplier_id, 0),
                           COALESCE(s.name, 'Sin proveedor'), COALESCE(s.contact_person, ''),
                           COALESCE(s.phone, ''), COALESCE(s.email, ''), pu.total_amount,
                           COALESCE(pu.notes, ''), pu.status, COALESCE(pu.stock_applied, 0), pu.created_by
                    FROM Purchases pu
                    LEFT JOIN Suppliers s ON s.id = pu.supplier_id
                    WHERE pu.id = ${purchase_id};")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id timestamp supplier_id supplier contact phone email total_amount notes status stock_applied created_by <<< "${row}"

    local item_rows item_out="" iid input_id input_name unit quantity unit_cost subtotal
    local -a message_lines=()
    item_rows=$(db_query "SELECT pi.id, pi.input_id, i.name, i.unit, pi.quantity, pi.unit_cost,
                                 pi.quantity * pi.unit_cost
                          FROM PurchaseItems pi
                          JOIN Inputs i ON i.id = pi.input_id
                          WHERE pi.purchase_id = ${purchase_id}
                          ORDER BY i.name;")
    while IFS='|' read -r iid input_id input_name unit quantity unit_cost subtotal; do
        [[ -z "${iid}" ]] && continue
        item_out+="${item_out:+,}$(printf '{"id":%s,"input_id":%s,"input_name":%s,"unit":%s,"quantity":%s,"unit_cost":%s,"subtotal":%s}' \
            "$(json_number "${iid}")" "$(json_number "${input_id}")" "$(json_quote "${input_name}")" \
            "$(json_quote "${unit}")" "$(json_number "${quantity}")" "$(json_number "${unit_cost}")" \
            "$(json_number "${subtotal}")")"
        message_lines+=("$(LC_ALL=C awk -v q="${quantity}" -v u="${unit}" -v n="${input_name}" \
            'BEGIN { printf "- %.2f %s de %s", q, u, n }')")
    done <<< "${item_rows}"

    local message="Pedido a ${supplier}"
    [[ -n "${contact}" ]] && message+=" (${contact})"
    message+=$'\n'"Fecha: ${timestamp}"$'\n'
    local line
    for line in "${message_lines[@]}"; do
        message+="${line}"$'\n'
    done
    message+="Total estimado: \$$(LC_ALL=C awk -v t="${total_amount}" 'BEGIN { printf "%.2f", t }')"

    printf '{"id":%s,"date":%s,"supplier_id":%s,"supplier":%s,"contact":%s,"phone":%s,"email":%s,"total":%s,"notes":%s,"status":%s,"stock_applied":%s,"created_by":%s,"items":[%s],"message":%s}' \
        "$(json_number "${id}")" "$(json_quote "${timestamp}")" "$(json_number "${supplier_id}")" \
        "$(json_quote "${supplier}")" "$(json_quote "${contact}")" "$(json_quote "${phone}")" \
        "$(json_quote "${email}")" "$(json_number "${total_amount}")" "$(json_quote "${notes}")" \
        "$(json_quote "${status}")" "$(json_number "${stock_applied}")" "$(json_quote "${created_by}")" \
        "${item_out}" "$(json_quote "${message}")"
}

api_recommendations_json() {
    local rows row id name unit stock threshold cost supplier supplier_id contact phone email
    rows=$(db_query "SELECT i.id, i.name, i.unit, i.stock, i.min_stock_threshold, i.cost,
                            COALESCE(s.name, 'Sin proveedor'), COALESCE(s.id, 0),
                            COALESCE(s.contact_person, ''), COALESCE(s.phone, ''), COALESCE(s.email, '')
                     FROM Inputs i
                     LEFT JOIN Suppliers s ON s.id = i.supplier_id AND s.active = 1
                     WHERE i.active = 1
                     ORDER BY i.name;")

    local item out="" total_consumed last_qty last_cost last_date
    local avg_daily projected need recommended days_left
    while IFS='|' read -r id name unit stock threshold cost supplier supplier_id contact phone email; do
        [[ -z "${id}" ]] && continue
        total_consumed=$(db_scalar "SELECT COALESCE(SUM(pi.quantity), 0)
                                    FROM ProductionInputs pi
                                    JOIN ProductionBatches pb ON pb.id = pi.batch_id
                                    WHERE pi.input_id = ${id}
                                      AND date(pb.timestamp) >= date('now', '-30 days');" 2>/dev/null || printf '0')
        IFS='|' read -r last_qty last_cost last_date <<< "$(db_query "SELECT pi.quantity, pi.unit_cost, datetime(pu.timestamp)
                                                                      FROM PurchaseItems pi
                                                                      JOIN Purchases pu ON pu.id = pi.purchase_id
                                                                      WHERE pi.input_id = ${id}
                                                                      ORDER BY pu.timestamp DESC, pi.id DESC
                                                                      LIMIT 1;" 2>/dev/null)"
        last_qty="${last_qty:-0}"
        last_cost="${last_cost:-${cost}}"
        last_date="${last_date:-}"

        read -r avg_daily projected need recommended days_left <<< "$(LC_ALL=C awk \
            -v stock="${stock}" -v threshold="${threshold}" -v consumed="${total_consumed}" -v lastqty="${last_qty}" '
            BEGIN {
                avg = consumed / 30;
                projected = avg * 14;
                need = projected + threshold - stock;
                if (need < 0) need = 0;
                recommended = need > lastqty ? need : lastqty;
                if (recommended < 1) recommended = 1;
                if (avg > 0) days = stock / avg; else days = 999;
                printf "%.4f %.4f %.4f %.4f %.2f", avg, projected, need, recommended, days;
            }')"

        if ! LC_ALL=C awk -v stock="${stock}" -v threshold="${threshold}" -v projected="${projected}" \
            'BEGIN { exit !(stock <= threshold || stock <= projected) }'; then
            continue
        fi

        item=$(printf '{"id":%s,"name":%s,"unit":%s,"stock":%s,"min_threshold":%s,"cost":%s,"supplier":%s,"supplier_id":%s,"contact":%s,"phone":%s,"email":%s,"avg_daily":%s,"projected_14d":%s,"need":%s,"recommended":%s,"last_quantity":%s,"last_unit_cost":%s,"last_purchase":%s,"days_left":%s}' \
            "$(json_number "${id}")" "$(json_quote "${name}")" "$(json_quote "${unit}")" \
            "$(json_number "${stock}")" "$(json_number "${threshold}")" "$(json_number "${cost}")" \
            "$(json_quote "${supplier}")" "$(json_number "${supplier_id}")" "$(json_quote "${contact}")" \
            "$(json_quote "${phone}")" "$(json_quote "${email}")" "$(json_number "${avg_daily}")" \
            "$(json_number "${projected}")" "$(json_number "${need}")" "$(json_number "${recommended}")" \
            "$(json_number "${last_qty}")" "$(json_number "${last_cost}")" "$(json_quote "${last_date}")" \
            "$(json_number "${days_left}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '[%s]' "${out}"
}

_api_purchases_validate_items() {
    local -n _purchase_input_ids=$1
    local -n _purchase_quantities=$2
    local -n _purchase_unit_costs=$3

    (( ${#_purchase_input_ids[@]} > 0 )) || { AUTH_ERROR="El pedido de compra debe incluir al menos un insumo."; return 1; }

    local -A seen=()
    local i input_id quantity unit_cost exists
    for (( i = 0; i < ${#_purchase_input_ids[@]}; i++ )); do
        input_id="${_purchase_input_ids[$i]}"
        quantity="${_purchase_quantities[$i]:-0}"
        unit_cost="${_purchase_unit_costs[$i]:-0}"
        [[ "${input_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Insumo inválido."; return 1; }
        [[ -z "${seen[${input_id}]:-}" ]] || { AUTH_ERROR="El pedido de compra contiene insumos duplicados."; return 1; }
        seen["${input_id}"]=1
        api_inv_is_positive "${quantity}" || { AUTH_ERROR="Cantidad de compra inválida."; return 1; }
        [[ "${unit_cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Costo unitario inválido."; return 1; }
        exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE id = ${input_id} AND active = 1;" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="El insumo ${input_id} no existe o está inactivo."; return 1; }
    done
    return 0
}

_api_purchases_insert_items() {
    local purchase_id="$1"
    local -n _purchase_input_ids=$2
    local -n _purchase_quantities=$3
    local -n _purchase_unit_costs=$4

    local i input_id quantity unit_cost
    for (( i = 0; i < ${#_purchase_input_ids[@]}; i++ )); do
        input_id="${_purchase_input_ids[$i]}"
        quantity="${_purchase_quantities[$i]}"
        unit_cost="${_purchase_unit_costs[$i]}"
        if ! db_exec "INSERT INTO PurchaseItems (purchase_id, input_id, quantity, unit_cost)
                      VALUES (${purchase_id}, ${input_id}, $(api_inv_decimal "${quantity}"),
                              $(api_inv_decimal "${unit_cost}"));"; then
            AUTH_ERROR="No se pudo agregar el insumo ${input_id}. ${DB_LAST_ERROR}"
            return 1
        fi
    done
    return 0
}

api_purchase_create() {
    local supplier_id="${1:-0}" notes="${2:-}" status="${3:-pending}"
    local -n _input_ids=$4
    local -n _quantities=$5
    local -n _unit_costs=$6

    AUTH_ERROR=""
    PURCHASE_ID=""

    case "${status}" in
        pending|processing|finished) ;;
        *) AUTH_ERROR="Estado inicial de compra inválido."; return 1 ;;
    esac
    [[ "${supplier_id}" =~ ^[0-9]+$ ]] && (( supplier_id > 0 )) || { AUTH_ERROR="Proveedor inválido."; return 1; }

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Suppliers WHERE id = ${supplier_id} AND active = 1;" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El proveedor no existe o está inactivo."; return 1; }

    _api_purchases_validate_items _input_ids _quantities _unit_costs || return 1

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "INSERT INTO Purchases (timestamp, supplier_id, total_amount, notes, status, created_by, stock_applied)
                  VALUES (datetime('now', 'localtime'), ${supplier_id}, 0, $(db_quote "${notes}"),
                          'pending', $(db_quote "${AUTH_USER:-sistema}"), 0);"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo registrar el pedido de compra.}"
        tx_rollback
        return 1
    fi
    PURCHASE_ID=$(db_last_insert_id)

    if ! _api_purchases_insert_items "${PURCHASE_ID}" _input_ids _quantities _unit_costs; then
        tx_rollback
        return 1
    fi

    if [[ "${status}" != "pending" ]]; then
        if ! db_exec "UPDATE Purchases SET status = $(db_quote "${status}") WHERE id = ${PURCHASE_ID};"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudo cambiar el estado del pedido de compra.}"
            tx_rollback
            return 1
        fi
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar el pedido de compra."
        tx_rollback
        return 1
    fi
    return 0
}

api_purchase_update() {
    local purchase_id="${1:-0}" supplier_id="${2:--1}" notes="${3:-__KEEP__}" items_provided="${4:-0}"
    local -n _input_ids=$5
    local -n _quantities=$6
    local -n _unit_costs=$7

    AUTH_ERROR=""

    [[ "${purchase_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Pedido de compra inválido."; return 1; }

    local row current_supplier current_notes stock_applied
    row=$(db_query "SELECT COALESCE(supplier_id, 0), COALESCE(notes, ''), COALESCE(stock_applied, 0)
                    FROM Purchases WHERE id = ${purchase_id};")
    [[ -z "${row}" ]] && { AUTH_ERROR="El pedido de compra no existe."; return 2; }
    IFS='|' read -r current_supplier current_notes stock_applied <<< "${row}"

    [[ "${supplier_id}" == "-1" ]] && supplier_id="${current_supplier}"
    [[ "${notes}" == "__KEEP__" ]] && notes="${current_notes}"

    if (( stock_applied == 1 )); then
        if (( items_provided == 1 )); then
            AUTH_ERROR="Reabra el pedido de compra antes de modificar sus insumos."
        else
            AUTH_ERROR="Reabra el pedido de compra antes de modificarlo."
        fi
        return 1
    fi

    [[ "${supplier_id}" =~ ^[0-9]+$ ]] && (( supplier_id > 0 )) || { AUTH_ERROR="Proveedor inválido."; return 1; }
    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Suppliers WHERE id = ${supplier_id} AND active = 1;" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El proveedor no existe o está inactivo."; return 1; }
    if (( items_provided == 1 )); then
        _api_purchases_validate_items _input_ids _quantities _unit_costs || return 1
    fi

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "UPDATE Purchases
                  SET supplier_id = ${supplier_id},
                      notes = $(db_quote "${notes}")
                  WHERE id = ${purchase_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo actualizar el pedido de compra.}"
        tx_rollback
        return 1
    fi

    if (( items_provided == 1 )); then
        if ! db_exec "DELETE FROM PurchaseItems WHERE purchase_id = ${purchase_id};"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudieron reemplazar los insumos del pedido.}"
            tx_rollback
            return 1
        fi
        if ! _api_purchases_insert_items "${purchase_id}" _input_ids _quantities _unit_costs; then
            tx_rollback
            return 1
        fi
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la actualización del pedido de compra."
        tx_rollback
        return 1
    fi
    return 0
}

api_purchase_set_status() {
    local purchase_id="${1:-0}" status="${2:-}"

    AUTH_ERROR=""

    [[ "${purchase_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Pedido de compra inválido."; return 1; }
    case "${status}" in
        pending|processing|finished) ;;
        *) AUTH_ERROR="Estado de compra inválido."; return 1 ;;
    esac

    local current_status
    current_status=$(db_scalar "SELECT status FROM Purchases WHERE id = ${purchase_id};" 2>/dev/null || printf '')
    [[ -n "${current_status}" ]] || { AUTH_ERROR="El pedido de compra no existe."; return 2; }
    [[ "${status}" != "${current_status}" ]] || return 0

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    if ! db_exec "UPDATE Purchases SET status = $(db_quote "${status}") WHERE id = ${purchase_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo cambiar el estado del pedido de compra.}"
        return 1
    fi
    return 0
}

api_purchase_delete() {
    local purchase_id="${1:-0}"

    AUTH_ERROR=""

    [[ "${purchase_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Pedido de compra inválido."; return 1; }
    local stock_applied
    stock_applied=$(db_scalar "SELECT COALESCE(stock_applied, 0) FROM Purchases WHERE id = ${purchase_id};" 2>/dev/null || printf '')
    [[ -n "${stock_applied}" ]] || { AUTH_ERROR="El pedido de compra no existe."; return 2; }
    (( stock_applied == 0 )) || { AUTH_ERROR="Reabra el pedido de compra antes de eliminarlo."; return 1; }

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    if ! db_exec "DELETE FROM Purchases WHERE id = ${purchase_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo eliminar el pedido de compra.}"
        return 1
    fi
    return 0
}
