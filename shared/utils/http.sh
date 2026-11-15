#!/usr/bin/env bash
#
# Parser y helpers HTTP para el router servido con socat.

[[ -n "${_ERP_HTTP_LOADED:-}" ]] && return 0
declare -g _ERP_HTTP_LOADED=1

declare -g HTTP_METHOD=""
declare -g HTTP_TARGET=""
declare -g HTTP_PATH=""
declare -g HTTP_QUERY=""
declare -g HTTP_VERSION="HTTP/1.1"
declare -g HTTP_BODY=""
declare -g HTTP_CONTENT_TYPE=""
declare -g HTTP_CONTENT_LENGTH=0
declare -ga HTTP_EXTRA_HEADERS=()
declare -gA HTTP_HEADERS=()
declare -gA HTTP_QUERY_PARAMS=()
declare -gA HTTP_BODY_PARAMS=()
declare -gA HTTP_COOKIES=()

url_decode() {
    local value="${1:-}"
    value="${value//+/ }"
    printf -v value '%b' "${value//%/\\x}"
    printf '%s' "${value}"
}

http_parse_pairs() {
    local raw="${1:-}"
    local -n _target=$2
    _target=()

    local pair key value
    local -a pairs=()
    IFS='&' read -ra pairs <<< "${raw}"
    for pair in "${pairs[@]}"; do
        [[ -z "${pair}" ]] && continue
        key="${pair%%=*}"
        value="${pair#*=}"
        [[ "${value}" == "${pair}" ]] && value=""
        key=$(url_decode "${key}")
        value=$(url_decode "${value}")
        _target["${key}"]="${value}"
    done
}

http_read_request() {
    HTTP_HEADERS=()
    HTTP_QUERY_PARAMS=()
    HTTP_BODY_PARAMS=()
    HTTP_COOKIES=()
    HTTP_EXTRA_HEADERS=()

    local request_line=""
    IFS= read -r -t 15 request_line || return 1
    request_line="${request_line%$'\r'}"
    [[ -z "${request_line}" ]] && return 1

    read -r HTTP_METHOD HTTP_TARGET HTTP_VERSION <<< "${request_line}"
    HTTP_VERSION="${HTTP_VERSION:-HTTP/1.1}"

    local target="${HTTP_TARGET}"
    if [[ "${target}" == *\?* ]]; then
        HTTP_PATH="${target%%\?*}"
        HTTP_QUERY="${target#*\?}"
    else
        HTTP_PATH="${target}"
        HTTP_QUERY=""
    fi
    HTTP_PATH=$(url_decode "${HTTP_PATH}")
    http_parse_pairs "${HTTP_QUERY}" HTTP_QUERY_PARAMS

    local line name value
    while IFS= read -r -t 15 line; do
        line="${line%$'\r'}"
        [[ -z "${line}" ]] && break
        name="${line%%:*}"
        value="${line#*:}"
        value="${value#"${value%%[![:space:]]*}"}"
        name="${name,,}"
        HTTP_HEADERS["${name}"]="${value}"
    done

    HTTP_CONTENT_TYPE="${HTTP_HEADERS[content-type]:-}"
    HTTP_CONTENT_LENGTH="${HTTP_HEADERS[content-length]:-0}"
    [[ "${HTTP_CONTENT_LENGTH}" =~ ^[0-9]+$ ]] || HTTP_CONTENT_LENGTH=0

    if (( HTTP_CONTENT_LENGTH > 0 )); then
        HTTP_BODY=$(head -c "${HTTP_CONTENT_LENGTH}")
    else
        HTTP_BODY=""
    fi

    local cookie_header="${HTTP_HEADERS[cookie]:-}"
    if [[ -n "${cookie_header}" ]]; then
        local -a cookie_parts=()
        local part
        IFS=';' read -ra cookie_parts <<< "${cookie_header}"
        for part in "${cookie_parts[@]}"; do
            part="${part#"${part%%[![:space:]]*}"}"
            [[ "${part}" == *=* ]] || continue
            name="${part%%=*}"
            value="${part#*=}"
            HTTP_COOKIES["${name}"]="${value}"
        done
    fi

    if [[ "${HTTP_CONTENT_TYPE}" == *application/x-www-form-urlencoded* ]]; then
        http_parse_pairs "${HTTP_BODY}" HTTP_BODY_PARAMS
    fi

    return 0
}

http_param() {
    local key="$1"
    local default="${2:-}"
    if [[ -n "${HTTP_BODY_PARAMS[${key}]+x}" ]]; then
        printf '%s' "${HTTP_BODY_PARAMS[${key}]}"
    elif [[ -n "${HTTP_QUERY_PARAMS[${key}]+x}" ]]; then
        printf '%s' "${HTTP_QUERY_PARAMS[${key}]}"
    else
        printf '%s' "${default}"
    fi
}

json_extract_raw() {
    local json="${1:-}"
    local key="${2:-}"
    [[ -z "${json}" || -z "${key}" ]] && return 1

    local compact rest value
    compact=$(printf '%s' "${json}" | tr -d '\n\r')

    # Se toma la primera aparición de la clave. Un `sed` con `.*` devolvería
    # la última coincidencia y confundiría, por ejemplo, el `quantity` de la
    # venta con el `quantity` de cada ítem del arreglo `items`.
    rest="${compact#*\"${key}\"}"
    [[ "${rest}" == "${compact}" ]] && return 1

    if [[ "${rest}" =~ ^[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
        value="${BASH_REMATCH[1]}"
        value="${value//\\\"/\"}"
        value="${value//\\\\/\\}"
        printf '%s' "${value}"
        return 0
    fi

    if [[ "${rest}" =~ ^[[:space:]]*:[[:space:]]*(-?[0-9]+([.][0-9]+)?) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "${rest}" =~ ^[[:space:]]*:[[:space:]]*(true|false) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

json_body_param() {
    local key="$1"
    local default="${2:-}"
    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        local value
        if value=$(json_extract_raw "${HTTP_BODY}" "${key}"); then
            printf '%s' "${value}"
            return 0
        fi
        printf '%s' "${default}"
    else
        http_param "${key}" "${default}"
    fi
}

json_body_parse_items() {
    local -n _product_ids=$1
    local -n _quantities=$2
    _product_ids=()
    _quantities=()

    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        local compact inner
        compact=$(printf '%s' "${HTTP_BODY}" | tr -d '\n\r')
        inner=$(printf '%s' "${compact}" | sed -n 's/.*"items"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')
        [[ -z "${inner}" ]] && return 1

        local rest="${inner}" object product_id quantity
        while [[ "${rest}" == *'{'* ]]; do
            object="${rest#*\{}"
            object="${object%%\}*}"
            product_id=$(json_extract_raw "${object}" "product_id" || true)
            quantity=$(json_extract_raw "${object}" "quantity" || true)
            if [[ -n "${product_id}" && -n "${quantity}" ]]; then
                _product_ids+=("${product_id}")
                _quantities+=("${quantity}")
            fi
            rest="${rest#*\}}"
        done
    else
        local count product_id quantity i
        count=$(http_param "items_count" "0")
        [[ "${count}" =~ ^[0-9]+$ ]] || count=0

        if (( count > 0 )); then
            for (( i = 0; i < count; i++ )); do
                product_id=$(http_param "product_id_${i}" "")
                quantity=$(http_param "quantity_${i}" "")
                if [[ -n "${product_id}" && -n "${quantity}" ]]; then
                    _product_ids+=("${product_id}")
                    _quantities+=("${quantity}")
                fi
            done
        else
            product_id=$(http_param "product_id" "")
            quantity=$(http_param "quantity" "")
            if [[ -n "${product_id}" && -n "${quantity}" ]]; then
                _product_ids+=("${product_id}")
                _quantities+=("${quantity}")
            fi
        fi
    fi

    (( ${#_product_ids[@]} > 0 ))
}

json_body_parse_input_items() {
    local -n _input_ids=$1
    local -n _quantities=$2
    local -n _unit_costs=$3
    _input_ids=()
    _quantities=()
    _unit_costs=()

    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        local compact inner
        compact=$(printf '%s' "${HTTP_BODY}" | tr -d '\n\r')
        inner=$(printf '%s' "${compact}" | sed -n 's/.*"items"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')
        [[ -z "${inner}" ]] && return 1

        local rest="${inner}" object input_id quantity unit_cost
        while [[ "${rest}" == *'{'* ]]; do
            object="${rest#*\{}"
            object="${object%%\}*}"
            input_id=$(json_extract_raw "${object}" "input_id" || true)
            quantity=$(json_extract_raw "${object}" "quantity" || true)
            unit_cost=$(json_extract_raw "${object}" "unit_cost" || true)
            if [[ -n "${input_id}" && -n "${quantity}" ]]; then
                _input_ids+=("${input_id}")
                _quantities+=("${quantity}")
                _unit_costs+=("${unit_cost:-0}")
            fi
            rest="${rest#*\}}"
        done
    else
        local count input_id quantity unit_cost i
        count=$(http_param "items_count" "0")
        [[ "${count}" =~ ^[0-9]+$ ]] || count=0

        if (( count > 0 )); then
            for (( i = 0; i < count; i++ )); do
                input_id=$(http_param "input_id_${i}" "")
                quantity=$(http_param "quantity_${i}" "")
                unit_cost=$(http_param "unit_cost_${i}" "0")
                if [[ -n "${input_id}" && -n "${quantity}" ]]; then
                    _input_ids+=("${input_id}")
                    _quantities+=("${quantity}")
                    _unit_costs+=("${unit_cost:-0}")
                fi
            done
        fi
    fi

    (( ${#_input_ids[@]} > 0 ))
}

json_body_parse_order_items() {
    local -n _product_ids=$1
    local -n _quantities=$2
    local -n _unit_prices=$3
    _product_ids=()
    _quantities=()
    _unit_prices=()

    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        local compact inner
        compact=$(printf '%s' "${HTTP_BODY}" | tr -d '\n\r')
        inner=$(printf '%s' "${compact}" | sed -n 's/.*"items"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')
        [[ -z "${inner}" ]] && return 1

        local rest="${inner}" object product_id quantity unit_price
        while [[ "${rest}" == *'{'* ]]; do
            object="${rest#*\{}"
            object="${object%%\}*}"
            product_id=$(json_extract_raw "${object}" "product_id" || true)
            quantity=$(json_extract_raw "${object}" "quantity" || true)
            unit_price=$(json_extract_raw "${object}" "unit_price" || true)
            if [[ -n "${product_id}" && -n "${quantity}" ]]; then
                _product_ids+=("${product_id}")
                _quantities+=("${quantity}")
                _unit_prices+=("${unit_price:-}")
            fi
            rest="${rest#*\}}"
        done
    else
        local count product_id quantity unit_price i
        count=$(http_param "items_count" "0")
        [[ "${count}" =~ ^[0-9]+$ ]] || count=0

        if (( count > 0 )); then
            for (( i = 0; i < count; i++ )); do
                product_id=$(http_param "product_id_${i}" "")
                quantity=$(http_param "quantity_${i}" "")
                unit_price=$(http_param "unit_price_${i}" "")
                if [[ -n "${product_id}" && -n "${quantity}" ]]; then
                    _product_ids+=("${product_id}")
                    _quantities+=("${quantity}")
                    _unit_prices+=("${unit_price}")
                fi
            done
        fi
    fi

    (( ${#_product_ids[@]} > 0 ))
}

json_body_parse_component_items() {
    local -n _component_ids=$1
    local -n _quantities=$2
    _component_ids=()
    _quantities=()

    if [[ "${HTTP_CONTENT_TYPE}" == *application/json* ]]; then
        local compact inner
        compact=$(printf '%s' "${HTTP_BODY}" | tr -d '\n\r')
        inner=$(printf '%s' "${compact}" | sed -n 's/.*"components"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')
        [[ -z "${inner}" ]] && return 1

        local rest="${inner}" object component_product_id quantity
        while [[ "${rest}" == *'{'* ]]; do
            object="${rest#*\{}"
            object="${object%%\}*}"
            component_product_id=$(json_extract_raw "${object}" "component_product_id" || true)
            quantity=$(json_extract_raw "${object}" "quantity" || true)
            if [[ -n "${component_product_id}" && -n "${quantity}" ]]; then
                _component_ids+=("${component_product_id}")
                _quantities+=("${quantity}")
            fi
            rest="${rest#*\}}"
        done
    else
        local count component_product_id quantity i
        count=$(http_param "components_count" "0")
        [[ "${count}" =~ ^[0-9]+$ ]] || count=0

        if (( count > 0 )); then
            for (( i = 0; i < count; i++ )); do
                component_product_id=$(http_param "component_product_id_${i}" "")
                quantity=$(http_param "quantity_${i}" "")
                if [[ -n "${component_product_id}" && -n "${quantity}" ]]; then
                    _component_ids+=("${component_product_id}")
                    _quantities+=("${quantity}")
                fi
            done
        fi
    fi

    (( ${#_component_ids[@]} > 0 ))
}

http_status_text() {
    case "$1" in
        200) printf 'OK' ;;
        201) printf 'Created' ;;
        204) printf 'No Content' ;;
        302) printf 'Found' ;;
        400) printf 'Bad Request' ;;
        401) printf 'Unauthorized' ;;
        403) printf 'Forbidden' ;;
        404) printf 'Not Found' ;;
        405) printf 'Method Not Allowed' ;;
        500) printf 'Internal Server Error' ;;
        *) printf 'OK' ;;
    esac
}

http_add_header() {
    HTTP_EXTRA_HEADERS+=("$1")
}

http_send() {
    local status="${1:-200}"
    local content_type="${2:-text/html; charset=UTF-8}"
    local body="${3:-}"
    local reason length

    reason=$(http_status_text "${status}")
    length=$(printf '%s' "${body}" | wc -c | tr -d ' ')

    printf 'HTTP/1.1 %s %s\r\n' "${status}" "${reason}"
    printf 'Content-Type: %s\r\n' "${content_type}"
    printf 'Content-Length: %s\r\n' "${length}"
    printf 'Cache-Control: no-store, no-cache, must-revalidate\r\n'
    printf 'Pragma: no-cache\r\n'
    printf 'X-Content-Type-Options: nosniff\r\n'
    printf 'X-Frame-Options: SAMEORIGIN\r\n'
    printf 'Connection: close\r\n'

    local header
    for header in "${HTTP_EXTRA_HEADERS[@]}"; do
        printf '%s\r\n' "${header}"
    done

    printf '\r\n'
    printf '%s' "${body}"
    HTTP_EXTRA_HEADERS=()
}

http_send_json() {
    local body="${1:-"{}"}"
    local status="${2:-200}"
    http_send "${status}" "application/json; charset=UTF-8" "${body}"
}

http_redirect() {
    local location="${1:-/login}"
    local status="${2:-302}"
    http_add_header "Location: ${location}"
    http_send "${status}" "text/html; charset=UTF-8" "<html><body>Redirigiendo...</body></html>"
}

http_send_file() {
    local path="$1"
    local content_type="${2:-application/octet-stream}"

    if [[ ! -f "${path}" ]]; then
        http_send 404 "text/plain; charset=UTF-8" "Recurso no encontrado"
        return
    fi

    local content
    content=$(cat "${path}")
    http_send 200 "${content_type}" "${content}"
}

http_json_error() {
    local message="${1:-Error interno}"
    local status="${2:-500}"
    http_send_json "{\"ok\":false,\"error\":$(json_quote "${message}")}" "${status}"
}
