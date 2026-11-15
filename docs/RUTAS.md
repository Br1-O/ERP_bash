# Rutas y API

Todas las rutas privadas requieren la cookie de sesión `erp_session`.

## Páginas

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/` | Redirige a `/dashboard`. |
| GET | `/login` | Formulario de acceso. |
| POST | `/login` | Autentica y crea la sesión. |
| GET/POST | `/logout` | Cierra la sesión. |
| GET | `/dashboard?tab=resumen\|stock\|catalogo\|agenda` | Dashboard analítico. |
| GET | `/inventario` | Productos, insumos, recetas y lotes. |
| GET | `/compras` | Compras, proveedores y recomendaciones. |
| GET | `/ventas` | Pedidos de clientes, estados y facturación. |
| GET | `/contactos` | Agenda de clientes y proveedores. |
| GET | `/configuracion` | Datos de la empresa para facturación. |

## Assets

| Ruta | Contenido |
|---|---|
| `/assets/app.css` | Estilos globales, componentes y responsive. |
| `/assets/app.js` | Dashboard, ventas, contactos y sincronización. |
| `/assets/billing.js` | Patrón Money y estrategias de descuento. |
| `/assets/components.js` | Carga/utilidades de web components. |
| `/components/<componente>/<archivo>.js\|css\|html` | Assets de componentes. |

## API

### Autenticación y estado

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/health` | Estado básico del servicio. |
| GET | `/api/dashboard` | Payload completo del dashboard. |
| GET | `/api/alerts` | Alertas de stock de productos e insumos. |
| GET | `/api/contacts?q=` | Búsqueda de clientes y proveedores. |

### Inventario y catálogo

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/products` | Lista de productos con `stock` disponible, `physical_stock` e `is_combo`. |
| GET | `/api/products/:id` | Detalle de producto, receta, pasos y componentes. |
| POST | `/api/products` | Crea un producto simple o combo. Acepta `is_combo`, `recipe_description`, `steps_text`, `recipe_ids`/`recipe_qtys` y `component_ids`/`component_qtys`. |
| PUT | `/api/products/:id` | Actualiza producto, receta, pasos y componentes. |
| DELETE | `/api/products/:id` | Elimina un producto. |
| POST | `/api/products/:id/stock` | Ajusta stock de productos simples. Los combos no admiten ajuste directo. |
| GET | `/api/inputs` | Lista de insumos. |
| GET | `/api/inputs/:id` | Detalle de insumo. |
| POST | `/api/inputs` | Crea un insumo. |
| PUT | `/api/inputs/:id` | Actualiza un insumo. |
| DELETE | `/api/inputs/:id` | Elimina un insumo. |
| POST | `/api/inputs/restock` | Repone stock de un insumo. |
| GET | `/api/inventory/products` | Productos con receta para la vista de inventario. |
| GET | `/api/inventory/inputs` | Insumos para la vista de inventario. |
| GET | `/api/inventory/meta` | Categorías, proveedores y metadatos. |

### Producción y ventas

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/api/production` | Registra un lote y consume insumos. |
| POST | `/api/sales` | Registra una venta con descuento opcional. |

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

### Compras y contactos

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/purchases` | Lista de compras. |
| GET | `/api/purchases/:id` | Detalle de compra. |
| POST | `/api/purchases` | Registra una compra y actualiza stock. |
| GET | `/api/recommendations` | Recomendaciones de reposición. |
| POST | `/api/customers` | Crea un cliente. |
| POST | `/api/suppliers` | Crea un proveedor. |

### Pedidos de clientes

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/orders?status=pending\|finished\|cancel\|all` | Lista pedidos con cliente e ítems. |
| GET | `/api/orders/:id` | Detalle del pedido. |
| POST | `/api/orders` | Crea un pedido; el stock se descuenta al pasar a `finished`. |
| PUT | `/api/orders/:id` | Actualiza cliente, pago, descuento o ítems mientras no tenga stock aplicado. |
| PUT | `/api/orders/:id/status` | Cambia estado a `pending`, `finished` o `cancel`. |
| DELETE | `/api/orders/:id` | Elimina pedidos sin stock aplicado. |

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
  "items": [
    { "product_id": 8, "quantity": 2, "unit_price": 150.5 }
  ]
}
```

`customer_id = 0` permite capturar un cliente nuevo y guardarlo con
`save_customer = 1`. Un `unit_price` vacío usa el precio actual del producto.
Al finalizar se descuenta el stock, incluidos los componentes de combos; al
cancelar o reabrir se restaura una sola vez.

### Datos de empresa y facturas

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/business-info` | Datos de la empresa usados en documentos. |
| PUT | `/api/business-info` | Actualiza datos. Requiere rol `admin`. |
| GET | `/api/invoices/purchases/:id` | JSON de factura de compra con folio `C-000001`. |
| GET | `/api/invoices/orders/:id` | JSON de factura de pedido finalizado con folio `P-000001`. |

Las facturas incluyen los datos de empresa y el detalle de la operación. La
generación de PDF y la impresión se realizan en el navegador sin conexión.

### Sincronización

Solo administradores (`role = admin`).

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/sync/status` | Configuración y última sincronización. |
| POST | `/api/sync/config` | Guarda `url` y, opcionalmente, `token`. Un token vacío conserva el actual; `clear_token=1` lo elimina. |
| POST | `/api/sync/push` | Envía el snapshot local al endpoint. |

Códigos esperados:

- `200`: configuración guardada o snapshot aceptado.
- `400`: URL/token inválidos o configuración incompleta.
- `401`: sesión inválida.
- `403`: usuario sin rol de administrador.
- `502`: endpoint remoto caído o respuesta no exitosa.
