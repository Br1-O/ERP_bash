#!/usr/bin/env bash
#
# Endpoint HTTP mínimo para probar la sincronización sin PostgreSQL.
# Uso: socat TCP-LISTEN:8100,fork,reuseaddr SYSTEM:'./tests/mock_sync.sh'
#
# Guarda la petición en ${TMPDIR:-/tmp} para inspeccionarla.

set -u

OUT_DIR="${ERP_SYNC_MOCK_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "${OUT_DIR}"

IFS= read -r request_line || exit 0
request_line="${request_line%$'\r'}"
printf '%s\n' "${request_line}" > "${OUT_DIR}/erp-sync-request-line.txt"

length=0
: > "${OUT_DIR}/erp-sync-headers.txt"
while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "${line}" ]] && break
    printf '%s\n' "${line}" >> "${OUT_DIR}/erp-sync-headers.txt"
    if [[ "${line}" =~ ^[Cc]ontent-[Ll]ength:\ *([0-9]+)$ ]]; then
        length="${BASH_REMATCH[1]}"
    fi
done

if (( length > 0 )); then
    dd bs="${length}" count=1 iflag=fullblock 2>/dev/null > "${OUT_DIR}/erp-sync-received.json"
else
    : > "${OUT_DIR}/erp-sync-received.json"
fi

response='{"ok":true,"received":true}'
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
    "${#response}" "${response}"
