#!/usr/bin/env bash

[[ -n "${_ERP_API_EVENTS_LOADED:-}" ]] && return 0
declare -g _ERP_API_EVENTS_LOADED=1

declare -g EVENT_ID=""
declare -g EVENT_REVENUE=""
declare -g EVENT_COGS=""
declare -g EVENT_LOSS=""
declare -g EVENT_NET_PROFIT=""
declare -g EVENT_BACKUP_PATH=""

api_events_int() {
    local value="${1:-}" default="${2:-1}" min="${3:-1}" max="${4:-100}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${default}"
    value=$((10#${value}))
    (( value < min )) && value="${min}"
    (( value > max )) && value="${max}"
    printf '%s' "${value}"
}

api_events_date_valid() {
    local value="${1:-}"
    [[ "${value}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    [[ "$(db_scalar "SELECT date($(db_quote "${value}"));" 2>/dev/null || true)" == "${value}" ]]
}

api_events_product_available_stock() {
    local event_id="${1:-0}" product_id="${2:-0}"
    [[ "${event_id}" =~ ^[0-9]+$ && "${product_id}" =~ ^[0-9]+$ ]] || { printf '0'; return 0; }
    db_scalar "SELECT CASE WHEN p.is_combo = 1 THEN COALESCE((
                           SELECT MIN(CAST((es.allocated_qty - es.sold_qty - es.loss_qty - es.returned_qty) / ci.quantity AS INTEGER))
                           FROM ComboItems ci
                           JOIN EventStock es ON es.event_id = ${event_id}
                                             AND es.product_id = ci.component_product_id
                           WHERE ci.combo_product_id = p.id
                       ), 0)
                       ELSE COALESCE((
                           SELECT MAX(0, es.allocated_qty - es.sold_qty - es.loss_qty - es.returned_qty)
                           FROM EventStock es
                           WHERE es.event_id = ${event_id} AND es.product_id = p.id
                       ), 0) END
               FROM Products p WHERE p.id = ${product_id};" 2>/dev/null || printf '0'
}

api_events_status_label() {
    case "${1:-}" in
        active) printf 'Activo' ;;
        closed) printf 'Cerrado' ;;
        cancelled) printf 'Cancelado' ;;
        *) printf '%s' "${1:-}" ;;
    esac
}

_api_events_aggregate_items() {
    local -n _event_ids_ref=$1
    local -n _event_qtys_ref=$2
    local -n _event_map_ref=$3

    _event_map_ref=()
    local i product_id quantity
    for (( i = 0; i < ${#_event_ids_ref[@]}; i++ )); do
        product_id="${_event_ids_ref[$i]}"
        quantity="${_event_qtys_ref[$i]:-0}"
        [[ "${product_id}" =~ ^[0-9]+$ ]] && (( product_id > 0 )) || return 1
        [[ "${quantity}" =~ ^[0-9]+$ ]] && (( quantity > 0 )) || return 1
        _event_map_ref["${product_id}"]=$(( ${_event_map_ref[${product_id}]:-0} + quantity ))
    done
    (( ${#_event_map_ref[@]} > 0 ))
}

_api_events_validate_product() {
    local product_id="$1" quantity="$2"
    local row name stock cost active is_combo
    row=$(db_query "SELECT name, stock, cost, active, is_combo FROM Products WHERE id = ${product_id};")
    [[ -n "${row}" ]] || { AUTH_ERROR="El producto ${product_id} no existe."; return 1; }
    IFS='|' read -r name stock cost active is_combo <<< "${row}"
    (( active == 1 )) || { AUTH_ERROR="El producto '${name}' está inactivo."; return 1; }
    (( is_combo == 0 )) || { AUTH_ERROR="El combo '${name}' no puede asignarse directamente a un evento."; return 1; }
    (( stock >= quantity )) || { AUTH_ERROR="Stock insuficiente para '${name}' (disponible: ${stock})."; return 1; }
    printf '%s' "${cost}"
}

_api_events_financials() {
    local event_id="$1"
    local row revenue cogs loss net sold loss_units
    row=$(db_query "SELECT
        CAST(ROUND(COALESCE((
            SELECT SUM(s.total_amount)
            FROM Sales s
            WHERE s.event_id = ${event_id}
              AND s.status = 'finished'
              AND (s.order_type = 'direct' OR s.order_stage IN ('paid', 'delivered'))
        ), 0) * 100) AS INTEGER),
        CAST(ROUND(COALESCE((
            SELECT SUM(es.sold_qty * es.unit_cost_snapshot)
            FROM EventStock es WHERE es.event_id = ${event_id}
        ), 0) * 100) AS INTEGER),
        CAST(ROUND(COALESCE((
            SELECT SUM(es.loss_qty * es.unit_cost_snapshot)
            FROM EventStock es WHERE es.event_id = ${event_id}
        ), 0) * 100) AS INTEGER),
        COALESCE((SELECT SUM(es.sold_qty) FROM EventStock es WHERE es.event_id = ${event_id}), 0),
        COALESCE((SELECT SUM(es.loss_qty) FROM EventStock es WHERE es.event_id = ${event_id}), 0);")
    IFS='|' read -r revenue cogs loss sold loss_units <<< "${row}"
    net=$(( revenue - cogs - loss ))
    printf '%s|%s|%s|%s|%s|%s' "${revenue}" "${cogs}" "${loss}" "${net}" "${sold}" "${loss_units}"
}

api_events_backup_database() {
    local destination="${1:-}"
    EVENT_BACKUP_PATH=""
    if [[ -z "${destination}" ]]; then
        destination="${ERP_ROOT_DIR:-.}/shared/data/backups/erp_licores_$(date +%Y%m%d_%H%M%S).db"
    fi
    [[ "${destination}" != *$'\n'* && "${destination}" != *$'\r'* ]] || {
        AUTH_ERROR="La ruta de respaldo contiene caracteres inválidos."
        return 1
    }
    mkdir -p "$(dirname "${destination}")" || {
        AUTH_ERROR="No se pudo crear el directorio de respaldo."
        return 1
    }
    [[ -e "${destination}" ]] && {
        AUTH_ERROR="El archivo de respaldo ya existe."
        return 1
    }
    if ! db_exec "VACUUM INTO $(db_quote "${destination}");"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo generar el respaldo.}"
        return 1
    fi
    EVENT_BACKUP_PATH="${destination}"
    return 0
}

api_events_create() {
    local name="${1:-}" location="${2:-}" start_date="${3:-}" end_date="${4:-}" notes="${5:-}"
    local -n _create_product_ids=$6
    local -n _create_quantities=$7

    AUTH_ERROR=""
    EVENT_ID=""

    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    [[ ${#name} -ge 1 && ${#name} -le 100 ]] || { AUTH_ERROR="El nombre del evento debe tener entre 1 y 100 caracteres."; return 1; }
    [[ ${#location} -le 150 ]] || { AUTH_ERROR="La ubicación no puede superar 150 caracteres."; return 1; }
    [[ ${#notes} -le 1000 ]] || { AUTH_ERROR="Las notas no pueden superar 1000 caracteres."; return 1; }
    api_events_date_valid "${start_date}" || { AUTH_ERROR="Fecha de inicio inválida."; return 1; }
    if [[ -n "${end_date}" ]]; then
        api_events_date_valid "${end_date}" || { AUTH_ERROR="Fecha de fin inválida."; return 1; }
        [[ "${end_date}" > "${start_date}" || "${end_date}" == "${start_date}" ]] || { AUTH_ERROR="La fecha de fin no puede ser anterior al inicio."; return 1; }
    fi

    local -A item_quantities=()
    _api_events_aggregate_items _create_product_ids _create_quantities item_quantities || {
        AUTH_ERROR="Debe incluir productos y cantidades válidas."
        return 1
    }

    local product_id quantity cost
    local -A costs=()
    for product_id in "${!item_quantities[@]}"; do
        quantity="${item_quantities[${product_id}]}"
        cost=$(_api_events_validate_product "${product_id}" "${quantity}") || return 1
        costs["${product_id}"]="${cost}"
    done

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "INSERT INTO Events (name, location, start_date, end_date, notes, created_by)
                  VALUES ($(db_quote "${name}"), $(db_quote "${location}"),
                          $(db_quote "${start_date}"),
                          $([[ -n "${end_date}" ]] && db_quote "${end_date}" || printf 'NULL'),
                          $(db_quote "${notes}"), $(db_quote "${AUTH_USER:-sistema}"));"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el evento.}"
        tx_rollback
        return 1
    fi
    EVENT_ID=$(db_last_insert_id)
    [[ -n "${EVENT_ID}" ]] || { AUTH_ERROR="No se obtuvo el identificador del evento."; tx_rollback; return 1; }

    for product_id in "${!item_quantities[@]}"; do
        quantity="${item_quantities[${product_id}]}"
        if ! db_exec "INSERT INTO EventStock (event_id, product_id, allocated_qty, unit_cost_snapshot)
                      VALUES (${EVENT_ID}, ${product_id}, ${quantity}, ${costs[${product_id}]});"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudo asignar stock al evento.}"
            tx_rollback
            return 1
        fi
    done

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar el evento."
        tx_rollback
        return 1
    fi
    return 0
}

api_events_add_stock() {
    local event_id="${1:-0}"
    local -n _add_product_ids=$2
    local -n _add_quantities=$3

    AUTH_ERROR=""
    EVENT_ID="${event_id}"
    [[ "${event_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Evento inválido."; return 1; }
    [[ "$(db_scalar "SELECT status FROM Events WHERE id = ${event_id};" 2>/dev/null || true)" == "active" ]] || {
        AUTH_ERROR="El evento no existe o no está activo."
        return 1
    }

    local -A item_quantities=()
    _api_events_aggregate_items _add_product_ids _add_quantities item_quantities || {
        AUTH_ERROR="Debe incluir productos y cantidades válidas."
        return 1
    }

    local product_id quantity cost allocated
    local -A costs=()
    for product_id in "${!item_quantities[@]}"; do
        quantity="${item_quantities[${product_id}]}"
        allocated=$(db_scalar "SELECT COALESCE(allocated_qty, 0) FROM EventStock
                               WHERE event_id = ${event_id} AND product_id = ${product_id};" 2>/dev/null || printf '0')
        if [[ "${allocated}" =~ ^[0-9]+$ ]] && (( allocated > 0 )); then
            cost=$(db_scalar "SELECT COALESCE(unit_cost_snapshot, 0) FROM EventStock
                              WHERE event_id = ${event_id} AND product_id = ${product_id};" 2>/dev/null || printf '0')
            local row name stock active is_combo
            row=$(db_query "SELECT name, stock, active, is_combo FROM Products WHERE id = ${product_id};")
            [[ -n "${row}" ]] || { AUTH_ERROR="El producto ${product_id} no existe."; return 1; }
            IFS='|' read -r name stock active is_combo <<< "${row}"
            (( active == 1 )) || { AUTH_ERROR="El producto '${name}' está inactivo."; return 1; }
            (( is_combo == 0 )) || { AUTH_ERROR="El combo '${name}' no puede asignarse directamente a un evento."; return 1; }
            (( stock >= quantity )) || { AUTH_ERROR="Stock insuficiente para '${name}' (disponible: ${stock})."; return 1; }
        else
            cost=$(_api_events_validate_product "${product_id}" "${quantity}") || return 1
        fi
        costs["${product_id}"]="${cost}"
    done

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    for product_id in "${!item_quantities[@]}"; do
        quantity="${item_quantities[${product_id}]}"
        if ! db_exec "INSERT INTO EventStock (event_id, product_id, allocated_qty, unit_cost_snapshot)
                      VALUES (${event_id}, ${product_id}, ${quantity}, ${costs[${product_id}]})
                      ON CONFLICT(event_id, product_id) DO UPDATE SET
                          allocated_qty = EventStock.allocated_qty + excluded.allocated_qty,
                          updated_at = CURRENT_TIMESTAMP;"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudo ampliar el stock del evento.}"
            tx_rollback
            return 1
        fi
    done

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la ampliación de stock."
        tx_rollback
        return 1
    fi
    return 0
}

api_events_close() {
    local event_id="${1:-0}"
    local -n _loss_product_ids=$2
    local -n _loss_quantities=$3

    AUTH_ERROR=""
    EVENT_ID="${event_id}"
    EVENT_REVENUE=""
    EVENT_COGS=""
    EVENT_LOSS=""
    EVENT_NET_PROFIT=""

    [[ "${event_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Evento inválido."; return 1; }
    [[ "$(db_scalar "SELECT status FROM Events WHERE id = ${event_id};" 2>/dev/null || true)" == "active" ]] || {
        AUTH_ERROR="El evento no existe o no está activo."
        return 1
    }

    local -A losses=()
    local i product_id quantity row allocated sold returned available
    for (( i = 0; i < ${#_loss_product_ids[@]}; i++ )); do
        product_id="${_loss_product_ids[$i]}"
        quantity="${_loss_quantities[$i]:-0}"
        [[ "${product_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Producto de pérdida inválido."; return 1; }
        [[ "${quantity}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Cantidad de pérdida inválida."; return 1; }
        (( quantity > 0 )) || continue
        losses["${product_id}"]=$(( ${losses[${product_id}]:-0} + quantity ))
    done

    for product_id in "${!losses[@]}"; do
        row=$(db_query "SELECT allocated_qty, sold_qty, returned_qty FROM EventStock
                        WHERE event_id = ${event_id} AND product_id = ${product_id};")
        [[ -n "${row}" ]] || { AUTH_ERROR="El producto ${product_id} no pertenece al evento."; return 1; }
        IFS='|' read -r allocated sold returned <<< "${row}"
        available=$(( allocated - sold - returned ))
        (( losses[${product_id}] <= available )) || {
            AUTH_ERROR="Las pérdidas del producto ${product_id} superan el stock disponible (${available})."
            return 1
        }
    done

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    for product_id in "${!losses[@]}"; do
        if ! db_exec "UPDATE EventStock
                         SET loss_qty = loss_qty + ${losses[${product_id}]},
                             updated_at = CURRENT_TIMESTAMP
                       WHERE event_id = ${event_id} AND product_id = ${product_id};"; then
            AUTH_ERROR="${DB_LAST_ERROR:-No se pudieron registrar las pérdidas.}"
            tx_rollback
            return 1
        fi
    done

    local financials revenue_cents cogs_cents loss_cents net_cents sold_units loss_units
    financials=$(_api_events_financials "${event_id}")
    IFS='|' read -r revenue_cents cogs_cents loss_cents net_cents sold_units loss_units <<< "${financials}"

    if ! db_exec "UPDATE Events
                     SET total_revenue_cents = ${revenue_cents},
                         total_cogs_cents = ${cogs_cents},
                         total_loss_cents = ${loss_cents},
                         net_profit_cents = ${net_cents},
                         status = 'closed',
                         closed_by = $(db_quote "${AUTH_USER:-sistema}"),
                         closed_at = datetime('now', 'localtime')
                   WHERE id = ${event_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo cerrar el evento.}"
        tx_rollback
        return 1
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar el cierre del evento."
        tx_rollback
        return 1
    fi

    EVENT_REVENUE=$(billing_cents_to_decimal "${revenue_cents}")
    EVENT_COGS=$(billing_cents_to_decimal "${cogs_cents}")
    EVENT_LOSS=$(billing_cents_to_decimal "${loss_cents}")
    EVENT_NET_PROFIT=$(billing_cents_to_decimal "${net_cents}")
    return 0
}

api_events_cancel() {
    local event_id="${1:-0}"
    AUTH_ERROR=""
    EVENT_ID="${event_id}"
    [[ "${event_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Evento inválido."; return 1; }
    [[ "$(db_scalar "SELECT status FROM Events WHERE id = ${event_id};" 2>/dev/null || true)" == "active" ]] || {
        AUTH_ERROR="El evento no existe o no está activo."
        return 1
    }

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "UPDATE Events
                     SET status = 'cancelled',
                         closed_by = $(db_quote "${AUTH_USER:-sistema}"),
                         closed_at = datetime('now', 'localtime')
                   WHERE id = ${event_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo cancelar el evento.}"
        tx_rollback
        return 1
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la cancelación del evento."
        tx_rollback
        return 1
    fi
    return 0
}

api_events_list_json() {
    local search="${1:-}" status="${2:-all}" page per_page
    page=$(api_events_int "${3:-1}" 1 1 100000)
    per_page=$(api_events_int "${4:-10}" 10 1 50)
    local date_from="${5:-}" date_to="${6:-}"

    case "${status}" in
        active|closed|cancelled|all) ;;
        *) status="all" ;;
    esac

    local -a where=("1 = 1")
    [[ "${status}" != "all" ]] && where+=("e.status = $(db_quote "${status}")")
    if [[ -n "${date_from}" ]] && api_events_date_valid "${date_from}"; then
        where+=("date(e.start_date) >= date($(db_quote "${date_from}"))")
    fi
    if [[ -n "${date_to}" ]] && api_events_date_valid "${date_to}"; then
        where+=("date(e.start_date) <= date($(db_quote "${date_to}"))")
    fi
    if [[ -n "${search}" ]]; then
        local like
        like=$(db_quote "%${search}%")
        where+=("(LOWER(e.name) LIKE LOWER(${like}) OR LOWER(e.location) LIKE LOWER(${like}) OR LOWER(e.notes) LIKE LOWER(${like}))")
    fi
    local where_sql="" clause sep=""
    for clause in "${where[@]}"; do
        where_sql+="${sep}${clause}"
        sep=" AND "
    done

    local total pages offset
    total=$(db_scalar "SELECT COUNT(*) FROM Events e WHERE ${where_sql};" 2>/dev/null || printf '0')
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    pages=$(( (total + per_page - 1) / per_page ))
    (( pages == 0 )) && page=1
    (( page > pages && pages > 0 )) && page="${pages}"
    offset=$(( (page - 1) * per_page ))

    local rows row id name location start_date end_date event_status notes created_by closed_by
    local created_at closed_at revenue_cents cogs_cents loss_cents net_cents
    local allocated sold lost returned item out=""
    rows=$(db_query "SELECT e.id, e.name, e.location, e.start_date, COALESCE(e.end_date, ''),
                            e.status, e.notes, e.created_by, COALESCE(e.closed_by, ''),
                            datetime(e.created_at), COALESCE(datetime(e.closed_at), ''),
                            e.total_revenue_cents, e.total_cogs_cents, e.total_loss_cents,
                            e.net_profit_cents,
                            COALESCE(SUM(es.allocated_qty), 0), COALESCE(SUM(es.sold_qty), 0),
                            COALESCE(SUM(es.loss_qty), 0), COALESCE(SUM(es.returned_qty), 0)
                     FROM Events e
                     LEFT JOIN EventStock es ON es.event_id = e.id
                     WHERE ${where_sql}
                     GROUP BY e.id
                     ORDER BY CASE e.status WHEN 'active' THEN 0 ELSE 1 END, e.start_date DESC, e.id DESC
                     LIMIT ${per_page} OFFSET ${offset};")

    local financials sold_units_live loss_units_live
    while IFS='|' read -r id name location start_date end_date event_status notes created_by closed_by \
        created_at closed_at revenue_cents cogs_cents loss_cents net_cents allocated sold lost returned; do
        [[ -z "${id}" ]] && continue
        if [[ "${event_status}" == "active" ]]; then
            financials=$(_api_events_financials "${id}")
            IFS='|' read -r revenue_cents cogs_cents loss_cents net_cents sold_units_live loss_units_live <<< "${financials}"
        fi
        item=$(printf '{"id":%s,"name":%s,"location":%s,"start_date":%s,"end_date":%s,"status":%s,"status_label":%s,"notes":%s,"created_by":%s,"closed_by":%s,"created_at":%s,"closed_at":%s,"revenue":%s,"cogs":%s,"loss":%s,"net_profit":%s,"allocated_units":%s,"sold_units":%s,"loss_units":%s,"returned_units":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${location}")" \
            "$(json_quote "${start_date}")" "$(json_quote "${end_date}")" \
            "$(json_quote "${event_status}")" "$(json_quote "$(api_events_status_label "${event_status}")")" \
            "$(json_quote "${notes}")" "$(json_quote "${created_by}")" "$(json_quote "${closed_by}")" \
            "$(json_quote "${created_at}")" "$(json_quote "${closed_at}")" \
            "$(json_number "$(billing_cents_to_decimal "${revenue_cents}")")" \
            "$(json_number "$(billing_cents_to_decimal "${cogs_cents}")")" \
            "$(json_number "$(billing_cents_to_decimal "${loss_cents}")")" \
            "$(json_number "$(billing_cents_to_decimal "${net_cents}")")" \
            "$(json_number "${allocated}")" "$(json_number "${sold}")" \
            "$(json_number "${lost}")" "$(json_number "${returned}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '{"items":[%s],"total":%s,"page":%s,"per_page":%s,"pages":%s}' \
        "${out}" "${total}" "${page}" "${per_page}" "${pages}"
}

api_events_active_json() {
    local rows row id name location start_date end_date allocated sold item out=""
    rows=$(db_query "SELECT e.id, e.name, e.location, e.start_date, COALESCE(e.end_date, ''),
                            COALESCE(SUM(es.allocated_qty), 0), COALESCE(SUM(es.sold_qty), 0)
                     FROM Events e
                     LEFT JOIN EventStock es ON es.event_id = e.id
                     WHERE e.status = 'active'
                     GROUP BY e.id
                     ORDER BY e.start_date DESC, e.id DESC;")
    while IFS='|' read -r id name location start_date end_date allocated sold; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%s,"name":%s,"location":%s,"start_date":%s,"end_date":%s,"allocated_units":%s,"sold_units":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${location}")" \
            "$(json_quote "${start_date}")" "$(json_quote "${end_date}")" \
            "$(json_number "${allocated}")" "$(json_number "${sold}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"
    printf '[%s]' "${out}"
}

api_events_detail_json() {
    local event_id="${1:-0}"
    [[ "${event_id}" =~ ^[0-9]+$ ]] || return 1

    local row id name location start_date end_date status notes created_by closed_by
    local created_at closed_at revenue_cents cogs_cents loss_cents net_cents
    row=$(db_query "SELECT id, name, location, start_date, COALESCE(end_date, ''), status, notes,
                           created_by, COALESCE(closed_by, ''), datetime(created_at),
                           COALESCE(datetime(closed_at), ''), total_revenue_cents,
                           total_cogs_cents, total_loss_cents, net_profit_cents
                    FROM Events WHERE id = ${event_id};")
    [[ -n "${row}" ]] || return 1
    IFS='|' read -r id name location start_date end_date status notes created_by closed_by \
        created_at closed_at revenue_cents cogs_cents loss_cents net_cents <<< "${row}"

    if [[ "${status}" == "active" ]]; then
        local live_financials live_sold live_loss
        live_financials=$(_api_events_financials "${event_id}")
        IFS='|' read -r revenue_cents cogs_cents loss_cents net_cents live_sold live_loss <<< "${live_financials}"
    fi

    local rows item out="" product_id product_name allocated sold lost returned unit_cost price available
    rows=$(db_query "SELECT es.product_id, p.name, es.allocated_qty, es.sold_qty, es.loss_qty,
                            es.returned_qty, es.unit_cost_snapshot, p.price,
                            es.allocated_qty - es.sold_qty - es.loss_qty - es.returned_qty
                     FROM EventStock es
                     JOIN Products p ON p.id = es.product_id
                     WHERE es.event_id = ${event_id}
                     ORDER BY p.name;")
    while IFS='|' read -r product_id product_name allocated sold lost returned unit_cost price available; do
        [[ -z "${product_id}" ]] && continue
        item=$(printf '{"product_id":%s,"name":%s,"allocated":%s,"sold":%s,"loss":%s,"returned":%s,"available":%s,"unit_cost":%s,"price":%s}' \
            "${product_id}" "$(json_quote "${product_name}")" \
            "$(json_number "${allocated}")" "$(json_number "${sold}")" \
            "$(json_number "${lost}")" "$(json_number "${returned}")" \
            "$(json_number "${available}")" "$(json_number "${unit_cost}")" \
            "$(json_number "${price}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    local products_out="" products_rows p_id p_name p_price p_is_combo p_stock p_available
    products_rows=$(db_query "SELECT p.id, p.name, p.price, p.is_combo, p.stock,
        CASE WHEN p.is_combo = 0 THEN
            COALESCE((SELECT MAX(0, es.allocated_qty - es.sold_qty - es.loss_qty - es.returned_qty)
                      FROM EventStock es
                      WHERE es.event_id = ${event_id} AND es.product_id = p.id), 0)
        ELSE
            COALESCE((SELECT MIN(CAST((es.allocated_qty - es.sold_qty - es.loss_qty - es.returned_qty) / ci.quantity AS INTEGER))
                      FROM ComboItems ci
                      JOIN EventStock es ON es.event_id = ${event_id} AND es.product_id = ci.component_product_id
                      WHERE ci.combo_product_id = p.id), 0)
        END
        FROM Products p
        WHERE p.active = 1
        ORDER BY p.name;")
    while IFS='|' read -r p_id p_name p_price p_is_combo p_stock p_available; do
        [[ -z "${p_id}" ]] && continue
        item=$(printf '{"id":%s,"name":%s,"price":%s,"is_combo":%s,"stock":%s,"available":%s}' \
            "${p_id}" "$(json_quote "${p_name}")" "$(json_number "${p_price}")" \
            "$(json_number "${p_is_combo}")" "$(json_number "${p_stock}")" \
            "$(json_number "${p_available}")")
        products_out+="${products_out:+,}${item}"
    done <<< "${products_rows}"

    local sales_out="" sales_rows s_id s_timestamp s_total s_payment s_stage s_channel s_type s_code
    sales_rows=$(db_query "SELECT s.id, datetime(s.timestamp), printf('%.2f', s.total_amount),
                                  s.payment_method, s.order_stage, s.channel, s.order_type,
                                  (CASE WHEN s.order_type = 'direct' THEN 'V-' ELSE 'P-' END) || printf('%06d', s.id)
                           FROM Sales s
                           WHERE s.event_id = ${event_id}
                             AND s.status = 'finished'
                             AND (s.order_type = 'direct' OR s.order_stage IN ('paid', 'delivered'))
                           ORDER BY s.id DESC
                           LIMIT 100;")
    while IFS='|' read -r s_id s_timestamp s_total s_payment s_stage s_channel s_type s_code; do
        [[ -z "${s_id}" ]] && continue
        item=$(printf '{"id":%s,"timestamp":%s,"total":%s,"payment_method":%s,"order_stage":%s,"channel":%s,"order_type":%s,"invoice_code":%s}' \
            "${s_id}" "$(json_quote "${s_timestamp}")" "$(json_number "${s_total}")" \
            "$(json_quote "${s_payment}")" "$(json_quote "${s_stage}")" \
            "$(json_quote "${s_channel}")" "$(json_quote "${s_type}")" \
            "$(json_quote "${s_code}")")
        sales_out+="${sales_out:+,}${item}"
    done <<< "${sales_rows}"

    local movements_out="" movement_rows m_id m_timestamp m_user m_action m_entity m_payload
    movement_rows=$(db_query "SELECT id, datetime(timestamp), user, action, entity,
                                     CASE WHEN json_valid(payload) THEN json(payload)
                                          ELSE json_quote(payload) END
                              FROM InventoryJournal
                              WHERE json_extract(payload, '$.event_id') = ${event_id}
                              ORDER BY id DESC
                              LIMIT 200;")
    while IFS='|' read -r m_id m_timestamp m_user m_action m_entity m_payload; do
        [[ -z "${m_id}" ]] && continue
        item=$(printf '{"id":%s,"timestamp":%s,"user":%s,"action":%s,"entity":%s,"payload":%s}' \
            "${m_id}" "$(json_quote "${m_timestamp}")" "$(json_quote "${m_user}")" \
            "$(json_quote "${m_action}")" "$(json_quote "${m_entity}")" "${m_payload:-null}")
        movements_out+="${movements_out:+,}${item}"
    done <<< "${movement_rows}"

    local sales_count sales_units sales_revenue
    row=$(db_query "SELECT COUNT(DISTINCT s.id), COALESCE(SUM(si.quantity), 0),
                           printf('%.2f', COALESCE(SUM(s.total_amount), 0))
                    FROM Sales s
                    LEFT JOIN SaleItems si ON si.sale_id = s.id
                    WHERE s.event_id = ${event_id}
                      AND s.status = 'finished'
                      AND (s.order_type = 'direct' OR s.order_stage IN ('paid', 'delivered'));")
    IFS='|' read -r sales_count sales_units sales_revenue <<< "${row}"

    printf '{"id":%s,"name":%s,"location":%s,"start_date":%s,"end_date":%s,"status":%s,"status_label":%s,"notes":%s,"created_by":%s,"closed_by":%s,"created_at":%s,"closed_at":%s,"revenue":%s,"cogs":%s,"loss":%s,"net_profit":%s,"sales_count":%s,"sales_units":%s,"sales_revenue":%s,"items":[%s],"products":[%s],"sales":[%s],"movements":[%s]}' \
        "${id}" "$(json_quote "${name}")" "$(json_quote "${location}")" \
        "$(json_quote "${start_date}")" "$(json_quote "${end_date}")" \
        "$(json_quote "${status}")" "$(json_quote "$(api_events_status_label "${status}")")" \
        "$(json_quote "${notes}")" "$(json_quote "${created_by}")" "$(json_quote "${closed_by}")" \
        "$(json_quote "${created_at}")" "$(json_quote "${closed_at}")" \
        "$(json_number "$(billing_cents_to_decimal "${revenue_cents}")")" \
        "$(json_number "$(billing_cents_to_decimal "${cogs_cents}")")" \
        "$(json_number "$(billing_cents_to_decimal "${loss_cents}")")" \
        "$(json_number "$(billing_cents_to_decimal "${net_cents}")")" \
        "$(json_number "${sales_count}")" "$(json_number "${sales_units}")" \
        "$(json_number "${sales_revenue}")" "${out}" "${products_out}" \
        "${sales_out}" "${movements_out}"
}

_api_events_stat_block() {
    local label="$1"
    shift
    local values=("$@")
    if (( ${#values[@]} == 0 )); then
        printf '"%s":{"count":0,"mean":0,"median":0,"min":0,"max":0,"range":0,"stddev":0,"cv":0}' "${label}"
        return 0
    fi
    printf '%s\n' "${values[@]}" | sort -n | awk -v label="${label}" '
        { a[NR] = $1; sum += $1 }
        END {
            n = NR
            mean = sum / n
            if (n % 2 == 1) median = a[(n + 1) / 2]
            else median = (a[n / 2] + a[n / 2 + 1]) / 2
            min = a[1]; max = a[n]
            variance = 0
            for (i = 1; i <= n; i++) variance += (a[i] - mean) ^ 2
            stddev = (n > 1) ? sqrt(variance / (n - 1)) : 0
            absmean = (mean < 0) ? -mean : mean
            cv = (absmean != 0) ? (stddev / absmean) * 100 : 0
            printf "\"%s\":{\"count\":%d,\"mean\":%.2f,\"median\":%.2f,\"min\":%.2f,\"max\":%.2f,\"range\":%.2f,\"stddev\":%.2f,\"cv\":%.2f}", label, n, mean, median, min, max, max - min, stddev, cv
        }'
}

api_events_stats_json() {
    local total active closed cancelled
    total=$(db_scalar "SELECT COUNT(*) FROM Events;" 2>/dev/null || printf '0')
    active=$(db_scalar "SELECT COUNT(*) FROM Events WHERE status = 'active';" 2>/dev/null || printf '0')
    closed=$(db_scalar "SELECT COUNT(*) FROM Events WHERE status = 'closed';" 2>/dev/null || printf '0')
    cancelled=$(db_scalar "SELECT COUNT(*) FROM Events WHERE status = 'cancelled';" 2>/dev/null || printf '0')

    local -a profits=() units=()
    local rows row id name net sold revenue_event loss_event returned_event series_out=""
    rows=$(db_query "SELECT e.id, e.name, e.total_revenue_cents, e.net_profit_cents,
                            COALESCE(SUM(es.sold_qty), 0), COALESCE(SUM(es.loss_qty), 0),
                            COALESCE(SUM(es.returned_qty), 0)
                     FROM Events e
                     LEFT JOIN EventStock es ON es.event_id = e.id
                     WHERE e.status = 'closed'
                     GROUP BY e.id
                     ORDER BY e.id;")
    while IFS='|' read -r id name revenue_event net sold loss_event returned_event; do
        [[ -z "${id}" ]] && continue
        profits+=("$(billing_cents_to_decimal "${net}")")
        units+=("${sold}")
        series_out+="${series_out:+,}$(printf '{"id":%s,"name":%s,"revenue":%s,"net_profit":%s,"sold":%s,"loss":%s,"returned":%s}' \
            "${id}" "$(json_quote "${name}")" \
            "$(json_number "$(billing_cents_to_decimal "${revenue_event}")")" \
            "$(json_number "$(billing_cents_to_decimal "${net}")")" \
            "$(json_number "${sold}")" "$(json_number "${loss_event}")" \
            "$(json_number "${returned_event}")")"
    done <<< "${rows}"

    local totals revenue_cents cogs_cents loss_cents net_cents allocated sold_units loss_units
    totals=$(db_query "SELECT
        COALESCE(SUM(total_revenue_cents), 0), COALESCE(SUM(total_cogs_cents), 0),
        COALESCE(SUM(total_loss_cents), 0), COALESCE(SUM(net_profit_cents), 0)
        FROM Events WHERE status = 'closed';")
    IFS='|' read -r revenue_cents cogs_cents loss_cents net_cents <<< "${totals}"
    allocated=$(db_scalar "SELECT COALESCE(SUM(es.allocated_qty), 0)
                           FROM EventStock es JOIN Events e ON e.id = es.event_id
                           WHERE e.status = 'closed';" 2>/dev/null || printf '0')
    sold_units=$(db_scalar "SELECT COALESCE(SUM(es.sold_qty), 0)
                            FROM EventStock es JOIN Events e ON e.id = es.event_id
                            WHERE e.status = 'closed';" 2>/dev/null || printf '0')
    loss_units=$(db_scalar "SELECT COALESCE(SUM(es.loss_qty), 0)
                            FROM EventStock es JOIN Events e ON e.id = es.event_id
                            WHERE e.status = 'closed';" 2>/dev/null || printf '0')

    local conversion=0 loss_rate=0
    if [[ "${allocated}" =~ ^[0-9]+$ ]] && (( allocated > 0 )); then
        conversion=$(awk -v s="${sold_units}" -v a="${allocated}" 'BEGIN { printf "%.2f", (s / a) * 100 }')
        loss_rate=$(awk -v l="${loss_units}" -v a="${allocated}" 'BEGIN { printf "%.2f", (l / a) * 100 }')
    fi

    local channel_out="" channel_rows channel count amount
    channel_rows=$(db_query "SELECT channel, COUNT(*), printf('%.2f', COALESCE(SUM(total_amount), 0))
                             FROM Sales
                             WHERE event_id IS NOT NULL
                               AND status = 'finished'
                               AND (order_type = 'direct' OR order_stage IN ('paid', 'delivered'))
                             GROUP BY channel;")
    while IFS='|' read -r channel count amount; do
        [[ -z "${channel}" ]] && continue
        channel_out+="${channel_out:+,}$(printf '{"channel":%s,"sales":%s,"revenue":%s}' \
            "$(json_quote "${channel}")" "$(json_number "${count}")" "$(json_number "${amount}")")"
    done <<< "${channel_rows}"

    local profit_block units_block
    profit_block=$(_api_events_stat_block "net_profit" "${profits[@]}")
    units_block=$(_api_events_stat_block "units_sold" "${units[@]}")

    printf '{"events":{"total":%s,"active":%s,"closed":%s,"cancelled":%s},"financials":{"revenue":%s,"cogs":%s,"loss":%s,"net_profit":%s},"units":{"allocated":%s,"sold":%s,"lost":%s,"returned":%s,"conversion":%s,"loss_rate":%s},%s,%s,"channels":[%s],"series":[%s]}' \
        "${total}" "${active}" "${closed}" "${cancelled}" \
        "$(json_number "$(billing_cents_to_decimal "${revenue_cents}")")" \
        "$(json_number "$(billing_cents_to_decimal "${cogs_cents}")")" \
        "$(json_number "$(billing_cents_to_decimal "${loss_cents}")")" \
        "$(json_number "$(billing_cents_to_decimal "${net_cents}")")" \
        "$(json_number "${allocated}")" "$(json_number "${sold_units}")" \
        "$(json_number "${loss_units}")" \
        "$(json_number "$(( allocated - sold_units - loss_units < 0 ? 0 : allocated - sold_units - loss_units ))")" \
        "$(json_number "${conversion}")" \
        "$(json_number "${loss_rate}")" "${profit_block}" "${units_block}" "${channel_out}" "${series_out}"
}
