#!/usr/bin/env bash
#
# Capa de negocio: ventas y producción con transacciones ACID.

[[ -n "${_ERP_API_SALES_LOADED:-}" ]] && return 0
declare -g _ERP_API_SALES_LOADED=1

declare -g SALE_ID=""
declare -g SALE_TOTAL=""
declare -g BATCH_ID=""

api_register_sale() {
    local customer_id="${1:-0}"
    local payment_method="${2:-Efectivo}"
    local -n _product_ids=$3
    local -n _quantities=$4

    AUTH_ERROR=""
    SALE_ID=""
    SALE_TOTAL=""

    if (( ${#_product_ids[@]} == 0 )); then
        AUTH_ERROR="La venta debe incluir al menos un producto."
        return 1
    fi

    case "${payment_method}" in
        Efectivo|Transferencia|Tarjeta) ;;
        *) AUTH_ERROR="Método de pago inválido."; return 1 ;;
    esac

    local safe_customer="NULL"
    if [[ "${customer_id}" =~ ^[0-9]+$ ]] && (( customer_id > 0 )); then
        local customer_exists
        customer_exists=$(db_scalar "SELECT COUNT(*) FROM Customers WHERE id = ${customer_id};" 2>/dev/null || printf '0')
        (( ${customer_exists:-0} > 0 )) || { AUTH_ERROR="El cliente no existe."; return 1; }
        safe_customer="${customer_id}"
    fi

    local -A quantity_by_product=()
    local i product_id quantity
    for (( i = 0; i < ${#_product_ids[@]}; i++ )); do
        product_id="${_product_ids[$i]}"
        quantity="${_quantities[$i]:-0}"

        [[ "${product_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Producto inválido."; return 1; }
        [[ "${quantity}" =~ ^[0-9]+$ ]] && (( quantity > 0 )) || { AUTH_ERROR="Cantidad inválida."; return 1; }
        quantity_by_product["${product_id}"]=$(( ${quantity_by_product[${product_id}]:-0} + quantity ))
    done

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    local stock price active name
    for product_id in "${!quantity_by_product[@]}"; do
        local row
        row=$(db_query "SELECT stock, price, active, name FROM Products WHERE id = ${product_id};")
        if [[ -z "${row}" ]]; then
            AUTH_ERROR="El producto ${product_id} no existe."
            tx_rollback
            return 1
        fi
        IFS='|' read -r stock price active name <<< "${row}"
        if (( active != 1 )); then
            AUTH_ERROR="El producto '${name}' está inactivo."
            tx_rollback
            return 1
        fi
        if (( stock < quantity_by_product[${product_id}] )); then
            AUTH_ERROR="Stock insuficiente para '${name}' (disponible: ${stock})."
            tx_rollback
            return 1
        fi
    done

    if ! db_exec "INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
                  VALUES (datetime('now', 'localtime'), ${safe_customer}, 0, $(db_quote "${payment_method}"));"; then
        AUTH_ERROR="No se pudo registrar la venta."
        tx_rollback
        return 1
    fi

    SALE_ID=$(db_last_insert_id)
    if [[ -z "${SALE_ID}" ]]; then
        AUTH_ERROR="No se obtuvo el identificador de la venta."
        tx_rollback
        return 1
    fi

    for product_id in "${!quantity_by_product[@]}"; do
        quantity="${quantity_by_product[${product_id}]}"
        if ! db_exec "INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
                      VALUES (${SALE_ID}, ${product_id}, ${quantity},
                              (SELECT price FROM Products WHERE id = ${product_id}));"; then
            AUTH_ERROR="No se pudo agregar el producto ${product_id} a la venta. ${DB_LAST_ERROR}"
            tx_rollback
            return 1
        fi
    done

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la venta."
        tx_rollback
        return 1
    fi

    SALE_TOTAL=$(db_scalar "SELECT printf('%.2f', total_amount) FROM Sales WHERE id = ${SALE_ID};" 2>/dev/null || printf '0')
    return 0
}

api_register_production_batch() {
    local product_id="${1:-0}"
    local quantity="${2:-0}"
    local unit_cost="${3:-0}"
    local notes="${4:-}"
    local -n _input_ids=$5
    local -n _input_quantities=$6

    AUTH_ERROR=""
    BATCH_ID=""

    [[ "${product_id}" =~ ^[0-9]+$ ]] && (( product_id > 0 )) || { AUTH_ERROR="Producto inválido."; return 1; }
    [[ "${quantity}" =~ ^[0-9]+$ ]] && (( quantity > 0 )) || { AUTH_ERROR="Cantidad de lote inválida."; return 1; }
    [[ "${unit_cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Costo unitario inválido."; return 1; }

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Products WHERE id = ${product_id} AND active = 1;" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El producto no existe o está inactivo."; return 1; }

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "INSERT INTO ProductionBatches (timestamp, product_id, quantity, unit_cost, notes)
                  VALUES (datetime('now', 'localtime'), ${product_id}, ${quantity}, ${unit_cost}, $(db_quote "${notes}"));"; then
        AUTH_ERROR="No se pudo crear el lote. ${DB_LAST_ERROR}"
        tx_rollback
        return 1
    fi

    BATCH_ID=$(db_last_insert_id)
    if [[ -z "${BATCH_ID}" ]]; then
        AUTH_ERROR="No se obtuvo el identificador del lote."
        tx_rollback
        return 1
    fi

    local i input_id input_quantity
    for (( i = 0; i < ${#_input_ids[@]}; i++ )); do
        input_id="${_input_ids[$i]}"
        input_quantity="${_input_quantities[$i]:-0}"
        [[ "${input_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Insumo inválido."; tx_rollback; return 1; }
        [[ "${input_quantity}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Cantidad de insumo inválida."; tx_rollback; return 1; }

        if ! db_exec "INSERT INTO ProductionInputs (batch_id, input_id, quantity)
                      VALUES (${BATCH_ID}, ${input_id}, ${input_quantity});"; then
            AUTH_ERROR="No se pudo consumir el insumo ${input_id}. ${DB_LAST_ERROR}"
            tx_rollback
            return 1
        fi
    done

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar el lote de producción."
        tx_rollback
        return 1
    fi

    return 0
}

api_recent_sales_json() {
    local limit="${1:-8}"
    [[ "${limit}" =~ ^[0-9]+$ ]] || limit=8
    (( limit > 50 )) && limit=50

    local rows row id timestamp customer total payment units item out=""
    rows=$(db_query "SELECT s.id, datetime(s.timestamp), COALESCE(c.name, 'Consumidor final'),
                            s.total_amount, s.payment_method, COALESCE(SUM(si.quantity), 0)
                     FROM Sales s
                     LEFT JOIN Customers c ON c.id = s.customer_id
                     LEFT JOIN SaleItems si ON si.sale_id = s.id
                     GROUP BY s.id
                     ORDER BY s.id DESC
                     LIMIT ${limit};")

    while IFS='|' read -r id timestamp customer total payment units; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"timestamp":%s,"customer":%s,"total":%s,"payment":%s,"units":%s}' \
            "${id}" "$(json_quote "${timestamp}")" "$(json_quote "${customer}")" \
            "$(json_number "${total}")" "$(json_quote "${payment}")" "$(json_number "${units}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '[%s]' "${out}"
}

api_journal_json() {
    local limit="${1:-10}"
    [[ "${limit}" =~ ^[0-9]+$ ]] || limit=10
    (( limit > 50 )) && limit=50

    local rows row id timestamp user action entity payload status item out=""
    rows=$(db_query "SELECT id, datetime(timestamp), user, action, entity,
                            COALESCE(payload, ''), status
                     FROM InventoryJournal
                     ORDER BY id DESC
                     LIMIT ${limit};")

    while IFS='|' read -r id timestamp user action entity payload status; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"timestamp":%s,"user":%s,"action":%s,"entity":%s,"payload":%s,"status":%s}' \
            "${id}" "$(json_quote "${timestamp}")" "$(json_quote "${user}")" \
            "$(json_quote "${action}")" "$(json_quote "${entity}")" \
            "$(json_quote "${payload}")" "$(json_quote "${status}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '[%s]' "${out}"
}
