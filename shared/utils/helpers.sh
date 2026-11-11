
ensure_package_installed() {
    local cmd_name="$1"
    local pkg_apt="${2:-$cmd_name}"
    local pkg_dnf="${3:-$cmd_name}"
    local pkg_pacman="${4:-$cmd_name}"
    local pkg_zypper="${5:-$cmd_name}"

    if [[ -z "$cmd_name" ]]; then
        printf "\nError interno: Se debe especificar el nombre del comando a verificar.\n\n"
        return 1
    fi

    # Si el ejecutable ya existe en el PATH, pasa la validación directamente
    if command -v "$cmd_name" >/dev/null 2>&1; then
        return 0
    fi

    printf "\n Se requiere '%s' para continuar y no se detectó en el sistema.\n\n" "$cmd_name"

    local confirm=""
    read -rp "¿Desea intentar instalarlo automáticamente? [s/N]: " confirm
    if [[ "${confirm,,}" != "s" ]]; then
        printf "\nInstalación cancelada. No se puede continuar sin '%s'.\n\n" "$cmd_name"
        return 1
    fi

    local pkg_manager=""
    local install_cmd=""

    if command -v apt-get >/dev/null 2>&1; then
        pkg_manager="apt-get"
        install_cmd="sudo apt-get update -qq && sudo apt-get install -y $pkg_apt"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
        install_cmd="sudo dnf install -y $pkg_dnf"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_manager="pacman"
        install_cmd="sudo pacman -S --noconfirm $pkg_pacman"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_manager="zypper"
        install_cmd="sudo zypper install -y $pkg_zypper"
    else
        printf "\nNo se detectó un gestor de paquetes soportado (apt, dnf, pacman, zypper).\n"
        printf "Por favor, instale '%s' manualmente.\n\n" "$cmd_name"
        return 1
    fi

    printf "\nSe procederá a instalar '%s' mediante %s.\n" "$cmd_name" "$pkg_manager"
    printf "Es posible que el sistema solicite su contraseña de superusuario (sudo):\n\n"

    if eval "$install_cmd"; then
        printf "\n '%s' se instaló correctamente.\n\n" "$cmd_name"
        return 0
    else
        printf "\nError durante la instalación de '%s'. Verifique sus permisos de sudo.\n\n" "$cmd_name"
        return 1
    fi
}

clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    elif command -v cls >/dev/null 2>&1; then
        cls
    else
        printf "\033[c\033[2J\033[H"
    fi
}

get_value_with_cancel_action_option() {
    local original_message="$1"
    local -n out_value_ref=$2
    local user_input=""

    read -r -p "${original_message}("q" para cancelar) " user_input

    if [[ "${user_input,,}" == "q" ]]; then
        clear_screen
        return 1
    fi

    out_value_ref="$user_input"
    return 0
}

update_array_length_variable_by_ref(){
    local -n ar_ref=$1
    local -n ar_length_ref=$2
    local -i new_ar_length=0

    local count=0
    for key in "${!ar_ref[@]}"; do
        [[ "$key" == *",id" ]] && ((count++))
    done

    ar_length_ref=$count
}