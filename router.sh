#!/usr/bin/env bash
#
# Punto de entrada solicitado por socat. Delega en el router del frontend.

ROUTER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROUTER_ROOT}" || exit 1
exec "${ROUTER_ROOT}/frontend/router.sh"
