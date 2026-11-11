#!/usr/bin/env bash
#
# Capa de negocio: catálogo, insumos y contactos.

[[ -n "${_ERP_API_CATALOG_LOADED:-}" ]] && return 0
declare -g _ERP_API_CATALOG_LOADED=1

api_list_products_json() {
    local only_active="${1:-0}"
    local where=""
    (( only_active == 1 )) && where="WHERE p.active = 1"

    local rows row id name category stock threshold cost price active seasonal item out=""
    rows=$(db_query "SELECT p.id, p.name, c.name, p.stock, p.min_production_threshold,
                            p.cost, p.price, p.active, p.is_seasonal
                     FROM Products p
                     JOIN Categories c ON c.id = p.category_id
                     ${where}
                     ORDER BY p.name;")

    while IFS='|' read -r id name category stock threshold cost price active seasonal; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"category":%s,"stock":%s,"min_threshold":%s,"cost":%s,"price":%s,"active":%s,"seasonal":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${category}")" \
            "$(json_number "${stock}")" "$(json_number "${threshold}")" \
            "$(json_number "${cost}")" "$(json_number "${price}")" \
            "$(json_number "${active}")" "$(json_number "${seasonal}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '[%s]' "${out}"
}

api_list_inputs_json() {
    local rows row id name category stock unit cost supplier threshold item out=""
    rows=$(db_query "SELECT i.id, i.name, COALESCE(c.name, 'Sin categoría'), i.stock, i.unit,
                            i.cost, COALESCE(s.name, 'Sin proveedor'), i.min_stock_threshold
                     FROM Inputs i
                     LEFT JOIN Categories c ON c.id = i.category_id
                     LEFT JOIN Suppliers s ON s.id = i.supplier_id
                     ORDER BY i.name;")

    while IFS='|' read -r id name category stock unit cost supplier threshold; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"category":%s,"stock":%s,"unit":%s,"cost":%s,"supplier":%s,"min_threshold":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${category}")" \
            "$(json_number "${stock}")" "$(json_quote "${unit}")" \
            "$(json_number "${cost}")" "$(json_quote "${supplier}")" \
            "$(json_number "${threshold}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '[%s]' "${out}"
}

api_list_customers_json() {
    local rows row id name type phone email purchases total item out=""
    rows=$(db_query "SELECT c.id, c.name, c.type, COALESCE(c.phone, ''), COALESCE(c.email, ''),
                            COUNT(s.id), COALESCE(SUM(s.total_amount), 0)
                     FROM Customers c
                     LEFT JOIN Sales s ON s.customer_id = c.id
                     GROUP BY c.id
                     ORDER BY c.name;")

    while IFS='|' read -r id name type phone email purchases total; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"type":%s,"phone":%s,"email":%s,"purchases":%s,"total":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${type}")" \
            "$(json_quote "${phone}")" "$(json_quote "${email}")" \
            "$(json_number "${purchases}")" "$(json_number "${total}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '[%s]' "${out}"
}

api_list_suppliers_json() {
    local rows row id name contact phone email address inputs item out=""
    rows=$(db_query "SELECT s.id, s.name, COALESCE(s.contact_person, ''), COALESCE(s.phone, ''),
                            COALESCE(s.email, ''), COALESCE(s.address, ''), COUNT(i.id)
                     FROM Suppliers s
                     LEFT JOIN Inputs i ON i.supplier_id = s.id
                     GROUP BY s.id
                     ORDER BY s.name;")

    while IFS='|' read -r id name contact phone email address inputs; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"contact":%s,"phone":%s,"email":%s,"address":%s,"inputs":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${contact}")" \
            "$(json_quote "${phone}")" "$(json_quote "${email}")" \
            "$(json_quote "${address}")" "$(json_number "${inputs}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '[%s]' "${out}"
}

api_contacts_json() {
    local search="${1:-}"
    local extra_supplier="" extra_customer=""

    if [[ -n "${search}" ]]; then
        local like
        like=$(db_quote "%${search}%")
        extra_supplier=" AND (LOWER(s.name) LIKE LOWER(${like}) OR LOWER(COALESCE(s.contact_person,'')) LIKE LOWER(${like}) OR LOWER(COALESCE(s.email,'')) LIKE LOWER(${like}))"
        extra_customer=" AND (LOWER(c.name) LIKE LOWER(${like}) OR LOWER(COALESCE(c.email,'')) LIKE LOWER(${like}))"
    fi

    local suppliers customers
    suppliers=$(db_query "SELECT s.id, s.name, COALESCE(s.contact_person, ''), COALESCE(s.phone, ''),
                                COALESCE(s.email, ''), COALESCE(s.address, ''), COUNT(i.id)
                         FROM Suppliers s
                         LEFT JOIN Inputs i ON i.supplier_id = s.id
                         WHERE 1 = 1 ${extra_supplier}
                         GROUP BY s.id ORDER BY s.name;")
    customers=$(db_query "SELECT c.id, c.name, c.type, COALESCE(c.phone, ''), COALESCE(c.email, ''),
                                COUNT(s.id), COALESCE(SUM(s.total_amount), 0)
                         FROM Customers c
                         LEFT JOIN Sales s ON s.customer_id = c.id
                         WHERE 1 = 1 ${extra_customer}
                         GROUP BY c.id ORDER BY c.name;")

    local out_sup="" out_cus="" item row
    local id name contact phone email address inputs

    while IFS='|' read -r id name contact phone email address inputs; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"contact":%s,"phone":%s,"email":%s,"address":%s,"inputs":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${contact}")" \
            "$(json_quote "${phone}")" "$(json_quote "${email}")" \
            "$(json_quote "${address}")" "$(json_number "${inputs}")")
        out_sup+="${out_sup:+,}${item}"
    done <<< "${suppliers}"

    local type purchases total
    while IFS='|' read -r id name type phone email purchases total; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"type":%s,"phone":%s,"email":%s,"purchases":%s,"total":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${type}")" \
            "$(json_quote "${phone}")" "$(json_quote "${email}")" \
            "$(json_number "${purchases}")" "$(json_number "${total}")")
        out_cus+="${out_cus:+,}${item}"
    done <<< "${customers}"

    printf '{"suppliers":[%s],"customers":[%s]}' "${out_sup}" "${out_cus}"
}

api_create_customer() {
    local name="${1:-}" type="${2:-Minorista}" phone="${3:-}" email="${4:-}"

    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de cliente inválido."; return 1; }
    [[ "${type}" != "Mayorista" && "${type}" != "Minorista" ]] && { AUTH_ERROR="Tipo de cliente inválido."; return 1; }
    [[ -n "${email}" && ! "${email}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && { AUTH_ERROR="Email inválido."; return 1; }

    db_set_context_user "${AUTH_USER:-sistema}"
    if ! db_exec "INSERT INTO Customers (name, type, phone, email)
                  VALUES ($(db_quote "${name}"), $(db_quote "${type}"), $(db_quote "${phone}"), $(db_quote "${email}"));"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el cliente.}"
        return 1
    fi
}

api_create_supplier() {
    local name="${1:-}" contact="${2:-}" phone="${3:-}" email="${4:-}" address="${5:-}"

    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de proveedor inválido."; return 1; }
    [[ -n "${email}" && ! "${email}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && { AUTH_ERROR="Email inválido."; return 1; }

    db_set_context_user "${AUTH_USER:-sistema}"
    if ! db_exec "INSERT INTO Suppliers (name, contact_person, phone, email, address)
                  VALUES ($(db_quote "${name}"), $(db_quote "${contact}"), $(db_quote "${phone}"),
                          $(db_quote "${email}"), $(db_quote "${address}"));"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el proveedor.}"
        return 1
    fi
}

api_create_product() {
    local name="${1:-}" category_id="${2:-0}" stock="${3:-0}" threshold="${4:-0}"
    local cost="${5:-0}" price="${6:-0}" seasonal="${7:-0}"

    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de producto inválido."; return 1; }
    [[ ! "${category_id}" =~ ^[0-9]+$ ]] && { AUTH_ERROR="Categoría inválida."; return 1; }
    [[ ! "${stock}" =~ ^[0-9]+$ ]] && { AUTH_ERROR="Stock inválido."; return 1; }
    [[ ! "${threshold}" =~ ^[0-9]+$ ]] && { AUTH_ERROR="Umbral inválido."; return 1; }
    [[ ! "${cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] && { AUTH_ERROR="Costo inválido."; return 1; }
    [[ ! "${price}" =~ ^[0-9]+([.][0-9]+)?$ ]] && { AUTH_ERROR="Precio inválido."; return 1; }
    [[ "${seasonal}" != "0" && "${seasonal}" != "1" ]] && seasonal=0

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Categories WHERE id = ${category_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="La categoría no existe."; return 1; }

    exists=$(db_scalar "SELECT COUNT(*) FROM Products WHERE LOWER(name) = LOWER($(db_quote "${name}"));" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) && { AUTH_ERROR="El producto ya existe."; return 2; }

    db_set_context_user "${AUTH_USER:-sistema}"
    if ! db_exec "INSERT INTO Products (name, category_id, stock, min_production_threshold, cost, price, active, is_seasonal)
                  VALUES ($(db_quote "${name}"), ${category_id}, ${stock}, ${threshold}, ${cost}, ${price}, 1, ${seasonal});"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el producto.}"
        return 1
    fi
}

api_create_input() {
    local name="${1:-}" category_id="${2:-0}" stock="${3:-0}" unit="${4:-unidades}"
    local cost="${5:-0}" supplier_id="${6:-0}" threshold="${7:-0}"

    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de insumo inválido."; return 1; }
    [[ ! "${stock}" =~ ^[0-9]+([.][0-9]+)?$ ]] && { AUTH_ERROR="Stock inválido."; return 1; }
    [[ ! "${cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] && { AUTH_ERROR="Costo inválido."; return 1; }
    [[ ! "${threshold}" =~ ^[0-9]+([.][0-9]+)?$ ]] && { AUTH_ERROR="Umbral inválido."; return 1; }

    local exists safe_category="NULL" safe_supplier="NULL"
    if [[ "${category_id}" =~ ^[0-9]+$ ]] && (( category_id > 0 )); then
        exists=$(db_scalar "SELECT COUNT(*) FROM Categories WHERE id = ${category_id};" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="La categoría no existe."; return 1; }
        safe_category="${category_id}"
    elif [[ "${category_id}" != "0" ]]; then
        AUTH_ERROR="Categoría inválida."
        return 1
    fi

    if [[ "${supplier_id}" =~ ^[0-9]+$ ]] && (( supplier_id > 0 )); then
        exists=$(db_scalar "SELECT COUNT(*) FROM Suppliers WHERE id = ${supplier_id};" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="El proveedor no existe."; return 1; }
        safe_supplier="${supplier_id}"
    elif [[ "${supplier_id}" != "0" ]]; then
        AUTH_ERROR="Proveedor inválido."
        return 1
    fi

    db_set_context_user "${AUTH_USER:-sistema}"
    if ! db_exec "INSERT INTO Inputs (name, category_id, stock, unit, cost, supplier_id, min_stock_threshold)
                  VALUES ($(db_quote "${name}"), ${safe_category}, ${stock}, $(db_quote "${unit}"),
                          ${cost}, ${safe_supplier}, ${threshold});"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el insumo.}"
        return 1
    fi
}

api_restock_input() {
    local input_id="${1:-0}" quantity="${2:-0}"

    [[ ! "${input_id}" =~ ^[0-9]+$ ]] && { AUTH_ERROR="Insumo inválido."; return 1; }
    [[ ! "${quantity}" =~ ^[0-9]+([.][0-9]+)?$ ]] && { AUTH_ERROR="Cantidad inválida."; return 1; }
    if ! LC_ALL=C awk -v q="${quantity}" 'BEGIN { exit !(q > 0) }'; then
        AUTH_ERROR="La cantidad debe ser mayor que cero."
        return 1
    fi

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE id = ${input_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El insumo no existe."; return 2; }

    db_set_context_user "${AUTH_USER:-sistema}"
    if ! db_exec "UPDATE Inputs SET stock = stock + ${quantity} WHERE id = ${input_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo reponer el insumo.}"
        return 1
    fi
}

api_list_categories_json() {
    local rows row id name item out=""
    rows=$(db_query "SELECT id, name FROM Categories ORDER BY name;")
    while IFS='|' read -r id name; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s}' "${id}" "$(json_quote "${name}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"
    printf '[%s]' "${out}"
}
