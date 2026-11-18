# Diagramas

Los diagramas usan Mermaid y se renderizan en visores compatibles (GitHub,
GitLab, VS Code, Obsidian). El backend está implementado con módulos Bash, no
con clases; el diagrama de clases modela responsabilidades y dependencias.

## 1. Diagrama de clases y módulos

```mermaid
classDiagram
    class Router {
        +handle_request()
        +assets_route()
        +current_alerts_count()
        +handle_api_production()
    }

    class Auth {
        +api_authenticate()
        +api_load_session()
        +api_session_cookie()
        +api_create_user()
        +api_validate_pin()
        +api_verify_authorization_pin()
        +api_user_set_pin()
    }

    class Catalog {
        +api_list_products_json()
        +api_list_inputs_json()
        +api_list_customers_json()
        +api_list_suppliers_json()
        +api_contacts_json()
    }

    class Inventory {
        +api_inv_products_json()
        +api_inv_inputs_json()
        +api_inv_product_detail_json()
        +api_inv_supplier_detail_json()
        +api_inv_product_available_stock()
        +api_inv_adjust_product_stock()
    }

    class Purchases {
        +api_recommendations_json()
        +api_purchase_create()
        +api_purchase_update()
        +api_purchase_set_status()
        +api_purchase_delete()
        +api_purchases_json()
        +api_purchase_detail_json()
    }

    class Sales {
        +api_register_sale()
        +api_register_production_batch()
        +api_recent_sales_json()
        +api_sales_cancel()
    }

    class Orders {
        +api_order_create()
        +api_order_update()
        +api_order_status()
        +api_order_delete()
        +api_order_detail_json()
    }

    class UserManager {
        +load_users()
        +create_user()
        +update_user()
        +set_pin()
    }

    class Billing {
        +billing_apply_strategy()
        +billing_money_to_cents()
        +billing_cents_to_decimal()
    }

    class Invoices {
        +api_invoice_purchase_json()
        +api_invoice_order_json()
    }

    class SyncService {
        +api_sync_save_config()
        +api_sync_push()
        +api_sync_status_json()
    }

    class LocalRepository {
        +local_repo_snapshot_json()
        +local_repo_save_sync_url()
        +local_repo_save_sync_token()
        +local_repo_record_sync()
    }

    class PostgresRepository {
        +pg_repo_push()
        +pg_repo_compose_endpoint()
    }

    class Analytics {
        +analytics_dashboard_json()
        +analytics_alerts_json()
        +analytics_reorder_products_json()
        +analytics_reorder_inputs_json()
        +analytics_low_products_json()
    }

    class DbSingleton {
        +db_query()
        +db_scalar()
        +db_exec()
        +db_last_insert_id()
        +db_set_context_user()
    }

    class Schema {
        +db_apply_schema()
        +ERP_SCHEMA_VERSION
    }

    class Transactions {
        +tx_begin()
        +tx_commit()
        +tx_rollback()
    }

    Router --> Auth
    Router --> Catalog
    Router --> Inventory
    Router --> Purchases
    Router --> Sales
    Router --> Orders
    Router --> Invoices
    Router --> SyncService
    Router --> Analytics
    Sales --> Billing
    Orders --> Billing
    Orders --> Inventory
    Purchases --> Inventory
    Inventory --> DbSingleton
    Sales --> DbSingleton
    Orders --> DbSingleton
    Purchases --> DbSingleton
    Catalog --> DbSingleton
    Analytics --> DbSingleton
    SyncService --> LocalRepository
    SyncService --> PostgresRepository
    LocalRepository --> DbSingleton
    DbSingleton --> Schema
    DbSingleton --> Transactions
```

### 1.1 Componentes web

```mermaid
classDiagram
    class ErpModal {
        +open()
        +close()
        +setTitle()
        +setBody()
        +setFooter()
    }

    class ErpPagination {
        +setData(page, pages)
        +page-change
    }

    class ErpRecipeEditor {
        +ready()
        +setMeta(meta)
        +setItems(items)
        +getItems()
        +input-created
    }

    class ProductManager {
        +_loadProducts()
        +_openDetail(id)
        +_openProduction(product)
        +_submitProduction(event)
        +_handleDeepLink()
    }

    class InputManager {
        +_loadInputs()
        +_openDetail(id)
        +_openRestock(input)
        +_submitRestock(event)
    }

    class PurchaseManager {
        +_loadRecommendations()
        +_startDraft(inputId)
        +_generateOrder()
        +_registerOrder()
        +_handleDeepLink()
    }

    class OrderManager {
        +_loadOrders()
        +_openDetail(id)
        +_handleAction(action, order)
        +_submit(event)
    }

    class InvoiceGenerator {
        +open(type, id)
        +_print()
        +_download()
    }

    class BusinessSettings {
        +_load()
        +_save(event)
    }

    class ContactManager {
        +_loadContacts()
        +_openSupplier(id)
        +_openCustomer(id)
    }

    ProductManager --> ErpModal
    ProductManager --> ErpRecipeEditor
    ProductManager --> ErpPagination
    InputManager --> ErpModal
    InputManager --> ErpPagination
    PurchaseManager --> ErpModal
    PurchaseManager --> InvoiceGenerator
    OrderManager --> ErpModal
    OrderManager --> InvoiceGenerator
    OrderManager --> ErpPagination
    BusinessSettings --> ErpModal
    ContactManager --> ErpModal
    ContactManager --> ErpPagination
```

## 2. Diagrama ER de la base de datos

```mermaid
erDiagram
    CATEGORIES {
        INTEGER id PK
        TEXT name UK
    }

    SUPPLIERS {
        INTEGER id PK
        TEXT name
        TEXT contact_person
        TEXT phone
        TEXT email
        TEXT address
    }

    CUSTOMERS {
        INTEGER id PK
        TEXT name
        TEXT type
        TEXT phone
        TEXT email
    }

    INPUTS {
        INTEGER id PK
        TEXT name
        INTEGER category_id FK
        REAL stock
        TEXT unit
        REAL cost
        INTEGER supplier_id FK
        REAL min_stock_threshold
        INTEGER active
    }

    PRODUCTS {
        INTEGER id PK
        TEXT name UK
        INTEGER category_id FK
        INTEGER stock
        INTEGER min_production_threshold
        REAL cost
        REAL price
        INTEGER active
        INTEGER is_seasonal
        TEXT recipe_description
        INTEGER is_combo
    }

    SALES {
        INTEGER id PK
        DATETIME timestamp
        INTEGER customer_id FK
        REAL subtotal_amount
        TEXT discount_type
        REAL discount_value
        REAL discount_amount
        REAL total_amount
        TEXT payment_method
        TEXT status
        TEXT notes
        TEXT created_by
        INTEGER stock_applied
        TEXT order_type
        TEXT order_stage
        TEXT cancel_reason
        TEXT cancelled_by
        TEXT cancel_authorized_by
        DATETIME cancelled_at
    }

    SALE_ITEMS {
        INTEGER id PK
        INTEGER sale_id FK
        INTEGER product_id FK
        INTEGER quantity
        REAL unit_price
    }

    PRODUCTION_BATCHES {
        INTEGER id PK
        DATETIME timestamp
        INTEGER product_id FK
        INTEGER quantity
        REAL unit_cost
        TEXT notes
    }

    PRODUCTION_INPUTS {
        INTEGER id PK
        INTEGER batch_id FK
        INTEGER input_id FK
        REAL quantity
    }

    PRODUCT_RECIPE {
        INTEGER id PK
        INTEGER product_id FK
        INTEGER input_id FK
        REAL quantity_per_unit
    }

    PRODUCT_RECIPE_STEP {
        INTEGER id PK
        INTEGER product_id FK
        INTEGER step_number
        TEXT instruction
    }

    COMBO_ITEMS {
        INTEGER id PK
        INTEGER combo_product_id FK
        INTEGER component_product_id FK
        INTEGER quantity
    }

    TASTING_FEEDBACK {
        INTEGER id PK
        INTEGER product_id FK
        INTEGER accepted
        DATETIME timestamp
    }

    PURCHASES {
        INTEGER id PK
        DATETIME timestamp
        INTEGER supplier_id FK
        REAL total_amount
        TEXT notes
        TEXT status
        TEXT created_by
    }

    PURCHASE_ITEMS {
        INTEGER id PK
        INTEGER purchase_id FK
        INTEGER input_id FK
        REAL quantity
        REAL unit_cost
    }

    BUSINESS_INFO {
        INTEGER id PK
        TEXT name
        TEXT instagram
        TEXT facebook
        TEXT phone
        TEXT email
        TEXT website
        DATETIME updated_at
    }

    INVENTORY_JOURNAL {
        INTEGER id PK
        DATETIME timestamp
        TEXT user
        TEXT action
        TEXT entity
        TEXT payload
        TEXT status
    }

    USERS {
        INTEGER id PK
        TEXT username UK
        TEXT password_hash
        TEXT salt
        TEXT role
        DATETIME created_at
        TEXT pin_hash
        TEXT pin_salt
        INTEGER can_view_metrics
        INTEGER can_manage_stock
        INTEGER active
    }

    SESSIONS {
        TEXT token PK
        TEXT username
        INTEGER expires_at
    }

    APP_CONTEXT {
        TEXT key PK
        TEXT value
    }

    SYNC_LOG {
        INTEGER id PK
        DATETIME timestamp
        TEXT status
        TEXT endpoint
        TEXT message
        INTEGER payload_bytes
    }

    CATEGORIES ||--o{ INPUTS : categoriza
    CATEGORIES ||--o{ PRODUCTS : categoriza
    SUPPLIERS ||--o{ INPUTS : provee
    SUPPLIERS ||--o{ PURCHASES : recibe
    CUSTOMERS ||--o{ SALES : compra
    SALES ||--o{ SALE_ITEMS : contiene
    PRODUCTS ||--o{ SALE_ITEMS : vendido
    PRODUCTS ||--o{ PRODUCTION_BATCHES : produce
    PRODUCTION_BATCHES ||--o{ PRODUCTION_INPUTS : consume
    INPUTS ||--o{ PRODUCTION_INPUTS : usado
    PRODUCTS ||--o{ PRODUCT_RECIPE : requiere
    INPUTS ||--o{ PRODUCT_RECIPE : ingrediente
    PRODUCTS ||--o{ PRODUCT_RECIPE_STEP : pasos
    PRODUCTS ||--o{ COMBO_ITEMS : combo
    PRODUCTS ||--o{ COMBO_ITEMS : componente
    PRODUCTS ||--o{ TASTING_FEEDBACK : evaluado
    PURCHASES ||--o{ PURCHASE_ITEMS : contiene
    INPUTS ||--o{ PURCHASE_ITEMS : comprado
```

## 3. Estados de una venta o pedido

```mermaid
stateDiagram-v2
    [*] --> draft: POST /api/orders
    [*] --> pending: POST /api/orders
    [*] --> preparing: POST /api/orders
    draft --> pending
    pending --> preparing
    preparing --> confirmed: Aplica stock
    draft --> confirmed: Aplica stock
    pending --> confirmed: Aplica stock
    confirmed --> paid: Cobro registrado
    confirmed --> delivered: Entrega registrada
    paid --> delivered
    draft --> cancel: Anular (motivo + PIN)
    pending --> cancel: Anular (motivo + PIN)
    preparing --> cancel: Anular (motivo + PIN)
    confirmed --> cancel: Anular + restaurar stock
    paid --> cancel: Anular + restaurar stock
    delivered --> cancel: Anular + restaurar stock
    [*] --> delivered: POST /api/sales (venta directa)
    delivered --> cancel: Anular (motivo + PIN)
    cancel --> [*]: Conserva historial
    paid --> [*]: Conserva historial
    delivered --> [*]: Conserva historial
```

Notas:

- `stock_applied=1` desde `confirmed` hasta antes de la anulación.
- `paid` y `delivered` cuentan como ingreso; `confirmed` no.
- Reabrir desde etapas finales no está permitido.
- Anular restaura stock una única vez y exige motivo + PIN de
  administrador/supervisor.
- La baja temprana (`DELETE`) es lógica y exige motivo + PIN.
- Las ventas directas nacen en `delivered` y no se reabren.

### 3.1 Estados de un pedido de compra

```mermaid
stateDiagram-v2
    [*] --> pending: POST /api/purchases
    pending --> processing: Iniciar proceso
    processing --> pending: Volver a pendiente
    pending --> finished: Finalizar (suma stock)
    processing --> finished: Finalizar (suma stock)
    finished --> processing: Reabrir (revierte stock)
    pending --> [*]: DELETE sin stock aplicado
    processing --> [*]: DELETE sin stock aplicado
    finished --> [*]: Conserva historial
```

Notas:

- El stock se aplica una sola vez al entrar en `finished`.
- Reabrir resta el stock recibido y falla si ya fue consumido.
- Con `stock_applied=1` no se editan ítems ni se elimina el pedido.

## 4. Secuencia: reposición de insumo desde una alerta

```mermaid
sequenceDiagram
    actor Admin
    participant Dashboard
    participant PurchaseManager
    participant API as API Bash
    participant DB as SQLite

    Admin->>Dashboard: Clic en insumo crítico
    Dashboard->>PurchaseManager: GET /compras?input=4
    PurchaseManager->>API: GET /api/recommendations
    API->>DB: Consulta insumos críticos y consumo
    API-->>PurchaseManager: Lista de recomendaciones
    PurchaseManager->>API: GET /api/suppliers/1
    API->>DB: Proveedor + insumos activos
    API-->>PurchaseManager: Datos de contacto e insumos
    PurchaseManager-->>Admin: Borrador con insumo 4 seleccionado
    Admin->>PurchaseManager: Ajusta cantidades y genera pedido
    PurchaseManager->>API: POST /api/purchases
    API->>DB: INSERT Purchases (pending) + PurchaseItems
    API-->>PurchaseManager: purchase_id
    PurchaseManager-->>Admin: Pedido pendiente
    Admin->>PurchaseManager: Finaliza desde el historial
    PurchaseManager->>API: PUT /api/purchases/:id/status
    API->>DB: UPDATE status = finished
    DB-->>API: Triggers suman stock y costo
    API-->>PurchaseManager: OK
    PurchaseManager-->>Admin: Pedido finalizado
```

## 5. Secuencia: producción desde una alerta de producto

```mermaid
sequenceDiagram
    actor Admin
    participant Dashboard
    participant ProductManager
    participant API as API Bash
    participant DB as SQLite

    Admin->>Dashboard: Clic en producto bajo
    Dashboard->>ProductManager: GET /inventario?product=3&produce=1
    ProductManager->>API: GET /api/products/3
    API->>DB: Producto + receta + stock de insumos
    API-->>ProductManager: Detalle con receta
    ProductManager-->>Admin: Modal de producción precargado
    Admin->>ProductManager: Confirma cantidad e insumos
    ProductManager->>API: POST /api/production con items
    API->>DB: INSERT ProductionBatches
    DB-->>API: Trigger suma stock del producto
    API->>DB: INSERT ProductionInputs
    DB-->>API: Trigger descuenta insumos
    API-->>ProductManager: batch_id
    ProductManager-->>Admin: Lote registrado
```

## 6. Secuencia: finalizar un pedido

```mermaid
sequenceDiagram
    actor Usuario
    participant OrderManager
    participant API as API Bash
    participant DB as SQLite

    Usuario->>OrderManager: Finalizar pedido
    OrderManager->>API: PUT /api/orders/102/status {status: confirmed}
    API->>DB: UPDATE Sales SET order_stage='confirmed', status='finished'
    DB->>DB: trg_sales_status_finish_bi valida stock
    DB->>DB: trg_sales_status_finish_af descuenta stock
    DB->>DB: stock_applied = 1
    API-->>OrderManager: ok
    OrderManager-->>Usuario: Pedido confirmado
```

## 6.1 Secuencia: anular una venta

```mermaid
sequenceDiagram
    actor Usuario
    participant UI as OrderManager/Dashboard
    participant API as API Bash
    participant DB as SQLite

    Usuario->>UI: Anular venta + motivo + PIN
    UI->>API: POST /api/sales/102/cancel
    API->>DB: valida PIN de admin/supervisor activo
    API->>DB: UPDATE Sales status='cancel', order_stage='cancel'
    DB->>DB: trg_sales_status_unapply_af restaura stock
    API->>DB: INSERT InventoryJournal SALE_CANCELLED
    API-->>UI: ok
    UI-->>Usuario: Venta anulada; crear venta corregida
```

## 7. Secuencia: sincronización con PostgreSQL

```mermaid
sequenceDiagram
    actor Admin
    participant UI as Dashboard
    participant API as API Bash
    participant Local as LocalRepository
    participant DB as SQLite
    participant Remote as Endpoint PostgreSQL

    Admin->>UI: Sincronizar
    UI->>API: POST /api/sync/push
    API->>Local: local_repo_snapshot_json()
    Local->>DB: json_object de tablas de negocio
    DB-->>Local: Snapshot JSON
    Local-->>API: Snapshot
    API->>Remote: POST ?source=sqlite&schema_version=7&mode=snapshot
    Remote-->>API: 2xx
    API->>DB: INSERT SyncLog
    API-->>UI: Estado y bytes enviados
    UI-->>Admin: Resultado
```
