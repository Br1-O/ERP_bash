#!/usr/bin/env bash
#
# Compatibilidad con el lanzador anterior. Toda la aplicación vive ahora en
# erp.sh: dashboard web por defecto y consola interactiva con "cli".

set -u

EJERCICIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-server}"

case "${mode,,}" in
    cli|--cli|terminal)
        exec "${EJERCICIO_DIR}/erp.sh" cli
        ;;
    tui)
        printf 'La TUI anterior fue reemplazada por el dashboard web. Iniciando servidor...\n'
        exec "${EJERCICIO_DIR}/erp.sh" server "${2:-8080}"
        ;;
    web|server|--web)
        exec "${EJERCICIO_DIR}/erp.sh" server "${2:-8080}"
        ;;
    init|seed)
        exec "${EJERCICIO_DIR}/erp.sh" init
        ;;
    help|-h|--help|"")
        exec "${EJERCICIO_DIR}/erp.sh" help
        ;;
    *)
        printf 'Opción desconocida: %s\n\n' "${mode}" >&2
        "${EJERCICIO_DIR}/erp.sh" help
        exit 1
        ;;
esac
