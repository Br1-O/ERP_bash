#!/usr/bin/env bash
#
# Patrón Singleton para la conexión SQLite del ERP.
#
# Una única instancia de sqlite3 se mantiene viva por proceso (coproceso) y
# todas las capas (modelo, API y vistas) reutilizan esa conexión a través de
# db_query / db_exec / db_scalar. De esta forma no se abren conexiones
# redundantes y se conservan el estado de las transacciones y last_insert_rowid().

[[ -n "${_ERP_DB_SINGLETON_LOADED:-}" ]] && return 0
declare -g _ERP_DB_SINGLETON_LOADED=1

ERP_ROOT_DIR="${ERP_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ERP_DB_PATH="${ERP_DB_PATH:-${ERP_ROOT_DIR}/shared/data/erp_licores.db}"
ERP_SCHEMA_VERSION="${ERP_SCHEMA_VERSION:-2}"

declare -g DB_SINGLETON_PID=""
declare -g DB_SINGLETON_IN_FD=""
declare -g DB_SINGLETON_OUT_FD=""
declare -g DB_LAST_ERROR=""

db_sqlite_available() {
    [[ -n "${ERP_SQLITE_BIN:-}" ]] && return 0
    command -v sqlite3 >/dev/null 2>&1 && return 0
    command -v python3 >/dev/null 2>&1 && [[ -f "${ERP_ROOT_DIR}/tools/sqlite3_shim.py" ]] && return 0
    return 1
}

db_is_open() {
    [[ -n "${DB_SINGLETON_PID}" ]] && kill -0 "${DB_SINGLETON_PID}" 2>/dev/null
}

db_open() {
    if db_is_open; then
        return 0
    fi

    local -a sqlite_cmd=()
    if [[ -n "${ERP_SQLITE_BIN:-}" ]]; then
        read -r -a sqlite_cmd <<< "${ERP_SQLITE_BIN}"
    elif command -v sqlite3 >/dev/null 2>&1; then
        sqlite_cmd=(sqlite3)
    elif command -v python3 >/dev/null 2>&1 && [[ -f "${ERP_ROOT_DIR}/tools/sqlite3_shim.py" ]]; then
        sqlite_cmd=(python3 "${ERP_ROOT_DIR}/tools/sqlite3_shim.py")
    else
        DB_LAST_ERROR="sqlite3 no está instalado."
        return 1
    fi

    mkdir -p "$(dirname "${ERP_DB_PATH}")" || return 1

    coproc ERP_DB_CONN { exec "${sqlite_cmd[@]}" -batch -noheader -separator '|' "${ERP_DB_PATH}" 2>&1; }
    DB_SINGLETON_PID="${ERP_DB_CONN_PID}"

    # Duplicamos los descriptores para que el coproceso siga accesible aunque
    # el arreglo ERP_DB_CONN se reutilice en otras funciones.
    exec {DB_SINGLETON_IN_FD}>&"${ERP_DB_CONN[1]}"
    exec {DB_SINGLETON_OUT_FD}<&"${ERP_DB_CONN[0]}"

    if ! db_is_open; then
        DB_LAST_ERROR="No se pudo iniciar la conexión Singleton con SQLite."
        return 1
    fi

    if ! _db_send "PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;" >/dev/null; then
        DB_LAST_ERROR="No se pudieron configurar los PRAGMA de SQLite."
        return 1
    fi

    return 0
}

db_close() {
    if db_is_open; then
        printf '.quit\n' >&"${DB_SINGLETON_IN_FD}" 2>/dev/null || true
        exec {DB_SINGLETON_IN_FD}>&- 2>/dev/null || true
        exec {DB_SINGLETON_OUT_FD}<&- 2>/dev/null || true
        wait "${DB_SINGLETON_PID}" 2>/dev/null || true
    fi
    DB_SINGLETON_PID=""
    DB_SINGLETON_IN_FD=""
    DB_SINGLETON_OUT_FD=""
}

# Envía una sentencia SQL y vuelca las filas devueltas. Usa un marcador para
# saber cuándo sqlite3 terminó de responder una consulta concreta.
_db_send() {
    local sql="${1:-}"
    [[ -z "${sql//[[:space:]]/}" ]] && return 0

    if ! db_is_open && ! db_open; then
        return 1
    fi

    local marker="__ERP_DB_${BASHPID}_${RANDOM}${RANDOM}__"
    sql="${sql%"${sql##*[![:space:]]}"}"
    [[ "${sql}" == *';' ]] && sql="${sql%;}"

    if ! printf "%s;\nSELECT '%s';\n" "${sql}" "${marker}" >&"${DB_SINGLETON_IN_FD}"; then
        DB_LAST_ERROR="No se pudo escribir en la conexión SQLite."
        return 1
    fi

    local line found=0
    while IFS= read -r -t 30 line <&"${DB_SINGLETON_OUT_FD}"; do
        if [[ "${line}" == "${marker}" ]]; then
            found=1
            break
        fi
        printf '%s\n' "${line}"
    done

    if (( ! found )); then
        DB_LAST_ERROR="SQLite no respondió a la consulta (conexión interrumpida)."
        return 1
    fi

    return 0
}

db_query() {
    _db_send "$1"
}

db_exec() {
    local output
    output=$(_db_send "$1")
    local rc=$?

    if (( rc != 0 )); then
        DB_LAST_ERROR="${output:-${DB_LAST_ERROR}}"
        return 1
    fi

    # db_exec se usa para DDL/DML que no devuelven filas. Cualquier salida
    # corresponde a un error reportado por sqlite3.
    if [[ -n "${output}" ]]; then
        DB_LAST_ERROR="${output}"
        return 1
    fi

    return 0
}

db_scalar() {
    local output rc
    output=$(db_query "$1")
    rc=$?
    (( rc == 0 )) || return "${rc}"
    [[ -z "${output}" ]] && return 1
    printf '%s\n' "${output%%$'\n'*}"
}

db_last_insert_id() {
    db_scalar "SELECT last_insert_rowid();"
}

db_changes() {
    db_scalar "SELECT changes();"
}

db_escape() {
    local value="${1:-}"
    value="${value//\'/\'\'}"
    printf '%s' "${value}"
}

db_quote() {
    printf "'%s'" "$(db_escape "${1:-}")"
}

db_set_context_user() {
    local user="${1:-sistema}"
    db_exec "INSERT INTO AppContext (key, value) VALUES ('user', $(db_quote "${user}"))
             ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
}

db_get_context_user() {
    db_scalar "SELECT value FROM AppContext WHERE key = 'user';" 2>/dev/null || printf 'sistema\n'
}

db_singleton_init() {
    db_open || return 1

    # La tabla de metadatos se crea siempre (es muy barata) para poder
    # consultar la versión sin provocar errores en una base nueva.
    db_exec "CREATE TABLE IF NOT EXISTS SchemaMeta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );" || return 1

    local version=""
    version=$(db_scalar "SELECT value FROM SchemaMeta WHERE key = 'schema_version';" 2>/dev/null || true)

    if [[ "${version}" != "${ERP_SCHEMA_VERSION}" ]]; then
        declare -F db_apply_schema >/dev/null || {
            DB_LAST_ERROR="db_apply_schema no está cargada."
            return 1
        }
        db_apply_schema || return 1
        db_seed_demo_data || return 1
        db_exec "INSERT INTO SchemaMeta (key, value) VALUES ('schema_version', $(db_quote "${ERP_SCHEMA_VERSION}"))
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value;" || return 1
    fi

    return 0
}
