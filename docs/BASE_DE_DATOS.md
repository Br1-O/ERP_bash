# Base de datos

- Motor: SQLite.
- Archivo local: `shared/data/erp_licores.db`.
- Versión de esquema: **8** (`ERP_SCHEMA_VERSION`).
- DDL y datos demo: `model/schema.sh`.
- Modo: WAL, `foreign_keys = ON`, `busy_timeout = 5000`.
- Separador de consultas del singleton: `|`.

El diagrama ER completo está en [DIAGRAMAS.md](DIAGRAMAS.md).

## 1. Resumen de tablas

| Tabla | Propósito |
|---|---|
| `Categories` | Categorías de productos e insumos. |
| `Suppliers` | Proveedores de insumos. |
| `Customers` | Clientes mayoristas y minoristas. |
| `Inputs` | Insumos con stock, costo, proveedor y umbral. |
| `Products` | Productos simples y combos, con stock, precio y umbral. |
| `Sales` | Ventas directas y pedidos de clientes, con canal y evento. |
| `Events` | Ferias/eventos con estado, finanzas y auditoría de cierre. |
| `EventStock` | Stock asignado a cada evento por producto y costo congelado. |
| `SaleItems` | Ítems de venta/pedido. |
| `ProductionBatches` | Lotes de producción. |
| `ProductionInputs` | Consumo de insumos por lote. |
| `ProductRecipe` | Insumos necesarios por unidad de producto. |
| `ProductRecipeStep` | Pasos de preparación de una receta. |
| `ComboItems` | Componentes y cantidades de un combo. |
| `TastingFeedback` | Pruebas de aceptación de sabores. |
| `Purchases` | Compras a proveedores. |
| `PurchaseItems` | Ítems de compra. |
| `BusinessInfo` | Datos de la empresa para facturas. |
| `InventoryJournal` | Outbox/auditoría de cambios y movimientos; alimenta `/auditoria`, `/api/audit` y la sincronización. |
| `Users` | Usuarios del sistema. |
| `Sessions` | Sesiones activas. |
| `AppContext` | Configuración local y usuario de auditoría. |
| `SyncLog` | Bitácora de sincronizaciones. |

## 2. Detalle de tablas

### 2.1 `Categories`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `name` | TEXT | UNIQUE, NOT NULL, máximo 50 caracteres. |

### 2.2 `Suppliers`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `name` | TEXT | NOT NULL, máximo 80 caracteres. |
| `contact_person` | TEXT | Opcional. |
| `phone` | TEXT | Opcional. |
| `email` | TEXT | Opcional. |
| `address` | TEXT | Opcional. |
| `active` | INTEGER | `0`/`1`, por defecto `1`; las bajas son lógicas. |

### 2.3 `Customers`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `name` | TEXT | NOT NULL, máximo 80 caracteres. |
| `type` | TEXT | `Mayorista` o `Minorista`; por defecto `Minorista`. |
| `phone` | TEXT | Opcional. |
| `email` | TEXT | Opcional. |
| `active` | INTEGER | `0`/`1`, por defecto `1`; las bajas son lógicas. |

### 2.4 `Inputs`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `name` | TEXT | NOT NULL, máximo 80 caracteres. |
| `category_id` | INTEGER | FK a `Categories.id`. |
| `stock` | REAL | NOT NULL, `>= 0`. |
| `unit` | TEXT | NOT NULL, por defecto `unidades`. |
| `cost` | REAL | NOT NULL, `>= 0`. |
| `supplier_id` | INTEGER | FK a `Suppliers.id`. |
| `min_stock_threshold` | REAL | NOT NULL, `>= 0`. |
| `active` | INTEGER | `0`/`1`, por defecto `1`. |

### 2.5 `Products`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `name` | TEXT | UNIQUE, NOT NULL, máximo 80 caracteres. |
| `category_id` | INTEGER | NOT NULL, FK a `Categories.id`. |
| `stock` | INTEGER | NOT NULL, `>= 0`. Para combos se mantiene en `0`. |
| `min_production_threshold` | INTEGER | NOT NULL, `>= 0`. |
| `cost` | REAL | NOT NULL, `>= 0`. |
| `price` | REAL | NOT NULL, `>= 0`. |
| `active` | INTEGER | `0`/`1`, por defecto `1`. |
| `is_seasonal` | INTEGER | `0`/`1`, por defecto `0`. |
| `recipe_description` | TEXT | Hasta 2000 caracteres. |
| `is_combo` | INTEGER | `0`/`1`, por defecto `0`. |

La disponibilidad de un combo se calcula, no se almacena:

```sql
MIN(CAST(componente.stock / combo_item.quantity AS INTEGER))
```

sobre los componentes activos.

### 2.6 `Sales`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `timestamp` | DATETIME | Por defecto `CURRENT_TIMESTAMP`. |
| `customer_id` | INTEGER | FK a `Customers.id`. |
| `subtotal_amount` | REAL | NOT NULL, `>= 0`. |
| `discount_type` | TEXT | `none`, `percent` o `fixed`; validado por `api/billing.sh`. |
| `discount_value` | REAL | NOT NULL, `>= 0`. |
| `discount_amount` | REAL | NOT NULL, `>= 0`. |
| `total_amount` | REAL | NOT NULL, `>= 0`. |
| `payment_method` | TEXT | `Efectivo`, `Transferencia` o `Tarjeta`. |
| `status` | TEXT | `pending`, `finished` o `cancel`; por defecto `finished`. |
| `notes` | TEXT | Opcional. |
| `created_by` | TEXT | Por defecto `sistema`. |
| `stock_applied` | INTEGER | `0`/`1`; evita doble descuento/restauración. |
| `order_type` | TEXT | `direct` u `order`; por defecto `direct`. |
| `order_stage` | TEXT | `draft`, `pending`, `preparing`, `confirmed`, `paid`, `delivered` o `cancel`; por defecto `delivered`. |
| `cancel_reason` | TEXT | Motivo obligatorio al anular; entre 3 y 300 caracteres. |
| `cancelled_by` | TEXT | Usuario que solicita la anulación. |
| `cancel_authorized_by` | TEXT | Administrador o supervisor que valida el PIN. |
| `cancelled_at` | DATETIME | Momento de la anulación. |
| `event_id` | INTEGER | FK opcional a `Events.id`; define venta de feria. |
| `channel` | TEXT | `LOCAL`, `FERIA` o `ECOMMERCE`; por defecto `LOCAL`. |

### 2.7 `SaleItems`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `sale_id` | INTEGER | NOT NULL, FK a `Sales.id` con `ON DELETE CASCADE`. |
| `product_id` | INTEGER | NOT NULL, FK a `Products.id`. |
| `quantity` | INTEGER | NOT NULL, `> 0`. |
| `unit_price` | REAL | NOT NULL, `>= 0`. |

### 2.8 `ProductionBatches`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `timestamp` | DATETIME | Por defecto `CURRENT_TIMESTAMP`. |
| `product_id` | INTEGER | NOT NULL, FK a `Products.id`. |
| `quantity` | INTEGER | NOT NULL, `> 0`. |
| `unit_cost` | REAL | NOT NULL, `>= 0`. |
| `notes` | TEXT | Opcional. |

### 2.9 `ProductionInputs`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `batch_id` | INTEGER | NOT NULL, FK a `ProductionBatches.id` con `ON DELETE CASCADE`. |
| `input_id` | INTEGER | NOT NULL, FK a `Inputs.id`. |
| `quantity` | REAL | NOT NULL, `> 0`. |

### 2.10 `ProductRecipe`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `product_id` | INTEGER | NOT NULL, FK a `Products.id` con `ON DELETE CASCADE`. |
| `input_id` | INTEGER | NOT NULL, FK a `Inputs.id`. |
| `quantity_per_unit` | REAL | NOT NULL, `> 0`. |

`UNIQUE (product_id, input_id)`.

### 2.11 `ProductRecipeStep`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `product_id` | INTEGER | NOT NULL, FK a `Products.id` con `ON DELETE CASCADE`. |
| `step_number` | INTEGER | NOT NULL, `> 0`. |
| `instruction` | TEXT | NOT NULL, entre 1 y 500 caracteres. |

`UNIQUE (product_id, step_number)`.

### 2.12 `ComboItems`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `combo_product_id` | INTEGER | NOT NULL, FK a `Products.id` con `ON DELETE CASCADE`. |
| `component_product_id` | INTEGER | NOT NULL, FK a `Products.id`. |
| `quantity` | INTEGER | NOT NULL, `> 0`. |

`UNIQUE (combo_product_id, component_product_id)` y
`CHECK (combo_product_id <> component_product_id)`.

### 2.13 `TastingFeedback`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `product_id` | INTEGER | NOT NULL, FK a `Products.id`. |
| `accepted` | INTEGER | `0`/`1`. |
| `timestamp` | DATETIME | Por defecto `CURRENT_TIMESTAMP`. |

### 2.14 `Purchases`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `timestamp` | DATETIME | Por defecto `CURRENT_TIMESTAMP`. |
| `supplier_id` | INTEGER | FK a `Suppliers.id`. |
| `total_amount` | REAL | NOT NULL, `>= 0`; recalculado por triggers. |
| `notes` | TEXT | Opcional. |
| `status` | TEXT | `pending`, `processing` o `finished`; por defecto `pending`. |
| `created_by` | TEXT | Por defecto `sistema`. |
| `stock_applied` | INTEGER | `0`/`1`; indica si el stock ya fue sumado. |

### 2.15 `PurchaseItems`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `purchase_id` | INTEGER | NOT NULL, FK a `Purchases.id` con `ON DELETE CASCADE`. |
| `input_id` | INTEGER | NOT NULL, FK a `Inputs.id`. |
| `quantity` | REAL | NOT NULL, `> 0`. |
| `unit_cost` | REAL | NOT NULL, `>= 0`. |

### 2.16 `BusinessInfo`

Tabla de una sola fila (`id = 1`).

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK, `CHECK (id = 1)`. |
| `name` | TEXT | Hasta 100 caracteres. |
| `instagram` | TEXT | Hasta 150 caracteres. |
| `facebook` | TEXT | Hasta 150 caracteres. |
| `phone` | TEXT | Hasta 40 caracteres. |
| `email` | TEXT | Hasta 100 caracteres. |
| `website` | TEXT | Hasta 150 caracteres. |
| `updated_at` | DATETIME | Por defecto `CURRENT_TIMESTAMP`. |

### 2.17 `InventoryJournal`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `timestamp` | DATETIME | Por defecto `CURRENT_TIMESTAMP`. |
| `user` | TEXT | Por defecto `sistema`. |
| `action` | TEXT | Acción auditada. |
| `entity` | TEXT | Tabla afectada. |
| `payload` | TEXT | Detalle JSON del movimiento (incluye `stock_delta` cuando aplica). |
| `status` | TEXT | Por defecto `DONE`. |
| `event_uuid` | TEXT | UUID v4 único generado por trigger; clave de idempotencia. |
| `origin` | TEXT | `LOCAL`, `WEB` o `ECOMMERCE`; por defecto `LOCAL`. |
| `synced` | INTEGER | `0` pendiente de push, `1` confirmado por el endpoint. |

### 2.18 `Users`, `Sessions`, `AppContext`, `SyncLog`

| Tabla | Columnas principales |
|---|---|
| `Users` | `id`, `username` UNIQUE, `password_hash`, `salt`, `role`, `created_at`, `pin_hash`, `pin_salt`, `can_view_metrics`, `can_manage_stock`, `active`. |
| `Sessions` | `token` PK, `username`, `expires_at` (epoch). |
| `AppContext` | `key` PK, `value`; se usa para `user`, `sync_url` y `sync_token`. |
| `SyncLog` | `id`, `timestamp`, `status`, `endpoint`, `message`, `payload_bytes`. |

### 2.19 `Events`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `name` | TEXT | NOT NULL, entre 1 y 100 caracteres. |
| `location` | TEXT | Hasta 150 caracteres. |
| `start_date` | DATE | NOT NULL. |
| `end_date` | DATE | Opcional, `>= start_date`. |
| `status` | TEXT | `active`, `closed` o `cancelled`; por defecto `active`. |
| `notes` | TEXT | Hasta 1000 caracteres. |
| `created_by` | TEXT | Usuario creador. |
| `closed_by` | TEXT | Usuario que cerró. |
| `total_revenue_cents` | INTEGER | Ingresos históricos en centavos. |
| `total_cogs_cents` | INTEGER | Costo de vendido en centavos. |
| `total_loss_cents` | INTEGER | Pérdidas valorizadas en centavos. |
| `net_profit_cents` | INTEGER | `revenue - cogs - loss`. |
| `created_at` | DATETIME | Por defecto `CURRENT_TIMESTAMP`. |
| `closed_at` | DATETIME | Momento de cierre. |

### 2.20 `EventStock`

| Columna | Tipo | Restricciones |
|---|---|---|
| `id` | INTEGER | PK autoincremental. |
| `event_id` | INTEGER | NOT NULL, FK a `Events.id` con `ON DELETE CASCADE`. |
| `product_id` | INTEGER | NOT NULL, FK a `Products.id`. |
| `allocated_qty` | INTEGER | `>= 0`. |
| `sold_qty` | INTEGER | `>= 0`. |
| `loss_qty` | INTEGER | `>= 0`. |
| `returned_qty` | INTEGER | `>= 0`. |
| `unit_cost_snapshot` | REAL | Costo congelado al asignar. |
| `created_at` / `updated_at` | DATETIME | Marcas de tiempo. |

`UNIQUE (event_id, product_id)` y
`sold_qty + loss_qty + returned_qty <= allocated_qty`.

## 3. Relaciones

```text
Categories 1──N Inputs
Categories 1──N Products
Suppliers  1──N Inputs
Suppliers  1──N Purchases
Customers  1──N Sales
Products   1──N SaleItems
Products   1──N ProductionBatches
Products   1──N ProductRecipe
Products   1──N ProductRecipeStep
Products   1──N ComboItems (como combo)
Products   1──N ComboItems (como componente)
Products   1──N TastingFeedback
Products   1──N EventStock
Events     1──N EventStock
Events     1──N Sales (event_id)
Inputs     1──N ProductRecipe
Inputs     1──N ProductionInputs
Inputs     1──N PurchaseItems
Sales      1──N SaleItems
Purchases  1──N PurchaseItems
ProductionBatches 1──N ProductionInputs
```

## 4. Índices

| Índice | Tabla/columnas |
|---|---|
| `idx_sales_timestamp` | `Sales(timestamp)` |
| `idx_saleitems_sale` | `SaleItems(sale_id)` |
| `idx_saleitems_product` | `SaleItems(product_id)` |
| `idx_journal_timestamp` | `InventoryJournal(timestamp)` |
| `idx_production_timestamp` | `ProductionBatches(timestamp)` |
| `idx_tasting_product` | `TastingFeedback(product_id)` |
| `idx_recipe_product` | `ProductRecipe(product_id)` |
| `idx_recipe_input` | `ProductRecipe(input_id)` |
| `idx_recipe_steps_product` | `ProductRecipeStep(product_id)` |
| `idx_combo_combo` | `ComboItems(combo_product_id)` |
| `idx_combo_component` | `ComboItems(component_product_id)` |
| `idx_sales_status` | `Sales(status)` |
| `idx_sales_order_type_status` | `Sales(order_type, status)` |
| `idx_sales_order_stage` | `Sales(order_stage)` |
| `idx_purchases_timestamp` | `Purchases(timestamp)` |
| `idx_purchases_status` | `Purchases(status)` |
| `idx_purchaseitems_purchase` | `PurchaseItems(purchase_id)` |
| `idx_purchaseitems_input` | `PurchaseItems(input_id)` |
| `idx_synclog_timestamp` | `SyncLog(timestamp)` |
| `idx_journal_event_uuid` | `InventoryJournal(event_uuid)` UNIQUE |
| `idx_journal_sync` | `InventoryJournal(synced, origin, id)` |
| `idx_sales_event` | `Sales(event_id)` |
| `idx_sales_channel` | `Sales(channel)` |
| `idx_events_status_dates` | `Events(status, start_date, end_date)` |
| `idx_eventstock_event` | `EventStock(event_id)` |
| `idx_eventstock_product` | `EventStock(product_id)` |

## 5. Triggers

| Trigger | Efecto |
|---|---|
| `trg_products_ai/au/ad` | Auditoría de altas, cambios y bajas de productos. |
| `trg_inputs_ai/au/ad` | Auditoría de insumos. |
| `trg_customers_ai/au/ad` | Auditoría de clientes. |
| `trg_suppliers_ai/au/ad` | Auditoría de proveedores. |
| `trg_sales_ai` | Auditoría de venta creada. |
| `trg_sales_au` | Auditoría de cambio de total. |
| `trg_saleitems_stock` | Valida stock de producto o componentes de combo antes de insertar un ítem en venta finalizada. |
| `trg_saleitems_after_insert` | Descuenta stock, recalcula subtotal/total y marca `stock_applied`. |
| `trg_saleitems_after_delete` | Restaura stock y recalcula totales. |
| `trg_sales_status_finish_bi` | Valida ítems, combos y stock antes de finalizar. |
| `trg_sales_status_finish_af` | Descuenta stock una sola vez y marca `stock_applied=1`. |
| `trg_sales_status_unapply_af` | Restaura stock al reabrir/cancelar y marca `stock_applied=0`. |
| `trg_batches_after_insert` | Suma la cantidad producida al stock del producto. |
| `trg_batchinput_stock` | Rechaza consumo de insumo sin stock suficiente. |
| `trg_batchinput_after_insert` | Descuenta insumos del lote. |
| `trg_purchases_ai/au/ad` | Auditoría de compras. |
| `trg_purchases_status_finish_bi` | Rechaza finalizar un pedido sin insumos. |
| `trg_purchases_status_finish_af` | Suma stock, actualiza costos y marca `stock_applied=1` una sola vez. |
| `trg_purchases_status_unapply_bi` | Rechaza reabrir si el stock recibido ya fue consumido. |
| `trg_purchases_status_unapply_af` | Resta el stock recibido y marca `stock_applied=0` al reabrir. |
| `trg_purchaseitems_stock` | Rechaza insumos inactivos y modificaciones con stock aplicado. |
| `trg_purchaseitems_delete_bi` | Rechaza eliminar ítems de un pedido con stock aplicado. |
| `trg_purchaseitems_ai/ad` | Recalcula el total del pedido. |
| `trg_recipe_ai/au/ad` | Auditoría de receta. |
| `trg_recipe_step_ai/au/ad` | Auditoría de pasos. |
| `trg_combo_ai/au/ad` | Auditoría de componentes de combo. |
| `trg_journal_event_uuid_ai` | Genera UUID v4 para cada evento del journal. |
| `trg_events_status_bi` | Valida transiciones de estado del evento. |
| `trg_events_immutable_bu` | Bloquea cambios en eventos cerrados/cancelados. |
| `trg_events_close_bi` | Calcula sobrantes, valida pérdidas y devuelve stock al cerrar. |
| `trg_events_cancel_bi` | Cancela solo sin ventas/pérdidas y devuelve el 100 %. |
| `trg_events_delete_bi` | Impide eliminar eventos. |
| `trg_event_stock_allocate_ai/_au` | Descuenta `SEDE` al asignar/ampliar stock y audita. |
| `trg_event_stock_immutable_bu` | Bloquea cambios de stock de eventos cerrados/cancelados. |
| `trg_event_stock_delete_bi` | Impide eliminar stock de evento. |
| `trg_sales_event_channel_bi/_bu` | Normaliza `channel` y valida `event_id`. |

## 6. Invariantes

1. `Products.stock` nunca es negativo.
2. Un combo no se ajusta directamente; su disponibilidad depende de componentes
   activos.
3. `Sales.stock_applied` es la única bandera que decide si corresponde
   restaurar stock.
4. Un pedido no puede finalizarse sin ítems ni con stock insuficiente.
5. `Purchases.total_amount` es la suma de `quantity * unit_cost`.
6. El stock de una compra se aplica únicamente al pasar a `finished` y se
   revierte al reabrir; `stock_applied` evita duplicarlo.
7. Una compra con `stock_applied=1` no puede modificar sus ítems ni eliminarse.
8. `ProductionInputs` no puede superar el stock del insumo.
9. Los descuentos nunca producen un total negativo.
10. Los datos de empresa son una única fila.
11. Los clientes y proveedores se desactivan lógicamente; sus referencias
    históricas se conservan.
12. Toda anulación exige motivo y PIN válido de un administrador o supervisor
    activo; el registro original nunca se borra físicamente.
13. `Sales.order_stage` no puede retroceder desde `paid`, `delivered` o
    `cancel`.
14. Una venta de feria (`event_id` no nulo) descuenta solo `EventStock`; una
    venta `LOCAL` descuenta `Products.stock`.
15. El stock asignado a un evento nunca se reduce; solo se amplía.
16. Un evento `closed` o `cancelled` es inmutable y no puede eliminarse.
17. La suma `sold_qty + loss_qty + returned_qty` siempre coincide con
    `allocated_qty` después del cierre.
18. Cada fila de `InventoryJournal` tiene `event_uuid` único y `synced=0`
    hasta que el endpoint confirma el lote.

## 7. Migración y datos demo

`_schema_migrate_legacy_columns` agrega columnas faltantes en bases anteriores:

- `Inputs.active`.
- `Products.recipe_description`, `Products.is_combo`.
- `Sales.subtotal_amount`, `discount_type`, `discount_value`,
  `discount_amount`, `status`, `notes`, `created_by`, `stock_applied`,
  `order_type`, `order_stage`, `cancel_reason`, `cancelled_by`,
  `cancel_authorized_by`, `cancelled_at`.
- `Users.pin_hash`, `pin_salt`, `can_view_metrics`, `can_manage_stock`,
  `active`.
- `Suppliers.active`, `Customers.active`.
- `Purchases.stock_applied`; normaliza estados legacy (`Recibida` →
  `finished`, etc.).
- `Sales.event_id`, `Sales.channel`.
- `InventoryJournal.event_uuid`, `origin`, `synced`; las filas previas reciben
  UUID y se marcan `synced=1` para no reenviar historia.
- Crea `Events`, `EventStock` y sus índices/triggers si no existen.

Al migrar, las ventas y compras existentes finalizadas quedan con
`stock_applied = 1` para no volver a mover stock. Las ventas legacy con
`status='cancel'` quedan con `order_stage='cancel'`; las ventas directas con
`delivered` y los pedidos finalizados con `delivered`.

`./erp.sh init` crea la base si no existe y carga datos demo reproducibles:
10 productos, 10 insumos, 8 clientes, 5 proveedores, 101 ventas, 12 lotes,
4 eventos de feria y los eventos de auditoría correspondientes.

## 8. Operación y respaldo

```bash
# Reiniciar datos demo
rm -f shared/data/erp_licores.db shared/data/erp_licores.db-wal shared/data/erp_licores.db-shm
./erp.sh init

# Respaldo en caliente (sin detener el servidor)
./erp.sh backup
./erp.sh backup /tmp/erp_backup.db
```

Si no existe `sqlite3`, usar el shim de Node para consultas de solo lectura:

```bash
node --no-warnings tools/sqlite3_shim.js shared/data/erp_licores.db \
  "SELECT COUNT(*) FROM Sales WHERE status = 'finished';"
```

Notas para scripts:

- `db_query` procesa una sola sentencia SELECT por llamada.
- El separador de columnas es `|`.
- Las consultas con nombres de columna duplicados requieren alias únicos; el
  shim usa arrays internamente para no colapsar valores.
