# Sincronización híbrida con PostgreSQL

La sincronización es manual, iniciada desde el botón **Sincronizar** del
encabezado. Está disponible para administradores y muestra un badge con la
cantidad de movimientos locales pendientes (`pending_events`).

## Flujo en 3 fases

`POST /api/sync/push` ejecuta siempre este orden:

1. **Push de eventos locales (`SQLite -> PostgreSQL`)**
   - Selecciona `InventoryJournal WHERE synced = 0 AND origin = 'LOCAL'`.
   - Envía el lote JSON al endpoint con `mode=events`.
   - PostgreSQL aplica los deltas con `ON CONFLICT (event_uuid) DO NOTHING`.
   - El endpoint responde los `event_uuid` procesados y SQLite los marca
     `synced = 1`.
   - Si la respuesta no incluye `event_uuids`, se marcan los UUID enviados
     (respuesta 2xx = lote aceptado).
2. **Pull de ventas e-commerce (`PostgreSQL -> SQLite`)**
   - Consulta `mode=pull&since_id=<last_remote_journal_id>`.
   - SQLite inserta los eventos remotos con `origin = 'ECOMMERCE'` y
     `synced = 1`, registra `Sales`/`SaleItems` y descuenta stock **solo de
     `SEDE`**. Nunca modifica `EventStock` de una feria.
   - El cursor `last_remote_journal_id` se guarda en `AppContext`.
3. **Snapshot de respaldo**
   - Envía el snapshot completo (`mode=snapshot`) con `events` y
     `event_stock`.
   - El resultado se audita en `SyncLog`.

Cada fase falla de forma independiente. Si una falla, se registra
`status = error` en `SyncLog`, se conservan los pendientes locales y la
operación local continúa sin bloqueos. Las llamadas usan
`--connect-timeout 4 --max-time 15`.

## Endpoint

La URL se compone agregando parámetros a la URL configurada:

- `...?source=sqlite&schema_version=8&mode=events`
- `...?source=sqlite&schema_version=8&mode=pull&since_id=42`
- `...?source=sqlite&schema_version=8&mode=snapshot`

Todas las peticiones envían:

- `Content-Type: application/json`
- `Accept: application/json`
- `Authorization: Bearer <token>` y `apikey: <token>` si hay token
- `X-ERP-Source: aurea-sqlite`

### Fase 1: `mode=events`

```json
{
  "source": "sqlite",
  "schema_version": 8,
  "events": [
    {
      "id": 123,
      "event_uuid": "2f1c9d7e-4a1b-4c3d-8e5f-1234567890ab",
      "timestamp": "2026-11-24 10:15:00",
      "user": "admin",
      "action": "TRANSFER_OUT",
      "entity": "EventStock",
      "payload": {
        "event_id": 3,
        "product_id": 1,
        "qty": 4,
        "stock_delta": -4,
        "location": "FERIA"
      },
      "status": "DONE",
      "origin": "LOCAL",
      "synced": 0
    }
  ]
}
```

Respuesta esperada:

```json
{ "ok": true, "event_uuids": ["2f1c9d7e-4a1b-4c3d-8e5f-1234567890ab"] }
```

### Fase 2: `mode=pull`

Respuesta esperada:

```json
{
  "ok": true,
  "last_remote_journal_id": 100,
  "events": [
    {
      "remote_id": 100,
      "event_uuid": "cccccccc-dddd-4eee-8fff-111111111111",
      "action": "ECOMMERCE_SALE",
      "payload": {
        "timestamp": "2026-11-24 11:00:00",
        "customer_id": null,
        "total": 30.00,
        "payment_method": "Tarjeta",
        "items": [
          { "product_id": 4, "quantity": 1, "unit_price": 30.00 }
        ]
      }
    }
  ]
}
```

También se acepta un único producto por evento con `product_id`, `quantity` y
`unit_price` en el nivel superior del `payload`. Para movimientos de stock se
usa `action = "ECOMMERCE_STOCK"` y `payload = {"product_id":4,"stock_delta":-2}`.
Los eventos ya presentes por `event_uuid` se ignoran (idempotencia).

### Fase 3: `mode=snapshot`

Se envía el snapshot completo:

```json
{
  "source": "sqlite",
  "schema_version": 8,
  "generated_at": "2026-11-24 12:00:00",
  "last_journal_id": 1234,
  "tables": {
    "categories": [],
    "suppliers": [],
    "customers": [],
    "inputs": [],
    "products": [],
    "product_recipe": [],
    "product_recipe_steps": [],
    "combo_items": [],
    "business_info": [],
    "sales": [],
    "sale_items": [],
    "production_batches": [],
    "production_inputs": [],
    "purchases": [],
    "purchase_items": [],
    "tasting_feedback": [],
    "events": [],
    "event_stock": [],
    "inventory_journal": []
  }
}
```

Las ventas incluyen `event_id` y `channel`; los eventos incluyen sus KPIs en
centavos y `event_stock` incluye cantidades asignadas, vendidas, perdidas,
devueltas y el costo congelado. El journal incluye `event_uuid`, `origin` y
`synced`.

## Idempotencia

- `event_uuid` es único en SQLite y en PostgreSQL.
- La función remota inserta primero en el ledger de deduplicación con
  `ON CONFLICT (event_uuid) DO NOTHING`.
- Si el UUID ya existe, no se aplica el delta ni se duplican ventas o stock.
- SQLite solo marca `synced = 1` después de una respuesta 2xx.
- Reintentar una sincronización es seguro.

## Respaldo en caliente

```bash
./erp.sh backup [ruta]
```

Sin ruta genera `shared/data/backups/erp_licores_YYYYmmdd_HHMMSS.db`. Usa
`sqlite3 .backup` cuando el binario está disponible; con el shim de Node usa
`VACUUM INTO`, que también produce una copia consistente de la base WAL.

## Seguridad

- La URL debe ser `http` o `https`; se recomienda HTTPS.
- El token se guarda en `AppContext` y no se devuelve en `/api/sync/status`;
  solo se informa si está configurado.
- El endpoint debe rechazar peticiones sin token y limitar el tamaño del cuerpo.
- El token no se escribe en los logs del servidor.

## Prueba local

```bash
socat TCP-LISTEN:8100,fork,reuseaddr SYSTEM:'./tests/mock_sync.sh'
```

Luego guardar la URL desde la interfaz o con:

```bash
curl -s -b cookies.txt -H 'Content-Type: application/json' \
  -d '{"url":"http://127.0.0.1:8100/sync","token":"demo"}' \
  http://127.0.0.1:8080/api/sync/config

curl -s -b cookies.txt -X POST http://127.0.0.1:8080/api/sync/push
curl -s -b cookies.txt http://127.0.0.1:8080/api/sync/status
```

## Limitaciones

- El pull solo aplica ventas e-commerce y deltas de stock `SEDE`; las
  asignaciones a ferias se crean localmente.
- No hay resolución automática de conflictos: el último snapshot gana.
- Las eliminaciones locales no se propagan por el snapshot.
- La disponibilidad depende de que el endpoint HTTP esté en línea.
