#!/usr/bin/env bash
#
# Modelo de datos del ERP de licores artesanales.
# Incluye DDL, triggers de auditoría/stock y datos demo reproducibles.

[[ -n "${_ERP_SCHEMA_LOADED:-}" ]] && return 0
declare -g _ERP_SCHEMA_LOADED=1

_schema_migrate_legacy_columns() {
    local table_exists has_column
    table_exists=$(db_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'Inputs';" 2>/dev/null || printf '0')
    if [[ "${table_exists:-0}" != "0" ]]; then
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Inputs') WHERE name = 'active';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Inputs ADD COLUMN active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1));" || return 1
        fi
    fi

    table_exists=$(db_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'Products';" 2>/dev/null || printf '0')
    if [[ "${table_exists:-0}" != "0" ]]; then
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Products') WHERE name = 'recipe_description';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Products ADD COLUMN recipe_description TEXT NOT NULL DEFAULT '';" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Products') WHERE name = 'is_combo';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Products ADD COLUMN is_combo INTEGER NOT NULL DEFAULT 0 CHECK (is_combo IN (0, 1));" || return 1
        fi
    fi

    table_exists=$(db_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'Sales';" 2>/dev/null || printf '0')
    if [[ "${table_exists:-0}" != "0" ]]; then
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'subtotal_amount';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN subtotal_amount REAL NOT NULL DEFAULT 0;" || return 1
            db_exec "UPDATE Sales SET subtotal_amount = total_amount WHERE total_amount > 0;" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'discount_type';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN discount_type TEXT NOT NULL DEFAULT 'none';" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'discount_value';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN discount_value REAL NOT NULL DEFAULT 0;" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'discount_amount';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN discount_amount REAL NOT NULL DEFAULT 0;" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'status';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN status TEXT NOT NULL DEFAULT 'finished' CHECK (status IN ('pending', 'finished', 'cancel'));" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'notes';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN notes TEXT;" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'created_by';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN created_by TEXT NOT NULL DEFAULT 'sistema';" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'stock_applied';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN stock_applied INTEGER NOT NULL DEFAULT 0 CHECK (stock_applied IN (0, 1));" || return 1
        fi
        has_column=$(db_scalar "SELECT COUNT(*) FROM pragma_table_info('Sales') WHERE name = 'order_type';" 2>/dev/null || printf '0')
        if [[ "${has_column:-0}" == "0" ]]; then
            db_exec "ALTER TABLE Sales ADD COLUMN order_type TEXT NOT NULL DEFAULT 'direct' CHECK (order_type IN ('direct', 'order'));" || return 1
        fi
        db_exec "UPDATE Sales SET stock_applied = 1 WHERE status = 'finished';" || return 1
    fi
    return 0
}

db_apply_schema() {
    local sql
    _schema_migrate_legacy_columns || return 1
    sql=$(cat <<'SQL'
CREATE TABLE IF NOT EXISTS Categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL CHECK (length(name) <= 50)
);

CREATE TABLE IF NOT EXISTS Suppliers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK (length(name) <= 80),
    contact_person TEXT,
    phone TEXT,
    email TEXT,
    address TEXT
);

CREATE TABLE IF NOT EXISTS Customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK (length(name) <= 80),
    type TEXT NOT NULL DEFAULT 'Minorista' CHECK (type IN ('Mayorista', 'Minorista')),
    phone TEXT,
    email TEXT
);

CREATE TABLE IF NOT EXISTS Inputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK (length(name) <= 80),
    category_id INTEGER REFERENCES Categories(id),
    stock REAL NOT NULL DEFAULT 0 CHECK (stock >= 0),
    unit TEXT NOT NULL DEFAULT 'unidades',
    cost REAL NOT NULL DEFAULT 0 CHECK (cost >= 0),
    supplier_id INTEGER REFERENCES Suppliers(id),
    min_stock_threshold REAL NOT NULL DEFAULT 0 CHECK (min_stock_threshold >= 0),
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1))
);

CREATE TABLE IF NOT EXISTS Products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE CHECK (length(name) <= 80),
    category_id INTEGER NOT NULL REFERENCES Categories(id),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    min_production_threshold INTEGER NOT NULL DEFAULT 0 CHECK (min_production_threshold >= 0),
    cost REAL NOT NULL DEFAULT 0 CHECK (cost >= 0),
    price REAL NOT NULL DEFAULT 0 CHECK (price >= 0),
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    is_seasonal INTEGER NOT NULL DEFAULT 0 CHECK (is_seasonal IN (0, 1)),
    recipe_description TEXT NOT NULL DEFAULT '' CHECK (length(recipe_description) <= 2000),
    is_combo INTEGER NOT NULL DEFAULT 0 CHECK (is_combo IN (0, 1))
);

CREATE TABLE IF NOT EXISTS Sales (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    customer_id INTEGER REFERENCES Customers(id),
    subtotal_amount REAL NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    discount_type TEXT NOT NULL DEFAULT 'none',
    discount_value REAL NOT NULL DEFAULT 0 CHECK (discount_value >= 0),
    discount_amount REAL NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    total_amount REAL NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    payment_method TEXT NOT NULL DEFAULT 'Efectivo',
    status TEXT NOT NULL DEFAULT 'finished' CHECK (status IN ('pending', 'finished', 'cancel')),
    notes TEXT,
    created_by TEXT NOT NULL DEFAULT 'sistema',
    stock_applied INTEGER NOT NULL DEFAULT 0 CHECK (stock_applied IN (0, 1)),
    order_type TEXT NOT NULL DEFAULT 'direct' CHECK (order_type IN ('direct', 'order'))
);

CREATE TABLE IF NOT EXISTS SaleItems (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sale_id INTEGER NOT NULL REFERENCES Sales(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES Products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price REAL NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE IF NOT EXISTS InventoryJournal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user TEXT NOT NULL DEFAULT 'sistema',
    action TEXT NOT NULL,
    entity TEXT NOT NULL,
    payload TEXT,
    status TEXT NOT NULL DEFAULT 'DONE'
);

CREATE TABLE IF NOT EXISTS ProductionBatches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    product_id INTEGER NOT NULL REFERENCES Products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_cost REAL NOT NULL CHECK (unit_cost >= 0),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS ProductionInputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES ProductionBatches(id) ON DELETE CASCADE,
    input_id INTEGER NOT NULL REFERENCES Inputs(id),
    quantity REAL NOT NULL CHECK (quantity > 0)
);

CREATE TABLE IF NOT EXISTS TastingFeedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES Products(id),
    accepted INTEGER NOT NULL CHECK (accepted IN (0, 1)),
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ProductRecipe (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES Products(id) ON DELETE CASCADE,
    input_id INTEGER NOT NULL REFERENCES Inputs(id),
    quantity_per_unit REAL NOT NULL CHECK (quantity_per_unit > 0),
    UNIQUE (product_id, input_id)
);

CREATE TABLE IF NOT EXISTS ProductRecipeStep (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES Products(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL CHECK (step_number > 0),
    instruction TEXT NOT NULL CHECK (length(instruction) BETWEEN 1 AND 500),
    UNIQUE (product_id, step_number)
);

CREATE TABLE IF NOT EXISTS ComboItems (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    combo_product_id INTEGER NOT NULL REFERENCES Products(id) ON DELETE CASCADE,
    component_product_id INTEGER NOT NULL REFERENCES Products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    UNIQUE (combo_product_id, component_product_id),
    CHECK (combo_product_id <> component_product_id)
);

CREATE TABLE IF NOT EXISTS BusinessInfo (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    name TEXT NOT NULL DEFAULT '' CHECK (length(name) <= 100),
    instagram TEXT NOT NULL DEFAULT '' CHECK (length(instagram) <= 150),
    facebook TEXT NOT NULL DEFAULT '' CHECK (length(facebook) <= 150),
    phone TEXT NOT NULL DEFAULT '' CHECK (length(phone) <= 40),
    email TEXT NOT NULL DEFAULT '' CHECK (length(email) <= 100),
    website TEXT NOT NULL DEFAULT '' CHECK (length(website) <= 150),
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO BusinessInfo (id, name, instagram, facebook, phone, email, website)
VALUES (1, 'Aurea Destilería Artesanal', '', '', '', '', '');

CREATE TABLE IF NOT EXISTS Purchases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    supplier_id INTEGER REFERENCES Suppliers(id),
    total_amount REAL NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'Recibida',
    created_by TEXT NOT NULL DEFAULT 'sistema'
);

CREATE TABLE IF NOT EXISTS PurchaseItems (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    purchase_id INTEGER NOT NULL REFERENCES Purchases(id) ON DELETE CASCADE,
    input_id INTEGER NOT NULL REFERENCES Inputs(id),
    quantity REAL NOT NULL CHECK (quantity > 0),
    unit_cost REAL NOT NULL CHECK (unit_cost >= 0)
);

CREATE TABLE IF NOT EXISTS Users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL CHECK (length(username) <= 50),
    password_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'admin',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Sessions (
    token TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    expires_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS AppContext (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS SyncLog (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status TEXT NOT NULL,
    endpoint TEXT,
    message TEXT,
    payload_bytes INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_sales_timestamp ON Sales(timestamp);
CREATE INDEX IF NOT EXISTS idx_saleitems_sale ON SaleItems(sale_id);
CREATE INDEX IF NOT EXISTS idx_saleitems_product ON SaleItems(product_id);
CREATE INDEX IF NOT EXISTS idx_journal_timestamp ON InventoryJournal(timestamp);
CREATE INDEX IF NOT EXISTS idx_production_timestamp ON ProductionBatches(timestamp);
CREATE INDEX IF NOT EXISTS idx_tasting_product ON TastingFeedback(product_id);
CREATE INDEX IF NOT EXISTS idx_recipe_product ON ProductRecipe(product_id);
CREATE INDEX IF NOT EXISTS idx_recipe_input ON ProductRecipe(input_id);
CREATE INDEX IF NOT EXISTS idx_recipe_steps_product ON ProductRecipeStep(product_id);
CREATE INDEX IF NOT EXISTS idx_combo_combo ON ComboItems(combo_product_id);
CREATE INDEX IF NOT EXISTS idx_combo_component ON ComboItems(component_product_id);
CREATE INDEX IF NOT EXISTS idx_sales_status ON Sales(status);
CREATE INDEX IF NOT EXISTS idx_sales_order_type_status ON Sales(order_type, status);
CREATE INDEX IF NOT EXISTS idx_purchases_timestamp ON Purchases(timestamp);
CREATE INDEX IF NOT EXISTS idx_purchaseitems_purchase ON PurchaseItems(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchaseitems_input ON PurchaseItems(input_id);
CREATE INDEX IF NOT EXISTS idx_synclog_timestamp ON SyncLog(timestamp);

DROP TRIGGER IF EXISTS trg_products_ai;
DROP TRIGGER IF EXISTS trg_products_au;
DROP TRIGGER IF EXISTS trg_products_ad;
DROP TRIGGER IF EXISTS trg_inputs_ai;
DROP TRIGGER IF EXISTS trg_inputs_au;
DROP TRIGGER IF EXISTS trg_inputs_ad;
DROP TRIGGER IF EXISTS trg_customers_ai;
DROP TRIGGER IF EXISTS trg_customers_au;
DROP TRIGGER IF EXISTS trg_customers_ad;
DROP TRIGGER IF EXISTS trg_suppliers_ai;
DROP TRIGGER IF EXISTS trg_suppliers_au;
DROP TRIGGER IF EXISTS trg_suppliers_ad;
DROP TRIGGER IF EXISTS trg_sales_ai;
DROP TRIGGER IF EXISTS trg_sales_au;
DROP TRIGGER IF EXISTS trg_sales_status_finish_bi;
DROP TRIGGER IF EXISTS trg_sales_status_finish_af;
DROP TRIGGER IF EXISTS trg_sales_status_unapply_af;
DROP TRIGGER IF EXISTS trg_saleitems_stock;
DROP TRIGGER IF EXISTS trg_saleitems_after_insert;
DROP TRIGGER IF EXISTS trg_saleitems_after_delete;
DROP TRIGGER IF EXISTS trg_batches_after_insert;
DROP TRIGGER IF EXISTS trg_batchinput_stock;
DROP TRIGGER IF EXISTS trg_batchinput_after_insert;
DROP TRIGGER IF EXISTS trg_purchases_ai;
DROP TRIGGER IF EXISTS trg_purchases_au;
DROP TRIGGER IF EXISTS trg_purchases_ad;
DROP TRIGGER IF EXISTS trg_purchaseitems_stock;
DROP TRIGGER IF EXISTS trg_purchaseitems_ai;
DROP TRIGGER IF EXISTS trg_purchaseitems_ad;
DROP TRIGGER IF EXISTS trg_recipe_ai;
DROP TRIGGER IF EXISTS trg_recipe_au;
DROP TRIGGER IF EXISTS trg_recipe_ad;
DROP TRIGGER IF EXISTS trg_recipe_step_ai;
DROP TRIGGER IF EXISTS trg_recipe_step_au;
DROP TRIGGER IF EXISTS trg_recipe_step_ad;
DROP TRIGGER IF EXISTS trg_combo_ai;
DROP TRIGGER IF EXISTS trg_combo_au;
DROP TRIGGER IF EXISTS trg_combo_ad;

CREATE TRIGGER trg_products_ai AFTER INSERT ON Products
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'INSERT', 'Products',
            'id=' || NEW.id || ';name=' || NEW.name || ';stock=' || NEW.stock || ';price=' || NEW.price,
            'DONE');
END;

CREATE TRIGGER trg_products_au AFTER UPDATE ON Products
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'UPDATE', 'Products',
            'id=' || NEW.id || ';name=' || NEW.name || ';stock=' || OLD.stock || '->' || NEW.stock || ';price=' || OLD.price || '->' || NEW.price,
            'DONE');
END;

CREATE TRIGGER trg_products_ad AFTER DELETE ON Products
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'DELETE', 'Products', 'id=' || OLD.id || ';name=' || OLD.name, 'DONE');
END;

CREATE TRIGGER trg_inputs_ai AFTER INSERT ON Inputs
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'INSERT', 'Inputs',
            'id=' || NEW.id || ';name=' || NEW.name || ';stock=' || NEW.stock || NEW.unit,
            'DONE');
END;

CREATE TRIGGER trg_inputs_au AFTER UPDATE ON Inputs
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'UPDATE', 'Inputs',
            'id=' || NEW.id || ';name=' || NEW.name || ';stock=' || OLD.stock || '->' || NEW.stock || NEW.unit,
            'DONE');
END;

CREATE TRIGGER trg_inputs_ad AFTER DELETE ON Inputs
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'DELETE', 'Inputs', 'id=' || OLD.id || ';name=' || OLD.name, 'DONE');
END;

CREATE TRIGGER trg_customers_ai AFTER INSERT ON Customers
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'INSERT', 'Customers', 'id=' || NEW.id || ';name=' || NEW.name || ';type=' || NEW.type, 'DONE');
END;

CREATE TRIGGER trg_customers_au AFTER UPDATE ON Customers
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'UPDATE', 'Customers', 'id=' || NEW.id || ';name=' || NEW.name, 'DONE');
END;

CREATE TRIGGER trg_customers_ad AFTER DELETE ON Customers
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'DELETE', 'Customers', 'id=' || OLD.id || ';name=' || OLD.name, 'DONE');
END;

CREATE TRIGGER trg_suppliers_ai AFTER INSERT ON Suppliers
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'INSERT', 'Suppliers', 'id=' || NEW.id || ';name=' || NEW.name, 'DONE');
END;

CREATE TRIGGER trg_suppliers_au AFTER UPDATE ON Suppliers
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'UPDATE', 'Suppliers', 'id=' || NEW.id || ';name=' || NEW.name, 'DONE');
END;

CREATE TRIGGER trg_suppliers_ad AFTER DELETE ON Suppliers
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'DELETE', 'Suppliers', 'id=' || OLD.id || ';name=' || OLD.name, 'DONE');
END;

CREATE TRIGGER trg_sales_ai AFTER INSERT ON Sales
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'SALE_CREATED', 'Sales',
            'sale_id=' || NEW.id || ';total=' || NEW.total_amount || ';status=' || NEW.status || ';payment=' || NEW.payment_method,
            'DONE');
END;

CREATE TRIGGER trg_sales_au AFTER UPDATE OF total_amount ON Sales
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'SALE_TOTAL_UPDATED', 'Sales', 'sale_id=' || NEW.id || ';total=' || OLD.total_amount || '->' || NEW.total_amount,
            'DONE');
END;

CREATE TRIGGER trg_saleitems_stock BEFORE INSERT ON SaleItems
WHEN (SELECT status FROM Sales WHERE id = NEW.sale_id) = 'finished'
BEGIN
    SELECT RAISE(ABORT, 'Stock insuficiente para el producto seleccionado')
    WHERE (SELECT COALESCE(is_combo, 0) FROM Products WHERE id = NEW.product_id) = 0
      AND (SELECT COALESCE(stock, 0) FROM Products WHERE id = NEW.product_id) < NEW.quantity;

    SELECT RAISE(ABORT, 'El combo no tiene componentes activos')
    WHERE (SELECT COALESCE(is_combo, 0) FROM Products WHERE id = NEW.product_id) = 1
      AND NOT EXISTS (
          SELECT 1 FROM ComboItems ci
          JOIN Products cp ON cp.id = ci.component_product_id
          WHERE ci.combo_product_id = NEW.product_id AND cp.active = 1
      );

    SELECT RAISE(ABORT, 'Stock insuficiente de componentes para el combo')
    WHERE (SELECT COALESCE(is_combo, 0) FROM Products WHERE id = NEW.product_id) = 1
      AND EXISTS (
          SELECT 1 FROM ComboItems ci
          JOIN Products cp ON cp.id = ci.component_product_id
          WHERE ci.combo_product_id = NEW.product_id
            AND (cp.active = 0 OR cp.stock < NEW.quantity * ci.quantity)
      );
END;

CREATE TRIGGER trg_saleitems_after_insert AFTER INSERT ON SaleItems
BEGIN
    UPDATE Products
       SET stock = stock - NEW.quantity
     WHERE id = NEW.product_id
       AND (SELECT COALESCE(is_combo, 0) FROM Products WHERE id = NEW.product_id) = 0
       AND (SELECT status FROM Sales WHERE id = NEW.sale_id) = 'finished';

    UPDATE Products
       SET stock = stock - (NEW.quantity * (
               SELECT ci.quantity FROM ComboItems ci
               WHERE ci.combo_product_id = NEW.product_id
                 AND ci.component_product_id = Products.id
           ))
     WHERE id IN (
           SELECT component_product_id FROM ComboItems
           WHERE combo_product_id = NEW.product_id
       )
       AND (SELECT status FROM Sales WHERE id = NEW.sale_id) = 'finished';

    UPDATE Sales SET
        subtotal_amount = (
            SELECT COALESCE(SUM(quantity * unit_price), 0) FROM SaleItems WHERE sale_id = NEW.sale_id
        ),
        total_amount = MAX(0, (
            SELECT COALESCE(SUM(quantity * unit_price), 0) FROM SaleItems WHERE sale_id = NEW.sale_id
        ) - discount_amount),
        stock_applied = CASE WHEN status = 'finished' THEN 1 ELSE stock_applied END
    WHERE id = NEW.sale_id;

    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            CASE WHEN (SELECT status FROM Sales WHERE id = NEW.sale_id) = 'finished'
                 THEN 'SALE_STOCK_OUT' ELSE 'ORDER_ITEM_ADDED' END,
            'SaleItems',
            'sale_id=' || NEW.sale_id || ';product_id=' || NEW.product_id || ';qty=' || NEW.quantity || ';unit_price=' || NEW.unit_price,
            'DONE');
END;

CREATE TRIGGER trg_saleitems_after_delete AFTER DELETE ON SaleItems
BEGIN
    UPDATE Products
       SET stock = stock + OLD.quantity
     WHERE id = OLD.product_id
       AND (SELECT COALESCE(is_combo, 0) FROM Products WHERE id = OLD.product_id) = 0
       AND (SELECT stock_applied FROM Sales WHERE id = OLD.sale_id) = 1;

    UPDATE Products
       SET stock = stock + (OLD.quantity * (
               SELECT ci.quantity FROM ComboItems ci
               WHERE ci.combo_product_id = OLD.product_id
                 AND ci.component_product_id = Products.id
           ))
     WHERE id IN (
           SELECT component_product_id FROM ComboItems
           WHERE combo_product_id = OLD.product_id
       )
       AND (SELECT stock_applied FROM Sales WHERE id = OLD.sale_id) = 1;

    UPDATE Sales SET
        subtotal_amount = (
            SELECT COALESCE(SUM(quantity * unit_price), 0) FROM SaleItems WHERE sale_id = OLD.sale_id
        ),
        total_amount = MAX(0, (
            SELECT COALESCE(SUM(quantity * unit_price), 0) FROM SaleItems WHERE sale_id = OLD.sale_id
        ) - discount_amount)
    WHERE id = OLD.sale_id;

    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'SALE_ITEM_DELETED', 'SaleItems',
            'sale_id=' || OLD.sale_id || ';product_id=' || OLD.product_id || ';qty=' || OLD.quantity,
            'DONE');
END;

CREATE TRIGGER trg_sales_status_finish_bi BEFORE UPDATE OF status ON Sales
WHEN NEW.status = 'finished' AND OLD.status <> 'finished' AND COALESCE(NEW.stock_applied, 0) = 0
BEGIN
    SELECT RAISE(ABORT, 'El pedido no tiene productos para finalizar')
    WHERE NOT EXISTS (SELECT 1 FROM SaleItems WHERE sale_id = NEW.id);

    SELECT RAISE(ABORT, 'El pedido contiene un combo sin componentes activos')
    WHERE EXISTS (
        SELECT 1 FROM SaleItems si
        JOIN Products p ON p.id = si.product_id
        WHERE si.sale_id = NEW.id AND p.is_combo = 1
          AND NOT EXISTS (
              SELECT 1 FROM ComboItems ci
              JOIN Products cp ON cp.id = ci.component_product_id
              WHERE ci.combo_product_id = p.id AND cp.active = 1
          )
    );

    SELECT RAISE(ABORT, 'Stock insuficiente para finalizar el pedido')
    WHERE EXISTS (
        SELECT 1
        FROM (
            SELECT pid, SUM(needed) AS total
            FROM (
                SELECT si.product_id AS pid, si.quantity AS needed
                FROM SaleItems si
                JOIN Products p ON p.id = si.product_id
                WHERE si.sale_id = NEW.id AND p.is_combo = 0
                UNION ALL
                SELECT ci.component_product_id AS pid, si.quantity * ci.quantity AS needed
                FROM SaleItems si
                JOIN ComboItems ci ON ci.combo_product_id = si.product_id
                WHERE si.sale_id = NEW.id
            ) parts
            GROUP BY pid
        ) needs
        JOIN Products p ON p.id = needs.pid
        WHERE p.active = 0 OR p.stock < needs.total
    );
END;

CREATE TRIGGER trg_sales_status_finish_af AFTER UPDATE OF status ON Sales
WHEN NEW.status = 'finished' AND OLD.status <> 'finished' AND COALESCE(NEW.stock_applied, 0) = 0
BEGIN
    UPDATE Products
       SET stock = stock - (
           SELECT COALESCE(SUM(si.quantity), 0)
           FROM SaleItems si
           JOIN Products p ON p.id = si.product_id
           WHERE si.sale_id = NEW.id AND p.is_combo = 0 AND si.product_id = Products.id
       )
     WHERE id IN (
           SELECT si.product_id FROM SaleItems si
           JOIN Products p ON p.id = si.product_id
           WHERE si.sale_id = NEW.id AND p.is_combo = 0
       );

    UPDATE Products
       SET stock = stock - (
           SELECT COALESCE(SUM(si.quantity * ci.quantity), 0)
           FROM SaleItems si
           JOIN ComboItems ci ON ci.combo_product_id = si.product_id
           WHERE si.sale_id = NEW.id AND ci.component_product_id = Products.id
       )
     WHERE id IN (
           SELECT ci.component_product_id
           FROM SaleItems si
           JOIN ComboItems ci ON ci.combo_product_id = si.product_id
           WHERE si.sale_id = NEW.id
       );

    UPDATE Sales SET stock_applied = 1 WHERE id = NEW.id;

    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'ORDER_FINISHED', 'Sales', 'sale_id=' || NEW.id || ';total=' || NEW.total_amount, 'DONE');
END;

CREATE TRIGGER trg_sales_status_unapply_af AFTER UPDATE OF status ON Sales
WHEN NEW.status <> 'finished' AND OLD.status = 'finished' AND OLD.stock_applied = 1
BEGIN
    UPDATE Products
       SET stock = stock + (
           SELECT COALESCE(SUM(si.quantity), 0)
           FROM SaleItems si
           JOIN Products p ON p.id = si.product_id
           WHERE si.sale_id = NEW.id AND p.is_combo = 0 AND si.product_id = Products.id
       )
     WHERE id IN (
           SELECT si.product_id FROM SaleItems si
           JOIN Products p ON p.id = si.product_id
           WHERE si.sale_id = NEW.id AND p.is_combo = 0
       );

    UPDATE Products
       SET stock = stock + (
           SELECT COALESCE(SUM(si.quantity * ci.quantity), 0)
           FROM SaleItems si
           JOIN ComboItems ci ON ci.combo_product_id = si.product_id
           WHERE si.sale_id = NEW.id AND ci.component_product_id = Products.id
       )
     WHERE id IN (
           SELECT ci.component_product_id
           FROM SaleItems si
           JOIN ComboItems ci ON ci.combo_product_id = si.product_id
           WHERE si.sale_id = NEW.id
       );

    UPDATE Sales SET stock_applied = 0 WHERE id = NEW.id;

    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            CASE WHEN NEW.status = 'cancel' THEN 'ORDER_CANCELLED' ELSE 'ORDER_REOPENED' END,
            'Sales', 'sale_id=' || NEW.id || ';status=' || NEW.status, 'DONE');
END;

CREATE TRIGGER trg_batches_after_insert AFTER INSERT ON ProductionBatches
BEGIN
    UPDATE Products SET stock = stock + NEW.quantity WHERE id = NEW.product_id;
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'PRODUCTION', 'ProductionBatches',
            'batch_id=' || NEW.id || ';product_id=' || NEW.product_id || ';qty=' || NEW.quantity || ';unit_cost=' || NEW.unit_cost,
            'DONE');
END;

CREATE TRIGGER trg_batchinput_stock BEFORE INSERT ON ProductionInputs
BEGIN
    SELECT RAISE(ABORT, 'Stock de insumo insuficiente para el lote de producción')
    WHERE (SELECT COALESCE(stock, 0) FROM Inputs WHERE id = NEW.input_id) < NEW.quantity;
END;

CREATE TRIGGER trg_batchinput_after_insert AFTER INSERT ON ProductionInputs
BEGIN
    UPDATE Inputs SET stock = stock - NEW.quantity WHERE id = NEW.input_id;
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'INPUT_CONSUMPTION', 'ProductionInputs',
            'batch_id=' || NEW.batch_id || ';input_id=' || NEW.input_id || ';qty=' || NEW.quantity,
            'DONE');
END;

CREATE TRIGGER trg_purchases_ai AFTER INSERT ON Purchases
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'PURCHASE_CREATED', 'Purchases',
            'purchase_id=' || NEW.id || ';supplier_id=' || COALESCE(NEW.supplier_id, 0) || ';status=' || NEW.status,
            'DONE');
END;

CREATE TRIGGER trg_purchases_au AFTER UPDATE ON Purchases
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'PURCHASE_UPDATED', 'Purchases',
            'purchase_id=' || NEW.id || ';total=' || OLD.total_amount || '->' || NEW.total_amount,
            'DONE');
END;

CREATE TRIGGER trg_purchases_ad AFTER DELETE ON Purchases
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'PURCHASE_DELETED', 'Purchases',
            'purchase_id=' || OLD.id || ';supplier_id=' || COALESCE(OLD.supplier_id, 0),
            'DONE');
END;

CREATE TRIGGER trg_purchaseitems_stock BEFORE INSERT ON PurchaseItems
BEGIN
    SELECT RAISE(ABORT, 'El insumo no existe o está inactivo')
    WHERE (SELECT COALESCE(active, 0) FROM Inputs WHERE id = NEW.input_id) = 0;
END;

CREATE TRIGGER trg_purchaseitems_ai AFTER INSERT ON PurchaseItems
BEGIN
    UPDATE Inputs
       SET stock = stock + NEW.quantity,
           cost = NEW.unit_cost
     WHERE id = NEW.input_id;
    UPDATE Purchases
       SET total_amount = (
           SELECT COALESCE(SUM(quantity * unit_cost), 0)
             FROM PurchaseItems WHERE purchase_id = NEW.purchase_id
       )
     WHERE id = NEW.purchase_id;
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'PURCHASE_RECEIVED', 'PurchaseItems',
            'purchase_id=' || NEW.purchase_id || ';input_id=' || NEW.input_id || ';qty=' || NEW.quantity || ';unit_cost=' || NEW.unit_cost,
            'DONE');
END;

CREATE TRIGGER trg_purchaseitems_ad AFTER DELETE ON PurchaseItems
BEGIN
    UPDATE Inputs SET stock = stock - OLD.quantity WHERE id = OLD.input_id;
    UPDATE Purchases
       SET total_amount = (
           SELECT COALESCE(SUM(quantity * unit_cost), 0)
             FROM PurchaseItems WHERE purchase_id = OLD.purchase_id
       )
     WHERE id = OLD.purchase_id;
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'PURCHASE_ITEM_DELETED', 'PurchaseItems',
            'purchase_id=' || OLD.purchase_id || ';input_id=' || OLD.input_id || ';qty=' || OLD.quantity,
            'DONE');
END;

CREATE TRIGGER trg_recipe_ai AFTER INSERT ON ProductRecipe
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'RECIPE_ADD', 'ProductRecipe',
            'product_id=' || NEW.product_id || ';input_id=' || NEW.input_id || ';qty_per_unit=' || NEW.quantity_per_unit,
            'DONE');
END;

CREATE TRIGGER trg_recipe_au AFTER UPDATE ON ProductRecipe
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'RECIPE_UPDATE', 'ProductRecipe',
            'product_id=' || NEW.product_id || ';input_id=' || NEW.input_id || ';qty=' || OLD.quantity_per_unit || '->' || NEW.quantity_per_unit,
            'DONE');
END;

CREATE TRIGGER trg_recipe_ad AFTER DELETE ON ProductRecipe
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'RECIPE_REMOVE', 'ProductRecipe',
            'product_id=' || OLD.product_id || ';input_id=' || OLD.input_id,
            'DONE');
END;

CREATE TRIGGER trg_recipe_step_ai AFTER INSERT ON ProductRecipeStep
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'RECIPE_STEP_ADD', 'ProductRecipeStep',
            'product_id=' || NEW.product_id || ';step=' || NEW.step_number, 'DONE');
END;

CREATE TRIGGER trg_recipe_step_au AFTER UPDATE ON ProductRecipeStep
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'RECIPE_STEP_UPDATE', 'ProductRecipeStep',
            'product_id=' || NEW.product_id || ';step=' || NEW.step_number, 'DONE');
END;

CREATE TRIGGER trg_recipe_step_ad AFTER DELETE ON ProductRecipeStep
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'RECIPE_STEP_REMOVE', 'ProductRecipeStep',
            'product_id=' || OLD.product_id || ';step=' || OLD.step_number, 'DONE');
END;

CREATE TRIGGER trg_combo_ai AFTER INSERT ON ComboItems
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'COMBO_ADD', 'ComboItems',
            'combo_id=' || NEW.combo_product_id || ';component_id=' || NEW.component_product_id || ';qty=' || NEW.quantity,
            'DONE');
END;

CREATE TRIGGER trg_combo_au AFTER UPDATE ON ComboItems
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'COMBO_UPDATE', 'ComboItems',
            'combo_id=' || NEW.combo_product_id || ';component_id=' || NEW.component_product_id || ';qty=' || OLD.quantity || '->' || NEW.quantity,
            'DONE');
END;

CREATE TRIGGER trg_combo_ad AFTER DELETE ON ComboItems
BEGIN
    INSERT INTO InventoryJournal (user, action, entity, payload, status)
    VALUES (COALESCE((SELECT value FROM AppContext WHERE key = 'user'), 'sistema'),
            'COMBO_REMOVE', 'ComboItems',
            'combo_id=' || OLD.combo_product_id || ';component_id=' || OLD.component_product_id,
            'DONE');
END;
SQL
)
    db_exec "${sql}"
}

_schema_hash_password() {
    local value="$1"
    printf '%s' "${value}" | sha256sum | awk '{print $1}'
}

db_seed_demo_data() {
    local product_count admin_salt admin_hash cashier_hash
    product_count=$(db_scalar "SELECT COUNT(*) FROM Products;" 2>/dev/null || printf '0')
    product_count="${product_count:-0}"

    admin_salt="e7c1a9f4b2d8"
    admin_hash=$(_schema_hash_password "${admin_salt}:admin123")
    cashier_hash=$(_schema_hash_password "b4f2c8d1a6e3:cajero123")

    if (( product_count > 0 )); then
        db_exec "INSERT OR IGNORE INTO Users (username, password_hash, salt, role)
                 VALUES ('admin', $(db_quote "${admin_hash}"), $(db_quote "${admin_salt}"), 'admin'),
                        ('cajero', $(db_quote "${cashier_hash}"), 'b4f2c8d1a6e3', 'vendedor');"
        return 0
    fi

    local seed_sql
    seed_sql=$(cat <<'SQL'
INSERT INTO Categories (id, name) VALUES
    (1, 'Licores Macerados'),
    (2, 'Destilados'),
    (3, 'Hidromieles'),
    (4, 'Gin & Botánicos'),
    (5, 'Insumos'),
    (6, 'Envases');

INSERT INTO Suppliers (id, name, contact_person, phone, email, address) VALUES
    (1, 'Finca Los Robles', 'Lucía Medina', '+54 11 4455-1201', 'ventas@losrobles.com', 'Ruta 8 Km 42, Mercedes'),
    (2, 'Destilería Andina', 'Martín Quiroga', '+54 261 442-8890', 'pedidos@andina.com', 'Parque Industrial, Mendoza'),
    (3, 'Apiario del Sur', 'Ana Torres', '+54 294 455-3301', 'hola@apiariodelsur.com', 'Valle de los Arrayanes, Neuquén'),
    (4, 'Packaging Norte', 'Diego Salas', '+54 11 4655-7788', 'cuentas@packnorte.com', 'Av. Industrial 740, Tigre'),
    (5, 'Fermentos del Valle', 'Carla Benítez', '+54 299 447-1122', 'insumos@fermentosvalle.com', 'Ruta 22, Cinco Saltos');

INSERT INTO Customers (id, name, type, phone, email) VALUES
    (1, 'Distribuidora El Tonel', 'Mayorista', '+54 11 4788-2200', 'compras@eltonel.com'),
    (2, 'Bar La Alquimia', 'Mayorista', '+54 11 4832-7710', 'barra@laalquimia.com'),
    (3, 'María Fernández', 'Minorista', '+54 11 5567-9902', 'maria.fernandez@mail.com'),
    (4, 'Juan Pérez', 'Minorista', '+54 11 5012-4433', 'juan.perez@mail.com'),
    (5, 'Hotel Mirador', 'Mayorista', '+54 11 4322-8899', 'eventos@hotelmirador.com'),
    (6, 'Sofía Ríos', 'Minorista', '+54 11 6144-2201', 'sofia.rios@mail.com'),
    (7, 'Café de Autor', 'Mayorista', '+54 11 4866-5521', 'compras@cafedeautor.com'),
    (8, 'Pedro Gómez', 'Minorista', '+54 11 5399-7712', 'pedro.gomez@mail.com');

INSERT INTO Inputs (id, name, category_id, stock, unit, cost, supplier_id, min_stock_threshold) VALUES
    (1, 'Alcohol neutro 96°', 5, 500, 'litros', 9.50, 2, 40),
    (2, 'Frutos rojos', 5, 500, 'kg', 4.20, 1, 15),
    (3, 'Miel pura', 5, 500, 'kg', 6.80, 3, 20),
    (4, 'Botánicos mixtos', 5, 500, 'kg', 11.50, 1, 10),
    (5, 'Botellas 750 ml', 6, 500, 'unidades', 1.20, 4, 120),
    (6, 'Corchos premium', 6, 500, 'unidades', 0.25, 4, 200),
    (7, 'Etiquetas premium', 6, 500, 'unidades', 0.35, 4, 100),
    (8, 'Agua mineral', 5, 500, 'litros', 0.15, 1, 80),
    (9, 'Levadura de hidromiel', 5, 500, 'unidades', 2.40, 3, 12),
    (10, 'Ácido cítrico', 5, 500, 'kg', 3.60, 2, 3);

INSERT INTO Products (id, name, category_id, stock, min_production_threshold, cost, price, active, is_seasonal) VALUES
    (1, 'Gin de Botánicos', 4, 900, 15, 7.80, 18.50, 1, 0),
    (2, 'Licor de Frutos Rojos', 1, 900, 12, 6.40, 14.00, 1, 0),
    (3, 'Hidromiel Clásica', 3, 900, 20, 4.20, 11.50, 1, 0),
    (4, 'Hidromiel de Lavanda', 3, 900, 10, 4.80, 12.50, 1, 0),
    (5, 'Whisky Artesanal', 2, 900, 8, 12.00, 29.00, 1, 0),
    (6, 'Gin Cítrico', 4, 900, 10, 7.20, 17.00, 1, 0),
    (7, 'Licor de Café', 1, 900, 8, 6.90, 15.50, 1, 0),
    (8, 'Vodka Artesanal', 2, 900, 10, 8.00, 19.00, 1, 0),
    (9, 'Gin de Saúco', 4, 900, 6, 8.10, 19.50, 1, 1),
    (10, 'Tónica Artesanal', 4, 900, 20, 2.10, 6.00, 1, 0);

INSERT INTO ProductionBatches (id, timestamp, product_id, quantity, unit_cost, notes) VALUES
    (1, datetime('now', '-35 days'), 1, 18, 7.60, 'Lote piloto de gin'),
    (2, datetime('now', '-32 days'), 3, 22, 4.10, 'Hidromiel base'),
    (3, datetime('now', '-29 days'), 5, 10, 11.50, 'Destilado de malta'),
    (4, datetime('now', '-26 days'), 2, 20, 6.20, 'Macerado de frutos'),
    (5, datetime('now', '-23 days'), 1, 24, 8.10, 'Gin botánicos intenso'),
    (6, datetime('now', '-20 days'), 3, 26, 4.40, 'Hidromiel con miel de azahar'),
    (7, datetime('now', '-17 days'), 5, 12, 12.30, 'Whisky barrica pequeña'),
    (8, datetime('now', '-14 days'), 9, 16, 8.00, 'Gin de saúco estacional'),
    (9, datetime('now', '-11 days'), 2, 18, 6.70, 'Licor frutos rojos'),
    (10, datetime('now', '-8 days'), 1, 22, 7.80, 'Gin de botánicos'),
    (11, datetime('now', '-5 days'), 3, 24, 4.60, 'Hidromiel clásica'),
    (12, datetime('now', '-2 days'), 9, 18, 8.30, 'Gin de saúco');

INSERT INTO ProductionInputs (batch_id, input_id, quantity) VALUES
    (1, 1, 7.5), (1, 4, 1.8), (1, 5, 18), (1, 6, 18),
    (2, 3, 8.0), (2, 9, 6), (2, 5, 22), (2, 6, 22),
    (3, 1, 5.5), (3, 8, 9.0), (3, 5, 10), (3, 6, 10),
    (4, 2, 9.5), (4, 1, 4.0), (4, 5, 20), (4, 7, 20),
    (5, 1, 9.0), (5, 4, 2.2), (5, 5, 24), (5, 7, 24),
    (6, 3, 9.5), (6, 9, 7), (6, 5, 26), (6, 7, 26),
    (7, 1, 6.0), (7, 8, 10.0), (7, 5, 12), (7, 6, 12),
    (8, 1, 6.0), (8, 4, 1.5), (8, 5, 16), (8, 7, 16),
    (9, 2, 8.0), (9, 1, 3.5), (9, 5, 18), (9, 7, 18),
    (10, 1, 8.5), (10, 4, 2.0), (10, 5, 22), (10, 7, 22),
    (11, 3, 9.0), (11, 9, 7), (11, 5, 24), (11, 6, 24),
    (12, 1, 6.5), (12, 4, 1.7), (12, 5, 18), (12, 7, 18);

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
SELECT datetime(date('now', '-44 days', '+' || d.n || ' day') || ' ' ||
              printf('%02d:%02d:00', 11 + ((d.n + s.slot * 3) % 10), (d.n * 13 + s.slot * 17) % 60)),
       ((d.n + s.slot) % 6) + 1,
       0,
       CASE (d.n + s.slot) % 3
           WHEN 0 THEN 'Efectivo'
           WHEN 1 THEN 'Transferencia'
           ELSE 'Tarjeta'
       END
FROM (
    WITH RECURSIVE days(n) AS (
        SELECT 0
        UNION ALL
        SELECT n + 1 FROM days WHERE n < 44
    )
    SELECT n FROM days
) d
JOIN (
    SELECT 1 AS slot
    UNION ALL SELECT 2
    UNION ALL SELECT 3
) s
WHERE s.slot <= 1 + ((d.n * 5) % 3)
ORDER BY d.n, s.slot;

INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT s.id,
       p.id,
       CASE WHEN ((s.id * 7 + p.id) % 19) = 0 THEN 9 ELSE ((s.id + p.id) % 3) + 1 END,
       p.price
FROM Sales s
JOIN (
    SELECT 1 AS k
    UNION ALL SELECT 2
    UNION ALL SELECT 3
) i ON i.k <= 1 + (s.id % 3)
JOIN Products p ON p.id = 1 + ((s.id * 5 + i.k * 3) % 10)
WHERE s.id <= (SELECT MAX(id) FROM Sales);

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-23 days', '19:15:00'), 1, 0, 'Transferencia');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 5, 40, (SELECT price FROM Products WHERE id = 5) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-14 days', '20:05:00'), 2, 0, 'Tarjeta');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 5, 38, (SELECT price FROM Products WHERE id = 5) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-5 days', '18:40:00'), 5, 0, 'Transferencia');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 5, 42, (SELECT price FROM Products WHERE id = 5) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-31 days', '19:20:00'), 3, 0, 'Efectivo');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 6, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 12, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-26 days', '18:10:00'), 4, 0, 'Tarjeta');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 9, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 18, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-21 days', '20:30:00'), 6, 0, 'Efectivo');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 6, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 12, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-17 days', '19:50:00'), 7, 0, 'Transferencia');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 12, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 24, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-13 days', '18:55:00'), 8, 0, 'Tarjeta');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 9, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 18, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-9 days', '20:15:00'), 1, 0, 'Transferencia');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 15, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 30, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-6 days', '19:10:00'), 2, 0, 'Tarjeta');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 12, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 24, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO Sales (timestamp, customer_id, total_amount, payment_method)
VALUES (datetime('now', '-2 days', '18:25:00'), 3, 0, 'Efectivo');
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 1, 6, (SELECT price FROM Products WHERE id = 1) FROM Sales;
INSERT INTO SaleItems (sale_id, product_id, quantity, unit_price)
SELECT MAX(id), 10, 12, (SELECT price FROM Products WHERE id = 10) FROM Sales;

INSERT INTO TastingFeedback (product_id, accepted, timestamp)
SELECT 9,
       CASE WHEN (n % 5) IN (0, 1, 3) THEN 1 ELSE 0 END,
       datetime('now', '-' || n || ' hours')
FROM (
    WITH RECURSIVE t(n) AS (
        SELECT 1
        UNION ALL
        SELECT n + 1 FROM t WHERE n < 80
    )
    SELECT n FROM t
);

INSERT INTO ProductRecipe (product_id, input_id, quantity_per_unit) VALUES
    (1, 1, 0.350), (1, 4, 0.070), (1, 5, 1), (1, 6, 1), (1, 7, 1),
    (2, 1, 0.250), (2, 2, 0.350), (2, 5, 1), (2, 7, 1),
    (3, 3, 0.320), (3, 9, 0.250), (3, 5, 1), (3, 6, 1),
    (4, 3, 0.300), (4, 4, 0.030), (4, 9, 0.220), (4, 5, 1), (4, 7, 1),
    (5, 1, 0.450), (5, 8, 0.200), (5, 5, 1), (5, 6, 1),
    (6, 1, 0.340), (6, 4, 0.050), (6, 10, 0.010), (6, 5, 1), (6, 7, 1),
    (7, 1, 0.220), (7, 3, 0.100), (7, 5, 1), (7, 7, 1),
    (8, 1, 0.400), (8, 8, 0.250), (8, 5, 1), (8, 6, 1),
    (9, 1, 0.330), (9, 4, 0.060), (9, 5, 1), (9, 7, 1),
    (10, 3, 0.040), (10, 8, 0.700), (10, 10, 0.020), (10, 5, 1), (10, 7, 1);

INSERT INTO Purchases (id, timestamp, supplier_id, total_amount, notes, status, created_by) VALUES
    (1, datetime('now', '-30 days'), 2, 0, 'Reposición de alcohol y agua mineral', 'Recibida', 'admin'),
    (2, datetime('now', '-18 days'), 1, 0, 'Frutos rojos y botánicos de temporada', 'Recibida', 'admin'),
    (3, datetime('now', '-9 days'), 4, 0, 'Envases y etiquetas para fin de mes', 'Recibida', 'cajero'),
    (4, datetime('now', '-3 days'), 3, 0, 'Miel y levadura para hidromiel', 'Recibida', 'admin');

INSERT INTO PurchaseItems (purchase_id, input_id, quantity, unit_cost) VALUES
    (1, 1, 20, 9.50), (1, 8, 50, 0.15), (1, 10, 2, 3.60),
    (2, 2, 15, 4.20), (2, 4, 5, 11.50), (2, 8, 20, 0.15),
    (3, 5, 100, 1.20), (3, 6, 200, 0.25), (3, 7, 100, 0.35),
    (4, 3, 20, 6.80), (4, 9, 10, 2.40);

UPDATE Products SET stock = 28 WHERE id = 1;
UPDATE Products SET stock = 42 WHERE id = 2;
UPDATE Products SET stock = 9  WHERE id = 3;
UPDATE Products SET stock = 31 WHERE id = 4;
UPDATE Products SET stock = 18 WHERE id = 5;
UPDATE Products SET stock = 24 WHERE id = 6;
UPDATE Products SET stock = 6  WHERE id = 7;
UPDATE Products SET stock = 22 WHERE id = 8;
UPDATE Products SET stock = 14 WHERE id = 9;
UPDATE Products SET stock = 55 WHERE id = 10;

UPDATE Inputs SET stock = 46   WHERE id = 1;
UPDATE Inputs SET stock = 12.5 WHERE id = 2;
UPDATE Inputs SET stock = 38   WHERE id = 3;
UPDATE Inputs SET stock = 7.8  WHERE id = 4;
UPDATE Inputs SET stock = 220  WHERE id = 5;
UPDATE Inputs SET stock = 380  WHERE id = 6;
UPDATE Inputs SET stock = 95   WHERE id = 7;
UPDATE Inputs SET stock = 140  WHERE id = 8;
UPDATE Inputs SET stock = 18   WHERE id = 9;
UPDATE Inputs SET stock = 5.4  WHERE id = 10;
SQL
)
    db_exec "${seed_sql}" || return 1

    db_exec "INSERT OR IGNORE INTO Users (username, password_hash, salt, role)
             VALUES ('admin', $(db_quote "${admin_hash}"), $(db_quote "${admin_salt}"), 'admin'),
                    ('cajero', $(db_quote "${cashier_hash}"), 'b4f2c8d1a6e3', 'vendedor');" || return 1

    return 0
}
