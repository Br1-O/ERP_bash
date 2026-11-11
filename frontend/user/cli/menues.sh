
#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/handlers.sh"

show_auth_menu(){
    printf "\n\n"
    local c_bold="\033[1m"
    local c_reset="\033[0m"

    printf "=============================================================\n"
    printf "                  ${c_bold}SISTEMA DE AUTENTICACIÓN${c_reset}\n"
    printf "=============================================================\n"
    printf "1. Registrar un nuevo usuario\n"
    printf "2. Acceder a tu usuario\n"
    printf "3. Salir\n\n"
}

get_option_from_user_and_execute_login_or_register(){
    local -r -i OPTION_REGISTER=1
    local -r -i OPTION_LOGIN=2
    local -r -i OPTION_EXIT=3

    local option=0

    while [[ "$option" != "$OPTION_EXIT" ]]; do
        show_auth_menu

        read -rp "Opcion: " option

        case $option in
            $OPTION_REGISTER)
                clear_screen
                handle_create_user
                ;;
            $OPTION_LOGIN)
                clear_screen
                if handle_auth_user; then
                    return 0
                fi
                ;;
            $OPTION_EXIT)
                printf "Saliendo del programa...\n"
                exit 0
                ;;
            *)
                printf "\nOpcion invalida.\n"
                ;;
        esac
    done
}