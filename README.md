# Aurea ERP · Licorería artesanal

ERP offline-first para una tienda de licores artesanales. La interfaz, la lógica
de negocio y la persistencia están implementadas con Bash, HTML, CSS, JavaScript
y SQLite. No requiere Python ni frameworks externos.

## Requisitos

- Bash 4 o superior.
- `socat` para el servidor HTTP.
- `curl` para la sincronización con PostgreSQL.
- `sqlite3` **o** Node.js 22+ con `node:sqlite`. Si el binario `sqlite3` no está
  instalado, se usa automáticamente `tools/sqlite3_shim.js`.

## Inicio rápido

```bash
./erp.sh                 # servidor web en http://localhost:8080
./erp.sh server 8099     # servidor web en otro puerto
./erp.sh init            # crea/verifica la base y datos demo
./erp.sh cli             # interfaz de terminal
./erp.sh help
```

Credenciales demo:

- Administrador: `admin / admin123`
- Cajero: `cajero / cajero123`

La base se guarda en `shared/data/erp_licores.db`. Para reiniciar los datos demo:

```bash
rm -f shared/data/erp_licores.db
./erp.sh init
```

## Arquitectura

```text
config.sh                 carga centralizada de módulos
model/                    esquema, singleton SQLite, transacciones
repositories/             acceso local y remoto (patrón Repository)
api/                      autenticación, inventario, compras, ventas, sync
frontend/                 router, vistas, assets y componentes web
shared/utils/             JSON, HTTP, validaciones y helpers
tools/sqlite3_shim.js     compatibilidad SQLite con node:sqlite
router.sh                 entrada usada por socat
```

Flujo de una petición HTTP:

1. `socat` ejecuta `frontend/router.sh` una vez por conexión.
2. El router carga `config.sh`, inicializa la base y resuelve la ruta.
3. Las APIs usan las funciones de `api/` y el singleton de `model/`.
4. Las vistas devuelven HTML; los assets se sirven desde `frontend/assets/` y
   `frontend/components/`.

## Funcionalidad

- Dashboard con KPIs, series diarias, stock crítico, recomendaciones, ventas
  recientes y auditoría.
- Inventario de productos e insumos, recetas, pasos de preparación, combos,
  lotes de producción y ajustes de stock.
- Compras con proveedores, detalle de insumos, reposición sugerida, mensajes
  generados y factura/PDF.
- Agenda de clientes y proveedores.
- Ventas directas y pedidos con múltiples ítems, estados, métodos de pago,
  descuentos y descuento/restauración automática de stock.
- Facturación de compras y pedidos finalizados con PDF generado en el navegador.
- Configuración de datos de la empresa para los documentos.
- Analítica estadística: medidas descriptivas, intervalos de confianza,
  binomial, regresión, correlaciones y análisis de canasta.
- Sincronización manual con PostgreSQL desde la interfaz, con estado y bitácora.

## Facturación y descuentos

Los importes se calculan en centavos para evitar errores de punto flotante. Las
estrategias de descuento viven en `api/billing.sh` y en
`frontend/assets/billing.js`:

- `none`: sin descuento.
- `percent`: porcentaje entre 0 y 100.
- `fixed`: monto fijo que no puede superar el subtotal.

El servidor siempre recalcula subtotal, descuento y total; la interfaz solo
muestra una previsualización. Las ventas guardan `subtotal_amount`,
`discount_type`, `discount_value`, `discount_amount`, `total_amount`,
`status`, `stock_applied` y `order_type` (esquema v5).

## Sincronización con PostgreSQL

El botón **Sincronizar** del encabezado está disponible para administradores.
Permite guardar la URL de un endpoint y un token, y enviar un snapshot JSON
idempotente de la base local.

- El ERP **no** abre una conexión directa al protocolo PostgreSQL.
- Compone la URL con `source=sqlite`, `schema_version` y `mode=snapshot`.
- Envía `Authorization: Bearer <token>` y `apikey: <token>`.
- El endpoint debe aceptar `POST` con JSON y aplicar UPSERT en PostgreSQL.
- Si no hay conexión, la operación falla sin borrar ni bloquear datos locales y
  queda registrada en `SyncLog`.

El contrato de referencia y el SQL para PostgreSQL están en
`docs/SYNC_POSTGRES.sql`. El detalle de la integración está en
`docs/SINCRONIZACION.md`.

## Verificación

```bash
bash -n config.sh erp.sh server.sh frontend/router.sh
node --check frontend/assets/app.js
node --check frontend/assets/billing.js
node --check frontend/components/order-manager/order-manager.js
node --check frontend/components/invoice-generator/invoice-generator.js
./erp.sh init
```

Pruebas funcionales sin navegador automatizado:

```bash
curl -s -c /tmp/erp-cookies.txt \
  -d 'username=admin&password=admin123' \
  http://127.0.0.1:8080/login

curl -s -b /tmp/erp-cookies.txt http://127.0.0.1:8080/api/sync/status
```

## Empaquetado

```bash
./bundle.sh
```

Genera `erp-licores-standalone.tar.gz` sin la base de datos. El paquete incluye
código, componentes, documentación y el shim de SQLite; la base se crea al
iniciar.
