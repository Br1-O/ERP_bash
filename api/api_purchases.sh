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
    local search="${1:-}" supplier_id="${2:-0}"
    local page per_page
    page=$(api_purchases_int "${3:-1}" 1 1 100000)
    per_page=$(api_purchases_int "${4:-8}" 8 1 50)
    [[ "${supplier_id}" =~ ^[0-9]+$ ]] || supplier_id=0

    local -a where=("1 = 1")
    if (( supplier_id > 0 )); then
        where+=("pu.supplier_id = ${supplier_id}")
    fi
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

    local rows row id timestamp supplier_name supplier_id_value total_amount notes status items units item out=""
    rows=$(db_query "SELECT pu.id, datetime(pu.timestamp), COALESCE(s.name, 'Sin proveedor'),
                            COALESCE(pu.supplier_id, 0), pu.total_amount, COALESCE(pu.notes, ''),
                            pu.status, COUNT(pi.id), COALESCE(SUM(pi.quantity), 0)
                     FROM Purchases pu
                     LEFT JOIN Suppliers s ON s.id = pu.supplier_id
                     LEFT JOIN PurchaseItems pi ON pi.purchase_id = pu.id
                     WHERE ${where_sql}
                     GROUP BY pu.id
                     ORDER BY pu.timestamp DESC, pu.id DESC
                     LIMIT ${per_page} OFFSET ${offset};")

    while IFS='|' read -r id timestamp supplier_name supplier_id_value total_amount notes status items units; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%s,"date":%s,"supplier":%s,"supplier_id":%s,"total":%s,"notes":%s,"status":%s,"items":%s,"units":%s}' \
            "$(json_number "${id}")" "$(json_quote "${timestamp}")" "$(json_quote "${supplier_name}")" \
            "$(json_number "${supplier_id_value}")" "$(json_number "${total_amount}")" \
            "$(json_quote "${notes}")" "$(json_quote "${status}")" \
            "$(json_number "${items}")" "$(json_number "${units}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '{"items":[%s],"total":%s,"page":%s,"per_page":%s,"pages":%s}' \
        "${out}" "${total}" "${page}" "${per_page}" "${pages}"
}

api_purchase_detail_json() {
    local purchase_id="${1:-0}"
    [[ "${purchase_id}" =~ ^[0-9]+$ ]] || return 1

    local row id timestamp supplier_id supplier contact phone email total_amount notes status created_by
    row=$(db_query "SELECT pu.id, datetime(pu.timestamp), COALESCE(pu.supplier_id, 0),
                           COALESCE(s.name, 'Sin proveedor'), COALESCE(s.contact_person, ''),
                           COALESCE(s.phone, ''), COALESCE(s.email, ''), pu.total_amount,
                           COALESCE(pu.notes, ''), pu.status, pu.created_by
                    FROM Purchases pu
                    LEFT JOIN Suppliers s ON s.id = pu.supplier_id
                    WHERE pu.id = ${purchase_id};")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id timestamp supplier_id supplier contact phone email total_amount notes status created_by <<< "${row}"

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

    printf '{"id":%s,"date":%s,"supplier_id":%s,"supplier":%s,"contact":%s,"phone":%s,"email":%s,"total":%s,"notes":%s,"status":%s,"created_by":%s,"items":[%s],"message":%s}' \
        "$(json_number "${id}")" "$(json_quote "${timestamp}")" "$(json_number "${supplier_id}")" \
        "$(json_quote "${supplier}")" "$(json_quote "${contact}")" "$(json_quote "${phone}")" \
        "$(json_quote "${email}")" "$(json_number "${total_amount}")" "$(json_quote "${notes}")" \
        "$(json_quote "${status}")" "$(json_quote "${created_by}")" "${item_out}" "$(json_quote "${message}")"
}

api_recommendations_json() {
    local rows row id name unit stock threshold cost supplier supplier_id contact phone email
    rows=$(db_query "SELECT i.id, i.name, i.unit, i.stock, i.min_stock_threshold, i.cost,
                            COALESCE(s.name, 'Sin proveedor'), COALESCE(i.supplier_id, 0),
                            COALESCE(s.contact_person, ''), COALESCE(s.phone, ''), COALESCE(s.email, '')
                     FROM Inputs i
                     LEFT JOIN Suppliers s ON s.id = i.supplier_id
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

api_purchase_create() {
    local supplier_id="${1:-0}" notes="${2:-}"
    local -n _input_ids=$3
    local -n _quantities=$4
    local -n _unit_costs=$5

    AUTH_ERROR=""
    PURCHASE_ID=""

    [[ "${supplier_id}" =~ ^[0-9]+$ ]] && (( supplier_id > 0 )) || { AUTH_ERROR="Proveedor inválido."; return 1; }
    (( ${#_input_ids[@]} > 0 )) || { AUTH_ERROR="La compra debe incluir al menos un insumo."; return 1; }

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Suppliers WHERE id = ${supplier_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El proveedor no existe."; return 1; }

    local -A seen=()
    local i input_id quantity unit_cost
    for (( i = 0; i < ${#_input_ids[@]}; i++ )); do
        input_id="${_input_ids[$i]}"
        quantity="${_quantities[$i]:-0}"
        unit_cost="${_unit_costs[$i]:-0}"
        [[ "${input_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Insumo inválido."; return 1; }
        [[ -z "${seen[${input_id}]:-}" ]] || { AUTH_ERROR="La compra contiene insumos duplicados."; return 1; }
        seen["${input_id}"]=1
        api_inv_is_positive "${quantity}" || { AUTH_ERROR="Cantidad de compra inválida."; return 1; }
        [[ "${unit_cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Costo unitario inválido."; return 1; }
        exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE id = ${input_id} AND active = 1;" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="El insumo ${input_id} no existe o está inactivo."; return 1; }
    done

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "INSERT INTO Purchases (timestamp, supplier_id, total_amount, notes, status, created_by)
                  VALUES (datetime('now', 'localtime'), ${supplier_id}, 0, $(db_quote "${notes}"),
                          'Recibida', $(db_quote "${AUTH_USER:-sistema}"));"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo registrar la compra.}"
        tx_rollback
        return 1
    fi
    PURCHASE_ID=$(db_last_insert_id)

    for (( i = 0; i < ${#_input_ids[@]}; i++ )); do
        input_id="${_input_ids[$i]}"
        quantity="${_quantities[$i]}"
        unit_cost="${_unit_costs[$i]}"
        if ! db_exec "INSERT INTO PurchaseItems (purchase_id, input_id, quantity, unit_cost)
                      VALUES (${PURCHASE_ID}, ${input_id}, $(api_inv_decimal "${quantity}"),
                              $(api_inv_decimal "${unit_cost}"));"; then
            AUTH_ERROR="No se pudo agregar el insumo ${input_id}. ${DB_LAST_ERROR}"
            tx_rollback
            return 1
        fi
    done

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la compra."
        tx_rollback
        return 1
    fi
    return 0
}
