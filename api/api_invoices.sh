#!/usr/bin/env bash
#
# Comprobantes de compras y pedidos de clientes.

[[ -n "${_ERP_API_INVOICES_LOADED:-}" ]] && return 0
declare -g _ERP_API_INVOICES_LOADED=1

api_invoice_purchase_json() {
    local purchase_id="${1:-0}"
    [[ "${purchase_id}" =~ ^[0-9]+$ ]] || return 1

    local business document
    business=$(api_business_json) || return 1
    document=$(api_purchase_detail_json "${purchase_id}") || return 1
    printf '{"type":"purchase","number":%s,"business":%s,"document":%s}' \
        "$(json_quote "$(printf 'C-%06d' "$((10#${purchase_id}))")")" "${business}" "${document}"
}

api_invoice_order_json() {
    local order_id="${1:-0}"
    [[ "${order_id}" =~ ^[0-9]+$ ]] || return 1

    local status
    status=$(db_scalar "SELECT status FROM Sales WHERE id = ${order_id} AND order_type = 'order';" 2>/dev/null || printf '')
    [[ -n "${status}" ]] || return 1
    [[ "${status}" == "finished" ]] || return 2

    local business document
    business=$(api_business_json) || return 1
    document=$(api_order_detail_json "${order_id}") || return 1
    printf '{"type":"order","number":%s,"business":%s,"document":%s}' \
        "$(json_quote "$(printf 'P-%06d' "$((10#${order_id}))")")" "${business}" "${document}"
}
