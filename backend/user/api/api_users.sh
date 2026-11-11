#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/validations.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../model/users_sqlite.sh"

declare CURRENT_USER=""

set_current_user() {
    CURRENT_USER="$1"
}

hash_password() {
    local password_value="$1"
    local -n _out_hash_ref=$2
    read -r _out_hash_ref _ < <(printf '%s' "${password_value}" | sha256sum)
}

api_create_user() {
    local username="$1"
    local password="$2"
    local hashed_password=""

    is_not_empty "$username" && is_alpha "$username" || return 1
    is_not_empty "$password" || return 1

    if db_username_exists "$username"; then
        return 2 
    fi

    hash_password "$password" hashed_password
    db_insert_user "$username" "$hashed_password"
}

api_verify_user_credentials() {
    local username="$1"
    local password="$2"
    local db_password=""
    local input_hash=""

    is_not_empty "$username" || return 1
    is_not_empty "$password" || return 1

    if ! db_find_password_by_username "$username" db_password; then
        return 1
    fi

    hash_password "$password" input_hash

    if [[ "${input_hash}" == "${db_password}" ]]; then
        set_current_user "$username"
        return 0
    fi

    return 1
}

api_check_username_exists() {
    db_username_exists "$1"
}