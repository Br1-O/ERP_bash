#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/utils/validations.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../model/inventory_sqlite.sh"

api_get_total_inventory_count() {
    db_get_total_inventory_count
}

api_insert_product() {
    local nombre="$1"
    local categoria="$2"
    local stock="$3"
    local costo="$4"
    local precio="$5"

    is_not_empty "$nombre" && is_alpha "$nombre" || return 1
    [[ ${#nombre} -gt 50 ]] && return 1
    is_not_empty "$categoria" || return 1
    is_numeric "$stock" && (( stock >= 0 )) || return 1
    is_decimal "$costo" || return 1
    is_decimal "$precio" || return 1

    if db_product_exists_by_name "$nombre"; then
        return 2 
    fi

    db_insert_product "$nombre" "$categoria" "$stock" "$costo" "$precio"
}

api_delete_product_by_id() {
    local -i id="$1"
    is_numeric "$id" && (( id > 0 )) || return 1

    if ! db_product_exists_by_id "$id"; then
        return 2 
    fi

    db_delete_product "$id"
}

api_update_product() {
    local -n prod_ref=$1
    local -i id="${prod_ref[id]:-0}"
    local nombre="${prod_ref[nombre]}"
    local categoria="${prod_ref[categoria]}"
    local stock="${prod_ref[stock]}"
    local costo="${prod_ref[costo]}"
    local precio="${prod_ref[precio]}"
    local -i activo="${prod_ref[activo]:-1}"

    is_numeric "$id" && (( id > 0 )) || return 1
    is_not_empty "$nombre" && is_alpha "$nombre" || return 1
    is_not_empty "$categoria" || return 1
    is_numeric "$stock" || return 1
    is_decimal "$costo" || return 1
    is_decimal "$precio" || return 1
    (( activo == 0 || activo == 1 )) || return 1

    db_update_product prod_ref
}

api_search_products() {
    local term="$1"
    local -n out_ref=$2
    local -n count_ref=$3
    db_search_products_by_name "$term" out_ref count_ref
}

api_get_total_journal_count() {
    db_get_total_journal_count
}

api_get_paginated_journal() {
    local -i limit="$1"
    local -i offset="$2"
    db_get_paginated_journal "$limit" "$offset"
}

api_get_all_inventory() {
    db_get_all_inventory
}

api_get_full_journal() {
    local total
    total=$(db_get_total_journal_count)
    if (( total > 0 )); then
        db_get_paginated_journal "$total" 0
    fi
}