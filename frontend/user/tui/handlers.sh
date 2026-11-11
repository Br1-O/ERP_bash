#!/usr/bin/env bash

[[ -n "${_FRONTEND_USER_TUI_HANDLERS_LOADED:-}" ]] && return 0
declare -g _FRONTEND_USER_TUI_HANDLERS_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/tui/tui_components.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/validations.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../backend/user/api/api_users.sh"

tui_handle_create_user() {
    local username=""
    local password=""

    while true; do
        if ! tui_input "Registro de Usuario" "Ingrese su nombre de usuario deseado:" username; then
            return 1
        fi
        
        if [[ -z "$username" ]]; then
            tui_msg "Aviso" "El nombre de usuario no puede estar vacío."
            continue
        fi

        if api_check_username_exists "${username}"; then
            tui_msg "Aviso" "¡El usuario ya existe! Por favor, ingrese otro."
        else
            break
        fi
    done

    while true; do
        if ! tui_pass "Seguridad" "Ingrese una contraseña para '$username':" password; then
            return 1
        fi
        
        if [[ -z "${password}" ]]; then
            tui_msg "Aviso" "No puede ingresar una contraseña vacía."
            continue
        fi
        break
    done

    if api_create_user "${username}" "${password}"; then
        tui_msg "Éxito" "¡El usuario se ha creado exitosamente!"
        return 0
    else
        tui_msg "Error" "¡Ha ocurrido un error al guardar el usuario en la base de datos!"
        return 1
    fi
}

tui_handle_auth_user() {
    local -i tries=0
    local username=""
    local password=""

    while (( tries < 5 )); do
        if ! tui_input "Iniciar Sesión" "Ingrese su usuario (Intento $((tries + 1))/5):" username; then
            return 1
        fi

        if [[ -z "$username" ]]; then
            continue
        fi

        if ! api_check_username_exists "${username}"; then
            (( tries++ ))
            tui_msg "Error" "No se ha encontrado registro para ese usuario. Intentos restantes: $(( 5 - tries ))"
        else
            break
        fi
    done        

    (( tries >= 5 )) && { tui_msg "Bloqueado" "¡Intentos fallidos máximos alcanzados!"; return 1; }

    tries=0
    while (( tries < 3 )); do
        if ! tui_pass "Iniciar Sesión" "Ingrese contraseña para '$username' (Intento $((tries + 1))/3):" password; then
            return 1
        fi

        [[ -z "${password}" ]] && { tui_msg "Aviso" "No puedes ingresar una contraseña vacía."; continue; }

        if api_verify_user_credentials "${username}" "${password}"; then
            tui_msg "Bienvenido" "Login exitoso. ¡Bienvenido, $username!"
            return 0
        fi

        (( tries++ ))
        tui_msg "Error" "Contraseña incorrecta. (Intentos restantes: $(( 3 - tries )))"
    done

    tui_msg "Bloqueado" "¡Intentos fallidos máximos alcanzados!"
    return 1
}