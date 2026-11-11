#!/usr/bin/env bash
#
# Punto de entrada del ERP.
#   ./erp.sh              Inicia el servidor web (puerto 8080)
#   ./erp.sh server 9000  Inicia el servidor web en otro puerto
#   ./erp.sh cli          Abre la interfaz de terminal
#   ./erp.sh init         Inicializa/verifica la base de datos
#   ./erp.sh help         Muestra esta ayuda

set -u

ERP_ENTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ERP_ENTRY_DIR}" || exit 1

# shellcheck disable=SC1091
source "${ERP_ENTRY_DIR}/config.sh"

erp_require_sqlite() {
    if ! db_sqlite_available; then
        ensure_package_installed "sqlite3" "sqlite3" "sqlite3" "sqlite" "sqlite3" || return 1
    fi
    db_sqlite_available
}

erp_show_help() {
    printf '%s\n' \
        'Aurea ERP · Licorería artesanal' \
        '' \
        'Uso:' \
        '  ./erp.sh                Inicia el servidor web en el puerto 8080' \
        '  ./erp.sh server [p]     Inicia el servidor web en el puerto p' \
        '  ./erp.sh cli            Abre la interfaz de terminal' \
        '  ./erp.sh init           Inicializa y verifica la base de datos' \
        '  ./erp.sh help           Muestra esta ayuda' \
        '' \
        'Acceso demo: admin / admin123 · cajero / cajero123'
}

erp_init_database() {
    erp_require_sqlite || return 1

    if ! db_singleton_init; then
        printf 'No se pudo inicializar la base de datos: %s\n' "${DB_LAST_ERROR:-error desconocido}" >&2
        return 1
    fi

    local products inputs customers suppliers sales batches journal
    products=$(db_scalar "SELECT COUNT(*) FROM Products;" 2>/dev/null || printf '0')
    inputs=$(db_scalar "SELECT COUNT(*) FROM Inputs;" 2>/dev/null || printf '0')
    customers=$(db_scalar "SELECT COUNT(*) FROM Customers;" 2>/dev/null || printf '0')
    suppliers=$(db_scalar "SELECT COUNT(*) FROM Suppliers;" 2>/dev/null || printf '0')
    sales=$(db_scalar "SELECT COUNT(*) FROM Sales;" 2>/dev/null || printf '0')
    batches=$(db_scalar "SELECT COUNT(*) FROM ProductionBatches;" 2>/dev/null || printf '0')
    journal=$(db_scalar "SELECT COUNT(*) FROM InventoryJournal;" 2>/dev/null || printf '0')

    printf '\nBase de datos lista: %s\n\n' "${ERP_DB_PATH}"
    printf '  Productos:    %s\n' "${products}"
    printf '  Insumos:      %s\n' "${inputs}"
    printf '  Clientes:     %s\n' "${customers}"
    printf '  Proveedores:  %s\n' "${suppliers}"
    printf '  Ventas:       %s\n' "${sales}"
    printf '  Lotes:        %s\n' "${batches}"
    printf '  Auditoría:    %s eventos\n\n' "${journal}"
}

mode="${1:-server}"

case "${mode}" in
    server|web|"")
        erp_require_sqlite || exit 1
        exec "${ERP_ENTRY_DIR}/server.sh" "${2:-8080}"
        ;;
    cli|terminal)
        erp_require_sqlite || exit 1
        if ! db_singleton_init; then
            printf 'No se pudo inicializar la base de datos: %s\n' "${DB_LAST_ERROR:-error desconocido}" >&2
            exit 1
        fi
        cli_run
        ;;
    init|seed)
        erp_init_database
        ;;
    help|-h|--help)
        erp_show_help
        ;;
    *)
        printf 'Modo desconocido: %s\n\n' "${mode}" >&2
        erp_show_help
        exit 1
        ;;
esac
