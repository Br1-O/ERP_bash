#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/handlers.sh"

welcome_message() {
    local c_blue="\033[1;34m"
    local c_bold="\033[1m"
    local c_dim="\033[2m"
    local c_reset="\033[0m"

    printf "${c_blue}+-----------------------------------------------------------+${c_reset}\n"
    printf "${c_blue}|${c_reset}                                                           ${c_blue}|${c_reset}\n"
    printf "${c_blue}|${c_reset}          ${c_bold}¡Bienvenido al sistema de inventario!${c_reset}            ${c_blue}|${c_reset}\n"
    printf "${c_blue}|${c_reset}              ${c_dim}Presiona CTRL+C para salir${c_reset}                   ${c_blue}|${c_reset}\n"
    printf "${c_blue}|${c_reset}                                                           ${c_blue}|${c_reset}\n"
    printf "${c_blue}+-----------------------------------------------------------+${c_reset}\n"
    printf "\n"
}

show_inventory_menu(){
    local c_bold="\033[1m"
    local c_reset="\033[0m"

    printf "\n"
    printf "=============================================================\n"
    printf "                    ${c_bold}MENÚ DE INVENTARIO${c_reset}\n"
    printf "=============================================================\n"
    printf " 1. Alta producto\n"
    printf " 2. Baja producto\n"
    printf " 3. Modificación producto\n"
    printf " 4. Mostrar inventario (Paginado)\n"
    printf " 5. Buscar producto por nombre\n"
    printf " 6. Generar archivo HTML\n"
    printf " 7. Iniciar o Detener el server del inventario\n"
    printf " 8. Mostrar Historial de acciones. (Paginado)\n"
    printf " 9. Salir\n"
    printf "=============================================================\n"
    printf "\n"
}

get_option_from_user_and_execute_inventory_action(){
    local -r -i OPTION_CREATE=1
    local -r -i OPTION_DELETE=2
    local -r -i OPTION_UPDATE=3
    local -r -i OPTION_SHOW_ALL=4
    local -r -i OPTION_SEARCH_ONE_BY_NAME=5
    local -r -i OPTION_GENERATE_HTML=6
    local -r -i OPTION_START_STOP_HTTP_SERVER=7
    local -r -i OPTION_SHOW_JOURNAL=8
    local -r -i OPTION_EXIT=9

    local action_option=0
    local products_categories=("frutas" "verduras" "enlatados" "almacen" "otros")
    local -n SERVER_PID=$1

    while [[ "$action_option" != "$OPTION_EXIT" ]]; do
        show_inventory_menu
        read -rsn 1 -p "Opcion: " action_option
        echo ""
        stty sane

        case $action_option in
            $OPTION_CREATE) 
                clear_screen; 
                handle_create_product ;;
            $OPTION_DELETE) 
                clear_screen; 
                handle_delete_product ;;
            $OPTION_UPDATE) 
                clear_screen; 
                handle_update_product ;;
            $OPTION_SHOW_ALL) 
                clear_screen; 
                handle_show_product_paginated ;;
            $OPTION_SEARCH_ONE_BY_NAME) 
                clear_screen; 
                handle_show_one_product ;;
            $OPTION_GENERATE_HTML) 
                clear_screen; 
                handle_generate_html ;;
            $OPTION_START_STOP_HTTP_SERVER) 
                clear_screen; 
                handle_http_server SERVER_PID ;;
            $OPTION_SHOW_JOURNAL) 
                clear_screen; 
                handle_show_journal_paginated ;;
            $OPTION_EXIT)
                printf "\nSaliendo del programa...\n"
                (( SERVER_PID > 0 )) && stop_local_http_server SERVER_PID 8081 >/dev/null 2>&1
                exit 0
                ;;
            *) printf "\nOpcion invalida.\n" ;;
        esac
    done
    return 0
}