
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

is_numeric() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

is_decimal() {
    if [[ "$1" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]]; then
        return 0
    else
        return 1
    fi
}

is_alpha() {
     if [[ "$1" =~ ^[a-zA-ZáéíóúÁÉÍÓÚñÑ[:space:]]+$ ]]; then
        return 0
    else
        return 1
    fi
}

is_not_empty(){
    if [[ -z "$1" ]]; then
            return 1
    fi

    return 0
}

is_not_empty_field_with_validation(){
    local field_msg=$1
    local -n field_reference=$2 
                
    while true; do

        is_not_empty "${field_reference}" && break

        printf $'No puedes ingresar un valor vacio para el campo.\n'

        ! get_value_with_cancel_action_option "${field_msg}" field_reference && return 1 

    done

    return 0
}

alpha_field_with_validation(){
    local field_message=$1
    local -n field_ref=$2 
    local is_required="${3:-required}"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    [[ "${is_required}" == "required" ]] && is_not_empty_field_with_validation "${field_message}" field_ref
    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0
                
    while true; do

        is_alpha "${field_ref}" && break

        printf "El campo solo puede poseer letras y espacios.\n"

        ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    done

    return 0
}

enum_field_with_validation(){
    local field_message=$1
    local -n valid_values=$2
    local -n field_ref=$3
    local is_required="${4:-required}"
    
    local joined_values
    joined_values=$(IFS=", "; echo "${valid_values[*]}")


    ! get_value_with_cancel_action_option "${field_message} [Valores posibles: ${joined_values}]: " field_ref && return 1 


    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0

    while true; do

        local value_match=false
        local val
        for val in "${valid_values[@]}"; do
            if [[ "$field_ref" == "$val" ]]; then
                value_match=true
                break
            fi
        done

        if [ "$value_match" = true ]; then
            break
        fi

        printf "Error: El valor introducido no es válido.\n"
        printf "Debe elegir una de las siguientes opciones: %s\n" "${joined_values}"
        
        ! get_value_with_cancel_action_option "${field_message} [Valores posibles: ${joined_values}]: " field_ref && return 1 
    done
    
    return 0
}

numeric_field_with_validation(){
    local field_message=$1
    local -n field_ref=$2 
    local is_required="${3:-required}"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    [[ "${is_required}" == "required" ]] && is_not_empty_field_with_validation "${field_message}" field_ref
    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0
                
    while ! is_numeric "${field_ref}"; do

        printf "El campo solo puede poseer números.\n"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    done

    return 0
}

decimal_field_with_validation(){
    local field_message=$1
    local -n field_ref=$2
    local is_required="${3:-required}"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    [[ "${is_required}" == "required" ]] && is_not_empty_field_with_validation "${field_message}" field_ref
    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0

                
    while ! is_decimal "${field_ref}"; do

        printf "El campo solo puede poseer números, comas y puntos.\n"

        ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    done

    return 0
}