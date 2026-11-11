
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/validations.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../backend/inventory/api/api_inventory.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../html/html_generator_inventory.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/nc_http_server.sh"

handle_create_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el nombre del producto a crear: " nombre_temp && return 1

    local categoria_temp="" stock_temp="" costo_temp="" precio_temp=""
    ! enum_field_with_validation "Ingrese Categoria: " products_categories categoria_temp && return 1
    ! numeric_field_with_validation "Ingrese Stock: " stock_temp && return 1
    ! decimal_field_with_validation "Ingrese Costo de Compra: " costo_temp && return 1
    ! decimal_field_with_validation "Ingrese Precio de venta: " precio_temp && return 1

    api_insert_product "$nombre_temp" "$categoria_temp" "$stock_temp" "$costo_temp" "$precio_temp"
    local -i status=$?

    if (( status == 0 )); then
        printf "Producto guardado correctamente en SQLite.\n"
        return 0
    elif (( status == 2 )); then
        printf "[Error]: ¡El producto '%s' ya existe!\n" "$nombre_temp"
        return 1
    else
        printf "[Error]: Validación fallida en la API.\n"
        return 1
    fi
}

handle_delete_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el nombre del producto a eliminar: " nombre_temp && return 1

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        printf "Ese nombre corresponde a más de un producto. Especifique mejor.\n"
        return 1
    elif (( count == 0 )); then
        printf "No se encontró ningún producto con ese nombre.\n"
        return 1
    fi

    clear_screen
    local -i product_id="${found[0,id]}"

    if api_delete_product_by_id "$product_id"; then
        printf "Producto '%s' (ID: %d) dado de baja con éxito.\n" "${found[0,nombre]}" "$product_id"
        return 0
    else
        printf "[Error]: No se pudo procesar la baja.\n"
        return 1
    fi
}

handle_update_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el nombre actual del producto a modificar: " nombre_temp && return 1

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        printf "Ese nombre corresponde a más de un producto. Especifique mejor.\n"
        return 1
    elif (( count == 0 )); then
        printf "No se encontró ningún producto con ese nombre.\n"
        return 1
    fi

    local -A p_temp=()
    p_temp[id]="${found[0,id]}"
    p_temp[nombre]="${found[0,nombre]}"
    p_temp[categoria]="${found[0,categoria]}"
    p_temp[stock]="${found[0,stock]}"
    p_temp[costo]="${found[0,costo]}"
    p_temp[precio]="${found[0,precio]}"
    p_temp[activo]="${found[0,activo]}"

    local categoria_temp="" stock_temp="" costo_temp="" precio_temp=""
    ! alpha_field_with_validation "Nuevo Nombre [Actual: ${p_temp[nombre]}]: " nombre_temp "not_required"
    p_temp[nombre]="${nombre_temp:-${p_temp[nombre]}}"

    ! enum_field_with_validation "Categoria [Actual: ${p_temp[categoria]}]: " products_categories categoria_temp "not_required"
    p_temp[categoria]="${categoria_temp:-${p_temp[categoria]}}"

    ! numeric_field_with_validation "Stock [Actual: ${p_temp[stock]}]: " stock_temp "not_required"
    p_temp[stock]="${stock_temp:-${p_temp[stock]}}"

    ! decimal_field_with_validation "Costo [Actual: ${p_temp[costo]}]: " costo_temp "not_required"
    p_temp[costo]="${costo_temp:-${p_temp[costo]}}"

    ! decimal_field_with_validation "Precio [Actual: ${p_temp[precio]}]: " precio_temp "not_required"
    p_temp[precio]="${precio_temp:-${p_temp[precio]}}"

    if (( "${p_temp[activo]}" == 0 )); then
        local -i reactivate=0
        local reactivate_options=( 0 1 )
        ! enum_field_with_validation "¿Desea reactivar? 0: No | 1: Sí" reactivate_options reactivate
        (( "${reactivate}" == 1 )) && p_temp[activo]=1
    fi

    clear_screen
    if api_update_product p_temp; then
        printf "Producto %d modificado con éxito.\n" "${p_temp[id]}"
        return 0
    else
        printf "[Error]: No se pudo actualizar el producto.\n"
        return 1
    fi
}

handle_show_product_paginated() {
    local -i page_size=5
    local -i current_page=1
    local total_items
    total_items=$(api_get_total_inventory_count)

    (( total_items == 0 )) && { printf "No se encontraron productos.\n"; return; }

    local -i total_pages=$(( (total_items + page_size - 1) / page_size ))
    local option=""

    while true; do
        clear
        local -i offset=$(( (current_page - 1) * page_size ))

        printf "=== LISTADO DE PRODUCTOS (Página %d de %d) ===\n\n" "$current_page" "$total_pages"
        printf "%-5s %-15s %-15s %-8s %-10s %-10s %-8s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
        printf "%s\n" "------------------------------------------------------------------------"

        local query="SELECT i.id, i.name, c.name AS category, i.stock, i.cost, i.price, i.active FROM Inventory i INNER JOIN Categories c ON i.category_id = c.id LIMIT $page_size OFFSET $offset;"
        
        while IFS='|' read -r id nombre categoria stock costo precio activo; do
            [[ -z "$id" ]] && continue
            local available_text="Disponible"
            (( activo == 0 )) && available_text="No Disponible"
            printf "%-5s %-15s %-15s %-8s %-9s %-9s %-8s\n" "$id" "$nombre" "$categoria" "$stock" "$costo" "$precio" "$available_text"
        done < <(sqlite3 -separator '|' "shared/data/datos_inventario.db" "$query")

        printf "%s\n" "------------------------------------------------------------------------"
        printf " [A] Anterior |  [S] Siguiente  |  [Q] Volver al menú: "
        read -rsn 1 option
        echo ""

        case "${option,,}" in
            s) (( current_page < total_pages )) && (( current_page++ )) ;;
            a) (( current_page > 1 )) && (( current_page-- )) ;;
            q) break ;;
        esac
    done
    clear_screen
}

handle_show_one_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el Nombre del producto a buscar: " nombre_temp && return 1

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count
    clear_screen

    if (( count > 0 )); then
        printf "%-5s %-15s %-15s %-8s %-10s %-10s %-8s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
        printf "%s\n" "------------------------------------------------------------------------"
        for ((i=0; i<count; i++)); do
            local avail="Disponible"
            (( found[$i,activo] == 0 )) && avail="No Disponible"
            printf "%-5s %-15s %-15s %-8s %-9s %-9s %-8s\n" \
                "${found[$i,id]}" "${found[$i,nombre]}" "${found[$i,categoria]}" \
                "${found[$i,stock]}" "${found[$i,costo]}" "${found[$i,precio]}" "$avail"
        done
    else
        printf "No se encontraron productos con ese nombre.\n"
    fi
}

handle_generate_html(){
    generate_html
}

handle_http_server() {
    local -n server_pid_ref=$1
    local SERVER_PORT=8080
    local HTML_FILE_PATH="./shared/data/vista_inventario.html"

    generate_html >/dev/null 2>&1

    if (( server_pid_ref > 0 )) && kill -0 "$server_pid_ref" 2>/dev/null; then
        stop_local_http_server SERVER_PID "$SERVER_PORT"
    else
        ensure_package_installed "nc" "netcat-openbsd" "nc" "openbsd-netcat" "netcat-openbsd"&&start_local_http_server SERVER_PID "$SERVER_PORT" "$HTML_FILE_PATH"     
    fi

    printf "\nPresione cualquier tecla para regresar al menú..."
    read -rsn 1
    echo ""
}

handle_show_journal_paginated() {
    local -i page_size=5
    local -i current_page=1
    local total_items
    total_items=$(api_get_total_journal_count)

    (( total_items == 0 )) && { printf "No se encontraron registros en el journal.\n"; return; }

    local -i total_pages=$(( (total_items + page_size - 1) / page_size ))
    local option=""

    while true; do
        clear
        local -i offset=$(( (current_page - 1) * page_size ))

        printf "=== AUDITORÍA DE INVENTARIO - JOURNAL (Página %d de %d) ===\n\n" "$current_page" "$total_pages"
        printf "%-5s %-19s %-12s %-8s %-10s %-30s %-8s\n" "ID" "FECHA/HORA" "USUARIO" "ACCION" "PROD_ID" "PAYLOAD" "ESTADO"
        printf "%s\n" "----------------------------------------------------------------------------------------------------------"

        local journal_data
        journal_data=$(api_get_paginated_journal "$page_size" "$offset")

        while IFS='|' read -r id timestamp user action product_id payload status; do
            [[ -z "$id" ]] && continue
            printf "%-5s %-19s %-12s %-8s %-10s %-30s %-8s\n" \
                "$id" "$timestamp" "$user" "$action" "${product_id:-N/A}" "$payload" "$status"
        done <<< "$journal_data"

        printf "%s\n" "----------------------------------------------------------------------------------------------------------"
        printf " [A] Anterior |  [S] Siguiente  |  [Q] Volver al menú: "
        read -rsn 1 option
        echo ""

        case "${option,,}" in
            s) (( current_page < total_pages )) && (( current_page++ )) ;;
            a) (( current_page > 1 )) && (( current_page-- )) ;;
            q) break ;;
        esac
    done
    clear_screen
}