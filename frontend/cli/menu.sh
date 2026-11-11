#!/usr/bin/env bash
#
# Interfaz de terminal para operar el ERP sin navegador.

[[ -n "${_ERP_CLI_MENU_LOADED:-}" ]] && return 0
declare -g _ERP_CLI_MENU_LOADED=1

cli_print_header() {
    printf '\n'
    printf '  Aurea ERP · Terminal\n'
    printf '  ==================================================\n'
}

cli_login() {
    cli_print_header
    printf '  Inicio de sesión\n'
    printf '  Demo: admin / admin123 · cajero / cajero123\n\n'

    local username="${ERP_CLI_USER:-}"
    local password="${ERP_CLI_PASSWORD:-}"
    local attempts=0

    while (( attempts < 3 )); do
        if [[ -z "${username}" ]]; then
            read -rp "  Usuario: " username
        fi
        if [[ -z "${password}" ]]; then
            read -rsp "  Contraseña: " password
            printf '\n'
        fi

        if api_authenticate "${username}" "${password}"; then
            CLI_USER="${AUTH_USER}"
            CLI_ROLE="${AUTH_ROLE}"
            printf '\n  Bienvenido, %s (%s).\n' "${CLI_USER}" "${CLI_ROLE}"
            return 0
        fi

        printf '  %s\n' "${AUTH_ERROR}"
        username=""
        password=""
        attempts=$(( attempts + 1 ))
    done

    printf '  Demasiados intentos fallidos.\n'
    return 1
}

cli_list_products() {
    local rows id name stock price threshold
    rows=$(db_query "SELECT id, name, stock, printf('%.2f', price), min_production_threshold
                     FROM Products WHERE active = 1 ORDER BY name;")
    printf '\n  %-5s %-36s %8s %10s\n' "ID" "Producto" "Stock" "Precio"
    printf '  %s\n' "-------------------------------------------------------------------"
    while IFS='|' read -r id name stock price threshold; do
        [[ -z "${id}" ]] && continue
        printf '  %-5s %-36s %8s %10s\n' "${id}" "${name:0:36}" "${stock}" "\$${price}"
    done <<< "${rows}"
    printf '\n'
}

cli_list_inputs() {
    local rows id name stock unit cost supplier
    rows=$(db_query "SELECT i.id, i.name, printf('%.2f', i.stock), i.unit,
                            printf('%.2f', i.cost), COALESCE(s.name, 'Sin proveedor')
                     FROM Inputs i LEFT JOIN Suppliers s ON s.id = i.supplier_id
                     ORDER BY i.name;")
    printf '\n  %-5s %-32s %9s %-10s %8s %-24s\n' "ID" "Insumo" "Stock" "Unidad" "Costo" "Proveedor"
    printf '  %s\n' "---------------------------------------------------------------------------------"
    while IFS='|' read -r id name stock unit cost supplier; do
        [[ -z "${id}" ]] && continue
        printf '  %-5s %-32s %9s %-10s %8s %-24s\n' "${id}" "${name:0:32}" "${stock}" "${unit}" "\$${cost}" "${supplier:0:24}"
    done <<< "${rows}"
    printf '\n'
}

cli_list_customers() {
    local rows id name type phone
    rows=$(db_query "SELECT id, name, type, COALESCE(phone, '') FROM Customers ORDER BY name;")
    printf '\n  %-5s %-34s %-14s %-18s\n' "ID" "Cliente" "Tipo" "Teléfono"
    printf '  %s\n' "-------------------------------------------------------------------"
    while IFS='|' read -r id name type phone; do
        [[ -z "${id}" ]] && continue
        printf '  %-5s %-34s %-14s %-18s\n' "${id}" "${name:0:34}" "${type}" "${phone}"
    done <<< "${rows}"
    printf '\n'
}

cli_new_sale() {
    cli_list_products
    local -a product_ids=()
    local -a quantities=()
    local product_id quantity

    while true; do
        read -rp "  ID de producto (0 para terminar): " product_id
        [[ "${product_id}" == "0" ]] && break
        if [[ ! "${product_id}" =~ ^[0-9]+$ ]]; then
            printf '  Producto inválido.\n'
            continue
        fi
        read -rp "  Cantidad: " quantity
        if [[ ! "${quantity}" =~ ^[0-9]+$ ]] || (( quantity <= 0 )); then
            printf '  Cantidad inválida.\n'
            continue
        fi
        product_ids+=("${product_id}")
        quantities+=("${quantity}")
        printf '  Agregado: producto %s × %s\n' "${product_id}" "${quantity}"
    done

    if (( ${#product_ids[@]} == 0 )); then
        printf '  Venta cancelada.\n'
        return 0
    fi

    cli_list_customers
    local customer_id
    read -rp "  ID de cliente (0 = consumidor final): " customer_id
    [[ "${customer_id}" =~ ^[0-9]+$ ]] || customer_id=0

    printf '\n  1) Efectivo  2) Transferencia  3) Tarjeta\n'
    local payment_option payment_method
    read -rp "  Método de pago [1]: " payment_option
    case "${payment_option}" in
        2) payment_method="Transferencia" ;;
        3) payment_method="Tarjeta" ;;
        *) payment_method="Efectivo" ;;
    esac

    if api_register_sale "${customer_id}" "${payment_method}" product_ids quantities; then
        printf '\n  Venta #%s registrada por $%s (%s).\n' "${SALE_ID}" "${SALE_TOTAL}" "${payment_method}"
    else
        printf '\n  No se pudo registrar la venta: %s\n' "${AUTH_ERROR}"
    fi
}

cli_new_batch() {
    cli_list_products
    local product_id quantity unit_cost notes
    read -rp "  ID de producto a producir: " product_id
    read -rp "  Unidades del lote: " quantity
    read -rp "  Costo unitario: " unit_cost
    read -rp "  Notas (opcional): " notes

    cli_list_inputs
    local input_id input_quantity
    local -a input_ids=()
    local -a input_quantities=()
    read -rp "  ID de insumo a consumir (0 = ninguno): " input_id
    if [[ "${input_id}" =~ ^[0-9]+$ ]] && (( input_id > 0 )); then
        read -rp "  Cantidad del insumo: " input_quantity
        input_ids+=("${input_id}")
        input_quantities+=("${input_quantity}")
    fi

    if api_register_production_batch "${product_id}" "${quantity}" "${unit_cost}" "${notes}" input_ids input_quantities; then
        printf '\n  Lote #%s registrado. El stock del producto y los insumos fue actualizado.\n' "${BATCH_ID}"
    else
        printf '\n  No se pudo registrar el lote: %s\n' "${AUTH_ERROR}"
    fi
}

cli_restock_input() {
    cli_list_inputs
    local input_id quantity
    read -rp "  ID de insumo a reponer: " input_id
    read -rp "  Cantidad recibida: " quantity

    if api_restock_input "${input_id}" "${quantity}"; then
        printf '\n  Insumo %s repuesto correctamente.\n' "${input_id}"
    else
        printf '\n  No se pudo reponer el insumo: %s\n' "${AUTH_ERROR}"
    fi
}

cli_show_alerts() {
    local rows id name stock threshold
    rows=$(db_query "SELECT id, name, printf('%.2f', stock), printf('%.2f', min_stock_threshold)
                     FROM Inputs WHERE stock <= min_stock_threshold ORDER BY (stock - min_stock_threshold);")
    printf '\n  Insumos bajo mínimo\n'
    printf '  %-5s %-34s %9s %10s\n' "ID" "Insumo" "Stock" "Mínimo"
    printf '  %s\n' "-------------------------------------------------------------------"
    while IFS='|' read -r id name stock threshold; do
        [[ -z "${id}" ]] && continue
        printf '  %-5s %-34s %9s %10s\n' "${id}" "${name:0:34}" "${stock}" "${threshold}"
    done <<< "${rows}"

    rows=$(db_query "SELECT id, name, stock, min_production_threshold
                     FROM Products WHERE active = 1 AND stock <= min_production_threshold
                     ORDER BY (stock - min_production_threshold);")
    printf '\n  Productos bajo mínimo\n'
    printf '  %-5s %-34s %9s %10s\n' "ID" "Producto" "Stock" "Mínimo"
    printf '  %s\n' "-------------------------------------------------------------------"
    while IFS='|' read -r id name stock threshold; do
        [[ -z "${id}" ]] && continue
        printf '  %-5s %-34s %9s %10s\n' "${id}" "${name:0:34}" "${stock}" "${threshold}"
    done <<< "${rows}"
    printf '\n'
}

cli_show_contacts() {
    local rows id name type phone email
    cli_list_customers

    rows=$(db_query "SELECT id, name, COALESCE(contact_person, ''), COALESCE(phone, ''), COALESCE(email, '')
                     FROM Suppliers ORDER BY name;")
    printf '  %-5s %-34s %-20s %-18s %-24s\n' "ID" "Proveedor" "Contacto" "Teléfono" "Correo"
    printf '  %s\n' "---------------------------------------------------------------------------------"
    while IFS='|' read -r id name type phone email; do
        [[ -z "${id}" ]] && continue
        printf '  %-5s %-34s %-20s %-18s %-24s\n' "${id}" "${name:0:34}" "${type:0:20}" "${phone}" "${email:0:24}"
    done <<< "${rows}"
    printf '\n'
}

cli_show_journal() {
    local rows id timestamp user action entity status
    rows=$(db_query "SELECT id, datetime(timestamp), user, action, entity, status
                     FROM InventoryJournal ORDER BY id DESC LIMIT 20;")
    printf '\n  Bitácora de auditoría (últimos 20 eventos)\n'
    printf '  %-5s %-20s %-12s %-16s %-18s %-8s\n' "ID" "Fecha" "Usuario" "Acción" "Entidad" "Estado"
    printf '  %s\n' "---------------------------------------------------------------------------------"
    while IFS='|' read -r id timestamp user action entity status; do
        [[ -z "${id}" ]] && continue
        printf '  %-5s %-20s %-12s %-16s %-18s %-8s\n' "${id}" "${timestamp}" "${user:0:12}" "${action:0:16}" "${entity:0:18}" "${status}"
    done <<< "${rows}"
    printf '\n'
}

cli_start_server() {
    printf '\n  Iniciando servidor web. Presione Ctrl+C para volver al menú.\n'
    "${APP_ROOT_DIR}/server.sh" "${1:-8080}"
    printf '\n  Servidor detenido.\n'
}

cli_run() {
    if ! cli_login; then
        return 1
    fi

    local option
    while true; do
        cli_print_header
        printf '  Usuario: %s (%s)\n\n' "${CLI_USER}" "${CLI_ROLE}"
        printf '  1) Registrar venta\n'
        printf '  2) Registrar lote de producción\n'
        printf '  3) Reponer insumo\n'
        printf '  4) Ver alertas de stock\n'
        printf '  5) Ver productos\n'
        printf '  6) Ver insumos\n'
        printf '  7) Ver contactos\n'
        printf '  8) Ver auditoría\n'
        printf '  9) Iniciar servidor web\n'
        printf '  0) Salir\n\n'
        read -rp "  Opción: " option

        case "${option}" in
            1) cli_new_sale ;;
            2) cli_new_batch ;;
            3) cli_restock_input ;;
            4) cli_show_alerts ;;
            5) cli_list_products ;;
            6) cli_list_inputs ;;
            7) cli_show_contacts ;;
            8) cli_show_journal ;;
            9) cli_start_server ;;
            0) printf '  Hasta luego.\n'; return 0 ;;
            *) printf '  Opción inválida.\n' ;;
        esac

        printf '\n  Presione Enter para continuar...'
        read -r _
    done
}
