#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/validations.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../backend/user/api/api_users.sh"

handle_create_user() {
    local username=""
    local password=""

    while true; do
        ! alpha_field_with_validation $'Ingresa tu nombre de usuario deseado:\n' username "required" && return 1
        if api_check_username_exists "${username}"; then
            printf "¡El usuario ya existe! Por favor, ingresa otro.\n\n"
        else
            break
        fi
    done

    while true; do
        read -rsp $'Ingresa una contraseña para tu usuario:\n' password
        echo ""
        [[ -n "${password}" ]] && break
        printf $'No puedes ingresar una contraseña vacía.\n'
    done

    if api_create_user "${username}" "${password}"; then
        printf "¡El usuario se ha creado exitosamente!\n"
        return 0
    else
        printf "¡Ha ocurrido un error al guardar el usuario en la base de datos!\n"
        return 1
    fi
}

handle_auth_user() {
    local -i tries=0
    local username=""
    local password=""

    while (( tries < 5 )); do
        ! alpha_field_with_validation $'Ingresa tu usuario:\n' username && return 1
        if ! api_check_username_exists "${username}"; then
            (( tries++ ))
            printf 'No se ha encontrado registro para ese usuario. Intentos restantes: %d\n' "$(( 5 - tries ))"
        else
            break
        fi
    done        

    (( tries >= 5 )) && { printf "¡Intentos fallidos máximos alcanzados!\n"; exit 1; }

    tries=0
    while (( tries < 3 )); do
        read -rsp $'Ingresa tu contraseña:\n' password
        echo ""

        [[ -z "${password}" ]] && { printf $'No puedes ingresar una contraseña vacía.\n'; continue; }

        if api_verify_user_credentials "${username}" "${password}"; then
            printf "Login exitoso. ¡Bienvenido, %s!\n" "$username"
            return 0
        fi

        (( tries++ ))
        printf "Contraseña incorrecta. (Intentos restantes: %d)\n" "$(( 3 - tries ))"
    done

    printf "¡Intentos fallidos máximos alcanzados!\n"
    exit 1
}