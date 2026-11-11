
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