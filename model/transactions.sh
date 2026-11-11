#!/usr/bin/env bash
#
# Utilidades de transacciones ACID. Todas las operaciones se ejecutan sobre
# la conexión Singleton, conservando BEGIN/COMMIT/ROLLBACK y last_insert_rowid().

[[ -n "${_ERP_TRANSACTIONS_LOADED:-}" ]] && return 0
declare -g _ERP_TRANSACTIONS_LOADED=1

tx_begin() {
    db_exec "BEGIN IMMEDIATE;"
}

tx_commit() {
    db_exec "COMMIT;"
}

tx_rollback() {
    db_exec "ROLLBACK;" >/dev/null 2>&1 || true
}

# Ejecuta una función dentro de una transacción atómica.
# Uso: tx_run nombre_funcion [argumentos...]
tx_run() {
    local callback="${1:-}"
    [[ -z "${callback}" ]] && return 1
    shift

    tx_begin || return 1

    "${callback}" "$@"
    local rc=$?

    if (( rc == 0 )); then
        if tx_commit; then
            return 0
        fi
        tx_rollback
        return 1
    fi

    tx_rollback
    return "${rc}"
}
