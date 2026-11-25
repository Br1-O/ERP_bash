#!/usr/bin/env bash
#
# Repositorio local (SQLite). Implementa la interfaz que usa el servicio de
# sincronización: configuración, snapshot y bitácora. Ninguna capa superior
# escribe SQL directamente para estas operaciones.

[[ -n "${_ERP_LOCAL_REPOSITORY_LOADED:-}" ]] && return 0
declare -g _ERP_LOCAL_REPOSITORY_LOADED=1

local_repo_get_sync_url() {
    db_scalar "SELECT value FROM AppContext WHERE key = 'sync_url';" 2>/dev/null || true
}

local_repo_get_sync_token() {
    db_scalar "SELECT value FROM AppContext WHERE key = 'sync_token';" 2>/dev/null || true
}

local_repo_save_sync_url() {
    local url="${1:-}"
    if [[ -z "${url}" ]]; then
        db_exec "DELETE FROM AppContext WHERE key = 'sync_url';"
        return
    fi
    db_exec "INSERT INTO AppContext (key, value) VALUES ('sync_url', $(db_quote "${url}"))
             ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
}

local_repo_save_sync_token() {
    local token="${1:-}"
    if [[ -z "${token}" ]]; then
        db_exec "DELETE FROM AppContext WHERE key = 'sync_token';"
        return
    fi
    db_exec "INSERT INTO AppContext (key, value) VALUES ('sync_token', $(db_quote "${token}"))
             ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
}

local_repo_snapshot_json() {
    local sql payload
    sql=$(cat <<SQL
SELECT json_object(
    'source', 'sqlite',
    'schema_version', ${ERP_SCHEMA_VERSION},
    'generated_at', datetime('now', 'localtime'),
    'last_journal_id', (SELECT COALESCE(MAX(id), 0) FROM InventoryJournal),
    'tables', json_object(
        'categories', (SELECT json_group_array(json_object(
            'id', id, 'name', name)) FROM (SELECT id, name FROM Categories ORDER BY id)),
        'suppliers', (SELECT json_group_array(json_object(
            'id', id, 'name', name, 'contact_person', contact_person,
            'phone', phone, 'email', email, 'address', address, 'active', active))
            FROM (SELECT id, name, contact_person, phone, email, address, active
                  FROM Suppliers ORDER BY id)),
        'customers', (SELECT json_group_array(json_object(
            'id', id, 'name', name, 'type', type, 'phone', phone, 'email', email,
            'active', active))
            FROM (SELECT id, name, type, phone, email, active FROM Customers ORDER BY id)),
        'inputs', (SELECT json_group_array(json_object(
            'id', id, 'name', name, 'category_id', category_id, 'stock', stock,
            'unit', unit, 'cost', cost, 'supplier_id', supplier_id,
            'min_stock_threshold', min_stock_threshold, 'active', active))
            FROM (SELECT id, name, category_id, stock, unit, cost, supplier_id,
                         min_stock_threshold, active FROM Inputs ORDER BY id)),
        'products', (SELECT json_group_array(json_object(
            'id', id, 'name', name, 'category_id', category_id, 'stock', stock,
            'min_production_threshold', min_production_threshold, 'cost', cost,
            'price', price, 'active', active, 'is_seasonal', is_seasonal,
            'recipe_description', recipe_description, 'is_combo', is_combo))
            FROM (SELECT id, name, category_id, stock, min_production_threshold, cost,
                         price, active, is_seasonal, recipe_description, is_combo
                  FROM Products ORDER BY id)),
        'product_recipe', (SELECT json_group_array(json_object(
            'id', id, 'product_id', product_id, 'input_id', input_id,
            'quantity_per_unit', quantity_per_unit))
            FROM (SELECT id, product_id, input_id, quantity_per_unit
                  FROM ProductRecipe ORDER BY id)),
        'product_recipe_steps', (SELECT json_group_array(json_object(
            'id', id, 'product_id', product_id, 'step_number', step_number,
            'instruction', instruction))
            FROM (SELECT id, product_id, step_number, instruction
                  FROM ProductRecipeStep ORDER BY id)),
        'combo_items', (SELECT json_group_array(json_object(
            'id', id, 'combo_product_id', combo_product_id,
            'component_product_id', component_product_id, 'quantity', quantity))
            FROM (SELECT id, combo_product_id, component_product_id, quantity
                  FROM ComboItems ORDER BY id)),
        'business_info', (SELECT json_group_array(json_object(
            'id', id, 'name', name, 'instagram', instagram, 'facebook', facebook,
            'phone', phone, 'email', email, 'website', website, 'updated_at', updated_at))
            FROM (SELECT id, name, instagram, facebook, phone, email, website, updated_at
                  FROM BusinessInfo ORDER BY id)),
        'sales', (SELECT json_group_array(json_object(
            'id', id, 'timestamp', timestamp, 'customer_id', customer_id,
            'subtotal_amount', subtotal_amount, 'discount_type', discount_type,
            'discount_value', discount_value, 'discount_amount', discount_amount,
            'total_amount', total_amount, 'payment_method', payment_method,
            'status', status, 'notes', notes, 'created_by', created_by,
            'stock_applied', stock_applied, 'order_type', order_type,
            'order_stage', order_stage, 'cancel_reason', cancel_reason,
            'cancelled_by', cancelled_by,
            'cancel_authorized_by', cancel_authorized_by,
            'cancelled_at', cancelled_at,
            'event_id', event_id, 'channel', channel))
            FROM (SELECT id, timestamp, customer_id, subtotal_amount, discount_type,
                         discount_value, discount_amount, total_amount, payment_method,
                         status, notes, created_by, stock_applied, order_type,
                         order_stage, cancel_reason, cancelled_by,
                         cancel_authorized_by, cancelled_at, event_id, channel
                  FROM Sales ORDER BY id)),
        'sale_items', (SELECT json_group_array(json_object(
            'id', id, 'sale_id', sale_id, 'product_id', product_id,
            'quantity', quantity, 'unit_price', unit_price))
            FROM (SELECT id, sale_id, product_id, quantity, unit_price
                  FROM SaleItems ORDER BY id)),
        'production_batches', (SELECT json_group_array(json_object(
            'id', id, 'timestamp', timestamp, 'product_id', product_id,
            'quantity', quantity, 'unit_cost', unit_cost, 'notes', notes))
            FROM (SELECT id, timestamp, product_id, quantity, unit_cost, notes
                  FROM ProductionBatches ORDER BY id)),
        'production_inputs', (SELECT json_group_array(json_object(
            'id', id, 'batch_id', batch_id, 'input_id', input_id, 'quantity', quantity))
            FROM (SELECT id, batch_id, input_id, quantity FROM ProductionInputs ORDER BY id)),
        'purchases', (SELECT json_group_array(json_object(
            'id', id, 'timestamp', timestamp, 'supplier_id', supplier_id,
            'total_amount', total_amount, 'notes', notes, 'status', status,
            'created_by', created_by, 'stock_applied', stock_applied))
            FROM (SELECT id, timestamp, supplier_id, total_amount, notes, status,
                         created_by, stock_applied
                  FROM Purchases ORDER BY id)),
        'purchase_items', (SELECT json_group_array(json_object(
            'id', id, 'purchase_id', purchase_id, 'input_id', input_id,
            'quantity', quantity, 'unit_cost', unit_cost))
            FROM (SELECT id, purchase_id, input_id, quantity, unit_cost
                  FROM PurchaseItems ORDER BY id)),
        'tasting_feedback', (SELECT json_group_array(json_object(
            'id', id, 'product_id', product_id, 'accepted', accepted, 'timestamp', timestamp))
            FROM (SELECT id, product_id, accepted, timestamp FROM TastingFeedback ORDER BY id)),
        'events', (SELECT json_group_array(json_object(
            'id', id, 'name', name, 'location', location,
            'start_date', start_date, 'end_date', end_date, 'status', status,
            'notes', notes, 'created_by', created_by, 'closed_by', closed_by,
            'total_revenue_cents', total_revenue_cents,
            'total_cogs_cents', total_cogs_cents,
            'total_loss_cents', total_loss_cents,
            'net_profit_cents', net_profit_cents))
            FROM (SELECT id, name, location, start_date, end_date, status, notes,
                         created_by, closed_by, total_revenue_cents, total_cogs_cents,
                         total_loss_cents, net_profit_cents
                  FROM Events ORDER BY id)),
        'event_stock', (SELECT json_group_array(json_object(
            'id', id, 'event_id', event_id, 'product_id', product_id,
            'allocated_qty', allocated_qty, 'sold_qty', sold_qty,
            'loss_qty', loss_qty, 'returned_qty', returned_qty,
            'unit_cost_snapshot', unit_cost_snapshot))
            FROM (SELECT id, event_id, product_id, allocated_qty, sold_qty,
                         loss_qty, returned_qty, unit_cost_snapshot
                  FROM EventStock ORDER BY id)),
        'inventory_journal', (SELECT json_group_array(json_object(
            'id', id, 'timestamp', timestamp, 'user', user, 'action', action,
            'entity', entity, 'payload', payload, 'status', status,
            'event_uuid', event_uuid, 'origin', origin, 'synced', synced))
            FROM (SELECT id, timestamp, user, action, entity, payload, status,
                         event_uuid, origin, synced
                  FROM InventoryJournal ORDER BY id))
    )
);
SQL
)
    payload=$(db_scalar "${sql}") || return 1
    [[ -z "${payload}" ]] && return 1
    printf '%s' "${payload}"
}

local_repo_sync_status_json() {
    local url token last_at last_status last_endpoint last_message last_bytes
    url=$(local_repo_get_sync_url)
    token=$(local_repo_get_sync_token)
    last_at=$(db_scalar "SELECT datetime(timestamp) FROM SyncLog ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)
    last_status=$(db_scalar "SELECT status FROM SyncLog ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)
    last_endpoint=$(db_scalar "SELECT COALESCE(endpoint, '') FROM SyncLog ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)
    last_message=$(db_scalar "SELECT COALESCE(message, '') FROM SyncLog ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)
    last_bytes=$(db_scalar "SELECT COALESCE(payload_bytes, 0) FROM SyncLog ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)
    local pending_events last_remote
    pending_events=$(local_repo_pending_event_count)
    last_remote=$(local_repo_last_remote_journal_id)

    local token_configured="false"
    [[ -n "${token}" ]] && token_configured="true"

    printf '{"configured":%s,"endpoint":%s,"token_configured":%s,"last_at":%s,"last_status":%s,"last_endpoint":%s,"last_message":%s,"last_bytes":%s,"pending_events":%s,"last_remote_journal_id":%s}' \
        "$([[ -n "${url}" ]] && printf true || printf false)" \
        "$(json_quote "${url}")" "${token_configured}" \
        "$(json_quote "${last_at}")" "$(json_quote "${last_status}")" \
        "$(json_quote "${last_endpoint}")" "$(json_quote "${last_message}")" \
        "$(json_number "${last_bytes:-0}")" "${pending_events:-0}" \
        "${last_remote:-0}"
}

local_repo_record_sync() {
    local status="${1:-ok}" endpoint="${2:-}" message="${3:-}" bytes="${4:-0}"
    [[ "${bytes}" =~ ^[0-9]+$ ]] || bytes=0
    db_exec "INSERT INTO SyncLog (timestamp, status, endpoint, message, payload_bytes)
             VALUES (datetime('now', 'localtime'), $(db_quote "${status}"),
                     $(db_quote "${endpoint}"), $(db_quote "${message}"), ${bytes});"
}

local_repo_pending_event_count() {
    local count
    count=$(db_scalar "SELECT COUNT(*) FROM InventoryJournal
                       WHERE synced = 0 AND origin = 'LOCAL';" 2>/dev/null || true)
    [[ "${count}" =~ ^[0-9]+$ ]] || count=0
    printf '%s' "${count}"
}

local_repo_pending_events_json() {
    local sql payload
    sql=$(cat <<SQL
SELECT COALESCE(json_group_array(json_object(
    'id', id, 'event_uuid', event_uuid, 'timestamp', timestamp,
    'user', user, 'action', action, 'entity', entity,
    'payload', CASE WHEN json_valid(payload) THEN json(payload) ELSE payload END,
    'status', status, 'origin', origin, 'synced', synced
)), '[]')
FROM (
    SELECT id, event_uuid, timestamp, user, action, entity, payload, status,
           origin, synced
    FROM InventoryJournal
    WHERE synced = 0 AND origin = 'LOCAL'
    ORDER BY id ASC
);
SQL
)
    payload=$(db_scalar "${sql}") || return 1
    [[ -z "${payload}" ]] && return 1
    printf '%s' "${payload}"
}

local_repo_pending_event_uuids_json() {
    local sql payload
    sql=$(cat <<SQL
SELECT COALESCE(json_group_array(event_uuid), '[]')
FROM (
    SELECT event_uuid
    FROM InventoryJournal
    WHERE synced = 0 AND origin = 'LOCAL' AND event_uuid IS NOT NULL
    ORDER BY id ASC
);
SQL
)
    payload=$(db_scalar "${sql}") || return 1
    [[ -z "${payload}" ]] && return 1
    printf '%s' "${payload}"
}

local_repo_mark_events_synced_json() {
    local uuids="${1:-[]}"
    [[ -z "${uuids}" ]] && uuids='[]'
    db_exec "UPDATE InventoryJournal
                SET synced = 1
              WHERE origin = 'LOCAL' AND synced = 0
                AND event_uuid IN (SELECT value FROM json_each($(db_quote "${uuids}")));"
}

local_repo_last_remote_journal_id() {
    local value
    value=$(db_scalar "SELECT value FROM AppContext WHERE key = 'last_remote_journal_id';" 2>/dev/null || true)
    [[ "${value}" =~ ^[0-9]+$ ]] || value=0
    printf '%s' "${value}"
}

local_repo_set_last_remote_journal_id() {
    local remote_id="${1:-0}"
    [[ "${remote_id}" =~ ^[0-9]+$ ]] || remote_id=0
    db_exec "INSERT INTO AppContext (key, value) VALUES ('last_remote_journal_id', '${remote_id}')
             ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
}

_local_repo_nonnegative_number() {
    local value="${1:-0}"
    if [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

_local_repo_remote_sale_apply() {
    local uuid="${1:-}" payload="${2:-}"
    local pq items_count total discount item_index product_id quantity unit_price sale_id start_id single_item=0
    pq=$(db_quote "${payload}")
    items_count=$(db_scalar "SELECT COALESCE(json_array_length(json_extract(${pq}, '$.items')), 0);" 2>/dev/null || printf '0')
    [[ "${items_count}" =~ ^[0-9]+$ ]] || items_count=0

    if (( items_count == 0 )); then
        product_id=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.product_id'), 0);" 2>/dev/null || printf '0')
        quantity=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.quantity'), 0);" 2>/dev/null || printf '0')
        unit_price=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.unit_price'), 0);" 2>/dev/null || printf '0')
        [[ "${product_id}" =~ ^[1-9][0-9]*$ ]] || return 1
        [[ "${quantity}" =~ ^[1-9][0-9]*$ ]] || return 1
        unit_price=$(_local_repo_nonnegative_number "${unit_price}")
        single_item=1
    fi

    total=$(_local_repo_nonnegative_number "$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.total'), 0);" 2>/dev/null || printf '0')")
    discount=$(_local_repo_nonnegative_number "$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.discount_amount'), 0);" 2>/dev/null || printf '0')")

    tx_begin || return 1

    db_exec "INSERT INTO InventoryJournal
                (timestamp, user, action, entity, payload, status, event_uuid, origin, synced)
             VALUES (COALESCE(json_extract(${pq}, '$.timestamp'), datetime('now', 'localtime')),
                     'ECOMMERCE', 'ECOMMERCE_SALE', 'Sales', ${pq}, 'DONE',
                     $(db_quote "${uuid}"), 'ECOMMERCE', 1);" || {
        tx_rollback
        return 1
    }
    start_id=$(db_last_insert_id)

    db_exec "INSERT INTO Sales
                (timestamp, customer_id, subtotal_amount, discount_type,
                 discount_value, discount_amount, total_amount, payment_method,
                 status, notes, created_by, stock_applied, order_type,
                 order_stage, channel)
             VALUES (COALESCE(json_extract(${pq}, '$.timestamp'), datetime('now', 'localtime')),
                     (SELECT id FROM Customers
                       WHERE id = CAST(json_extract(${pq}, '$.customer_id') AS INTEGER)),
                     0, 'none', 0, ${discount}, ${total},
                     COALESCE(json_extract(${pq}, '$.payment_method'), 'Efectivo'),
                     'finished', 'Importado de ecommerce', 'ECOMMERCE', 0,
                     'direct', 'delivered', 'ECOMMERCE');" || {
        tx_rollback
        return 1
    }
    sale_id=$(db_last_insert_id)

    if (( single_item == 1 )); then
        db_exec "INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
                 VALUES (${sale_id}, ${product_id}, ${quantity}, ${unit_price});" || {
            tx_rollback
            return 1
        }
    else
        item_index=0
        while (( item_index < items_count )); do
            product_id=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.items[${item_index}].product_id'), 0);" 2>/dev/null || printf '0')
            quantity=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.items[${item_index}].quantity'), 0);" 2>/dev/null || printf '0')
            unit_price=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.items[${item_index}].unit_price'), 0);" 2>/dev/null || printf '0')
            if [[ "${product_id}" =~ ^[1-9][0-9]*$ && "${quantity}" =~ ^[1-9][0-9]*$ ]]; then
                unit_price=$(_local_repo_nonnegative_number "${unit_price}")
                db_exec "INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
                         VALUES (${sale_id}, ${product_id}, ${quantity}, ${unit_price});" || {
                    tx_rollback
                    return 1
                }
            fi
            item_index=$((item_index + 1))
        done
    fi

    db_exec "UPDATE InventoryJournal
                SET synced = 1, origin = 'ECOMMERCE'
              WHERE id > ${start_id};" || {
        tx_rollback
        return 1
    }

    tx_commit
}

_local_repo_remote_stock_apply() {
    local uuid="${1:-}" payload="${2:-}"
    local pq product_id delta start_id changes
    pq=$(db_quote "${payload}")
    product_id=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.product_id'), 0);" 2>/dev/null || printf '0')
    delta=$(db_scalar "SELECT COALESCE(json_extract(${pq}, '$.stock_delta'), json_extract(${pq}, '$.delta'), 0);" 2>/dev/null || printf '0')
    [[ "${product_id}" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "${delta}" =~ ^-?[0-9]+$ ]] || return 1

    tx_begin || return 1

    db_exec "INSERT INTO InventoryJournal
                (timestamp, user, action, entity, payload, status, event_uuid, origin, synced)
             VALUES (COALESCE(json_extract(${pq}, '$.timestamp'), datetime('now', 'localtime')),
                     'ECOMMERCE', 'ECOMMERCE_STOCK', 'Products', ${pq}, 'DONE',
                     $(db_quote "${uuid}"), 'ECOMMERCE', 1);" || {
        tx_rollback
        return 1
    }
    start_id=$(db_last_insert_id)

    db_exec "UPDATE Products SET stock = stock + (${delta}) WHERE id = ${product_id};" || {
        tx_rollback
        return 1
    }
    changes=$(db_changes)
    if [[ "${changes}" != "1" ]]; then
        tx_rollback
        return 1
    fi

    db_exec "UPDATE InventoryJournal
                SET synced = 1, origin = 'ECOMMERCE'
              WHERE id > ${start_id};" || {
        tx_rollback
        return 1
    }

    tx_commit
}

local_repo_apply_remote_events() {
    local response="${1:-}"
    local q count index applied=0 uuid action payload pq has_items has_delta valid
    LOCAL_REPO_PULL_ERROR=""
    LOCAL_REPO_PULL_APPLIED=0

    q=$(db_quote "${response}")
    valid=$(db_scalar "SELECT json_valid(${q});" 2>/dev/null || printf '0')
    if [[ "${valid}" != "1" ]]; then
        LOCAL_REPO_PULL_ERROR="La respuesta del endpoint no es JSON válido."
        return 1
    fi

    count=$(db_scalar "SELECT COALESCE(json_array_length(json_extract(${q}, '$.events')), 0);" 2>/dev/null || printf '0')
    [[ "${count}" =~ ^[0-9]+$ ]] || count=0

    index=0
    while (( index < count )); do
        uuid=$(db_scalar "SELECT COALESCE(json_extract(${q}, '$.events[${index}].event_uuid'), '');" 2>/dev/null || true)
        if [[ -z "${uuid}" ]]; then
            index=$((index + 1))
            continue
        fi

        if [[ "$(db_scalar "SELECT COUNT(*) FROM InventoryJournal WHERE event_uuid = $(db_quote "${uuid}");" 2>/dev/null || printf '0')" != "0" ]]; then
            index=$((index + 1))
            continue
        fi

        action=$(db_scalar "SELECT COALESCE(json_extract(${q}, '$.events[${index}].action'), '');" 2>/dev/null || true)
        payload=$(db_scalar "SELECT json_extract(${q}, '$.events[${index}].payload');" 2>/dev/null || true)
        valid=$(db_scalar "SELECT json_valid($(db_quote "${payload}"));" 2>/dev/null || printf '0')
        if [[ -z "${payload}" || "${valid}" != "1" ]]; then
            index=$((index + 1))
            continue
        fi

        pq=$(db_quote "${payload}")
        has_items=$(db_scalar "SELECT COALESCE(json_array_length(json_extract(${pq}, '$.items')), 0);" 2>/dev/null || printf '0')
        has_delta=$(db_scalar "SELECT CASE WHEN json_extract(${pq}, '$.stock_delta') IS NOT NULL
                                             OR json_extract(${pq}, '$.delta') IS NOT NULL
                                        THEN 1 ELSE 0 END;" 2>/dev/null || printf '0')

        if [[ "${action}" == *SALE* ]] || [[ "${has_items}" =~ ^[1-9][0-9]*$ ]]; then
            if ! _local_repo_remote_sale_apply "${uuid}" "${payload}"; then
                LOCAL_REPO_PULL_ERROR="No se pudo aplicar la venta remota ${uuid}."
                return 1
            fi
            applied=$((applied + 1))
        elif [[ "${has_delta}" == "1" ]]; then
            if ! _local_repo_remote_stock_apply "${uuid}" "${payload}"; then
                LOCAL_REPO_PULL_ERROR="No se pudo aplicar el delta remoto ${uuid}."
                return 1
            fi
            applied=$((applied + 1))
        fi

        index=$((index + 1))
    done

    local remote_id current
    remote_id=$(db_scalar "SELECT COALESCE(json_extract(${q}, '$.last_remote_journal_id'), 0);" 2>/dev/null || printf '0')
    [[ "${remote_id}" =~ ^[0-9]+$ ]] || remote_id=0
    current=$(local_repo_last_remote_journal_id)
    if (( remote_id > current )); then
        local_repo_set_last_remote_journal_id "${remote_id}"
    fi

    LOCAL_REPO_PULL_APPLIED="${applied}"
    printf '%s' "${applied}"
}

local_repo_processed_uuids_json() {
    local response="${1:-}" fallback="${2:-[]}"
    local q uuids
    [[ -z "${fallback}" ]] && fallback='[]'
    q=$(db_quote "${response}")
    uuids=$(db_scalar "SELECT COALESCE(json_group_array(value), '[]')
                       FROM json_each(json_extract(${q}, '$.event_uuids'))
                       WHERE value IS NOT NULL;" 2>/dev/null || true)
    if [[ -z "${uuids}" || "${uuids}" == "[]" ]]; then
        uuids="${fallback}"
    fi
    printf '%s' "${uuids}"
}
