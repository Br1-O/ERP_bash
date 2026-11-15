#!/usr/bin/env bash

[[ -n "${_ERP_API_INVENTORY_LOADED:-}" ]] && return 0
declare -g _ERP_API_INVENTORY_LOADED=1

declare -g INV_PRODUCT_ID=""
declare -g INV_INPUT_ID=""

api_inv_int() {
    local value="${1:-}" default="${2:-1}" min="${3:-1}" max="${4:-100}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${default}"
    value=$((10#${value}))
    (( value < min )) && value="${min}"
    (( value > max )) && value="${max}"
    printf '%s' "${value}"
}

api_inv_is_positive() {
    LC_ALL=C awk -v value="${1:-0}" 'BEGIN { exit !(value > 0) }'
}

api_inv_is_nonnegative() {
    LC_ALL=C awk -v value="${1:-0}" 'BEGIN { exit !(value >= 0) }'
}

api_inv_decimal() {
    LC_ALL=C awk -v value="${1:-0}" 'BEGIN { printf "%.6f", value }'
}

api_inv_product_available_stock() {
    local product_id="${1:-0}"
    [[ "${product_id}" =~ ^[0-9]+$ ]] || { printf '0'; return 0; }
    db_scalar "SELECT CASE WHEN p.is_combo = 1 THEN COALESCE((
                           SELECT MIN(CAST(cp.stock / ci.quantity AS INTEGER))
                           FROM ComboItems ci
                           JOIN Products cp ON cp.id = ci.component_product_id
                           WHERE ci.combo_product_id = p.id AND cp.active = 1
                       ), 0)
                       ELSE p.stock END
               FROM Products p WHERE p.id = ${product_id};" 2>/dev/null || printf '0'
}

api_inv_product_name_exists() {
    local name="$1" exclude_id="${2:-0}"
    db_scalar "SELECT COUNT(*) FROM Products
               WHERE LOWER(name) = LOWER($(db_quote "${name}"))
                 AND id <> ${exclude_id};" 2>/dev/null || printf '0'
}

api_inv_products_json() {
    local search="${1:-}" category="${2:-0}" state="${3:-active}"
    local page per_page
    page=$(api_inv_int "${4:-1}" 1 1 100000)
    per_page=$(api_inv_int "${5:-8}" 8 1 50)
    [[ "${category}" =~ ^[0-9]+$ ]] || category=0

    local -a where=("1 = 1")
    case "${state}" in
        inactive) where+=("p.active = 0") ;;
        all) ;;
        low) where+=("p.active = 1 AND CASE WHEN p.is_combo = 1 THEN COALESCE((
                          SELECT MIN(CAST(cp.stock / ci.quantity AS INTEGER))
                          FROM ComboItems ci
                          JOIN Products cp ON cp.id = ci.component_product_id
                          WHERE ci.combo_product_id = p.id AND cp.active = 1
                      ), 0) ELSE p.stock END <= p.min_production_threshold") ;;
        *) where+=("p.active = 1") ;;
    esac
    if (( category > 0 )); then
        where+=("p.category_id = ${category}")
    fi
    if [[ -n "${search}" ]]; then
        local like
        like=$(db_quote "%${search}%")
        where+=("(LOWER(p.name) LIKE LOWER(${like}) OR LOWER(c.name) LIKE LOWER(${like}))")
    fi
    local where_sql="" clause sep=""
    for clause in "${where[@]}"; do
        where_sql+="${sep}${clause}"
        sep=" AND "
    done

    local total pages offset
    total=$(db_scalar "SELECT COUNT(*) FROM Products p JOIN Categories c ON c.id = p.category_id WHERE ${where_sql};" 2>/dev/null || printf '0')
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    pages=$(( (total + per_page - 1) / per_page ))
    (( pages < 1 && total > 0 )) && pages=1
    (( page > pages && pages > 0 )) && page="${pages}"
    offset=$(( (page - 1) * per_page ))

    local rows row id name category_name stock physical_stock threshold cost price active seasonal is_combo recipes supplies state_label item out=""
    rows=$(db_query "SELECT p.id, p.name, c.name,
                            CASE WHEN p.is_combo = 1 THEN COALESCE((
                                SELECT MIN(CAST(cp.stock / ci.quantity AS INTEGER))
                                FROM ComboItems ci
                                JOIN Products cp ON cp.id = ci.component_product_id
                                WHERE ci.combo_product_id = p.id AND cp.active = 1
                            ), 0) ELSE p.stock END,
                            p.stock, p.min_production_threshold,
                            p.cost, p.price, p.active, p.is_seasonal, p.is_combo, COUNT(pr.id),
                            COALESCE(GROUP_CONCAT(i.name, ', '), '')
                     FROM Products p
                     JOIN Categories c ON c.id = p.category_id
                     LEFT JOIN ProductRecipe pr ON pr.product_id = p.id
                     LEFT JOIN Inputs i ON i.id = pr.input_id
                     WHERE ${where_sql}
                     GROUP BY p.id
                     ORDER BY p.name
                     LIMIT ${per_page} OFFSET ${offset};")

    while IFS='|' read -r id name category_name stock physical_stock threshold cost price active seasonal is_combo recipes supplies; do
        [[ -z "${id}" ]] && continue
        if (( active != 1 )); then
            state_label="inactivo"
        elif LC_ALL=C awk -v s="${stock}" -v t="${threshold}" 'BEGIN { exit !(s <= t) }'; then
            state_label="bajo"
        else
            state_label="ok"
        fi
        item=$(printf '{"id":%d,"name":%s,"category":%s,"stock":%s,"physical_stock":%s,"min_threshold":%s,"cost":%s,"price":%s,"active":%s,"seasonal":%s,"is_combo":%s,"recipe_count":%s,"supplies":%s,"state":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${category_name}")" \
            "$(json_number "${stock}")" "$(json_number "${physical_stock}")" "$(json_number "${threshold}")" \
            "$(json_number "${cost}")" "$(json_number "${price}")" \
            "$(json_number "${active}")" "$(json_number "${seasonal}")" "$(json_number "${is_combo}")" \
            "$(json_number "${recipes}")" "$(json_quote "${supplies}")" "$(json_quote "${state_label}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '{"items":[%s],"total":%s,"page":%s,"per_page":%s,"pages":%s}' \
        "${out}" "${total}" "${page}" "${per_page}" "${pages}"
}

api_inv_inputs_json() {
    local search="${1:-}" supplier="${2:-0}" state="${3:-active}"
    local page per_page
    page=$(api_inv_int "${4:-1}" 1 1 100000)
    per_page=$(api_inv_int "${5:-8}" 8 1 50)
    [[ "${supplier}" =~ ^[0-9]+$ ]] || supplier=0

    local -a where=("1 = 1")
    case "${state}" in
        inactive) where+=("i.active = 0") ;;
        all) ;;
        low) where+=("i.active = 1 AND i.stock <= i.min_stock_threshold") ;;
        *) where+=("i.active = 1") ;;
    esac
    if (( supplier > 0 )); then
        where+=("i.supplier_id = ${supplier}")
    fi
    if [[ -n "${search}" ]]; then
        local like
        like=$(db_quote "%${search}%")
        where+=("(LOWER(i.name) LIKE LOWER(${like}) OR LOWER(COALESCE(s.name, '')) LIKE LOWER(${like}) OR LOWER(COALESCE(c.name, '')) LIKE LOWER(${like}))")
    fi
    local where_sql="" clause sep=""
    for clause in "${where[@]}"; do
        where_sql+="${sep}${clause}"
        sep=" AND "
    done

    local total pages offset
    total=$(db_scalar "SELECT COUNT(*) FROM Inputs i
                       LEFT JOIN Suppliers s ON s.id = i.supplier_id
                       LEFT JOIN Categories c ON c.id = i.category_id
                       WHERE ${where_sql};" 2>/dev/null || printf '0')
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    pages=$(( (total + per_page - 1) / per_page ))
    (( page > pages && pages > 0 )) && page="${pages}"
    offset=$(( (page - 1) * per_page ))

    local rows row id name category_name category_id stock unit cost supplier_name supplier_id threshold active uses state_label item out=""
    rows=$(db_query "SELECT i.id, i.name, COALESCE(c.name, 'Sin categoría'), COALESCE(i.category_id, 0),
                            i.stock, i.unit, i.cost, COALESCE(s.name, 'Sin proveedor'),
                            COALESCE(i.supplier_id, 0), i.min_stock_threshold, i.active,
                            COUNT(DISTINCT pr.product_id)
                     FROM Inputs i
                     LEFT JOIN Categories c ON c.id = i.category_id
                     LEFT JOIN Suppliers s ON s.id = i.supplier_id
                     LEFT JOIN ProductRecipe pr ON pr.input_id = i.id
                     WHERE ${where_sql}
                     GROUP BY i.id
                     ORDER BY i.name
                     LIMIT ${per_page} OFFSET ${offset};")

    while IFS='|' read -r id name category_name category_id stock unit cost supplier_name supplier_id threshold active uses; do
        [[ -z "${id}" ]] && continue
        if (( active != 1 )); then
            state_label="inactivo"
        elif LC_ALL=C awk -v s="${stock}" -v t="${threshold}" 'BEGIN { exit !(s <= t) }'; then
            state_label="bajo"
        else
            state_label="ok"
        fi
        item=$(printf '{"id":%d,"name":%s,"category":%s,"category_id":%s,"stock":%s,"unit":%s,"cost":%s,"supplier":%s,"supplier_id":%s,"min_threshold":%s,"active":%s,"recipe_uses":%s,"state":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_quote "${category_name}")" \
            "$(json_number "${category_id}")" "$(json_number "${stock}")" \
            "$(json_quote "${unit}")" "$(json_number "${cost}")" \
            "$(json_quote "${supplier_name}")" "$(json_number "${supplier_id}")" \
            "$(json_number "${threshold}")" "$(json_number "${active}")" \
            "$(json_number "${uses}")" "$(json_quote "${state_label}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"

    printf '{"items":[%s],"total":%s,"page":%s,"per_page":%s,"pages":%s}' \
        "${out}" "${total}" "${page}" "${per_page}" "${pages}"
}

api_inv_product_detail_json() {
    local product_id="${1:-0}"
    [[ "${product_id}" =~ ^[0-9]+$ ]] || return 1

    local row id name category_id category stock threshold cost price active seasonal is_combo recipe_description
    row=$(db_query "SELECT p.id, p.name, p.category_id, c.name, p.stock, p.min_production_threshold,
                           p.cost, p.price, p.active, p.is_seasonal, p.is_combo,
                           COALESCE(p.recipe_description, '')
                    FROM Products p JOIN Categories c ON c.id = p.category_id
                    WHERE p.id = ${product_id};")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id name category_id category stock threshold cost price active seasonal is_combo recipe_description <<< "${row}"

    local available_stock
    available_stock=$(api_inv_product_available_stock "${product_id}")

    local recipe_rows recipe_out="" rid input_id input_name unit qty_per_unit input_stock input_cost supplier
    recipe_rows=$(db_query "SELECT pr.id, pr.input_id, i.name, i.unit, pr.quantity_per_unit,
                                   i.stock, i.cost, COALESCE(s.name, 'Sin proveedor')
                            FROM ProductRecipe pr
                            JOIN Inputs i ON i.id = pr.input_id
                            LEFT JOIN Suppliers s ON s.id = i.supplier_id
                            WHERE pr.product_id = ${product_id}
                            ORDER BY i.name;")
    while IFS='|' read -r rid input_id input_name unit qty_per_unit input_stock input_cost supplier; do
        [[ -z "${rid}" ]] && continue
        recipe_out+="${recipe_out:+,}$(printf '{"id":%s,"input_id":%s,"input_name":%s,"unit":%s,"quantity_per_unit":%s,"input_stock":%s,"input_cost":%s,"supplier":%s}' \
            "$(json_number "${rid}")" "$(json_number "${input_id}")" "$(json_quote "${input_name}")" \
            "$(json_quote "${unit}")" "$(json_number "${qty_per_unit}")" \
            "$(json_number "${input_stock}")" "$(json_number "${input_cost}")" \
            "$(json_quote "${supplier}")")"
    done <<< "${recipe_rows}"

    local step_rows step_out="" instruction
    step_rows=$(db_query "SELECT instruction FROM ProductRecipeStep
                          WHERE product_id = ${product_id} ORDER BY step_number;")
    while IFS= read -r instruction; do
        [[ -z "${instruction}" ]] && continue
        step_out+="${step_out:+,}$(json_quote "${instruction}")"
    done <<< "${step_rows}"

    local combo_rows combo_out="" component_id component_name component_stock quantity
    combo_rows=$(db_query "SELECT ci.component_product_id, p.name, p.stock, ci.quantity
                           FROM ComboItems ci
                           JOIN Products p ON p.id = ci.component_product_id
                           WHERE ci.combo_product_id = ${product_id}
                           ORDER BY p.name;")
    while IFS='|' read -r component_id component_name component_stock quantity; do
        [[ -z "${component_id}" ]] && continue
        combo_out+="${combo_out:+,}$(printf '{"component_product_id":%s,"component_name":%s,"stock":%s,"quantity":%s}' \
            "$(json_number "${component_id}")" "$(json_quote "${component_name}")" \
            "$(json_number "${component_stock}")" "$(json_number "${quantity}")")"
    done <<< "${combo_rows}"

    local max_units=0
    if [[ -n "${recipe_rows}" ]]; then
        max_units=$(LC_ALL=C awk -F'|' '
            { if ($5 > 0) { units = int($6 / $5); if (min == "" || units < min) min = units } }
            END { if (min == "") min = 0; print min }' <<< "${recipe_rows}")
    fi

    printf '{"id":%s,"name":%s,"category_id":%s,"category":%s,"stock":%s,"available_stock":%s,"min_threshold":%s,"cost":%s,"price":%s,"active":%s,"seasonal":%s,"is_combo":%s,"recipe_description":%s,"max_producible":%s,"recipe":[%s],"recipe_steps":[%s],"combo":[%s]}' \
        "$(json_number "${id}")" "$(json_quote "${name}")" "$(json_number "${category_id}")" \
        "$(json_quote "${category}")" "$(json_number "${stock}")" "$(json_number "${available_stock}")" \
        "$(json_number "${threshold}")" "$(json_number "${cost}")" "$(json_number "${price}")" \
        "$(json_number "${active}")" "$(json_number "${seasonal}")" "$(json_number "${is_combo}")" \
        "$(json_quote "${recipe_description}")" "$(json_number "${max_units}")" \
        "${recipe_out}" "${step_out}" "${combo_out}"
}

api_inv_input_detail_json() {
    local input_id="${1:-0}"
    [[ "${input_id}" =~ ^[0-9]+$ ]] || return 1

    local row id name category_id category stock unit cost supplier_id supplier contact phone email threshold active
    row=$(db_query "SELECT i.id, i.name, COALESCE(i.category_id, 0), COALESCE(c.name, 'Sin categoría'),
                           i.stock, i.unit, i.cost, COALESCE(i.supplier_id, 0),
                           COALESCE(s.name, 'Sin proveedor'), COALESCE(s.contact_person, ''),
                           COALESCE(s.phone, ''), COALESCE(s.email, ''), i.min_stock_threshold, i.active
                    FROM Inputs i
                    LEFT JOIN Categories c ON c.id = i.category_id
                    LEFT JOIN Suppliers s ON s.id = i.supplier_id
                    WHERE i.id = ${input_id};")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id name category_id category stock unit cost supplier_id supplier contact phone email threshold active <<< "${row}"

    local product_rows product_out="" pid product_name qty_per_unit
    product_rows=$(db_query "SELECT p.id, p.name, pr.quantity_per_unit
                             FROM ProductRecipe pr
                             JOIN Products p ON p.id = pr.product_id
                             WHERE pr.input_id = ${input_id}
                             ORDER BY p.name;")
    while IFS='|' read -r pid product_name qty_per_unit; do
        [[ -z "${pid}" ]] && continue
        product_out+="${product_out:+,}$(printf '{"id":%s,"name":%s,"quantity_per_unit":%s}' \
            "$(json_number "${pid}")" "$(json_quote "${product_name}")" "$(json_number "${qty_per_unit}")")"
    done <<< "${product_rows}"

    local purchase_rows purchase_out="" purchase_id purchase_date purchase_supplier quantity unit_cost
    purchase_rows=$(db_query "SELECT pu.id, datetime(pu.timestamp), COALESCE(s.name, 'Sin proveedor'),
                                     pi.quantity, pi.unit_cost
                              FROM PurchaseItems pi
                              JOIN Purchases pu ON pu.id = pi.purchase_id
                              LEFT JOIN Suppliers s ON s.id = pu.supplier_id
                              WHERE pi.input_id = ${input_id}
                              ORDER BY pu.timestamp DESC
                              LIMIT 5;")
    while IFS='|' read -r purchase_id purchase_date purchase_supplier quantity unit_cost; do
        [[ -z "${purchase_id}" ]] && continue
        purchase_out+="${purchase_out:+,}$(printf '{"id":%s,"date":%s,"supplier":%s,"quantity":%s,"unit_cost":%s}' \
            "$(json_number "${purchase_id}")" "$(json_quote "${purchase_date}")" \
            "$(json_quote "${purchase_supplier}")" "$(json_number "${quantity}")" \
            "$(json_number "${unit_cost}")")"
    done <<< "${purchase_rows}"

    printf '{"id":%s,"name":%s,"category_id":%s,"category":%s,"stock":%s,"unit":%s,"cost":%s,"supplier_id":%s,"supplier":%s,"contact":%s,"phone":%s,"email":%s,"min_threshold":%s,"active":%s,"products":[%s],"purchases":[%s]}' \
        "$(json_number "${id}")" "$(json_quote "${name}")" "$(json_number "${category_id}")" \
        "$(json_quote "${category}")" "$(json_number "${stock}")" "$(json_quote "${unit}")" \
        "$(json_number "${cost}")" "$(json_number "${supplier_id}")" "$(json_quote "${supplier}")" \
        "$(json_quote "${contact}")" "$(json_quote "${phone}")" "$(json_quote "${email}")" \
        "$(json_number "${threshold}")" "$(json_number "${active}")" "${product_out}" "${purchase_out}"
}

api_inv_meta_json() {
    local cat_rows sup_rows input_rows cat_out="" sup_out="" input_out=""
    local id name contact phone unit stock supplier_id supplier_name
    cat_rows=$(db_query "SELECT id, name FROM Categories ORDER BY name;")
    while IFS='|' read -r id name; do
        [[ -z "${id}" ]] && continue
        cat_out+="${cat_out:+,}$(printf '{"id":%s,"name":%s}' "$(json_number "${id}")" "$(json_quote "${name}")")"
    done <<< "${cat_rows}"

    sup_rows=$(db_query "SELECT id, name, COALESCE(contact_person, ''), COALESCE(phone, '')
                         FROM Suppliers ORDER BY name;")
    while IFS='|' read -r id name contact phone; do
        [[ -z "${id}" ]] && continue
        sup_out+="${sup_out:+,}$(printf '{"id":%s,"name":%s,"contact":%s,"phone":%s}' \
            "$(json_number "${id}")" "$(json_quote "${name}")" "$(json_quote "${contact}")" "$(json_quote "${phone}")")"
    done <<< "${sup_rows}"

    input_rows=$(db_query "SELECT i.id, i.name, i.unit, i.stock, COALESCE(i.supplier_id, 0),
                                  COALESCE(s.name, 'Sin proveedor')
                           FROM Inputs i
                           LEFT JOIN Suppliers s ON s.id = i.supplier_id
                           WHERE i.active = 1
                           ORDER BY i.name;")
    while IFS='|' read -r id name unit stock supplier_id supplier_name; do
        [[ -z "${id}" ]] && continue
        input_out+="${input_out:+,}$(printf '{"id":%s,"name":%s,"unit":%s,"stock":%s,"supplier_id":%s,"supplier":%s}' \
            "$(json_number "${id}")" "$(json_quote "${name}")" "$(json_quote "${unit}")" \
            "$(json_number "${stock}")" "$(json_number "${supplier_id}")" "$(json_quote "${supplier_name}")")"
    done <<< "${input_rows}"

    printf '{"categories":[%s],"suppliers":[%s],"inputs":[%s]}' "${cat_out}" "${sup_out}" "${input_out}"
}

api_inv_supplier_detail_json() {
    local supplier_id="${1:-0}"
    [[ "${supplier_id}" =~ ^[0-9]+$ ]] || return 1

    local row id name contact phone email address
    row=$(db_query "SELECT id, name, COALESCE(contact_person, ''), COALESCE(phone, ''),
                           COALESCE(email, ''), COALESCE(address, '')
                    FROM Suppliers WHERE id = ${supplier_id};")
    [[ -z "${row}" ]] && return 1
    IFS='|' read -r id name contact phone email address <<< "${row}"

    local input_rows input_out="" iid input_name stock unit cost threshold
    input_rows=$(db_query "SELECT id, name, stock, unit, cost, min_stock_threshold
                           FROM Inputs WHERE supplier_id = ${supplier_id} AND active = 1
                           ORDER BY name;")
    while IFS='|' read -r iid input_name stock unit cost threshold; do
        [[ -z "${iid}" ]] && continue
        input_out+="${input_out:+,}$(printf '{"id":%s,"name":%s,"stock":%s,"unit":%s,"cost":%s,"min_threshold":%s}' \
            "$(json_number "${iid}")" "$(json_quote "${input_name}")" "$(json_number "${stock}")" \
            "$(json_quote "${unit}")" "$(json_number "${cost}")" "$(json_number "${threshold}")")"
    done <<< "${input_rows}"

    local purchase_rows count total last_purchase
    purchase_rows=$(db_query "SELECT COUNT(*), COALESCE(SUM(total_amount), 0), COALESCE(MAX(datetime(timestamp)), '')
                              FROM Purchases WHERE supplier_id = ${supplier_id};")
    IFS='|' read -r count total last_purchase <<< "${purchase_rows}"

    printf '{"id":%s,"name":%s,"contact":%s,"phone":%s,"email":%s,"address":%s,"purchases":%s,"total":%s,"last_purchase":%s,"inputs":[%s]}' \
        "$(json_number "${id}")" "$(json_quote "${name}")" "$(json_quote "${contact}")" \
        "$(json_quote "${phone}")" "$(json_quote "${email}")" "$(json_quote "${address}")" \
        "$(json_number "${count}")" "$(json_number "${total}")" "$(json_quote "${last_purchase}")" "${input_out}"
}

_api_inv_replace_recipe() {
    local product_id="$1"
    local -n _recipe_ref_ids=$2
    local -n _recipe_ref_qtys=$3

    db_exec "DELETE FROM ProductRecipe WHERE product_id = ${product_id};" || return 1

    local -A seen=()
    local i input_id quantity exists
    for (( i = 0; i < ${#_recipe_ref_ids[@]}; i++ )); do
        input_id="${_recipe_ref_ids[$i]}"
        quantity="${_recipe_ref_qtys[$i]:-0}"
        [[ "${input_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Insumo inválido en la receta."; return 1; }
        [[ -n "${seen[${input_id}]:-}" ]] && { AUTH_ERROR="La receta contiene insumos duplicados."; return 1; }
        seen["${input_id}"]=1
        api_inv_is_positive "${quantity}" || { AUTH_ERROR="Cantidad de receta inválida."; return 1; }
        exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE id = ${input_id} AND active = 1;" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="El insumo ${input_id} no existe o está inactivo."; return 1; }
        if ! db_exec "INSERT INTO ProductRecipe (product_id, input_id, quantity_per_unit)
                      VALUES (${product_id}, ${input_id}, $(api_inv_decimal "${quantity}"));"; then
            AUTH_ERROR="No se pudo guardar la receta. ${DB_LAST_ERROR}"
            return 1
        fi
    done
    return 0
}

_api_inv_replace_recipe_steps() {
    local product_id="$1" steps_text="${2:-}"

    db_exec "DELETE FROM ProductRecipeStep WHERE product_id = ${product_id};" || return 1
    [[ -z "${steps_text}" ]] && return 0

    steps_text="${steps_text//\\r/}"
    steps_text="${steps_text//\\n/$'\n'}"
    steps_text="${steps_text//$'\r'/}"

    local count=0 line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "${line}" ]] && continue
        (( count += 1 ))
        (( count <= 20 )) || { AUTH_ERROR="La receta admite hasta 20 pasos."; return 1; }
        [[ ${#line} -le 500 ]] || { AUTH_ERROR="Cada paso admite hasta 500 caracteres."; return 1; }
        if ! db_exec "INSERT INTO ProductRecipeStep (product_id, step_number, instruction)
                      VALUES (${product_id}, ${count}, $(db_quote "${line}"));"; then
            AUTH_ERROR="No se pudieron guardar los pasos de la receta. ${DB_LAST_ERROR}"
            return 1
        fi
    done <<< "${steps_text}"
    return 0
}

_api_inv_replace_combo_items() {
    local product_id="$1"
    local -n _component_ref_ids=$2
    local -n _component_ref_qtys=$3

    db_exec "DELETE FROM ComboItems WHERE combo_product_id = ${product_id};" || return 1

    local -A seen=()
    local i component_id quantity exists component_name
    for (( i = 0; i < ${#_component_ref_ids[@]}; i++ )); do
        component_id="${_component_ref_ids[$i]}"
        quantity="${_component_ref_qtys[$i]:-0}"
        [[ "${component_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Componente inválido en el combo."; return 1; }
        (( component_id != product_id )) || { AUTH_ERROR="Un combo no puede contenerse a sí mismo."; return 1; }
        [[ -n "${seen[${component_id}]:-}" ]] && { AUTH_ERROR="El combo contiene componentes duplicados."; return 1; }
        seen["${component_id}"]=1
        [[ "${quantity}" =~ ^[1-9][0-9]*$ ]] || { AUTH_ERROR="Cantidad de componente inválida."; return 1; }
        exists=$(db_query "SELECT name, is_combo FROM Products WHERE id = ${component_id} AND active = 1;")
        [[ -z "${exists}" ]] && { AUTH_ERROR="El componente ${component_id} no existe o está inactivo."; return 1; }
        component_name="${exists%%|*}"
        [[ "${exists##*|}" == "1" ]] && { AUTH_ERROR="El producto '${component_name}' es un combo y no puede ser componente."; return 1; }
        if ! db_exec "INSERT INTO ComboItems (combo_product_id, component_product_id, quantity)
                      VALUES (${product_id}, ${component_id}, ${quantity});"; then
            AUTH_ERROR="No se pudo guardar el combo. ${DB_LAST_ERROR}"
            return 1
        fi
    done
    return 0
}

_api_inv_consume_inputs() {
    local product_id="$1" units="$2" use_custom="$3"
    local -n _custom_ref_ids=$4
    local -n _custom_ref_qtys=$5

    local -a input_ids=()
    local -a quantities=()
    local rows row input_id qty

    if (( use_custom == 1 )) && (( ${#_custom_ref_ids[@]} > 0 )); then
        input_ids=("${_custom_ref_ids[@]}")
        quantities=("${_custom_ref_qtys[@]}")
    else
        rows=$(db_query "SELECT input_id, quantity_per_unit FROM ProductRecipe
                         WHERE product_id = ${product_id} ORDER BY input_id;")
        while IFS='|' read -r input_id qty; do
            [[ -z "${input_id}" ]] && continue
            input_ids+=("${input_id}")
            quantities+=("${qty}")
        done <<< "${rows}"
    fi

    (( ${#input_ids[@]} > 0 )) || { AUTH_ERROR="El producto no tiene receta asociada."; return 1; }

    local -A seen=()
    local -A totals=()
    local i total
    for (( i = 0; i < ${#input_ids[@]}; i++ )); do
        input_id="${input_ids[$i]}"
        qty="${quantities[$i]:-0}"
        [[ "${input_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Insumo inválido para el consumo."; return 1; }
        [[ -n "${seen[${input_id}]:-}" ]] && { AUTH_ERROR="El consumo contiene insumos duplicados."; return 1; }
        seen["${input_id}"]=1
        api_inv_is_positive "${qty}" || { AUTH_ERROR="Cantidad de consumo inválida."; return 1; }
        if (( use_custom == 1 && ${#_custom_ref_ids[@]} > 0 )); then
            total="${qty}"
        else
            total=$(LC_ALL=C awk -v q="${qty}" -v u="${units}" 'BEGIN { printf "%.6f", q * u }')
        fi
        totals["${input_id}"]="${total}"
    done

    local stock name unit
    for input_id in "${!totals[@]}"; do
        total="${totals[${input_id}]}"
        row=$(db_query "SELECT stock, name, unit FROM Inputs WHERE id = ${input_id};")
        [[ -z "${row}" ]] && { AUTH_ERROR="El insumo ${input_id} no existe."; return 1; }
        IFS='|' read -r stock name unit <<< "${row}"
        if ! LC_ALL=C awk -v available="${stock}" -v needed="${total}" 'BEGIN { exit !(available >= needed) }'; then
            AUTH_ERROR="Stock insuficiente de '${name}' (disponible: ${stock} ${unit}, necesario: ${total} ${unit})."
            return 1
        fi
        if ! db_exec "UPDATE Inputs SET stock = stock - ${total} WHERE id = ${input_id};"; then
            AUTH_ERROR="No se pudo descontar el insumo ${name}."
            return 1
        fi
        db_exec "INSERT INTO InventoryJournal (user, action, entity, payload, status)
                 VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
                         'RECIPE_CONSUMPTION', 'Inputs',
                         'product_id=${product_id};input_id=${input_id};qty=${total}',
                         'DONE');" >/dev/null 2>&1 || true
    done
    return 0
}

api_inv_create_product() {
    local name="${1:-}" category_id="${2:-0}" stock="${3:-0}" threshold="${4:-0}"
    local cost="${5:-0}" price="${6:-0}" seasonal="${7:-0}" consume="${8:-0}"
    local is_combo="${9:-0}" recipe_description="${10:-}" steps_text="${11:-}"
    local -n _recipe_ids=${12}
    local -n _recipe_qtys=${13}
    local -n _component_ids=${14}
    local -n _component_qtys=${15}

    AUTH_ERROR=""
    INV_PRODUCT_ID=""

    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de producto inválido."; return 1; }
    [[ "${category_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Categoría inválida."; return 1; }
    [[ "${stock}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Stock inválido."; return 1; }
    [[ "${threshold}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Umbral inválido."; return 1; }
    [[ "${cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Costo inválido."; return 1; }
    [[ "${price}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Precio inválido."; return 1; }
    [[ "${seasonal}" == "1" ]] || seasonal=0
    [[ "${consume}" == "1" ]] || consume=0
    [[ "${is_combo}" == "1" ]] || is_combo=0
    [[ ${#recipe_description} -le 2000 ]] || { AUTH_ERROR="La descripción de la receta es demasiado larga."; return 1; }

    if (( is_combo == 1 )); then
        consume=0
        stock=0
    fi

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Categories WHERE id = ${category_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="La categoría no existe."; return 1; }
    exists=$(api_inv_product_name_exists "${name}" 0)
    (( ${exists:-0} > 0 )) && { AUTH_ERROR="El producto ya existe."; return 2; }
    if (( is_combo == 1 && ${#_component_ids[@]} == 0 )); then
        AUTH_ERROR="Debe asociar al menos un componente al combo."
        return 1
    fi
    if (( is_combo == 0 && consume == 1 && ${#_recipe_ids[@]} == 0 )); then
        AUTH_ERROR="Debe asociar una receta para consumir insumos."
        return 1
    fi

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "INSERT INTO Products (name, category_id, stock, min_production_threshold, cost, price,
                                        active, is_seasonal, is_combo, recipe_description)
                  VALUES ($(db_quote "${name}"), ${category_id}, 0, ${threshold}, ${cost}, ${price},
                          1, ${seasonal}, ${is_combo}, $(db_quote "${recipe_description}"));"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el producto.}"
        tx_rollback
        return 1
    fi
    INV_PRODUCT_ID=$(db_last_insert_id)

    if ! _api_inv_replace_recipe "${INV_PRODUCT_ID}" _recipe_ids _recipe_qtys; then
        tx_rollback
        return 1
    fi
    if ! _api_inv_replace_recipe_steps "${INV_PRODUCT_ID}" "${steps_text}"; then
        tx_rollback
        return 1
    fi
    if (( is_combo == 1 )); then
        if ! _api_inv_replace_combo_items "${INV_PRODUCT_ID}" _component_ids _component_qtys; then
            tx_rollback
            return 1
        fi
    fi

    if (( stock > 0 )); then
        if (( consume == 1 )); then
            if ! _api_inv_consume_inputs "${INV_PRODUCT_ID}" "${stock}" 0 _recipe_ids _recipe_qtys; then
                tx_rollback
                return 1
            fi
        fi
        if ! db_exec "UPDATE Products SET stock = ${stock} WHERE id = ${INV_PRODUCT_ID};"; then
            AUTH_ERROR="No se pudo inicializar el stock."
            tx_rollback
            return 1
        fi
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la creación del producto."
        tx_rollback
        return 1
    fi
    return 0
}

api_inv_update_product() {
    local product_id="${1:-0}" name="${2:-}" category_id="${3:-0}" threshold="${4:-0}"
    local cost="${5:-0}" price="${6:-0}" seasonal="${7:-0}" active="${8:-1}"
    local update_recipe="${9:-0}" is_combo="${10:-0}" recipe_description="${11:-}"
    local steps_text="${12:-}" update_combo="${13:-0}"
    local -n _recipe_ids=${14}
    local -n _recipe_qtys=${15}
    local -n _component_ids=${16}
    local -n _component_qtys=${17}

    AUTH_ERROR=""
    [[ "${product_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Producto inválido."; return 1; }
    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de producto inválido."; return 1; }
    [[ "${category_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Categoría inválida."; return 1; }
    [[ "${threshold}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Umbral inválido."; return 1; }
    [[ "${cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Costo inválido."; return 1; }
    [[ "${price}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Precio inválido."; return 1; }
    [[ "${seasonal}" == "1" ]] || seasonal=0
    [[ "${active}" == "0" ]] || active=1
    [[ "${update_recipe}" == "1" ]] || update_recipe=0
    [[ "${update_combo}" == "1" ]] || update_combo=0
    [[ "${is_combo}" == "1" ]] || is_combo=0
    [[ ${#recipe_description} -le 2000 ]] || { AUTH_ERROR="La descripción de la receta es demasiado larga."; return 1; }

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Products WHERE id = ${product_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El producto no existe."; return 2; }
    exists=$(db_scalar "SELECT COUNT(*) FROM Categories WHERE id = ${category_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="La categoría no existe."; return 1; }
    exists=$(api_inv_product_name_exists "${name}" "${product_id}")
    (( ${exists:-0} > 0 )) && { AUTH_ERROR="Ya existe otro producto con ese nombre."; return 2; }

    if (( is_combo == 1 )); then
        exists=$(db_scalar "SELECT COUNT(*) FROM ComboItems WHERE component_product_id = ${product_id};" 2>/dev/null || printf '0')
        (( ${exists:-0} == 0 )) || { AUTH_ERROR="El producto es componente de un combo y no puede convertirse en combo."; return 1; }
        if (( update_combo == 1 && ${#_component_ids[@]} == 0 )); then
            AUTH_ERROR="Debe asociar al menos un componente al combo."
            return 1
        fi
    fi

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if ! db_exec "UPDATE Products
                  SET name = $(db_quote "${name}"), category_id = ${category_id},
                      min_production_threshold = ${threshold}, cost = ${cost},
                      price = ${price}, is_seasonal = ${seasonal}, active = ${active},
                      is_combo = ${is_combo}, recipe_description = $(db_quote "${recipe_description}"),
                      stock = CASE WHEN ${is_combo} = 1 THEN 0 ELSE stock END
                  WHERE id = ${product_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo actualizar el producto.}"
        tx_rollback
        return 1
    fi

    if (( update_recipe == 1 )); then
        if ! _api_inv_replace_recipe "${product_id}" _recipe_ids _recipe_qtys; then
            tx_rollback
            return 1
        fi
        if ! _api_inv_replace_recipe_steps "${product_id}" "${steps_text}"; then
            tx_rollback
            return 1
        fi
    fi

    if (( update_combo == 1 )); then
        if ! _api_inv_replace_combo_items "${product_id}" _component_ids _component_qtys; then
            tx_rollback
            return 1
        fi
    fi

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar la actualización del producto."
        tx_rollback
        return 1
    fi
    return 0
}

api_inv_delete_product() {
    local product_id="${1:-0}"
    AUTH_ERROR=""
    [[ "${product_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Producto inválido."; return 1; }

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Products WHERE id = ${product_id} AND active = 1;" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El producto no existe o ya está inactivo."; return 2; }

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    if ! db_exec "UPDATE Products SET active = 0 WHERE id = ${product_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo eliminar el producto.}"
        return 1
    fi
    return 0
}

api_inv_adjust_product_stock() {
    local product_id="${1:-0}" quantity="${2:-0}" mode="${3:-add}" consume="${4:-0}"
    local -n _custom_ids=$5
    local -n _custom_qtys=$6

    AUTH_ERROR=""
    [[ "${product_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Producto inválido."; return 1; }
    [[ "${quantity}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Cantidad inválida."; return 1; }
    [[ "${mode}" == "set" ]] || mode="add"
    [[ "${consume}" == "1" ]] || consume=0

    local row current name delta is_combo
    row=$(db_query "SELECT stock, name, is_combo FROM Products WHERE id = ${product_id};")
    [[ -z "${row}" ]] && { AUTH_ERROR="El producto no existe."; return 2; }
    IFS='|' read -r current name is_combo <<< "${row}"
    (( is_combo == 0 )) || { AUTH_ERROR="El stock de un combo se calcula desde sus componentes."; return 1; }

    if [[ "${mode}" == "set" ]]; then
        delta=$(( quantity - current ))
    else
        (( quantity > 0 )) || { AUTH_ERROR="La cantidad a agregar debe ser mayor que cero."; return 1; }
        delta="${quantity}"
    fi
    (( current + delta >= 0 )) || { AUTH_ERROR="El stock no puede quedar negativo."; return 1; }
    (( delta == 0 )) && { AUTH_ERROR="No hay cambios de stock para aplicar."; return 1; }

    tx_begin || { AUTH_ERROR="No se pudo iniciar la transacción."; return 1; }
    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true

    if (( delta > 0 && consume == 1 )); then
        if ! _api_inv_consume_inputs "${product_id}" "${delta}" "$([[ ${#_custom_ids[@]} -gt 0 ]] && printf 1 || printf 0)" _custom_ids _custom_qtys; then
            tx_rollback
            return 1
        fi
    fi

    if ! db_exec "UPDATE Products SET stock = stock + (${delta}) WHERE id = ${product_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo actualizar el stock.}"
        tx_rollback
        return 1
    fi

    db_exec "INSERT INTO InventoryJournal (user, action, entity, payload, status)
             VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
                     'PRODUCT_STOCK_${mode^^}', 'Products',
                     'product_id=${product_id};delta=${delta};consume=${consume}',
                     'DONE');" >/dev/null 2>&1 || true

    if ! tx_commit; then
        AUTH_ERROR="No se pudo confirmar el ajuste de stock."
        tx_rollback
        return 1
    fi
    return 0
}

api_inv_create_input() {
    local name="${1:-}" category_id="${2:-0}" stock="${3:-0}" unit="${4:-unidades}"
    local cost="${5:-0}" supplier_id="${6:-0}" threshold="${7:-0}"

    AUTH_ERROR=""
    INV_INPUT_ID=""
    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de insumo inválido."; return 1; }
    [[ "${stock}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Stock inválido."; return 1; }
    [[ "${cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Costo inválido."; return 1; }
    [[ "${threshold}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Umbral inválido."; return 1; }
    [[ -z "${unit}" || ${#unit} -gt 30 ]] && { AUTH_ERROR="Unidad inválida."; return 1; }

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE LOWER(name) = LOWER($(db_quote "${name}"));" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) && { AUTH_ERROR="El insumo ya existe."; return 2; }

    local safe_category="NULL" safe_supplier="NULL"
    if [[ "${category_id}" =~ ^[0-9]+$ ]] && (( category_id > 0 )); then
        exists=$(db_scalar "SELECT COUNT(*) FROM Categories WHERE id = ${category_id};" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="La categoría no existe."; return 1; }
        safe_category="${category_id}"
    fi
    if [[ "${supplier_id}" =~ ^[0-9]+$ ]] && (( supplier_id > 0 )); then
        exists=$(db_scalar "SELECT COUNT(*) FROM Suppliers WHERE id = ${supplier_id};" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="El proveedor no existe."; return 1; }
        safe_supplier="${supplier_id}"
    fi

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    if ! db_exec "INSERT INTO Inputs (name, category_id, stock, unit, cost, supplier_id, min_stock_threshold, active)
                  VALUES ($(db_quote "${name}"), ${safe_category}, $(api_inv_decimal "${stock}"),
                          $(db_quote "${unit}"), $(api_inv_decimal "${cost}"), ${safe_supplier},
                          $(api_inv_decimal "${threshold}"), 1);"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo crear el insumo.}"
        return 1
    fi
    INV_INPUT_ID=$(db_last_insert_id)
    return 0
}

api_inv_update_input() {
    local input_id="${1:-0}" name="${2:-}" category_id="${3:-0}" unit="${4:-unidades}"
    local cost="${5:-0}" supplier_id="${6:-0}" threshold="${7:-0}" active="${8:-1}"
    local stock="${9:-}"

    AUTH_ERROR=""
    [[ "${input_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Insumo inválido."; return 1; }
    [[ -z "${name}" || ${#name} -gt 80 ]] && { AUTH_ERROR="Nombre de insumo inválido."; return 1; }
    [[ "${cost}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Costo inválido."; return 1; }
    [[ "${threshold}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Umbral inválido."; return 1; }
    [[ -z "${unit}" || ${#unit} -gt 30 ]] && { AUTH_ERROR="Unidad inválida."; return 1; }
    [[ "${active}" == "0" ]] || active=1
    local stock_sql=""
    if [[ -n "${stock}" ]]; then
        [[ "${stock}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { AUTH_ERROR="Stock inválido."; return 1; }
        stock_sql=", stock = $(api_inv_decimal "${stock}")"
    fi

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE id = ${input_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El insumo no existe."; return 2; }
    exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE LOWER(name) = LOWER($(db_quote "${name}")) AND id <> ${input_id};" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) && { AUTH_ERROR="Ya existe otro insumo con ese nombre."; return 2; }

    local safe_category="NULL" safe_supplier="NULL"
    if [[ "${category_id}" =~ ^[0-9]+$ ]] && (( category_id > 0 )); then
        exists=$(db_scalar "SELECT COUNT(*) FROM Categories WHERE id = ${category_id};" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="La categoría no existe."; return 1; }
        safe_category="${category_id}"
    fi
    if [[ "${supplier_id}" =~ ^[0-9]+$ ]] && (( supplier_id > 0 )); then
        exists=$(db_scalar "SELECT COUNT(*) FROM Suppliers WHERE id = ${supplier_id};" 2>/dev/null || printf '0')
        (( ${exists:-0} > 0 )) || { AUTH_ERROR="El proveedor no existe."; return 1; }
        safe_supplier="${supplier_id}"
    fi

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    if ! db_exec "UPDATE Inputs
                  SET name = $(db_quote "${name}"), category_id = ${safe_category},
                      unit = $(db_quote "${unit}"), cost = $(api_inv_decimal "${cost}"),
                      supplier_id = ${safe_supplier}, min_stock_threshold = $(api_inv_decimal "${threshold}"),
                      active = ${active}${stock_sql}
                  WHERE id = ${input_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo actualizar el insumo.}"
        return 1
    fi
    return 0
}

api_inv_delete_input() {
    local input_id="${1:-0}"
    AUTH_ERROR=""
    [[ "${input_id}" =~ ^[0-9]+$ ]] || { AUTH_ERROR="Insumo inválido."; return 1; }

    local exists
    exists=$(db_scalar "SELECT COUNT(*) FROM Inputs WHERE id = ${input_id} AND active = 1;" 2>/dev/null || printf '0')
    (( ${exists:-0} > 0 )) || { AUTH_ERROR="El insumo no existe o ya está inactivo."; return 2; }

    db_set_context_user "${AUTH_USER:-sistema}" >/dev/null 2>&1 || true
    if ! db_exec "UPDATE Inputs SET active = 0 WHERE id = ${input_id};"; then
        AUTH_ERROR="${DB_LAST_ERROR:-No se pudo eliminar el insumo.}"
        return 1
    fi
    return 0
}
