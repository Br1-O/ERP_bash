#!/usr/bin/env bash

[[ -n "${_FRONTEND_INVENTORY_TUI_HANDLERS_LOADED:-}" ]] && return 0
declare -g _FRONTEND_INVENTORY_TUI_HANDLERS_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/tui/tui_components.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../backend/inventory/api/api_inventory.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../html/html_generator_inventory.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/nc_http_server.sh"

tui_select_category() {
    local -n _cat_out=$1
    local choice=""
    if ! choice="$(whiptail --title "Seleccionar Categoría" --menu "Elija una categoría válida:" 15 50 5 \
        "frutas" "Frutas" \
        "verduras" "Verduras" \
        "enlatados" "Enlatados" \
        "almacén" "Almacén" \
        "otros" "Otros" 3>&1 1>&2 2>&3)"; then
        return 1
    fi
    _cat_out="$choice"
    return 0
}

tui_api_insert_product_wrapper() {
    local nombre="$1" categoria="$2" stock="$3" costo="$4" precio="$5"
    api_insert_product "$nombre" "$categoria" "$stock" "$costo" "$precio"
    local status=$?
    case $status in
        0) 
            printf "¡Éxito!\n\nEl producto '%s' fue registrado correctamente en la base de datos con stock %s y precio $%s.\n" "$nombre" "$stock" "$precio" 
            ;;
        1) printf "[Error de Validación]: Verifique los datos ingresados.\n- Nombre alfabético (máx 50 car).\n- Stock entero >= 0.\n- Costo y Precio numéricos válidos.\n" ;;
        2) printf "[Error de Conflicto]: El producto '%s' ya existe.\n" "$nombre" ;;
        *) printf "[Error Inesperado]: Código de error %d.\n" "$status" ;;
    esac
}

tui_handle_create_product() {
    local nombre categoria stock costo precio
    tui_input "Alta de Producto" "Ingrese Nombre del producto:" nombre || return 0
    [[ -z "$nombre" ]] && return 0

    tui_select_category categoria || return 0

    tui_input "Alta de Producto" "Ingrese Stock inicial:" stock || return 0
    tui_input "Alta de Producto" "Ingrese Costo de Compra ($):" costo || return 0
    tui_input "Alta de Producto" "Ingrese Precio de Venta ($):" precio || return 0

    tui_run_show "Alta de Producto" tui_api_insert_product_wrapper "$nombre" "$categoria" "$stock" "$costo" "$precio"
}

tui_handle_delete_product() {
    local nombre_temp
    tui_input "Baja de Producto" "Ingrese el nombre del producto a eliminar:" nombre_temp || return 0
    [[ -z "$nombre_temp" ]] && return 0

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        tui_msg "Baja de Producto" "Ese nombre corresponde a más de un producto ($count encontrados). Especifique el nombre completo."
        return 0
    elif (( count == 0 )); then
        tui_msg "Baja de Producto" "No se encontró ningún producto con el nombre '$nombre_temp'."
        return 0
    fi

    local -i product_id="${found[0,id]}"
    local prod_name="${found[0,nombre]}"

    if tui_confirm "Confirmar Baja" "¿Está seguro de dar de baja el producto '$prod_name' (ID: $product_id)?"; then
        if api_delete_product_by_id "$product_id"; then
            tui_msg "Éxito en Baja" "¡El producto '$prod_name' (ID: $product_id) fue dado de baja exitosamente!"
        else
            tui_msg "Error" "No se pudo procesar la baja del producto."
        fi
    fi
}

tui_handle_update_product() {
    local nombre_temp
    tui_input "Modificar Producto" "Ingrese el nombre del producto a modificar:" nombre_temp || return 0
    [[ -z "$nombre_temp" ]] && return 0

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        tui_msg "Modificación" "Ese nombre corresponde a más de un producto ($count encontrados). Especifique mejor."
        return 0
    elif (( count == 0 )); then
        tui_msg "Modificación" "No se encontró ningún producto con el nombre '$nombre_temp'."
        return 0
    fi

    local -A p_temp=()
    p_temp[id]="${found[0,id]}"
    p_temp[nombre]="${found[0,nombre]}"
    p_temp[categoria]="${found[0,categoria]}"
    p_temp[stock]="${found[0,stock]}"
    p_temp[costo]="${found[0,costo]}"
    p_temp[precio]="${found[0,precio]}"
    p_temp[activo]="${found[0,activo]}"

    local nuevo_nombre nueva_cat nuevo_stock nuevo_costo nuevo_precio
    tui_input "Editar Producto (ID ${p_temp[id]})" "Nombre actual [${p_temp[nombre]}]:" nuevo_nombre || return 0
    p_temp[nombre]="${nuevo_nombre:-${p_temp[nombre]}}"

    if tui_confirm "Cambiar Categoría" "La categoría actual es '${p_temp[categoria]}'. ¿Desea modificarla?"; then
        tui_select_category nueva_cat || return 0
        p_temp[categoria]="${nueva_cat:-${p_temp[categoria]}}"
    fi

    tui_input "Editar Producto (ID ${p_temp[id]})" "Stock actual [${p_temp[stock]}]:" nuevo_stock || return 0
    p_temp[stock]="${nuevo_stock:-${p_temp[stock]}}"

    tui_input "Editar Producto (ID ${p_temp[id]})" "Costo actual [${p_temp[costo]}]:" nuevo_costo || return 0
    p_temp[costo]="${nuevo_costo:-${p_temp[costo]}}"

    tui_input "Editar Producto (ID ${p_temp[id]})" "Precio actual [${p_temp[precio]}]:" nuevo_precio || return 0
    p_temp[precio]="${nuevo_precio:-${p_temp[precio]}}"

    if (( p_temp[activo] == 0 )); then
        if tui_confirm "Reactivar Producto" "El producto está INACTIVO.\n¿Desea reactivarlo a estado Disponible?"; then
            p_temp[activo]=1
        fi
    fi

    if api_update_product p_temp; then
        tui_msg "Éxito en Modificación" "¡El producto ID ${p_temp[id]} ('${p_temp[nombre]}') fue actualizado correctamente!"
    else
        tui_msg "Error" "No se pudo actualizar el producto en la base de datos."
    fi
}

tui_render_journal() {
    local total_items
    total_items=$(api_get_total_journal_count)
    (( total_items == 0 )) && { printf "No hay registros en el historial.\n"; return; }
    
    local journal_data
    journal_data=$(api_get_full_journal)

    printf "=== AUDITORÍA DE INVENTARIO - JOURNAL ===\n\n"
    printf "%-5s  %-19s  %-12s  %-8s  %-8s  %-40s  %-8s\n" "ID" "FECHA/HORA" "USUARIO" "ACCION" "PROD_ID" "PAYLOAD" "ESTADO"
    printf '%s\n' "-------------------------------------------------------------------------------------------------------------------"
    while IFS='|' read -r id timestamp user action product_id payload status; do
        [[ -z "$id" ]] && continue
        printf "%-5s  %-19s  %-12s  %-8s  %-8s  %-40s  %-8s\n" \
            "$id" "$timestamp" "$user" "$action" "${product_id:-N/A}" "$payload" "$status"
    done <<< "$journal_data"
}

tui_handle_show_journal() {
    tui_text_show "Historial de Auditoría" tui_render_journal
}

tui_render_inventory_list() {
    printf "=== INVENTARIO COMPLETO ===\n\n"
    printf "%-5s %-15s %-12s %-7s %-9s %-9s %-10s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
    printf '%s\n' "--------------------------------------------------------------------------------"
    
    local inventory_data
    inventory_data=$(api_get_all_inventory)

    while IFS='|' read -r id nombre categoria stock costo precio activo; do
        [[ -z "$id" ]] && continue
        
        local available_text="Disponible"
        (( activo == 0 )) && available_text="No Disp."

        printf "%-5s %-15s %-12s %-7s %-9s %-9s %-10s\n" \
            "$id" "$nombre" "$categoria" "$stock" "$costo" "$precio" "$available_text"
    done <<< "$inventory_data"
}

tui_handle_show_paginated() {
    tui_text_show "Inventario Completo" tui_render_inventory_list
}

tui_render_search_results() {
    printf "=== RESULTADOS DE BÚSQUEDA ===\n\n"
    printf "%-5s %-15s %-15s %-8s %-10s %-10s %-8s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
    printf '%s\n' "------------------------------------------------------------------------"
    for ((i=0; i<count; i++)); do
        local avail="Disponible"
        (( found[$i,activo] == 0 )) && avail="No Disp."
        printf "%-5s %-15s %-15s %-8s %-9s %-9s %-8s\n" \
            "${found[$i,id]}" "${found[$i,nombre]}" "${found[$i,categoria]}" \
            "${found[$i,stock]}" "${found[$i,costo]}" "${found[$i,precio]}" "$avail"
    done
}

tui_handle_search_product() {
    local nombre_temp
    tui_input "Buscar Producto" "Ingrese el nombre a buscar:" nombre_temp || return 0
    [[ -z "$nombre_temp" ]] && return 0

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 0 )); then
        local render_search_results=()
        
        tui_text_show "Resultados de Búsqueda" tui_render_search_results
    else
        tui_msg "Buscar Producto" "No se encontraron productos con el nombre '$nombre_temp'."
    fi
}

tui_handle_generate_html() {
    tui_run_show "Reporte HTML" generate_html
}

tui_handle_http_server() {
    local -n server_pid_ref=$1
    local SERVER_PORT=8080
    local HTML_FILE_PATH="./shared/data/vista_inventario.html"

    generate_html >/dev/null 2>&1

    if (( server_pid_ref > 0 )) && kill -0 "$server_pid_ref" 2>/dev/null; then
        stop_local_http_server server_pid_ref "$SERVER_PORT"
        tui_msg "Servidor HTTP" "El servidor HTTP ha sido detenido."
    else
        start_local_http_server server_pid_ref "$SERVER_PORT" "$HTML_FILE_PATH"     
        tui_msg "Servidor HTTP" "Servidor iniciado con éxito en http://localhost:$SERVER_PORT"
    fi
}