#!/usr/bin/env bash
#
# Facturación: dinero en centavos y estrategias de descuento.
#
# El patrón Strategy permite agregar nuevas promociones sin tocar el registro
# de ventas: cada estrategia valida su entrada y calcula el descuento en
# centavos. El total siempre se calcula en el servidor; el navegador solo
# muestra una previsualización.

[[ -n "${_ERP_API_BILLING_LOADED:-}" ]] && return 0
declare -g _ERP_API_BILLING_LOADED=1

declare -g BILLING_SUBTOTAL_CENTS=0
declare -g BILLING_DISCOUNT_CENTS=0
declare -g BILLING_TOTAL_CENTS=0
declare -g BILLING_DISCOUNT_VALUE_DB="0"
declare -g BILLING_ERROR=""

# Convierte un monto decimal (punto o coma) a centavos sin usar punto flotante.
billing_money_to_cents() {
    local raw="${1:-0}"
    raw="${raw//[[:space:]]/}"
    if [[ "${raw}" == *,* && "${raw}" != *.* ]]; then
        raw="${raw/,/.}"
    fi

    if [[ ! "${raw}" =~ ^(-?)([0-9]{1,12})([.]([0-9]*))?$ ]]; then
        return 1
    fi

    local sign="${BASH_REMATCH[1]}"
    local whole="${BASH_REMATCH[2]}"
    local fraction="${BASH_REMATCH[4]:-}"
    while (( ${#fraction} < 3 )); do
        fraction+="0"
    done

    local cents=$(( 10#${whole} * 100 + 10#${fraction:0:2} ))
    if (( 10#${fraction:2:1} >= 5 )); then
        cents=$(( cents + 1 ))
    fi
    if [[ "${sign}" == "-" ]]; then
        cents=$(( -cents ))
    fi
    printf '%s' "${cents}"
}

billing_cents_to_decimal() {
    local cents="${1:-0}"
    local sign=""
    if (( cents < 0 )); then
        sign="-"
        cents=$(( -cents ))
    fi
    printf '%s%d.%02d' "${sign}" $(( cents / 100 )) $(( cents % 100 ))
}

billing_strategy_none() {
    BILLING_DISCOUNT_CENTS=0
    BILLING_DISCOUNT_VALUE_DB="0"
    return 0
}

billing_strategy_percent() {
    local basis_points
    basis_points=$(billing_money_to_cents "${1:-}") || {
        BILLING_ERROR="Porcentaje de descuento inválido."
        return 1
    }
    if (( basis_points < 0 || basis_points > 10000 )); then
        BILLING_ERROR="El porcentaje debe estar entre 0 y 100."
        return 1
    fi
    BILLING_DISCOUNT_VALUE_DB=$(billing_cents_to_decimal "${basis_points}")
    BILLING_DISCOUNT_CENTS=$(( (BILLING_SUBTOTAL_CENTS * basis_points + 5000) / 10000 ))
    return 0
}

billing_strategy_fixed() {
    local amount
    amount=$(billing_money_to_cents "${1:-}") || {
        BILLING_ERROR="Monto de descuento inválido."
        return 1
    }
    if (( amount < 0 )); then
        BILLING_ERROR="El descuento no puede ser negativo."
        return 1
    fi
    if (( amount > BILLING_SUBTOTAL_CENTS )); then
        BILLING_ERROR="El descuento no puede superar el subtotal."
        return 1
    fi
    BILLING_DISCOUNT_VALUE_DB=$(billing_cents_to_decimal "${amount}")
    BILLING_DISCOUNT_CENTS="${amount}"
    return 0
}

declare -gA BILLING_STRATEGY_HANDLERS=(
    [none]=billing_strategy_none
    [percent]=billing_strategy_percent
    [fixed]=billing_strategy_fixed
)

billing_apply_strategy() {
    local type="${1:-none}"
    local value="${2:-0}"
    local subtotal="${3:-0}"

    BILLING_ERROR=""
    BILLING_SUBTOTAL_CENTS="${subtotal}"
    BILLING_DISCOUNT_CENTS=0
    BILLING_DISCOUNT_VALUE_DB="0"
    BILLING_TOTAL_CENTS="${subtotal}"

    local handler="${BILLING_STRATEGY_HANDLERS[${type}]:-}"
    if [[ -z "${handler}" ]]; then
        BILLING_ERROR="Tipo de descuento inválido."
        return 1
    fi
    if ! "${handler}" "${value}"; then
        return 1
    fi
    BILLING_TOTAL_CENTS=$(( BILLING_SUBTOTAL_CENTS - BILLING_DISCOUNT_CENTS ))
    if (( BILLING_TOTAL_CENTS < 0 )); then
        BILLING_ERROR="El total no puede ser negativo."
        return 1
    fi
    return 0
}
