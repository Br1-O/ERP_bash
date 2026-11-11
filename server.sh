#!/usr/bin/env bash
#
# Servidor HTTP liviano basado en socat.
# Uso: ./server.sh [puerto]

set -u

SERVER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SERVER_ROOT}" || exit 1

# shellcheck disable=SC1091
source "${SERVER_ROOT}/config.sh"

PORT="${1:-8080}"
if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
    printf 'Puerto inválido: %s\n' "${PORT}" >&2
    exit 1
fi
PORT=$((10#${PORT}))
if (( PORT < 1 || PORT > 65535 )); then
    printf 'Puerto inválido: %s\n' "${PORT}" >&2
    exit 1
fi

if ! db_sqlite_available; then
    ensure_package_installed "sqlite3" "sqlite3" "sqlite3" "sqlite" "sqlite3" || {
        printf 'Se requiere sqlite3 (o Python 3 con el módulo sqlite3) para iniciar el ERP.\n' >&2
        exit 1
    }
fi

if ! command -v socat >/dev/null 2>&1; then
    ensure_package_installed "socat" "socat" "socat" "socat" "socat" || {
        printf 'Se requiere socat para iniciar el servidor HTTP.\n' >&2
        exit 1
    }
fi

if ! db_singleton_init; then
    printf 'No se pudo inicializar la base de datos: %s\n' "${DB_LAST_ERROR:-error desconocido}" >&2
    exit 1
fi

LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -z "${LOCAL_IP}" ]] && LOCAL_IP="127.0.0.1"

printf '\n'
printf '  Aurea ERP · Servidor HTTP con socat\n'
printf '  ------------------------------------------------\n'
printf '  Base de datos: %s\n' "${ERP_DB_PATH}"
printf '  Acceso local:  http://localhost:%s\n' "${PORT}"
printf '  Red local:     http://%s:%s\n' "${LOCAL_IP}" "${PORT}"
printf '  Acceso demo:   admin / admin123\n'
printf '  Ctrl+C para detener el servidor.\n'
printf '  ------------------------------------------------\n\n'

exec socat TCP-LISTEN:"${PORT}",fork,reuseaddr EXEC:"./router.sh"
