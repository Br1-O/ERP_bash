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
            'phone', phone, 'email', email, 'address', address))
            FROM (SELECT id, name, contact_person, phone, email, address FROM Suppliers ORDER BY id)),
        'customers', (SELECT json_group_array(json_object(
            'id', id, 'name', name, 'type', type, 'phone', phone, 'email', email))
            FROM (SELECT id, name, type, phone, email FROM Customers ORDER BY id)),
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
            'stock_applied', stock_applied, 'order_type', order_type))
            FROM (SELECT id, timestamp, customer_id, subtotal_amount, discount_type,
                         discount_value, discount_amount, total_amount, payment_method,
                         status, notes, created_by, stock_applied, order_type
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
            'created_by', created_by))
            FROM (SELECT id, timestamp, supplier_id, total_amount, notes, status, created_by
                  FROM Purchases ORDER BY id)),
        'purchase_items', (SELECT json_group_array(json_object(
            'id', id, 'purchase_id', purchase_id, 'input_id', input_id,
            'quantity', quantity, 'unit_cost', unit_cost))
            FROM (SELECT id, purchase_id, input_id, quantity, unit_cost
                  FROM PurchaseItems ORDER BY id)),
        'tasting_feedback', (SELECT json_group_array(json_object(
            'id', id, 'product_id', product_id, 'accepted', accepted, 'timestamp', timestamp))
            FROM (SELECT id, product_id, accepted, timestamp FROM TastingFeedback ORDER BY id)),
        'inventory_journal', (SELECT json_group_array(json_object(
            'id', id, 'timestamp', timestamp, 'user', user, 'action', action,
            'entity', entity, 'payload', payload, 'status', status))
            FROM (SELECT id, timestamp, user, action, entity, payload, status
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

    local token_configured="false"
    [[ -n "${token}" ]] && token_configured="true"

    printf '{"configured":%s,"endpoint":%s,"token_configured":%s,"last_at":%s,"last_status":%s,"last_endpoint":%s,"last_message":%s,"last_bytes":%s}' \
        "$([[ -n "${url}" ]] && printf true || printf false)" \
        "$(json_quote "${url}")" "${token_configured}" \
        "$(json_quote "${last_at}")" "$(json_quote "${last_status}")" \
        "$(json_quote "${last_endpoint}")" "$(json_quote "${last_message}")" \
        "$(json_number "${last_bytes:-0}")"
}

local_repo_record_sync() {
    local status="${1:-ok}" endpoint="${2:-}" message="${3:-}" bytes="${4:-0}"
    [[ "${bytes}" =~ ^[0-9]+$ ]] || bytes=0
    db_exec "INSERT INTO SyncLog (timestamp, status, endpoint, message, payload_bytes)
             VALUES (datetime('now', 'localtime'), $(db_quote "${status}"),
                     $(db_quote "${endpoint}"), $(db_quote "${message}"), ${bytes});"
}
