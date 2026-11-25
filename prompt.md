# Prompt Maestro de Evolución: Módulo de Eventos/Ferias, Segmentación Temporal de Stock, Replicación Híbrida y Patrones de Resiliencia (Esquema v8)

Actúa como un Arquitecto de Software Senior experto en **Bash 4+**, **SQLite (WAL + Triggers ACID)**, **socat**, **Web Components nativos** y **arquitecturas distribuidas offline-first (Master Local + Réplica Web PostgreSQL)**.

Necesito evolucionar el ERP **Aurea Destilería Artesanal** (`ERP_bash`, actualmente en `ERP_SCHEMA_VERSION=7`) hacia la versión **8**, incorporando un sistema completo de **Eventos / Ferias con Segmentación Temporal de Stock**, **Replicación Híbrida Idempotente (Event Log por Deltas + Snapshot)** y **Patrones de Diseño para Resiliencia Operativa**, manteniendo estrictamente las restricciones del proyecto (solo **Bash, SQLite, socat, curl, HTML/CSS/JS nativo**, sin Python ni dependencias externas, dinero en centavos del lado del servidor y arquitectura MVC / Repositorios).

---

## 1. Problema de Negocio y Semántica de Stock (Cero Gaps)

Cuando el emprendimiento asiste a una feria, evento o degustación, necesita apartar una fracción del inventario físico para llevarlo al evento sin que el canal general (tienda / ecommerce) sufra sobreventas ni desfasajes de inventario:

1. **Reserva / Segmentación (`SEDE` -> `FERIA`):** Al crear un evento, se apartan unidades específicas de productos simples hacia el evento. Ese stock deja de estar disponible para la venta general (`Products.stock` / depósito `SEDE` disminuye) y pasa a formar parte del stock exclusivo del evento (`EventStock`).
2. **Operación en Feria (Offline-First):** Desde la sección `/ventas`, los usuarios con acceso a ventas pueden operar sobre una pestaña/selector de **Segmentación Activa (Evento)**. Al registrar una venta directa vinculada a un evento:
   - El descuento de stock se ejecuta exclusivamente sobre el stock apartado del evento (`EventStock`), comportándose visual y operativamente como si fuera el inventario total disponible en la feria.
   - Sin embargo, la venta se registra en `Sales` como una venta real de la empresa (`event_id` asociado y canal `'FERIA'`), impactando en la facturación general, comprobantes (`V-*`), descuentos, auditoría (`InventoryJournal`) y reportes globales.
3. **Cierre y Liquidación de Evento:** Al finalizar el evento, el usuario cierra la sesión itinerante informando si existieron **mermas o pérdidas** (botellas rotas, degustación sin cargo, etc.) por producto:
   - Se valida que `vendido + merma <= apartado_inicial` (y en el cierre se calcula `sobrante = apartado_inicial - vendido - merma`).
   - El **stock sobrante sano** (`sobrante`) retorna automáticamente al inventario general (`Products.stock` / depósito `SEDE`).
   - Las mermas quedan registradas con su impacto económico (costo perdido) en el cierre del evento.
   - Se calculan y muestran los KPIs definitivos del evento (ingresos brutos, costo de mercadería vendida, costo de mermas, ganancia neta, tasa de conversión de stock llevado vs. vendido y tasa de merma).

---

## 2. Actualización del Modelo de Datos (`model/schema.sh` -> v8)

Actualiza `ERP_SCHEMA_VERSION=8` con migración segura de datos legacy y nuevos triggers:

1. **Evolución de `InventoryJournal` (Motor de Replicación):**
   - Agregar `event_uuid TEXT UNIQUE` (generado automáticamente en SQLite mediante `lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))` en los triggers cuando no venga provisto).
   - Agregar `origin TEXT NOT NULL DEFAULT 'LOCAL'` (`'LOCAL'`, `'WEB'`, `'ECOMMERCE'`).
   - Agregar `synced INTEGER NOT NULL DEFAULT 0` (`0` = pendiente de Push, `1` = sincronizado).
   - Asegurar que `payload` almacene **JSON estructurado con deltas explícitos** (ej. `{"product_id":1,"delta":-2,"location":"FERIA","event_id":3}`) para que PostgreSQL aplique variaciones relativas sin recalcular fórmulas.

2. **Nueva tabla `Events` (Ferias / Eventos Itinerantes):**
   - `id` INTEGER PK AUTOINCREMENT
   - `name` TEXT NOT NULL
   - `location` TEXT
   - `start_date` DATETIME NOT NULL
   - `end_date` DATETIME
   - `status` TEXT NOT NULL DEFAULT `'active'` (`'active'`, `'closed'`, `'cancelled'`)
   - `notes` TEXT
   - `created_by` TEXT NOT NULL
   - `closed_by` TEXT
   - `total_revenue_cents` INTEGER DEFAULT 0
   - `total_cogs_cents` INTEGER DEFAULT 0
   - `total_loss_cents` INTEGER DEFAULT 0
   - `net_profit_cents` INTEGER DEFAULT 0

3. **Nueva tabla `EventStock` (Depósito Temporal de Feria):**
   - `id` INTEGER PK AUTOINCREMENT
   - `event_id` INTEGER NOT NULL FK `Events(id)` ON DELETE CASCADE
   - `product_id` INTEGER NOT NULL FK `Products(id)`
   - `allocated_qty` INTEGER NOT NULL CHECK (`allocated_qty > 0`)
   - `sold_qty` INTEGER NOT NULL DEFAULT 0 CHECK (`sold_qty >= 0`)
   - `loss_qty` INTEGER NOT NULL DEFAULT 0 CHECK (`loss_qty >= 0`)
   - `returned_qty` INTEGER NOT NULL DEFAULT 0 CHECK (`returned_qty >= 0`)
   - `unit_cost_snapshot` REAL NOT NULL
   - `UNIQUE(event_id, product_id)`
   - *Stock disponible en feria:* `allocated_qty - sold_qty - loss_qty - returned_qty`.

4. **Modificación en `Sales`:**
   - Agregar `event_id` INTEGER NULL FK `Events(id)` (si es `NULL`, opera sobre el depósito `SEDE` / tienda general; si tiene ID, opera sobre el depósito `FERIA` de ese evento).
   - Agregar `channel` TEXT NOT NULL DEFAULT `'LOCAL'` (`'LOCAL'`, `'FERIA'`, `'ECOMMERCE'`).

5. **Triggers ACID Obligatorios:**
   - **`trg_event_stock_allocate_ai`:** Valida que el producto sea simple (`is_combo = 0`), activo y con `Products.stock >= NEW.allocated_qty`; descuenta `NEW.allocated_qty` de `Products.stock` (transferencia `SEDE -> FERIA`) e inserta en `InventoryJournal` con `action='TRANSFER_OUT'` y payload JSON delta.
   - **`trg_saleitems_stock` y `trg_saleitems_after_insert` (Bifurcación por Canal):**
     - Si `Sales.event_id IS NULL`: valida y descuenta contra `Products.stock` (`SEDE`).
     - Si `Sales.event_id IS NOT NULL`: verifica que `Events.status = 'active'`, valida disponibilidad en `EventStock` (o de cada componente en `EventStock` si se vende un combo en la feria) e incrementa `EventStock.sold_qty` sin tocar `Products.stock`.
   - **Reintegro y Auditoría de Cierre:** Al cerrar el evento (`status = 'closed'`), devuelve `returned_qty` a `Products.stock` (`TRANSFER_RETURN`) y registra el delta JSON en `InventoryJournal`.

---

## 3. Servicios de Negocio, Analítica y Sincronización Bidireccional (`api/` y `repositories/`)

1. **Servicio de Eventos (`api/api_events.sh`):**
   - `events_list_paginated`: Listado con filtros (`q`, `status=active|closed|all`, fechas) y paginación estándar (`items, total, page, per_page, pages`).
   - `events_create`: Transacción ACID que crea el evento y aparta los ítems en `EventStock`.
   - `events_add_stock`: Permite transferir más unidades desde `SEDE` hacia un evento activo.
   - `events_close`: Recibe pérdidas/roturas por producto `[{product_id, loss_qty}]`, valida `sold_qty + loss_qty <= allocated_qty`, calcula `returned_qty = allocated_qty - sold_qty - loss_qty`, reintegra el sobrante sano a `Products.stock`, liquida ingresos/costos/pérdidas/ganancia neta en centavos y retorna los KPIs del evento cerrado.

2. **Actualización en `api/api_sales.sh` y `api/api_orders.sh`:**
   - Permitir recibir `event_id` opcional en `POST /api/sales`. Si `event_id` está presente, exigir que el evento esté en estado `'active'` y validar disponibilidad contra `EventStock`.

3. **Sincronización Híbrida Push + Pull (`api/api_sync.sh`, `repositories/local_repository.sh`, `repositories/postgres_repository.sh`):**
   - Implementar un flujo ordenado en **3 fases** al ejecutar `POST /api/sync/push` (o comando de sincronización):
     1. **Fase 1 — Push de Eventos Locales (`SQLite -> PostgreSQL`):** Selecciona `SELECT * FROM InventoryJournal WHERE synced = 0 AND origin = 'LOCAL' ORDER BY id ASC`. Envía el lote en JSON al endpoint remoto; PostgreSQL aplica los deltas idempotentemente usando `ON CONFLICT (event_uuid) DO NOTHING` y responde con los `event_uuid` procesados para que SQLite los marque `synced = 1`.
     2. **Fase 2 — Pull de Ventas E-commerce (`PostgreSQL -> SQLite`):** Consulta al endpoint remoto los eventos creados online (`origin = 'ECOMMERCE'`) posteriores al último `last_remote_journal_id` guardado en `AppContext`. SQLite los inserta en `InventoryJournal` (`synced = 1`), registra las ventas en `Sales`/`SaleItems` y descuenta los deltas exclusivamente del stock `SEDE` (sin afectar nunca el stock apartado en `FERIA`).
     3. **Fase 3 — Snapshot de Respaldo:** Envía el snapshot completo (incluyendo `events` y `event_stock`) como respaldo consolidado y lo audita en `SyncLog`.

4. **Motor Estadístico de Eventos (`api/analytics.sh`):**
   - Implementar `analytics_events_summary_json` para calcular sobre el historial de eventos:
     - **KPIs Consolidados:** Cantidad de eventos, ingresos brutos totales, ganancia neta acumulada, margen neto promedio, tasa de conversión de inventario (`vendido / apartado %`) y tasa de merma (`merma / apartado %`).
     - **Medidas de Centralización y Dispersión (Unidad 1):** Media ($\bar{x}$), Mediana, Rango, Desvío Estándar Muestral ($s$) y Coeficiente de Variación ($CV\%$) de la **ganancia neta por evento** y de las **unidades vendidas por evento**.
     - **Comparativa de Canales:** Desglose de ventas entre `SEDE`, `FERIA` y `ECOMMERCE`.

---

## 4. Rutas y Frontend (Web Components + UI Responsiva)

1. **Nuevas Rutas en `frontend/router.sh`:**
   - `GET /eventos` -> Vista dedicada a gestión e historial de eventos (`frontend/views/events.sh`).
   - `GET /api/events` -> Listado paginado + resumen estadístico global de eventos.
   - `GET /api/events/:id` -> Detalle de stock apartado, vendido, mermas, devuelto, ventas y KPIs del evento.
   - `POST /api/events` -> Alta de evento y asignación de stock inicial.
   - `POST /api/events/:id/stock` -> Transferir stock adicional desde `SEDE` al evento activo.
   - `POST /api/events/:id/close` -> Liquidación y cierre del evento con declaración de pérdidas.

2. **Integración en `/ventas` (`frontend/components/order-manager/`):**
   - Añadir un selector/pestaña superior de canal operativo: **"Canal de Venta: Tienda General (SEDE) | Evento / Feria Activa [Selector]"**.
   - Al elegir un evento activo, la venta directa opera exclusivamente contra el stock disponible de ese evento (`EventStock`), manteniendo el flujo cotidiano intacto (clientes, descuentos en centavos, medios de pago y comprobante `V-*`).
   - En el historial de `/ventas`, mostrar un badge indicando el canal (`Tienda`, `Feria: <Nombre>`, `E-commerce`).

3. **Nueva Sección `/eventos` en el Menú Lateral (`frontend/components/event-manager/`):**
   - **Resumen Analítico General (Cabecera):** Tarjetas de KPIs globales de todos los eventos juntos, tabla de medidas de centralización y dispersión ($\bar{x}$, Mediana, $s$, $CV\%$), y gráficos SVG/CSS nativos (barras comparativas de ingresos vs. ganancia neta por evento y gráfico de torta de distribución vendido / reintegrado / merma).
   - **Histórico Paginado y Filtrable:** Uso de `<erp-pagination>` y filtros por estado (`Todos`, `Activos`, `Finalizados`) y búsqueda por nombre/ubicación.
   - **Modales con `<erp-modal>`:**
     - **Alta de Evento:** Formulario para nombre, lugar, fechas y selección de productos con cantidades a apartar (validando stock disponible en `SEDE`).
     - **Cierre y Liquidación de Evento:** Tabla interactiva por producto mostrando `Apartado` y `Vendido`, con campo numérico para declarar `Pérdidas/Roturas`, previsualizando en tiempo real el `Sobrante a reintegrar a SEDE` y la `Ganancia Neta final`.
     - **Detalle de Evento:** Vista completa de métricas, movimientos y comprobantes emitidos en esa feria.

---

## 5. Patrones de Diseño y Resiliencia Operativa (Obligatorios en v8)

Para garantizar tolerancia a fallos en ferias itinerantes, cortes de energía o conectividad intermitente sin dependencias externas, implementa los siguientes patrones arquitectónicos:

1. **Transactional Outbox Pattern (`InventoryJournal` + Triggers ACID):**
   - Toda mutación de negocio (`Sales`, `EventStock`, `ProductionBatches`, `Purchases`, `Products`) y su correspondiente inserción en `InventoryJournal` (`event_uuid`, `origin`, `synced=0`, `payload` JSON con delta) deben ejecutarse **dentro de la misma transacción SQLite** (`tx_begin` ... `tx_commit`).
   - De este modo es imposible que exista una venta o transferencia de stock sin su evento de replicación encolado, incluso ante un apagón repentino.

2. **Idempotency Key & Dedup Ledger en PostgreSQL (`docs/SYNC_POSTGRES.sql`):**
   - El campo `event_uuid` funciona como clave de idempotencia global.
   - En la función remota `erp.sync_snapshot` / `erp.apply_events`, antes de aplicar cualquier delta sobre las tablas espejo (`stock = stock + delta`), inserta o verifica `event_uuid` con `ON CONFLICT (event_uuid) DO NOTHING`. Si el evento ya fue procesado en un intento previo interrumpido por red, ignora el efecto lateral sin duplicar ventas ni stock y retorna `200 OK` con el UUID confirmado para que SQLite marque `synced = 1`.

3. **State Machine (Máquina de Estados Estricta) para `Events`:**
   - Implementa validación de transiciones tanto en `api/api_events.sh` como mediante triggers `BEFORE UPDATE` en SQLite:
     - `active` -> `closed` (requiere liquidación de sobrantes/mermas y reintegro de stock).
     - `active` -> `cancelled` (solo permitido si `sold_qty = 0` en todos sus ítems; devuelve el 100% de `allocated_qty` a `Products.stock`).
     - Prohibido cualquier retroceso o modificación una vez que `status IN ('closed', 'cancelled')` (inmutabilidad histórica).

4. **Snapshot de Costo Histórico y Patrón Money (Enteros en Centavos):**
   - Todo cálculo financiero de eventos (`total_revenue_cents`, `total_cogs_cents`, `total_loss_cents`, `net_profit_cents`) se calcula en enteros (centavos) en el servidor usando `api/billing.sh` y tomando `EventStock.unit_cost_snapshot` (congelado al momento de apartar la mercadería), evitando que cambios posteriores en el costo de insumos alteren la rentabilidad histórica de ferias pasadas.

5. **Graceful Degradation, Indicador de Pendientes y Backup Atómico:**
   - **Tolerancia a desconexión:** Las llamadas `curl` en `pg_repo_push` deben usar timeouts cortos (`--connect-timeout 4 --max-time 15`). Ante fallo de red, se registra `status='error'` en `SyncLog`, se conservan los registros con `synced = 0` intactos y la operación local continúa sin bloqueos.
   - **Visibilidad de estado:** Exponer en `GET /api/sync/status` el contador `pending_events` (`SELECT COUNT(*) FROM InventoryJournal WHERE synced = 0 AND origin = 'LOCAL'`) y mostrar un badge en el botón **Sincronizar** del encabezado para saber en todo momento cuántos movimientos faltan respaldar en la nube.
   - **Respaldo seguro en caliente:** Agregar un subcomando `./erp.sh backup [ruta]` (y opción previa al cierre de evento) que ejecute `sqlite3 "$DB_PATH" ".backup '$DEST'"` para generar una copia íntegra y consistente de la base WAL antes o después de trasladar el equipo a una feria.

---

## 6. Documentación y SQL Remoto

Actualiza `docs/SYNC_POSTGRES.sql` (incorporando `event_uuid`, `origin`, tablas `events` y `event_stock`, y la lógica de aplicación de deltas idempotentes), los documentos técnicos en `docs/` (`ARQUITECTURA.md`, `BASE_DE_DATOS.md`, `RUTAS.md`, `ESTADISTICA.md`, `SINCRONIZACION.md`) y el `README.md` principal para reflejar la versión **8**.