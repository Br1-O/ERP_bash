#!/usr/bin/env bash
#
# Carga centralizada de módulos del ERP (MVC en Bash).

APP_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export APP_ROOT_DIR
export ERP_ROOT_DIR="${ERP_ROOT_DIR:-${APP_ROOT_DIR}}"
export ERP_DB_PATH="${ERP_DB_PATH:-${APP_ROOT_DIR}/shared/data/erp_licores.db}"

export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=C
export LANG=C.UTF-8 2>/dev/null

load_erp_modules() {
    local module

    for module in \
        shared/utils/json.sh \
        shared/utils/http.sh \
        shared/utils/helpers.sh \
        shared/utils/validations.sh \
        model/db_singleton.sh \
        model/schema.sh \
        model/transactions.sh \
        api/api_auth.sh \
        api/api_catalog.sh \
        api/api_sales.sh \
        api/analytics.sh \
        frontend/views/layout.sh \
        frontend/views/login.sh \
        frontend/views/dashboard.sh \
        frontend/cli/menu.sh
    do
        if [[ -f "${APP_ROOT_DIR}/${module}" ]]; then
            # shellcheck disable=SC1090
            source "${APP_ROOT_DIR}/${module}"
        else
            printf 'No se encontró el módulo %s\n' "${module}" >&2
            return 1
        fi
    done
}

load_erp_modules
