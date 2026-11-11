#!/usr/bin/env bash
# Generado automáticamente - Sistema de Inventario (CLI + TUI)


ensure_package_installed() {
    local cmd_name="$1"
    local pkg_apt="${2:-$cmd_name}"
    local pkg_dnf="${3:-$cmd_name}"
    local pkg_pacman="${4:-$cmd_name}"
    local pkg_zypper="${5:-$cmd_name}"

    if [[ -z "$cmd_name" ]]; then
        printf "\nError interno: Se debe especificar el nombre del comando a verificar.\n\n"
        return 1
    fi

    # Si el ejecutable ya existe en el PATH, pasa la validación directamente
    if command -v "$cmd_name" >/dev/null 2>&1; then
        return 0
    fi

    printf "\n Se requiere '%s' para continuar y no se detectó en el sistema.\n\n" "$cmd_name"

    local confirm=""
    read -rp "¿Desea intentar instalarlo automáticamente? [s/N]: " confirm
    if [[ "${confirm,,}" != "s" ]]; then
        printf "\nInstalación cancelada. No se puede continuar sin '%s'.\n\n" "$cmd_name"
        return 1
    fi

    local pkg_manager=""
    local install_cmd=""

    if command -v apt-get >/dev/null 2>&1; then
        pkg_manager="apt-get"
        install_cmd="sudo apt-get update -qq && sudo apt-get install -y $pkg_apt"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
        install_cmd="sudo dnf install -y $pkg_dnf"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_manager="pacman"
        install_cmd="sudo pacman -S --noconfirm $pkg_pacman"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_manager="zypper"
        install_cmd="sudo zypper install -y $pkg_zypper"
    else
        printf "\nNo se detectó un gestor de paquetes soportado (apt, dnf, pacman, zypper).\n"
        printf "Por favor, instale '%s' manualmente.\n\n" "$cmd_name"
        return 1
    fi

    printf "\nSe procederá a instalar '%s' mediante %s.\n" "$cmd_name" "$pkg_manager"
    printf "Es posible que el sistema solicite su contraseña de superusuario (sudo):\n\n"

    if eval "$install_cmd"; then
        printf "\n '%s' se instaló correctamente.\n\n" "$cmd_name"
        return 0
    else
        printf "\nError durante la instalación de '%s'. Verifique sus permisos de sudo.\n\n" "$cmd_name"
        return 1
    fi
}

clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    elif command -v cls >/dev/null 2>&1; then
        cls
    else
        printf "\033[c\033[2J\033[H"
    fi
}

get_value_with_cancel_action_option() {
    local original_message="$1"
    local -n out_value_ref=$2
    local user_input=""

    read -r -p "${original_message}("q" para cancelar) " user_input

    if [[ "${user_input,,}" == "q" ]]; then
        clear_screen
        return 1
    fi

    out_value_ref="$user_input"
    return 0
}

update_array_length_variable_by_ref(){
    local -n ar_ref=$1
    local -n ar_length_ref=$2
    local -i new_ar_length=0

    local count=0
    for key in "${!ar_ref[@]}"; do
        [[ "$key" == *",id" ]] && ((count++))
    done

    ar_length_ref=$count
}


is_numeric() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

is_decimal() {
    if [[ "$1" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]]; then
        return 0
    else
        return 1
    fi
}

is_alpha() {
     if [[ "$1" =~ ^[a-zA-ZáéíóúÁÉÍÓÚñÑ[:space:]]+$ ]]; then
        return 0
    else
        return 1
    fi
}

is_not_empty(){
    if [[ -z "$1" ]]; then
            return 1
    fi

    return 0
}

is_not_empty_field_with_validation(){
    local field_msg=$1
    local -n field_reference=$2 
                
    while true; do

        is_not_empty "${field_reference}" && break

        printf $'No puedes ingresar un valor vacio para el campo.\n'

        ! get_value_with_cancel_action_option "${field_msg}" field_reference && return 1 

    done

    return 0
}

alpha_field_with_validation(){
    local field_message=$1
    local -n field_ref=$2 
    local is_required="${3:-required}"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    [[ "${is_required}" == "required" ]] && is_not_empty_field_with_validation "${field_message}" field_ref
    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0
                
    while true; do

        is_alpha "${field_ref}" && break

        printf "El campo solo puede poseer letras y espacios.\n"

        ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    done

    return 0
}

enum_field_with_validation(){
    local field_message=$1
    local -n valid_values=$2
    local -n field_ref=$3
    local is_required="${4:-required}"
    
    local joined_values
    joined_values=$(IFS=", "; echo "${valid_values[*]}")


    ! get_value_with_cancel_action_option "${field_message} [Valores posibles: ${joined_values}]: " field_ref && return 1 


    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0

    while true; do

        local value_match=false
        local val
        for val in "${valid_values[@]}"; do
            if [[ "$field_ref" == "$val" ]]; then
                value_match=true
                break
            fi
        done

        if [ "$value_match" = true ]; then
            break
        fi

        printf "Error: El valor introducido no es válido.\n"
        printf "Debe elegir una de las siguientes opciones: %s\n" "${joined_values}"
        
        ! get_value_with_cancel_action_option "${field_message} [Valores posibles: ${joined_values}]: " field_ref && return 1 
    done
    
    return 0
}

numeric_field_with_validation(){
    local field_message=$1
    local -n field_ref=$2 
    local is_required="${3:-required}"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    [[ "${is_required}" == "required" ]] && is_not_empty_field_with_validation "${field_message}" field_ref
    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0
                
    while ! is_numeric "${field_ref}"; do

        printf "El campo solo puede poseer números.\n"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    done

    return 0
}

decimal_field_with_validation(){
    local field_message=$1
    local -n field_ref=$2
    local is_required="${3:-required}"

    ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    [[ "${is_required}" == "required" ]] && is_not_empty_field_with_validation "${field_message}" field_ref
    [[ "${is_required}" == "not_required" ]] && [[ -z "${field_ref}" ]] && return 0

                
    while ! is_decimal "${field_ref}"; do

        printf "El campo solo puede poseer números, comas y puntos.\n"

        ! get_value_with_cancel_action_option "${field_message}" field_ref && return 1 

    done

    return 0
}
start_local_http_server() {
    local -n pid_ref=$1
    local -i port=${2:-8080}
    local html_file="$3"

    if (( pid_ref > 0 )) && kill -0 "$pid_ref" 2>/dev/null; then
        printf "\nEl servidor ya está activo (PID: %d).\n" "$pid_ref"
        return 1
    fi

    if [[ ! -f "$html_file" ]]; then
        printf "\nError: No se encontró el archivo %s para servir.\n\n" "$html_file"
        return 1
    fi

    fuser -k -9 "$port/tcp" >/dev/null 2>&1

    (
        trap 'pkill -P $$; exit 0' TERM INT EXIT
        while true; do
            {
                printf "HTTP/1.1 200 OK\r\n"
                printf "Content-Type: text/html; charset=UTF-8\r\n"
                printf "Content-Length: %d\r\n" "$(wc -c < "$html_file")"
                printf "Cache-Control: no-cache, no-store, must-revalidate\r\n"
                printf "Pragma: no-cache\r\n"
                printf "Expires: 0\r\n"
                printf "Connection: close\r\n\r\n"
                cat "$html_file"
            } | nc -l -p "$port" -q 1 >/dev/null 2>&1
        done
    ) &

    pid_ref=$!

    local local_ip
    local_ip=$(hostname -I | awk '{print $1}')
    
    printf "\nServidor HTTP iniciado (PID: %d).\n" "$pid_ref"
    printf "   ➜ Acceso local:   http://localhost:%d\n" "$port"
    printf "   ➜ Red Local (LAN): http://%s:%d\n\n" "$local_ip" "$port"
}

stop_local_http_server() {
    local -n pid_ref=$1
    local -i port=${2:-8080}

    set +m 2>/dev/null

    (
        pkill -9 -f "nc -l -p $port" 2>/dev/null

        if (( pid_ref > 0 )); then
            kill -9 "$pid_ref" 2>/dev/null
            kill -9 -"$pid_ref" 2>/dev/null
            wait "$pid_ref" 2>/dev/null
        fi

        fuser -k -9 "$port/tcp" 2>/dev/null
    ) >/dev/null 2>&1

    pid_ref=0
    printf "\nServidor detenido correctamente.\n\n"
}

#!/usr/bin/env bash

SQLITE_INVENTORY_PATH="shared/data/datos_inventario.db"

init_db() {
    mkdir -p "$(dirname "$SQLITE_INVENTORY_PATH")"
    sqlite3 "$SQLITE_INVENTORY_PATH" >/dev/null <<EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS Categories (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE NOT NULL CHECK (length(name) <= 50)
);

CREATE TABLE IF NOT EXISTS Inventory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK (length(name) <= 50),
    category_id INTEGER NOT NULL,
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    cost REAL NOT NULL DEFAULT 0.0,
    price REAL NOT NULL DEFAULT 0.0,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    FOREIGN KEY (category_id) REFERENCES Categories(id)
);

CREATE TABLE IF NOT EXISTS InventoryJournal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    user TEXT NOT NULL,
    action TEXT NOT NULL,
    product_id INTEGER,
    payload TEXT NOT NULL,
    status TEXT DEFAULT 'DONE'
);

INSERT OR IGNORE INTO Categories (id, name) VALUES (1, 'General');
EOF
}

db_get_total_inventory_count() {
    sqlite3 "$SQLITE_INVENTORY_PATH" "SELECT COUNT(*) FROM Inventory;"
}

db_product_exists_by_name() {
    local name="$1"
    local count
    count=$(sqlite3 "$SQLITE_INVENTORY_PATH" "SELECT COUNT(*) FROM Inventory WHERE LOWER(name) = LOWER('$name');")
    (( count > 0 )) && return 0
    return 1
}

db_product_exists_by_id() {
    local -i id="$1"
    local count
    count=$(sqlite3 "$SQLITE_INVENTORY_PATH" "SELECT COUNT(*) FROM Inventory WHERE id=$id;")
    (( count > 0 )) && return 0
    return 1
}

db_insert_product() {
    local nombre="$1" categoria="$2" stock="$3" costo="$4" precio="$5"
    local user="${CURRENT_USER:-sistema}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local payload="$nombre|$categoria|$stock|$costo|$precio|1"

    sqlite3 "$SQLITE_INVENTORY_PATH" >/dev/null <<EOF
PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

INSERT OR IGNORE INTO Categories (name) VALUES ('$categoria');

INSERT INTO Inventory (name, category_id, stock, cost, price, active)
VALUES ('$nombre', (SELECT id FROM Categories WHERE name='$categoria'), $stock, $costo, $precio, 1);

INSERT INTO InventoryJournal (timestamp, user, action, product_id, payload, status)
VALUES ('$timestamp', '$user', 'INSERT', last_insert_rowid(), '$payload', 'DONE');

COMMIT;
EOF
}

db_search_products_by_name() {
    local search_name="$1"
    local -n _out_ref=$2
    local -n _count_ref=$3

    _out_ref=()
    _count_ref=0

    local query="SELECT i.id, i.name, c.name, i.stock, i.cost, i.price, i.active FROM Inventory i JOIN Categories c ON i.category_id = c.id WHERE LOWER(i.name) LIKE LOWER('%$search_name%');"

    while IFS='|' read -r id nombre categoria stock costo precio activo; do
        [[ -z "$id" ]] && continue
        local idx=$_count_ref
        _out_ref["$idx,id"]="$id"
        _out_ref["$idx,nombre"]="$nombre"
        _out_ref["$idx,categoria"]="$categoria"
        _out_ref["$idx,stock"]="$stock"
        _out_ref["$idx,costo"]="$costo"
        _out_ref["$idx,precio"]="$precio"
        _out_ref["$idx,activo"]="$activo"
        ((_count_ref++))
    done < <(sqlite3 -separator '|' "$SQLITE_INVENTORY_PATH" "$query")
}

db_delete_product() {
    local -i id=$1
    local user="${CURRENT_USER:-sistema}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local row
    row=$(sqlite3 -separator '|' "$SQLITE_INVENTORY_PATH" "SELECT i.id, i.name, c.name, i.stock, i.cost, i.price, i.active FROM Inventory i JOIN Categories c ON i.category_id = c.id WHERE i.id=$id;")

    sqlite3 "$SQLITE_INVENTORY_PATH" >/dev/null <<EOF
PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

UPDATE Inventory SET active=0 WHERE id=$id;

INSERT INTO InventoryJournal (timestamp, user, action, product_id, payload, status)
VALUES ('$timestamp', '$user', 'DELETE', $id, '$row', 'DONE');

COMMIT;
EOF
}

db_update_product() {
    local -n produc_ref=$1
    local user="${CURRENT_USER:-sistema}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local payload="${produc_ref[id]}|${produc_ref[nombre]}|${produc_ref[categoria]}|${produc_ref[stock]}|${produc_ref[costo]}|${produc_ref[precio]}|${produc_ref[activo]}"

    sqlite3 "$SQLITE_INVENTORY_PATH" >/dev/null <<EOF
PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

INSERT OR IGNORE INTO Categories (name) VALUES ('${produc_ref[categoria]}');

UPDATE Inventory SET
    name='${produc_ref[nombre]}',
    category_id=(SELECT id FROM Categories WHERE name='${produc_ref[categoria]}'),
    stock=${produc_ref[stock]},
    cost=${produc_ref[costo]},
    price=${produc_ref[precio]},
    active=${produc_ref[activo]}
WHERE id=${produc_ref[id]};

INSERT INTO InventoryJournal (timestamp, user, action, product_id, payload, status)
VALUES ('$timestamp', '$user', 'UPDATE', ${produc_ref[id]}, '$payload', 'DONE');

COMMIT;
EOF
}

db_get_total_journal_count() {
    sqlite3 "$SQLITE_INVENTORY_PATH" "SELECT COUNT(*) FROM InventoryJournal;"
}

db_get_paginated_journal() {
    local -i limit="$1"
    local -i offset="$2"

    local query="SELECT id, timestamp, user, action, product_id, payload, status FROM InventoryJournal ORDER BY id DESC LIMIT $limit OFFSET $offset;"
    sqlite3 -separator '|' "$SQLITE_INVENTORY_PATH" "$query"
}

db_get_all_inventory() {
    local query="SELECT i.id, i.name, c.name AS category, i.stock, i.cost, i.price, i.active FROM Inventory i INNER JOIN Categories c ON i.category_id = c.id;"
    sqlite3 -separator '|' "$SQLITE_INVENTORY_PATH" "$query"
}
#!/usr/bin/env bash

SQLITE_USERS_PATH="shared/data/datos_usuarios.db"

init_users_storage() {
    mkdir -p "$(dirname "$SQLITE_USERS_PATH")"
    sqlite3 "$SQLITE_USERS_PATH" >/dev/null <<EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS Users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL CHECK (length(username) <= 50),
    password TEXT NOT NULL CHECK (length(password) <= 100)
);
EOF
}

db_insert_user() {
    local username="$1"
    local hashed_password="$2"
    init_users_storage
    
    local safe_username="${username//\'/\'\'}"
    sqlite3 "$SQLITE_USERS_PATH" "INSERT INTO Users (username, password) VALUES ('$safe_username', '$hashed_password');" 2>/dev/null
    return $?
}

db_username_exists() {
    local entered_username="$1"
    [[ ! -f "$SQLITE_USERS_PATH" ]] && return 2

    local safe_username="${entered_username//\'/\'\'}"
    local count=0
    read -r count < <(sqlite3 "$SQLITE_USERS_PATH" "SELECT COUNT(*) FROM Users WHERE username='$safe_username';")

    (( count > 0 )) && return 0 || return 1
}

db_find_password_by_username() {
    local entered_username="$1"
    local -n _out_pass_ref=$2
    [[ ! -f "$SQLITE_USERS_PATH" ]] && return 1

    local safe_username="${entered_username//\'/\'\'}"
    _out_pass_ref=""
    read -r _out_pass_ref < <(sqlite3 "$SQLITE_USERS_PATH" "SELECT password FROM Users WHERE username='$safe_username';")

    [[ -n "$_out_pass_ref" ]] && return 0 || return 1
}
#!/usr/bin/env bash


api_get_total_inventory_count() {
    db_get_total_inventory_count
}

api_insert_product() {
    local nombre="$1"
    local categoria="$2"
    local stock="$3"
    local costo="$4"
    local precio="$5"

    is_not_empty "$nombre" && is_alpha "$nombre" || return 1
    [[ ${#nombre} -gt 50 ]] && return 1
    is_not_empty "$categoria" || return 1
    is_numeric "$stock" && (( stock >= 0 )) || return 1
    is_decimal "$costo" || return 1
    is_decimal "$precio" || return 1

    if db_product_exists_by_name "$nombre"; then
        return 2 
    fi

    db_insert_product "$nombre" "$categoria" "$stock" "$costo" "$precio"
}

api_delete_product_by_id() {
    local -i id="$1"
    is_numeric "$id" && (( id > 0 )) || return 1

    if ! db_product_exists_by_id "$id"; then
        return 2 
    fi

    db_delete_product "$id"
}

api_update_product() {
    local -n prod_ref=$1
    local -i id="${prod_ref[id]:-0}"
    local nombre="${prod_ref[nombre]}"
    local categoria="${prod_ref[categoria]}"
    local stock="${prod_ref[stock]}"
    local costo="${prod_ref[costo]}"
    local precio="${prod_ref[precio]}"
    local -i activo="${prod_ref[activo]:-1}"

    is_numeric "$id" && (( id > 0 )) || return 1
    is_not_empty "$nombre" && is_alpha "$nombre" || return 1
    is_not_empty "$categoria" || return 1
    is_numeric "$stock" || return 1
    is_decimal "$costo" || return 1
    is_decimal "$precio" || return 1
    (( activo == 0 || activo == 1 )) || return 1

    db_update_product prod_ref
}

api_search_products() {
    local term="$1"
    local -n out_ref=$2
    local -n count_ref=$3
    db_search_products_by_name "$term" out_ref count_ref
}

api_get_total_journal_count() {
    db_get_total_journal_count
}

api_get_paginated_journal() {
    local -i limit="$1"
    local -i offset="$2"
    db_get_paginated_journal "$limit" "$offset"
}

api_get_all_inventory() {
    db_get_all_inventory
}

api_get_full_journal() {
    local total
    total=$(db_get_total_journal_count)
    if (( total > 0 )); then
        db_get_paginated_journal "$total" 0
    fi
}
#!/usr/bin/env bash


declare CURRENT_USER=""

set_current_user() {
    CURRENT_USER="$1"
}

hash_password() {
    local password_value="$1"
    local -n _out_hash_ref=$2
    read -r _out_hash_ref _ < <(printf '%s' "${password_value}" | sha256sum)
}

api_create_user() {
    local username="$1"
    local password="$2"
    local hashed_password=""

    is_not_empty "$username" && is_alpha "$username" || return 1
    is_not_empty "$password" || return 1

    if db_username_exists "$username"; then
        return 2 
    fi

    hash_password "$password" hashed_password
    db_insert_user "$username" "$hashed_password"
}

api_verify_user_credentials() {
    local username="$1"
    local password="$2"
    local db_password=""
    local input_hash=""

    is_not_empty "$username" || return 1
    is_not_empty "$password" || return 1

    if ! db_find_password_by_username "$username" db_password; then
        return 1
    fi

    hash_password "$password" input_hash

    if [[ "${input_hash}" == "${db_password}" ]]; then
        set_current_user "$username"
        return 0
    fi

    return 1
}

api_check_username_exists() {
    db_username_exists "$1"
}
#!/usr/bin/env bash

HTML_VIEW_PATH="shared/data/vista_inventario.html"
SQLITE_INVENTORY_PATH="shared/data/datos_inventario.db"

generate_html() {
    {
        cat << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reporte de Productos</title>
    <style>
        :root {
            --bg-color: #f4f6f9;
            --card-bg: #ffffff;
            --primary: #6c5ce7;
            --primary-light: #a29bfe;
            --text-color: #2d3436;
            --border-color: #dfe6e9;
            --zebra-bg: #f8f9fa;
            --stock-low-bg: #fde8e8;
            --stock-low-text: #c0392b;
            --stock-mid-bg: #fff5cc;
            --stock-mid-text: #b7791f;
            --stock-high-bg: #e6f4ea;
            --stock-high-text: #27ae60;
            --inactive-bg: #f1f2f6;
            --inactive-text: #a4b0be;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
        }
        .container {
            width: 100%;
            max-width: 800px;
            background: var(--card-bg);
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.05);
        }
        h1 {
            text-align: center;
            color: var(--primary);
            margin-bottom: 20px;
            font-size: 1.8rem;
        }
        .table-responsive {
            overflow-x: auto;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            border-radius: 8px;
            overflow: hidden;
        }
        caption {
            caption-side: top;
            text-align: left;
            font-weight: bold;
            color: #636e72;
            margin-bottom: 10px;
            text-transform: uppercase;
            font-size: 0.85rem;
            letter-spacing: 1px;
        }
        th {
            background-color: var(--primary-light);
            color: #ffffff;
            padding: 12px 15px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid var(--border-color);
        }
        tbody tr:nth-child(even) {
            background-color: var(--zebra-bg);
        }
        tbody tr:hover {
            background-color: #eef2f7;
            transition: background-color 0.2s ease;
        }
        tbody tr.stock-low {
            background-color: var(--stock-low-bg) !important;
            color: var(--stock-low-text);
        }
        tbody tr.stock-low:hover {
            background-color: #fabbbb !important;
        }
        tbody tr.stock-mid {
            background-color: var(--stock-mid-bg) !important;
            color: var(--stock-mid-text);
        }
        tbody tr.stock-mid:hover {
            background-color: #ffe899 !important;
        }
        tbody tr.stock-high {
            background-color: var(--stock-high-bg) !important;
            color: var(--stock-high-text);
        }
        tbody tr.stock-high:hover {
            background-color: #d1ebd6 !important;
        }
        tbody tr.row-inactive {
            background-color: var(--inactive-bg) !important;
            color: var(--inactive-text) !important;
            cursor: not-allowed;
            opacity: 0.8;
        }
        tbody tr.row-inactive:hover {
            background-color: #e4e7eb !important;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Listado de Productos</h1>
        <div class="table-responsive">
            <table border="0">
                <caption>Inventario Actual</caption>
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Nombre</th>
                        <th>Categoria</th>
                        <th>Stock</th>
                        <th>Costo</th>
                        <th>Precio</th>
                        <th>Estado</th>
                    </tr>
                </thead>
                <tbody>
EOF

        # Consultamos directamente SQLite mediante separador '|'
        local query="SELECT i.id, i.name, c.name AS category, i.stock, i.cost, i.price, i.active FROM Inventory i INNER JOIN Categories c ON i.category_id = c.id;"
        
        while IFS='|' read -r id nombre categoria stock costo precio activo; do
            [[ -z "$id" ]] && continue

            local estado_texto="no disponible"
            local row_class=""
            local -i stock_val=${stock:-0}

            if [[ "$activo" == "1" ]]; then
                estado_texto="disponible"
                if (( stock_val < 20 )); then
                    row_class="class=\"stock-low\""
                elif (( stock_val <= 30 )); then
                    row_class="class=\"stock-mid\""
                else
                    row_class="class=\"stock-high\""
                fi
            else
                row_class="class=\"row-inactive\""
            fi

            printf '        <tr %s>\n' "${row_class}"
            printf '            <td>%s</td>\n' "$id"
            printf '            <td>%s</td>\n' "$nombre"
            printf '            <td>%s</td>\n' "$categoria"
            printf '            <td>%s</td>\n' "$stock"
            printf '            <td>%s</td>\n' "$costo"
            printf '            <td>%s</td>\n' "$precio"
            printf '            <td>%s</td>\n' "${estado_texto}"
            printf '        </tr>\n'
        done < <(sqlite3 -separator '|' "$SQLITE_INVENTORY_PATH" "$query")

        cat << 'EOF'
                </tbody>
            </table>
        </div>

        <!-- Web Component de Paginación -->
        <app-pagination page-size="10"></app-pagination>
    </div>

    <script>
        class AppPagination extends HTMLElement {
            constructor() {
                super();
                this.attachShadow({ mode: 'open' });
                this.currentPage = 1;
                this.pageSize = parseInt(this.getAttribute('page-size')) || 10;
                this.pageSizeOptions = [5, 10, 20, 50];
            }

            connectedCallback() {
                setTimeout(() => {
                    this.tableBody = document.querySelector('tbody');
                    if (!this.tableBody) return;
                    this.allRows = Array.from(this.tableBody.querySelectorAll('tr'));
                    this.render();
                    this.updateTable();
                }, 0);
            }

            get totalPages() {
                return Math.ceil(this.allRows.length / this.pageSize) || 1;
            }

            updateTable() {
                const start = (this.currentPage - 1) * this.pageSize;
                const end = start + this.pageSize;

                this.allRows.forEach((row, index) => {
                    if (index >= start && index < end) {
                        row.style.display = '';
                    } else {
                        row.style.display = 'none';
                    }
                });

                this.render();
            }

            changePage(newPage) {
                if (newPage < 1 || newPage > this.totalPages) return;
                this.currentPage = newPage;
                this.updateTable();
            }

            changePageSize(newSize) {
                this.pageSize = parseInt(newSize);
                this.currentPage = 1;
                this.updateTable();
            }

            render() {
                if (this.allRows && this.allRows.length === 0) {
                    this.shadowRoot.innerHTML = '';
                    return;
                }

                this.shadowRoot.innerHTML = `
                    <style>
                        :host {
                            display: block;
                            margin-top: 20px;
                        }
                        .pagination-container {
                            display: flex;
                            flex-direction: column;
                            align-items: center;
                            justify-content: space-between;
                            gap: 12px;
                            background-color: #ffffff;
                            border: 1px solid var(--border-color, #dfe6e9);
                            border-radius: 10px;
                            padding: 12px 16px;
                            font-size: 0.85rem;
                            color: #2d3436;
                            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.03);
                        }
                        @media (min-width: 640px) {
                            .pagination-container {
                                flex-direction: row;
                            }
                        }
                        .controls-group {
                            display: flex;
                            align-items: center;
                            gap: 8px;
                        }
                        .label {
                            font-size: 0.8rem;
                            color: #636e72;
                        }
                        select {
                            background-color: #f8f9fa;
                            color: #2d3436;
                            border: 1px solid #dfe6e9;
                            border-radius: 6px;
                            padding: 4px 8px;
                            font-size: 0.8rem;
                            outline: none;
                            cursor: pointer;
                            transition: border-color 0.2s;
                        }
                        select:focus {
                            border-color: #6c5ce7;
                        }
                        button {
                            padding: 6px 12px;
                            background-color: #ffffff;
                            border: 1px solid #dfe6e9;
                            border-radius: 6px;
                            color: #2d3436;
                            font-size: 0.8rem;
                            font-weight: 600;
                            cursor: pointer;
                            transition: all 0.2s;
                        }
                        button:hover:not(:disabled) {
                            border-color: #6c5ce7;
                            color: #6c5ce7;
                            background-color: #f8f9fa;
                        }
                        button:disabled {
                            opacity: 0.4;
                            cursor: not-allowed;
                        }
                        .page-info {
                            font-size: 0.8rem;
                            color: #636e72;
                        }
                        .page-info strong {
                            color: #2d3436;
                        }
                    </style>

                    <div class="pagination-container">
                        <div class="controls-group">
                            <span class="label">Mostrar:</span>
                            <select id="size-select">
                                ${this.pageSizeOptions.map(opt => `
                                    <option value="${opt}" ${opt === this.pageSize ? 'selected' : ''}>
                                        ${opt} por página
                                    </option>
                                `).join('')}
                            </select>
                        </div>

                        <div class="controls-group">
                            <button id="btn-prev" ${this.currentPage === 1 ? 'disabled' : ''}>
                                Anterior
                            </button>

                            <span class="page-info">
                                Página <strong>${this.currentPage}</strong> de <strong>${this.totalPages}</strong>
                            </span>

                            <button id="btn-next" ${this.currentPage === this.totalPages ? 'disabled' : ''}>
                                Siguiente
                            </button>
                        </div>
                    </div>
                `;

                this.shadowRoot.querySelector('#size-select').addEventListener('change', (e) => {
                    this.changePageSize(e.target.value);
                });

                this.shadowRoot.querySelector('#btn-prev').addEventListener('click', () => {
                    this.changePage(this.currentPage - 1);
                });

                this.shadowRoot.querySelector('#btn-next').addEventListener('click', () => {
                    this.changePage(this.currentPage + 1);
                });
            }
        }

        customElements.define('app-pagination', AppPagination);
    </script>
</body>
</html>
EOF
    } > "${HTML_VIEW_PATH}"

    if [ $? -eq 0 ]; then
        printf "Se ha generado el informe html correctamente en %s.\n" "$HTML_VIEW_PATH"
    else
        printf "No se ha podido generar el informe html.\n"
    fi
}


handle_create_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el nombre del producto a crear: " nombre_temp && return 1

    local categoria_temp="" stock_temp="" costo_temp="" precio_temp=""
    ! enum_field_with_validation "Ingrese Categoria: " products_categories categoria_temp && return 1
    ! numeric_field_with_validation "Ingrese Stock: " stock_temp && return 1
    ! decimal_field_with_validation "Ingrese Costo de Compra: " costo_temp && return 1
    ! decimal_field_with_validation "Ingrese Precio de venta: " precio_temp && return 1

    api_insert_product "$nombre_temp" "$categoria_temp" "$stock_temp" "$costo_temp" "$precio_temp"
    local -i status=$?

    if (( status == 0 )); then
        printf "Producto guardado correctamente en SQLite.\n"
        return 0
    elif (( status == 2 )); then
        printf "[Error]: ¡El producto '%s' ya existe!\n" "$nombre_temp"
        return 1
    else
        printf "[Error]: Validación fallida en la API.\n"
        return 1
    fi
}

handle_delete_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el nombre del producto a eliminar: " nombre_temp && return 1

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        printf "Ese nombre corresponde a más de un producto. Especifique mejor.\n"
        return 1
    elif (( count == 0 )); then
        printf "No se encontró ningún producto con ese nombre.\n"
        return 1
    fi

    clear_screen
    local -i product_id="${found[0,id]}"

    if api_delete_product_by_id "$product_id"; then
        printf "Producto '%s' (ID: %d) dado de baja con éxito.\n" "${found[0,nombre]}" "$product_id"
        return 0
    else
        printf "[Error]: No se pudo procesar la baja.\n"
        return 1
    fi
}

handle_update_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el nombre actual del producto a modificar: " nombre_temp && return 1

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        printf "Ese nombre corresponde a más de un producto. Especifique mejor.\n"
        return 1
    elif (( count == 0 )); then
        printf "No se encontró ningún producto con ese nombre.\n"
        return 1
    fi

    local -A p_temp=()
    p_temp[id]="${found[0,id]}"
    p_temp[nombre]="${found[0,nombre]}"
    p_temp[categoria]="${found[0,categoria]}"
    p_temp[stock]="${found[0,stock]}"
    p_temp[costo]="${found[0,costo]}"
    p_temp[precio]="${found[0,precio]}"
    p_temp[activo]="${found[0,activo]}"

    local categoria_temp="" stock_temp="" costo_temp="" precio_temp=""
    ! alpha_field_with_validation "Nuevo Nombre [Actual: ${p_temp[nombre]}]: " nombre_temp "not_required"
    p_temp[nombre]="${nombre_temp:-${p_temp[nombre]}}"

    ! enum_field_with_validation "Categoria [Actual: ${p_temp[categoria]}]: " products_categories categoria_temp "not_required"
    p_temp[categoria]="${categoria_temp:-${p_temp[categoria]}}"

    ! numeric_field_with_validation "Stock [Actual: ${p_temp[stock]}]: " stock_temp "not_required"
    p_temp[stock]="${stock_temp:-${p_temp[stock]}}"

    ! decimal_field_with_validation "Costo [Actual: ${p_temp[costo]}]: " costo_temp "not_required"
    p_temp[costo]="${costo_temp:-${p_temp[costo]}}"

    ! decimal_field_with_validation "Precio [Actual: ${p_temp[precio]}]: " precio_temp "not_required"
    p_temp[precio]="${precio_temp:-${p_temp[precio]}}"

    if (( "${p_temp[activo]}" == 0 )); then
        local -i reactivate=0
        local reactivate_options=( 0 1 )
        ! enum_field_with_validation "¿Desea reactivar? 0: No | 1: Sí" reactivate_options reactivate
        (( "${reactivate}" == 1 )) && p_temp[activo]=1
    fi

    clear_screen
    if api_update_product p_temp; then
        printf "Producto %d modificado con éxito.\n" "${p_temp[id]}"
        return 0
    else
        printf "[Error]: No se pudo actualizar el producto.\n"
        return 1
    fi
}

handle_show_product_paginated() {
    local -i page_size=5
    local -i current_page=1
    local total_items
    total_items=$(api_get_total_inventory_count)

    (( total_items == 0 )) && { printf "No se encontraron productos.\n"; return; }

    local -i total_pages=$(( (total_items + page_size - 1) / page_size ))
    local option=""

    while true; do
        clear
        local -i offset=$(( (current_page - 1) * page_size ))

        printf "=== LISTADO DE PRODUCTOS (Página %d de %d) ===\n\n" "$current_page" "$total_pages"
        printf "%-5s %-15s %-15s %-8s %-10s %-10s %-8s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
        printf "%s\n" "------------------------------------------------------------------------"

        local query="SELECT i.id, i.name, c.name AS category, i.stock, i.cost, i.price, i.active FROM Inventory i INNER JOIN Categories c ON i.category_id = c.id LIMIT $page_size OFFSET $offset;"
        
        while IFS='|' read -r id nombre categoria stock costo precio activo; do
            [[ -z "$id" ]] && continue
            local available_text="Disponible"
            (( activo == 0 )) && available_text="No Disponible"
            printf "%-5s %-15s %-15s %-8s %-9s %-9s %-8s\n" "$id" "$nombre" "$categoria" "$stock" "$costo" "$precio" "$available_text"
        done < <(sqlite3 -separator '|' "shared/data/datos_inventario.db" "$query")

        printf "%s\n" "------------------------------------------------------------------------"
        printf " [A] Anterior |  [S] Siguiente  |  [Q] Volver al menú: "
        read -rsn 1 option
        echo ""

        case "${option,,}" in
            s) (( current_page < total_pages )) && (( current_page++ )) ;;
            a) (( current_page > 1 )) && (( current_page-- )) ;;
            q) break ;;
        esac
    done
    clear_screen
}

handle_show_one_product() {
    local nombre_temp=""
    ! alpha_field_with_validation "Ingrese el Nombre del producto a buscar: " nombre_temp && return 1

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count
    clear_screen

    if (( count > 0 )); then
        printf "%-5s %-15s %-15s %-8s %-10s %-10s %-8s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
        printf "%s\n" "------------------------------------------------------------------------"
        for ((i=0; i<count; i++)); do
            local avail="Disponible"
            (( found[$i,activo] == 0 )) && avail="No Disponible"
            printf "%-5s %-15s %-15s %-8s %-9s %-9s %-8s\n" \
                "${found[$i,id]}" "${found[$i,nombre]}" "${found[$i,categoria]}" \
                "${found[$i,stock]}" "${found[$i,costo]}" "${found[$i,precio]}" "$avail"
        done
    else
        printf "No se encontraron productos con ese nombre.\n"
    fi
}

handle_generate_html(){
    generate_html
}

handle_http_server() {
    local -n server_pid_ref=$1
    local SERVER_PORT=8080
    local HTML_FILE_PATH="./shared/data/vista_inventario.html"

    generate_html >/dev/null 2>&1

    if (( server_pid_ref > 0 )) && kill -0 "$server_pid_ref" 2>/dev/null; then
        stop_local_http_server SERVER_PID "$SERVER_PORT"
    else
        ensure_package_installed "nc" "netcat-openbsd" "nc" "openbsd-netcat" "netcat-openbsd"&&start_local_http_server SERVER_PID "$SERVER_PORT" "$HTML_FILE_PATH"     
    fi

    printf "\nPresione cualquier tecla para regresar al menú..."
    read -rsn 1
    echo ""
}

handle_show_journal_paginated() {
    local -i page_size=5
    local -i current_page=1
    local total_items
    total_items=$(api_get_total_journal_count)

    (( total_items == 0 )) && { printf "No se encontraron registros en el journal.\n"; return; }

    local -i total_pages=$(( (total_items + page_size - 1) / page_size ))
    local option=""

    while true; do
        clear
        local -i offset=$(( (current_page - 1) * page_size ))

        printf "=== AUDITORÍA DE INVENTARIO - JOURNAL (Página %d de %d) ===\n\n" "$current_page" "$total_pages"
        printf "%-5s %-19s %-12s %-8s %-10s %-30s %-8s\n" "ID" "FECHA/HORA" "USUARIO" "ACCION" "PROD_ID" "PAYLOAD" "ESTADO"
        printf "%s\n" "----------------------------------------------------------------------------------------------------------"

        local journal_data
        journal_data=$(api_get_paginated_journal "$page_size" "$offset")

        while IFS='|' read -r id timestamp user action product_id payload status; do
            [[ -z "$id" ]] && continue
            printf "%-5s %-19s %-12s %-8s %-10s %-30s %-8s\n" \
                "$id" "$timestamp" "$user" "$action" "${product_id:-N/A}" "$payload" "$status"
        done <<< "$journal_data"

        printf "%s\n" "----------------------------------------------------------------------------------------------------------"
        printf " [A] Anterior |  [S] Siguiente  |  [Q] Volver al menú: "
        read -rsn 1 option
        echo ""

        case "${option,,}" in
            s) (( current_page < total_pages )) && (( current_page++ )) ;;
            a) (( current_page > 1 )) && (( current_page-- )) ;;
            q) break ;;
        esac
    done
    clear_screen
}
#!/usr/bin/env bash


handle_create_user() {
    local username=""
    local password=""

    while true; do
        ! alpha_field_with_validation $'Ingresa tu nombre de usuario deseado:\n' username "required" && return 1
        if api_check_username_exists "${username}"; then
            printf "¡El usuario ya existe! Por favor, ingresa otro.\n\n"
        else
            break
        fi
    done

    while true; do
        read -rsp $'Ingresa una contraseña para tu usuario:\n' password
        echo ""
        [[ -n "${password}" ]] && break
        printf $'No puedes ingresar una contraseña vacía.\n'
    done

    if api_create_user "${username}" "${password}"; then
        printf "¡El usuario se ha creado exitosamente!\n"
        return 0
    else
        printf "¡Ha ocurrido un error al guardar el usuario en la base de datos!\n"
        return 1
    fi
}

handle_auth_user() {
    local -i tries=0
    local username=""
    local password=""

    while (( tries < 5 )); do
        ! alpha_field_with_validation $'Ingresa tu usuario:\n' username && return 1
        if ! api_check_username_exists "${username}"; then
            (( tries++ ))
            printf 'No se ha encontrado registro para ese usuario. Intentos restantes: %d\n' "$(( 5 - tries ))"
        else
            break
        fi
    done        

    (( tries >= 5 )) && { printf "¡Intentos fallidos máximos alcanzados!\n"; exit 1; }

    tries=0
    while (( tries < 3 )); do
        read -rsp $'Ingresa tu contraseña:\n' password
        echo ""

        [[ -z "${password}" ]] && { printf $'No puedes ingresar una contraseña vacía.\n'; continue; }

        if api_verify_user_credentials "${username}" "${password}"; then
            printf "Login exitoso. ¡Bienvenido, %s!\n" "$username"
            return 0
        fi

        (( tries++ ))
        printf "Contraseña incorrecta. (Intentos restantes: %d)\n" "$(( 3 - tries ))"
    done

    printf "¡Intentos fallidos máximos alcanzados!\n"
    exit 1
}
#!/usr/bin/env bash


welcome_message() {
    local c_blue="\033[1;34m"
    local c_bold="\033[1m"
    local c_dim="\033[2m"
    local c_reset="\033[0m"

    printf "${c_blue}+-----------------------------------------------------------+${c_reset}\n"
    printf "${c_blue}|${c_reset}                                                           ${c_blue}|${c_reset}\n"
    printf "${c_blue}|${c_reset}          ${c_bold}¡Bienvenido al sistema de inventario!${c_reset}            ${c_blue}|${c_reset}\n"
    printf "${c_blue}|${c_reset}              ${c_dim}Presiona CTRL+C para salir${c_reset}                   ${c_blue}|${c_reset}\n"
    printf "${c_blue}|${c_reset}                                                           ${c_blue}|${c_reset}\n"
    printf "${c_blue}+-----------------------------------------------------------+${c_reset}\n"
    printf "\n"
}

show_inventory_menu(){
    local c_bold="\033[1m"
    local c_reset="\033[0m"

    printf "\n"
    printf "=============================================================\n"
    printf "                    ${c_bold}MENÚ DE INVENTARIO${c_reset}\n"
    printf "=============================================================\n"
    printf " 1. Alta producto\n"
    printf " 2. Baja producto\n"
    printf " 3. Modificación producto\n"
    printf " 4. Mostrar inventario (Paginado)\n"
    printf " 5. Buscar producto por nombre\n"
    printf " 6. Generar archivo HTML\n"
    printf " 7. Iniciar o Detener el server del inventario\n"
    printf " 8. Mostrar Historial de acciones. (Paginado)\n"
    printf " 9. Salir\n"
    printf "=============================================================\n"
    printf "\n"
}

get_option_from_user_and_execute_inventory_action(){
    local -r -i OPTION_CREATE=1
    local -r -i OPTION_DELETE=2
    local -r -i OPTION_UPDATE=3
    local -r -i OPTION_SHOW_ALL=4
    local -r -i OPTION_SEARCH_ONE_BY_NAME=5
    local -r -i OPTION_GENERATE_HTML=6
    local -r -i OPTION_START_STOP_HTTP_SERVER=7
    local -r -i OPTION_SHOW_JOURNAL=8
    local -r -i OPTION_EXIT=9

    local action_option=0
    local products_categories=("frutas" "verduras" "enlatados" "almacen" "otros")
    local -n SERVER_PID=$1

    while [[ "$action_option" != "$OPTION_EXIT" ]]; do
        show_inventory_menu
        read -rsn 1 -p "Opcion: " action_option
        echo ""
        stty sane

        case $action_option in
            $OPTION_CREATE) 
                clear_screen; 
                handle_create_product ;;
            $OPTION_DELETE) 
                clear_screen; 
                handle_delete_product ;;
            $OPTION_UPDATE) 
                clear_screen; 
                handle_update_product ;;
            $OPTION_SHOW_ALL) 
                clear_screen; 
                handle_show_product_paginated ;;
            $OPTION_SEARCH_ONE_BY_NAME) 
                clear_screen; 
                handle_show_one_product ;;
            $OPTION_GENERATE_HTML) 
                clear_screen; 
                handle_generate_html ;;
            $OPTION_START_STOP_HTTP_SERVER) 
                clear_screen; 
                handle_http_server SERVER_PID ;;
            $OPTION_SHOW_JOURNAL) 
                clear_screen; 
                handle_show_journal_paginated ;;
            $OPTION_EXIT)
                printf "\nSaliendo del programa...\n"
                (( SERVER_PID > 0 )) && stop_local_http_server SERVER_PID 8081 >/dev/null 2>&1
                exit 0
                ;;
            *) printf "\nOpcion invalida.\n" ;;
        esac
    done
    return 0
}

#!/usr/bin/env bash


show_auth_menu(){
    printf "\n\n"
    local c_bold="\033[1m"
    local c_reset="\033[0m"

    printf "=============================================================\n"
    printf "                  ${c_bold}SISTEMA DE AUTENTICACIÓN${c_reset}\n"
    printf "=============================================================\n"
    printf "1. Registrar un nuevo usuario\n"
    printf "2. Acceder a tu usuario\n"
    printf "3. Salir\n\n"
}

get_option_from_user_and_execute_login_or_register(){
    local -r -i OPTION_REGISTER=1
    local -r -i OPTION_LOGIN=2
    local -r -i OPTION_EXIT=3

    local option=0

    while [[ "$option" != "$OPTION_EXIT" ]]; do
        show_auth_menu

        read -rp "Opcion: " option

        case $option in
            $OPTION_REGISTER)
                clear_screen
                handle_create_user
                ;;
            $OPTION_LOGIN)
                clear_screen
                if handle_auth_user; then
                    return 0
                fi
                ;;
            $OPTION_EXIT)
                printf "Saliendo del programa...\n"
                exit 0
                ;;
            *)
                printf "\nOpcion invalida.\n"
                ;;
        esac
    done
}
#!/usr/bin/env bash

[[ -n "${_FRONTEND_INVENTORY_TUI_HANDLERS_LOADED:-}" ]] && return 0
declare -g _FRONTEND_INVENTORY_TUI_HANDLERS_LOADED=1


tui_select_category() {
    local -n _cat_out=$1
    local choice=""
    if ! choice="$(whiptail --title "Seleccionar Categoría" --menu "Elija una categoría válida:" 15 50 5 \
        "frutas" "Frutas" \
        "verduras" "Verduras" \
        "enlatados" "Enlatados" \
        "almacén" "Almacén" \
        "otros" "Otros" 3>&1 1>&2 2>&3)"; then
        return 1
    fi
    _cat_out="$choice"
    return 0
}

tui_api_insert_product_wrapper() {
    local nombre="$1" categoria="$2" stock="$3" costo="$4" precio="$5"
    api_insert_product "$nombre" "$categoria" "$stock" "$costo" "$precio"
    local status=$?
    case $status in
        0) 
            printf "¡Éxito!\n\nEl producto '%s' fue registrado correctamente en la base de datos con stock %s y precio $%s.\n" "$nombre" "$stock" "$precio" 
            ;;
        1) printf "[Error de Validación]: Verifique los datos ingresados.\n- Nombre alfabético (máx 50 car).\n- Stock entero >= 0.\n- Costo y Precio numéricos válidos.\n" ;;
        2) printf "[Error de Conflicto]: El producto '%s' ya existe.\n" "$nombre" ;;
        *) printf "[Error Inesperado]: Código de error %d.\n" "$status" ;;
    esac
}

tui_handle_create_product() {
    local nombre categoria stock costo precio
    tui_input "Alta de Producto" "Ingrese Nombre del producto:" nombre || return 0
    [[ -z "$nombre" ]] && return 0

    tui_select_category categoria || return 0

    tui_input "Alta de Producto" "Ingrese Stock inicial:" stock || return 0
    tui_input "Alta de Producto" "Ingrese Costo de Compra ($):" costo || return 0
    tui_input "Alta de Producto" "Ingrese Precio de Venta ($):" precio || return 0

    tui_run_show "Alta de Producto" tui_api_insert_product_wrapper "$nombre" "$categoria" "$stock" "$costo" "$precio"
}

tui_handle_delete_product() {
    local nombre_temp
    tui_input "Baja de Producto" "Ingrese el nombre del producto a eliminar:" nombre_temp || return 0
    [[ -z "$nombre_temp" ]] && return 0

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        tui_msg "Baja de Producto" "Ese nombre corresponde a más de un producto ($count encontrados). Especifique el nombre completo."
        return 0
    elif (( count == 0 )); then
        tui_msg "Baja de Producto" "No se encontró ningún producto con el nombre '$nombre_temp'."
        return 0
    fi

    local -i product_id="${found[0,id]}"
    local prod_name="${found[0,nombre]}"

    if tui_confirm "Confirmar Baja" "¿Está seguro de dar de baja el producto '$prod_name' (ID: $product_id)?"; then
        if api_delete_product_by_id "$product_id"; then
            tui_msg "Éxito en Baja" "¡El producto '$prod_name' (ID: $product_id) fue dado de baja exitosamente!"
        else
            tui_msg "Error" "No se pudo procesar la baja del producto."
        fi
    fi
}

tui_handle_update_product() {
    local nombre_temp
    tui_input "Modificar Producto" "Ingrese el nombre del producto a modificar:" nombre_temp || return 0
    [[ -z "$nombre_temp" ]] && return 0

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 1 )); then
        tui_msg "Modificación" "Ese nombre corresponde a más de un producto ($count encontrados). Especifique mejor."
        return 0
    elif (( count == 0 )); then
        tui_msg "Modificación" "No se encontró ningún producto con el nombre '$nombre_temp'."
        return 0
    fi

    local -A p_temp=()
    p_temp[id]="${found[0,id]}"
    p_temp[nombre]="${found[0,nombre]}"
    p_temp[categoria]="${found[0,categoria]}"
    p_temp[stock]="${found[0,stock]}"
    p_temp[costo]="${found[0,costo]}"
    p_temp[precio]="${found[0,precio]}"
    p_temp[activo]="${found[0,activo]}"

    local nuevo_nombre nueva_cat nuevo_stock nuevo_costo nuevo_precio
    tui_input "Editar Producto (ID ${p_temp[id]})" "Nombre actual [${p_temp[nombre]}]:" nuevo_nombre || return 0
    p_temp[nombre]="${nuevo_nombre:-${p_temp[nombre]}}"

    if tui_confirm "Cambiar Categoría" "La categoría actual es '${p_temp[categoria]}'. ¿Desea modificarla?"; then
        tui_select_category nueva_cat || return 0
        p_temp[categoria]="${nueva_cat:-${p_temp[categoria]}}"
    fi

    tui_input "Editar Producto (ID ${p_temp[id]})" "Stock actual [${p_temp[stock]}]:" nuevo_stock || return 0
    p_temp[stock]="${nuevo_stock:-${p_temp[stock]}}"

    tui_input "Editar Producto (ID ${p_temp[id]})" "Costo actual [${p_temp[costo]}]:" nuevo_costo || return 0
    p_temp[costo]="${nuevo_costo:-${p_temp[costo]}}"

    tui_input "Editar Producto (ID ${p_temp[id]})" "Precio actual [${p_temp[precio]}]:" nuevo_precio || return 0
    p_temp[precio]="${nuevo_precio:-${p_temp[precio]}}"

    if (( p_temp[activo] == 0 )); then
        if tui_confirm "Reactivar Producto" "El producto está INACTIVO.\n¿Desea reactivarlo a estado Disponible?"; then
            p_temp[activo]=1
        fi
    fi

    if api_update_product p_temp; then
        tui_msg "Éxito en Modificación" "¡El producto ID ${p_temp[id]} ('${p_temp[nombre]}') fue actualizado correctamente!"
    else
        tui_msg "Error" "No se pudo actualizar el producto en la base de datos."
    fi
}

tui_render_journal() {
    local total_items
    total_items=$(api_get_total_journal_count)
    (( total_items == 0 )) && { printf "No hay registros en el historial.\n"; return; }
    
    local journal_data
    journal_data=$(api_get_full_journal)

    printf "=== AUDITORÍA DE INVENTARIO - JOURNAL ===\n\n"
    printf "%-5s  %-19s  %-12s  %-8s  %-8s  %-40s  %-8s\n" "ID" "FECHA/HORA" "USUARIO" "ACCION" "PROD_ID" "PAYLOAD" "ESTADO"
    printf '%s\n' "-------------------------------------------------------------------------------------------------------------------"
    while IFS='|' read -r id timestamp user action product_id payload status; do
        [[ -z "$id" ]] && continue
        printf "%-5s  %-19s  %-12s  %-8s  %-8s  %-40s  %-8s\n" \
            "$id" "$timestamp" "$user" "$action" "${product_id:-N/A}" "$payload" "$status"
    done <<< "$journal_data"
}

tui_handle_show_journal() {
    tui_text_show "Historial de Auditoría" tui_render_journal
}

tui_render_inventory_list() {
    printf "=== INVENTARIO COMPLETO ===\n\n"
    printf "%-5s %-15s %-12s %-7s %-9s %-9s %-10s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
    printf '%s\n' "--------------------------------------------------------------------------------"
    
    local inventory_data
    inventory_data=$(api_get_all_inventory)

    while IFS='|' read -r id nombre categoria stock costo precio activo; do
        [[ -z "$id" ]] && continue
        
        local available_text="Disponible"
        (( activo == 0 )) && available_text="No Disp."

        printf "%-5s %-15s %-12s %-7s %-9s %-9s %-10s\n" \
            "$id" "$nombre" "$categoria" "$stock" "$costo" "$precio" "$available_text"
    done <<< "$inventory_data"
}

tui_handle_show_paginated() {
    tui_text_show "Inventario Completo" tui_render_inventory_list
}

tui_render_search_results() {
    printf "=== RESULTADOS DE BÚSQUEDA ===\n\n"
    printf "%-5s %-15s %-15s %-8s %-10s %-10s %-8s\n" "ID" "NOMBRE" "CATEGORIA" "STOCK" "COSTO" "PRECIO" "ESTADO"
    printf '%s\n' "------------------------------------------------------------------------"
    for ((i=0; i<count; i++)); do
        local avail="Disponible"
        (( found[$i,activo] == 0 )) && avail="No Disp."
        printf "%-5s %-15s %-15s %-8s %-9s %-9s %-8s\n" \
            "${found[$i,id]}" "${found[$i,nombre]}" "${found[$i,categoria]}" \
            "${found[$i,stock]}" "${found[$i,costo]}" "${found[$i,precio]}" "$avail"
    done
}

tui_handle_search_product() {
    local nombre_temp
    tui_input "Buscar Producto" "Ingrese el nombre a buscar:" nombre_temp || return 0
    [[ -z "$nombre_temp" ]] && return 0

    local -A found=()
    local -i count=0
    api_search_products "$nombre_temp" found count

    if (( count > 0 )); then
        local render_search_results=()
        
        tui_text_show "Resultados de Búsqueda" tui_render_search_results
    else
        tui_msg "Buscar Producto" "No se encontraron productos con el nombre '$nombre_temp'."
    fi
}

tui_handle_generate_html() {
    tui_run_show "Reporte HTML" generate_html
}

tui_handle_http_server() {
    local -n server_pid_ref=$1
    local SERVER_PORT=8080
    local HTML_FILE_PATH="./shared/data/vista_inventario.html"

    generate_html >/dev/null 2>&1

    if (( server_pid_ref > 0 )) && kill -0 "$server_pid_ref" 2>/dev/null; then
        stop_local_http_server server_pid_ref "$SERVER_PORT"
        tui_msg "Servidor HTTP" "El servidor HTTP ha sido detenido."
    else
        start_local_http_server server_pid_ref "$SERVER_PORT" "$HTML_FILE_PATH"     
        tui_msg "Servidor HTTP" "Servidor iniciado con éxito en http://localhost:$SERVER_PORT"
    fi
}
#!/usr/bin/env bash

[[ -n "${_FRONTEND_USER_TUI_HANDLERS_LOADED:-}" ]] && return 0
declare -g _FRONTEND_USER_TUI_HANDLERS_LOADED=1


tui_handle_create_user() {
    local username=""
    local password=""

    while true; do
        if ! tui_input "Registro de Usuario" "Ingrese su nombre de usuario deseado:" username; then
            return 1
        fi
        
        if [[ -z "$username" ]]; then
            tui_msg "Aviso" "El nombre de usuario no puede estar vacío."
            continue
        fi

        if api_check_username_exists "${username}"; then
            tui_msg "Aviso" "¡El usuario ya existe! Por favor, ingrese otro."
        else
            break
        fi
    done

    while true; do
        if ! tui_pass "Seguridad" "Ingrese una contraseña para '$username':" password; then
            return 1
        fi
        
        if [[ -z "${password}" ]]; then
            tui_msg "Aviso" "No puede ingresar una contraseña vacía."
            continue
        fi
        break
    done

    if api_create_user "${username}" "${password}"; then
        tui_msg "Éxito" "¡El usuario se ha creado exitosamente!"
        return 0
    else
        tui_msg "Error" "¡Ha ocurrido un error al guardar el usuario en la base de datos!"
        return 1
    fi
}

tui_handle_auth_user() {
    local -i tries=0
    local username=""
    local password=""

    while (( tries < 5 )); do
        if ! tui_input "Iniciar Sesión" "Ingrese su usuario (Intento $((tries + 1))/5):" username; then
            return 1
        fi

        if [[ -z "$username" ]]; then
            continue
        fi

        if ! api_check_username_exists "${username}"; then
            (( tries++ ))
            tui_msg "Error" "No se ha encontrado registro para ese usuario. Intentos restantes: $(( 5 - tries ))"
        else
            break
        fi
    done        

    (( tries >= 5 )) && { tui_msg "Bloqueado" "¡Intentos fallidos máximos alcanzados!"; return 1; }

    tries=0
    while (( tries < 3 )); do
        if ! tui_pass "Iniciar Sesión" "Ingrese contraseña para '$username' (Intento $((tries + 1))/3):" password; then
            return 1
        fi

        [[ -z "${password}" ]] && { tui_msg "Aviso" "No puedes ingresar una contraseña vacía."; continue; }

        if api_verify_user_credentials "${username}" "${password}"; then
            tui_msg "Bienvenido" "Login exitoso. ¡Bienvenido, $username!"
            return 0
        fi

        (( tries++ ))
        tui_msg "Error" "Contraseña incorrecta. (Intentos restantes: $(( 3 - tries )))"
    done

    tui_msg "Bloqueado" "¡Intentos fallidos máximos alcanzados!"
    return 1
}
#!/usr/bin/env bash

[[ -n "${_FRONTEND_INVENTORY_TUI_MENU_LOADED:-}" ]] && return 0
declare -g _FRONTEND_INVENTORY_TUI_MENU_LOADED=1


tui_inventory_menu() {
    local choice=""
    local -n SERVER_PID=$1

    while true; do
        if ! choice="$(whiptail --title "Menú Principal de Inventario" --menu "Seleccione una opción:" 18 65 9 \
            "1" "Alta de producto" \
            "2" "Baja de producto" \
            "3" "Modificación de producto" \
            "4" "Mostrar inventario completo" \
            "5" "Buscar producto por nombre" \
            "6" "Generar archivo HTML" \
            "7" "Iniciar o Detener servidor HTTP" \
            "8" "Mostrar Historial de Auditoría (Journal)" \
            "9" "Cerrar sesión / Salir" 3>&1 1>&2 2>&3)"; then
            
            if tui_confirm "Salir" "¿Desea cerrar la aplicación?"; then
                (( SERVER_PID > 0 )) && stop_local_http_server SERVER_PID 8081 >/dev/null 2>&1
                return 0
            fi
            continue
        fi

        case "$choice" in
            1) tui_handle_create_product ;;
            2) tui_handle_delete_product ;;
            3) tui_handle_update_product ;;
            4) tui_handle_show_paginated ;;
            5) tui_handle_search_product ;;
            6) tui_handle_generate_html ;;
            7) tui_handle_http_server SERVER_PID ;;
            8) tui_handle_show_journal ;;
            9)
                if tui_confirm "Salir" "¿Desea salir del sistema?"; then
                    (( SERVER_PID > 0 )) && stop_local_http_server SERVER_PID 8081 >/dev/null 2>&1
                    return 0
                fi
                ;;
        esac
    done
}
#!/usr/bin/env bash

[[ -n "${_FRONTEND_USER_TUI_MENU_LOADED:-}" ]] && return 0
declare -g _FRONTEND_USER_TUI_MENU_LOADED=1


tui_auth_menu() {
    local choice=""
    while true; do
        if ! choice="$(whiptail --title "Sistema de Autenticación" --menu "Seleccione una opción de acceso:" 15 50 3 \
            "1" "Registrar un nuevo usuario" \
            "2" "Acceder a su cuenta (Login)" \
            "3" "Salir de la aplicación" 3>&1 1>&2 2>&3)"; then
            
            if tui_confirm "Salir" "¿Desea salir del programa?"; then
                exit 0
            fi
            continue
        fi

        case "$choice" in
            1)
                tui_handle_create_user || true
                ;;
            2) 
                if tui_handle_auth_user; then
                    return 0 
                fi
                ;;
            3)
                exit 0
                ;;
        esac
    done
}
#!/usr/bin/env bash

export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=es_AR.UTF-8 2>/dev/null
export LANG=C.UTF-8 2>/dev/null

declare SERVER_PID_VALUE=0
declare MODE="tui"

if [[ "${1,,}" == "cli" || "${1,,}" == "--cli" ]]; then
    MODE="cli"
fi

CONFIG_IMPORTS_PATH="./config.sh"
[[ -f "${CONFIG_IMPORTS_PATH}" ]] && source "${CONFIG_IMPORTS_PATH}"

cleanup() {
    stop_local_http_server SERVER_PID_VALUE >/dev/null 2>&1
    stty sane 2>/dev/null
    exit 0
}

main() {
    trap cleanup SIGINT SIGHUP SIGTERM
    trap 'stty sane 2>/dev/null' EXIT INT TERM

    init_users_storage
    init_db

    if [[ "$MODE" == "cli" ]]; then
       
        welcome_message

        if ! get_option_from_user_and_execute_login_or_register; then
            return 1
        fi

        get_option_from_user_and_execute_inventory_action SERVER_PID_VALUE
    else
     
        ensure_package_installed "whiptail" "whiptail" "whiptail" "whiptail" "whiptail" || {
            echo "[Error]: Se requiere 'whiptail' para la interfaz TUI." >&2
            echo "Ejecute con './ejercicio-4.sh cli' para el modo consola." >&2
            exit 1
        }

        if ! tui_auth_menu; then
            return 1
        fi

        tui_inventory_menu SERVER_PID_VALUE
    fi

    return 0
}

main "$@"
