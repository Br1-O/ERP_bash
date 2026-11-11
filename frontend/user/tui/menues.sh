#!/usr/bin/env bash

[[ -n "${_FRONTEND_USER_TUI_MENU_LOADED:-}" ]] && return 0
declare -g _FRONTEND_USER_TUI_MENU_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/handlers.sh"

tui_auth_menu() {
    local choice=""
    while true; do
        if ! choice="$(whiptail --title "Sistema de Autenticación" --menu "Seleccione una opción de acceso:" 15 50 3 \
            "1" "Registrar un nuevo usuario" \
            "2" "Acceder a su cuenta (Login)" \
            "3" "Salir de la aplicación" 3>&1 1>&2 2>&3)"; then
            
            if tui_confirm "Salir" "¿Desea salir del programa?"; then
                exit 0
            fi
            continue
        fi

        case "$choice" in
            1)
                tui_handle_create_user || true
                ;;
            2) 
                if tui_handle_auth_user; then
                    return 0 
                fi
                ;;
            3)
                exit 0
                ;;
        esac
    done
}