# Rutas y API

Todas las rutas privadas requieren la cookie de sesión `erp_session`. Las
páginas redirigen a `/login`; las APIs responden `401` con JSON.

## 1. Páginas

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/` | Redirige a `/dashboard`. |
| GET | `/login` | Formulario de acceso. |
| POST | `/login` | Autentica y crea la sesión. |
| GET/POST | `/logout` | Cierra la sesión. |
| GET | `/dashboard?tab=resumen\|stock\|catalogo\|agenda` | Dashboard analítico. También acepta `#resumen`, `#stock`, `#catalogo`, `#agenda`. |
| GET | `/inteligencia` | Página completa de inteligencia de canasta: matriz de Pearson, combos inteligentes y productos sustitutos con búsqueda, orden y paginación. |
| GET | `/inventario` | Productos, insumos, recetas, combos, lotes y producción. |
| GET | `/inventario?product=<id>` | Abre el detalle del producto. |
| GET | `/inventario?product=<id>&produce=1` | Abre el modal de producción con receta precargada. Si es combo, abre el detalle. |
| GET | `/compras` | Pedidos de compra, estados, proveedores y reposición sugerida. Incluye alta manual de pedidos. |
| GET | `/compras?input=<id>` | Inicia un borrador de pedido con el insumo seleccionado y los demás insumos activos del mismo proveedor. |
| GET | `/ventas` | Todas las ventas y pedidos, estados, alta de venta directa, selección de canal/evento, anulación y facturación. |
| GET | `/eventos` | Ferias: KPIs, gráficos, asignación de stock, cierre con pérdidas y cancelación. |
| GET | `/auditoria` | Historial completo de `InventoryJournal` con búsqueda, paginación y enlaces a entidades. |
| GET | `/contactos` | Agenda de clientes y proveedores. |
| GET | `/usuarios` | Administración de vendedores y supervisores. Solo `admin`. |
| GET | `/configuracion` | Datos de la empresa para facturación. |

Acceso por rol:

| Página | Roles permitidos |
|---|---|
| `/dashboard`, `/inteligencia` | `admin`, supervisor con `can_view_metrics=1`. |
| `/inventario`, `/compras` | `admin`, supervisor con `can_manage_stock=1`. |
| `/ventas`, `/eventos`, `/auditoria`, `/contactos` | Cualquier usuario activo. |
| `/usuarios`, `/configuracion` | Solo `admin`. |

Si el usuario no tiene permiso para una página, el router lo redirige a su
página inicial (`/ventas` para vendedores; dashboard o ventas según sus
permisos).

### 1.1 Enlaces profundos de reposición

- Las alertas de insumos del dashboard y las filas de “Reposición sugerida”
  apuntan a `/compras?input=<id>`.
- Las alertas de productos y las filas de punto de pedido apuntan a
  `/inventario?product=<id>&produce=1`.
- Los combos no se producen: sus enlaces abren el detalle para revisar
  componentes.
- El borrador de compra permite agregar otros insumos activos del proveedor
  antes de generar el pedido.
- El modal de producción calcula las cantidades de insumos con
  `quantity_per_unit * cantidad` y las envía como arreglo `items`.

## 2. Assets

| Ruta | Contenido |
|---|---|
| `/assets/app.css` | Estilos globales, componentes y responsive. |
| `/assets/app.js` | Dashboard, ventas, contactos y sincronización (badge de pendientes). |
| `/assets/insights.js` | Página de inteligencia de canasta: matriz, combos y sustitutos. |
| `/assets/billing.js` | Patrón Money y estrategias de descuento. |
| `/assets/components.js` | Carga y utilidades de web components. |
| `/components/<componente>/<archivo>.js\|css\|html` | Assets de componentes, incluido `event-manager`. |

## 3. API

### 3.1 Autenticación y estado

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/health` | Estado básico del servicio y ruta de la base. No requiere sesión. |
| GET | `/api/dashboard` | Payload completo del dashboard (KPIs, alertas, reposición, catálogo, agenda). |
| GET | `/api/alerts` | Alertas de stock de insumos y productos. |
| GET | `/api/contacts?q=` | Búsqueda de clientes y proveedores. |

`/api/alerts` devuelve:

```json
{
  "inputs": [
    { "id": 4, "name": "Botánicos mixtos", "stock": 7.8, "unit": "kg", "threshold": 10, "deficit": 2.2 }
  ],
  "products": [
    { "id": 3, "name": "Hidromiel Clásica", "stock": 9, "threshold": 20, "deficit": 11, "is_combo": 0 }
  ],
  "count": 2
}
```

Para combos, `stock` es la disponibilidad calculada desde sus componentes.

### 3.2 Inventario y catálogo

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/products` | Lista de productos con `category_id`, `stock` disponible, `physical_stock`, `min_threshold`, `seasonal` e `is_combo`. |
| GET | `/api/products/:id` | Detalle con receta, pasos, componentes, `available_stock` y `max_producible`. |
| POST | `/api/products` | Crea un producto simple o combo. |
| PUT | `/api/products/:id` | Actualiza producto, receta, pasos y componentes. |
| DELETE | `/api/products/:id` | Elimina (desactiva) un producto. |
| POST | `/api/products/:id/stock` | Ajusta stock de productos simples. Los combos no admiten ajuste directo. |
| GET | `/api/inputs` | Lista de insumos. |
| GET | `/api/inputs/:id` | Detalle de insumo, productos que lo usan y últimas compras. |
| POST | `/api/inputs` | Crea un insumo. |
| PUT | `/api/inputs/:id` | Actualiza un insumo. |
| DELETE | `/api/inputs/:id` | Elimina (desactiva) un insumo. |
| POST | `/api/inputs/restock` | Repone stock de un insumo sin registrar compra. |
| GET | `/api/inventory/products` | Productos paginados para la vista de inventario. |
| GET | `/api/inventory/inputs` | Insumos paginados para la vista de inventario. |
| GET | `/api/inventory/meta` | Categorías, proveedores e insumos para formularios. |
| GET | `/api/suppliers/:id` | Proveedor, contacto e insumos activos. |

Parámetros de `/api/inventory/products`:

- `q`: búsqueda por nombre o categoría.
- `category`: id de categoría, `combos` o `0`.
- `state`: `active`, `inactive`, `low` o `all`.
- `page`: página desde `1`.
- `per_page`: 1 a 50.

Parámetros de `/api/inventory/inputs`:

- `q`, `page`, `per_page`.
- `supplier`: id de proveedor o `0`.
- `state`: `active`, `inactive`, `low` o `all`.

Ejemplo de producto simple:

```json
{
  "name": "Gin de Saúco",
  "category_id": 1,
  "min_threshold": 6,
  "cost": 8.1,
  "price": 18.5,
  "seasonal": 1,
  "is_combo": 0,
  "recipe_description": "Gin macerado con saúco",
  "steps_text": "Macerar 48 horas\nFiltrar\nEmbotellar",
  "items": [
    { "input_id": 1, "quantity": 0.25 },
    { "input_id": 5, "quantity": 1 }
  ]
}
```

Ejemplo de combo:

```json
{
  "name": "Combo Gin + Tónica",
  "category_id": 1,
  "min_threshold": 5,
  "cost": 10,
  "price": 22,
  "is_combo": 1,
  "components": [
    { "component_product_id": 1, "quantity": 1 },
    { "component_product_id": 10, "quantity": 2 }
  ]
}
```

Reposición directa de insumo:

```json
{
  "input_id": 4,
  "quantity": 10
}
```

### 3.3 Producción y ventas

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/api/production` | Registra un lote y consume insumos. |
| POST | `/api/sales` | Registra una venta directa con descuento opcional. |

Ejemplo de producción con múltiples insumos:

```json
{
  "product_id": 3,
  "quantity": 11,
  "unit_cost": 4.35,
  "notes": "Lote de reposición",
  "items": [
    { "input_id": 5, "quantity": 11 },
    { "input_id": 6, "quantity": 11 },
    { "input_id": 9, "quantity": 2.75 },
    { "input_id": 3, "quantity": 3.52 }
  ]
}
```

Respuesta:

```json
{ "ok": true, "batch_id": 13 }
```

También se acepta el formato anterior de un solo insumo con `input_id` e
`input_quantity`.

Ejemplo de venta:

```json
{
  "customer_id": 1,
  "payment_method": "Efectivo",
  "discount_type": "percent",
  "discount_value": 10,
  "items": [
    { "product_id": 8, "quantity": 2 }
  ]
}
```

`discount_type` acepta `none`, `percent` o `fixed`. La respuesta incluye
`sale_id`, `subtotal`, `discount` y `total`.

### 3.4 Compras, proveedores y reposición

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/purchases` | Lista paginada de pedidos de compra. |
| GET | `/api/purchases/:id` | Detalle de pedido con ítems, estado y `stock_applied`. |
| POST | `/api/purchases` | Crea un pedido de compra; por defecto queda `pending`. |
| PUT | `/api/purchases/:id` | Edita proveedor, nota e ítems mientras no tenga stock aplicado. |
| PUT | `/api/purchases/:id/status` | Cambia el estado a `pending`, `processing` o `finished`. |
| DELETE | `/api/purchases/:id` | Elimina un pedido sin stock aplicado. |
| GET | `/api/recommendations` | Recomendaciones de reposición de insumos. |
| POST | `/api/customers` | Crea un cliente. |
| PUT | `/api/customers/:id` | Edita un cliente activo. |
| DELETE | `/api/customers/:id` | Desactiva lógicamente un cliente. |
| POST | `/api/suppliers` | Crea un proveedor. |
| PUT | `/api/suppliers/:id` | Edita un proveedor activo. |
| DELETE | `/api/suppliers/:id` | Desactiva lógicamente un proveedor. |
| GET | `/api/suppliers/:id` | Proveedor, contacto e insumos activos. |

Parámetros de `/api/purchases`: `q`, `supplier`, `status`
(`pending|processing|finished|all`), `page`, `per_page`.

Ejemplo de pedido:

```json
{
  "supplier_id": 1,
  "notes": "Pedido generado desde reposición sugerida",
  "status": "pending",
  "items": [
    { "input_id": 4, "quantity": 5.65, "unit_cost": 11.5 },
    { "input_id": 2, "quantity": 15, "unit_cost": 4.2 }
  ]
}
```

Respuesta:

```json
{ "ok": true, "purchase_id": 6 }
```

El stock y los costos se actualizan al pasar a `finished`; al reabrir se
revierte el stock. Un pedido con `stock_applied=1` rechaza cambios de ítems y
eliminación hasta ser reabierto. Las bajas de clientes y proveedores son
lógicas (`active=0`) y conservan sus referencias históricas.

`/api/recommendations` devuelve solo insumos activos que cumplen
`stock <= threshold` o `stock <= proyección_14d`, con datos de proveedor,
consumo, última compra y cantidad sugerida.

### 3.5 Ventas y pedidos

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/orders?q=&status=<stage>\|all&page=&per_page=` | Lista ventas y pedidos. `status` filtra por `order_stage` (`draft`, `pending`, `preparing`, `confirmed`, `paid`, `delivered`, `cancel`), por el alias legacy `finished` o por `all`. Cada registro incluye `order_type` (`direct` u `order`), `channel`, `event_id`, `event_name` y datos de anulación. |
| GET | `/api/orders/:id` | Detalle de una venta directa o pedido, con `order_stage`, `order_type`, `channel`, `event_id`, `event_name` y datos de anulación. |
| POST | `/api/orders` | Crea un pedido. Acepta `status` inicial y `event_id` opcional para ferias; desde `confirmed` se descuenta stock del evento o de `SEDE`. |
| PUT | `/api/orders/:id` | Actualiza cliente, pago, descuento o ítems mientras el pedido esté en `draft`, `pending` o `preparing`. |
| PUT | `/api/orders/:id/status` | Cambia el `order_stage` a `draft`, `pending`, `preparing`, `confirmed`, `paid` o `delivered`. `finished` se interpreta como `delivered`. |
| DELETE | `/api/orders/:id` | Baja lógica de pedidos en `draft`, `pending` o `preparing`; exige `reason` y `pin`. |
| POST | `/api/orders/:id/cancel` | Anula cualquier pedido con `reason` y `pin`. |
| POST | `/api/sales/:id/cancel` | Anula una venta directa o un pedido con `reason` y `pin`. |

Etapas de una venta o pedido:

| `order_stage` | Stock | Ingresos | Editable |
|---|---|---|---|
| `draft`, `pending`, `preparing` | No aplicado | No | Sí |
| `confirmed` | Aplicado | No | No |
| `paid`, `delivered` | Aplicado | Sí | No |
| `cancel` | Revertido | No | No |

Las ventas directas (`order_type='direct'`) se crean en `delivered` y no se
editan ni eliminan mediante `/api/orders`; se anulan con
`POST /api/sales/:id/cancel`. La facturación de pedidos usa
`/api/invoices/orders/:id` y la de ventas directas
`/api/invoices/sales/:id`.

Ejemplo de creación:

```json
{
  "customer_id": 0,
  "customer_name": "Cliente Mostrador",
  "customer_type": "Minorista",
  "customer_phone": "555-0100",
  "customer_email": "cliente@example.com",
  "save_customer": 1,
  "payment_method": "Efectivo",
  "discount_type": "percent",
  "discount_value": 5,
  "status": "pending",
  "notes": "Entregar el viernes",
  "event_id": 3,
  "items": [
    { "product_id": 8, "quantity": 2, "unit_price": 150.5 }
  ]
}
```

`customer_id = 0` permite capturar un cliente nuevo y guardarlo con
`save_customer = 1`. Un `unit_price` vacío usa el precio actual del producto.
`event_id` es opcional: si se envía, el pedido queda con `channel="FERIA"` y al
confirmar descuenta `EventStock`; sin evento usa `channel="LOCAL"` y descuenta
`Products.stock`. Al anular se restaura una sola vez en el ámbito correcto.

Ejemplo de cambio de estado:

```json
{ "status": "confirmed" }
```

Ejemplo de anulación:

```json
{
  "reason": "Cobro duplicado en mostrador",
  "pin": "1234"
}
```

La anulación exige un motivo de 3 a 300 caracteres y un PIN válido de un
administrador o supervisor activo. Nunca se borra el registro: se marca
`order_stage='cancel'`, se guarda `cancel_reason`, `cancelled_by`,
`cancel_authorized_by` y `cancelled_at`, y se agrega un evento
`SALE_CANCELLED` u `ORDER_CANCELLED` a `InventoryJournal`. Si el stock estaba
aplicado, se restaura una sola vez.

Errores frecuentes:

- `400`: transición inválida, pedido sin ítems o stock insuficiente.
- `400`: intento de editar un pedido fuera de `draft`, `pending` o `preparing`.
- `400`: motivo o PIN inválido.
- `404`: registro inexistente o venta directa intentando una acción de pedido.

### 3.6 Auditoría y detalles de entidades

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/audit?q=&page=&per_page=` | Lista paginada de `InventoryJournal`. `q` busca en usuario, acción, entidad, payload, estado e ID; `per_page` admite hasta 100. Devuelve `items`, `total`, `page`, `per_page` y `pages`. |
| GET | `/api/users?username=` | Detalle público de un usuario: `id`, `username`, `role` y `created_at` (sin contraseña). |
| GET | `/api/users` | Lista de usuarios con rol, estado y permisos. Solo `admin`. |
| POST | `/api/users` | Crea vendedor o supervisor. Solo `admin`; no permite crear administradores. |
| PUT | `/api/users/:username` | Edita rol, estado y permisos. Solo `admin`; la cuenta administradora solo permite cambiar su PIN. |
| PUT | `/api/users/:username/pin` | Cambia el PIN de un administrador o supervisor. Solo `admin`. |
| GET | `/api/customers/:id` | Ficha de cliente con cantidad de compras, total histórico y últimas 5 ventas. |

La página `/auditoria` consume `/api/audit` y convierte las referencias del
payload en enlaces clicables a productos, usuarios, insumos, proveedores,
clientes, ventas y compras.

Ejemplo de alta de supervisor:

```json
{
  "username": "sup1",
  "password": "clave-segura",
  "role": "supervisor",
  "can_view_metrics": 1,
  "can_manage_stock": 0,
  "pin": "2468"
}
```

El PIN es obligatorio para supervisores y administradores; se usa solo para
autorizar anulaciones. Los vendedores no tienen PIN.

### 3.7 Datos de empresa y facturas

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/business-info` | Datos de la empresa usados en documentos. |
| PUT | `/api/business-info` | Actualiza datos. Requiere rol `admin`. |
| GET | `/api/invoices/purchases/:id` | JSON de factura de compra finalizada con folio `C-000001`. |
| GET | `/api/invoices/orders/:id` | JSON de factura de pedido finalizado con folio `P-000001`. |
| GET | `/api/invoices/sales/:id` | JSON de factura de venta directa finalizada con folio `V-000001`. |

Ejemplo de actualización:

```json
{
  "name": "Aurea Destilería Artesanal",
  "instagram": "@aurea.destileria",
  "facebook": "Aurea Destilería",
  "phone": "+54 11 5555-0101",
  "email": "hola@aurea.example",
  "website": "https://aurea.example"
}
```

Las facturas incluyen los datos de empresa y el detalle de la operación. La
generación de PDF y la impresión se realizan en el navegador sin conexión.
Las facturas de compra solo están disponibles si `status='finished'`. Las de
pedido requieren `order_stage IN ('paid','delivered')`; las de venta directa
requieren `order_stage='delivered'`. En caso contrario responden `409`.

### 3.8 Sincronización

Solo administradores (`role = admin`).

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/sync/status` | Configuración, última sincronización, `pending_events` y `last_remote_journal_id`. |
| POST | `/api/sync/config` | Guarda `url` y, opcionalmente, `token`. Un token vacío conserva el actual; `clear_token=1` lo elimina. |
| POST | `/api/sync/push` | Ejecuta las 3 fases: push de eventos pendientes, pull e-commerce y snapshot de respaldo. |

Códigos esperados:

- `200`: configuración guardada o sincronización completa aceptada.
- `400`: URL/token inválidos o configuración incompleta.
- `401`: sesión inválida.
- `403`: usuario sin rol de administrador.
- `502`: endpoint remoto caído o respuesta no exitosa en alguna fase.

### 3.9 Analítica de canasta

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/dashboard` | Payload compacto del dashboard. La canasta incluye hasta 6 productos, 3 combos y 3 sustitutos. |
| GET | `/api/analytics/basket` | Canasta completa: todos los productos con ventas, matriz de Pearson, combos positivos y sustitutos. |

Cada combo incluye `a_id`, `b_id`, `a_name`, `b_name`, `corr`, `slope`,
`intercept` y `cooccurrence`. Cada sustituto incluye `a_id`, `b_id`, `a_name`,
`b_name`, `corr` y `cov`. Los productos de la matriz incluyen `id`, `name` y
`units`. La página `/inteligencia` consume el endpoint completo; el dashboard
mantiene los límites compactos.

### 3.10 Eventos y ferias

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/events?status=&q=&date_from=&date_to=&page=&per_page=` | Lista paginada de eventos con KPIs y filtros por estado, texto y rango de fecha de inicio. |
| GET | `/api/events/active` | Eventos activos para los selectores de venta/pedido. |
| GET | `/api/events/:id` | Detalle del evento con stock asignado, finanzas, ventas/comprobantes (`sales`) y movimientos auditados (`movements`). |
| POST | `/api/events` | Crea un evento (`name`, `location`, `start_date`, `end_date`, `notes`). |
| POST | `/api/events/:id/stock` | Amplía el stock asignado. Acepta `items: [{product_id, quantity}]` o los arreglos `product_ids`/`quantities`. |
| POST | `/api/events/:id/close` | Cierra un evento; acepta `losses: [{product_id, loss_qty}]` y `backup: 1` para respaldar la base antes del cierre; calcula sobrantes y devuelve stock a `SEDE`. |
| POST | `/api/events/:id/cancel` | Cancela un evento sin ventas ni pérdidas y devuelve el 100 % del stock. |
| GET | `/api/events/:id/stats` | Estadísticas del evento: finanzas, unidades, canales y `series` histórica. |

Ejemplo de cierre:

```json
{
  "losses": [
    { "product_id": 1, "loss_qty": 2 }
  ],
  "backup": 1
}
```

Con `backup: 1` se genera un archivo en `shared/data/backups/` antes de
liquidar; la respuesta incluye `backup_path`. Si el respaldo falla, el cierre
no se ejecuta.

El evento debe estar `active`. El cierre exige que no haya pedidos pendientes ni
devoluciones previas, calcula `returned_qty = allocated_qty - sold_qty - loss_qty`
y guarda `total_revenue_cents`, `total_cogs_cents`, `total_loss_cents` y
`net_profit_cents`. La cancelación solo se permite si `sold_qty=0` y
`loss_qty=0`. Después de `closed` o `cancelled` el evento y su stock son
inmutables.

## 4. Códigos de estado generales

| Código | Significado |
|---|---|
| `200` | Operación exitosa. |
| `201` | Recurso creado. |
| `400` | Datos inválidos o regla de negocio incumplida. |
| `401` | Sesión ausente o expirada. |
| `403` | Rol insuficiente. |
| `404` | Recurso no encontrado. |
| `405` | Método o ruta no permitida. |
| `409` | Conflicto (por ejemplo, factura de compra/pedido/venta no finalizada). |
| `500` | Error interno de base o servidor. |
| `502` | Fallo del endpoint remoto de sincronización. |

## 5. Roles

- `admin`: acceso completo, usuarios, configuración de empresa y
  sincronización. Su PIN se usa para autorizar anulaciones.
- `supervisor`: operación de ventas y pedidos, más `can_view_metrics` y
  `can_manage_stock` configurables. Su PIN puede autorizar anulaciones.
- `vendedor`: operación de ventas y pedidos; siempre sin métricas ni gestión de
  stock. No tiene PIN.

Solo los administradores crean o editan usuarios. Un administrador no puede
crear otro administrador, cambiar su propio rol ni desactivarse desde la API.

Los errores de permisos usan mensajes específicos según la página o API
(`Solo un administrador puede realizar esta acción.`, redirección a `/ventas`,
etc.).
