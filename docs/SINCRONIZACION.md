# Sincronización con PostgreSQL

La sincronización es manual, iniciada desde el botón **Sincronizar** del
encabezado. Solo está disponible para usuarios con rol `admin`.

## Flujo

1. El administrador guarda la URL del endpoint y, opcionalmente, un token.
2. El ERP construye un snapshot JSON completo de las tablas de negocio.
3. Se compone la URL:
   `https://host/ruta?source=sqlite&schema_version=5&mode=snapshot`
4. Se envía `POST` con:
   - `Content-Type: application/json`
   - `Authorization: Bearer <token>`
   - `apikey: <token>`
   - `X-ERP-Source: aurea-sqlite`
5. El endpoint valida el token, aplica UPSERT y responde `2xx`.
6. El resultado se guarda en `SyncLog` y se muestra en el modal.

La operación es idempotente: enviar el mismo snapshot dos veces no duplica
filas porque las tablas usan IDs estables y `ON CONFLICT (id) DO UPDATE`.

## Snapshot

```json
{
  "source": "sqlite",
  "schema_version": 5,
  "generated_at": "2026-11-11 18:30:00",
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
    "inventory_journal": []
  }
}
```

No se envían usuarios, sesiones, configuración local ni la bitácora de
sincronización. Las ventas incluyen subtotal, tipo/valor de descuento, descuento,
total, estado, `stock_applied` y `order_type`. Los productos incluyen
`recipe_description` e `is_combo`; los pasos de receta, componentes de combos y
datos de empresa se envían en sus propias tablas.

## Offline-first

- SQLite sigue siendo la fuente local y nunca se bloquea por falta de red.
- Si el endpoint falla, se registra `status = error` en `SyncLog`.
- La siguiente sincronización reenvía el snapshot completo; no hay una cola de
  eventos que pueda quedar corrupta.
- No se eliminan datos locales al sincronizar.

## Contrato del endpoint

El endpoint debe aceptar el snapshot **tal cual** en el cuerpo HTTP y ejecutar:

```sql
SELECT erp.sync_snapshot($1::jsonb);
```

El SQL de referencia está en `docs/SYNC_POSTGRES.sql`. Puede implementarse con
una función serverless, un servicio propio o un adaptador HTTP sobre PostgreSQL.
No se usa el protocolo nativo de PostgreSQL porque el ERP solo depende de Bash,
JS, HTML, CSS, SQLite y `curl`.

La función remota no borra filas ausentes en el snapshot. Si se necesita un
espejo exacto, agregar una política de borrado explícita y auditable; no se hace
por defecto para evitar pérdidas de datos.

## Seguridad

- La URL debe ser `http` o `https`; se recomienda HTTPS.
- El token se guarda en `AppContext` de la base local y no se devuelve en
  `/api/sync/status`; solo se informa si está configurado.
- El endpoint debe rechazar peticiones sin token y limitar el tamaño del cuerpo.
- El token no se escribe en los logs del servidor.

## Prueba local

Se puede usar un mock HTTP en Bash con `socat`:

```bash
socat TCP-LISTEN:8100,fork,reuseaddr SYSTEM:'./tests/mock_sync.sh'
```

Luego guardar `http://127.0.0.1:8100/sync` desde la interfaz o con:

```bash
curl -s -b cookies.txt -H 'Content-Type: application/json' \
  -d '{"url":"http://127.0.0.1:8100/sync","token":"demo"}' \
  http://127.0.0.1:8080/api/sync/config

curl -s -b cookies.txt -X POST http://127.0.0.1:8080/api/sync/push
```

## Limitaciones

- Es un snapshot completo, no replicación incremental en tiempo real.
- No hay resolución automática de conflictos: el último UPSERT gana.
- Las eliminaciones locales no se propagan.
- La disponibilidad depende de que el endpoint HTTP esté en línea.
