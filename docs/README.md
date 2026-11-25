# Documentación del ERP

Documentación vigente del ERP offline-first **Aurea Destilería Artesanal**.
La fuente de verdad del esquema es `model/schema.sh` y la versión actual es
**8**.

| Documento | Contenido |
|---|---|
| [ARQUITECTURA.md](ARQUITECTURA.md) | Capas, módulos, flujo de una petición, frontend, seguridad y pruebas. |
| [RUTAS.md](RUTAS.md) | Rutas web, enlaces profundos, API HTTP, payloads y códigos de estado. |
| [BASE_DE_DATOS.md](BASE_DE_DATOS.md) | Tablas, columnas, relaciones, índices, triggers, invariantes y migración v8. |
| [DIAGRAMAS.md](DIAGRAMAS.md) | Diagramas Mermaid de clases/módulos, ER de base de datos, estados y secuencias. |
| [SINCRONIZACION.md](SINCRONIZACION.md) | Contrato híbrido de eventos, pull e-commerce y snapshot con PostgreSQL. |
| [SYNC_POSTGRES.sql](SYNC_POSTGRES.sql) | DDL y funciones de referencia (`apply_events`, `pull_events`, `sync_snapshot`) para el endpoint PostgreSQL. |
| [ESTADISTICA.md](ESTADISTICA.md) | Criterios de las métricas y análisis estadísticos del dashboard. |

## Convenciones

- Backend: Bash 4+, SQLite y `socat`. No hay Python ni frameworks externos.
- Frontend: HTML generado en servidor + web components nativos y JavaScript
  sin dependencias.
- Persistencia: SQLite en `shared/data/erp_licores.db`; WAL y claves foráneas
  activas.
- Dinero: cálculos autoritativos en centavos del lado servidor; el navegador
  solo previsualiza.
- Fechas: `datetime('now', 'localtime')` para registros nuevos.
- Idioma de interfaz, mensajes y documentación: español.

## Inicio rápido

```bash
./erp.sh init
./erp.sh server 8080
```

Credenciales demo:

- `admin / admin123`
- `cajero / cajero123`
