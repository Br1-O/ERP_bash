#!/usr/bin/env bash

[[ -n "${_FRONTEND_INVENTORY_TUI_MENU_LOADED:-}" ]] && return 0
declare -g _FRONTEND_INVENTORY_TUI_MENU_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/handlers.sh"

tui_inventory_menu() {
    local choice=""
    local -n SERVER_PID=$1

    while true; do
        if ! choice="$(whiptail --title "Menú Principal de Inventario" --menu "Seleccione una opción:" 18 65 9 \
            "1" "Alta de producto" \
            "2" "Baja de producto" \
            "3" "Modificación de producto" \
            "4" "Mostrar inventario completo" \
            "5" "Buscar producto por nombre" \
            "6" "Generar archivo HTML" \
            "7" "Iniciar o Detener servidor HTTP" \
            "8" "Mostrar Historial de Auditoría (Journal)" \
            "9" "Cerrar sesión / Salir" 3>&1 1>&2 2>&3)"; then
            
            if tui_confirm "Salir" "¿Desea cerrar la aplicación?"; then
                (( SERVER_PID > 0 )) && stop_local_http_server SERVER_PID 8081 >/dev/null 2>&1
                return 0
            fi
            continue
        fi

        case "$choice" in
            1) tui_handle_create_product ;;
            2) tui_handle_delete_product ;;
            3) tui_handle_update_product ;;
            4) tui_handle_show_paginated ;;
            5) tui_handle_search_product ;;
            6) tui_handle_generate_html ;;
            7) tui_handle_http_server SERVER_PID ;;
            8) tui_handle_show_journal ;;
            9)
                if tui_confirm "Salir" "¿Desea salir del sistema?"; then
                    (( SERVER_PID > 0 )) && stop_local_http_server SERVER_PID 8081 >/dev/null 2>&1
                    return 0
                fi
                ;;
        esac
    done
}