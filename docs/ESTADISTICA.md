# Estadística del dashboard

El motor está en `api/analytics.sh`. Los cálculos se ejecutan en el servidor y
el frontend solo representa los resultados. El periodo de ventas es de 30 días
salvo donde se indique otro. Solo cuentan las ventas y pedidos con estado
`finished`; los pedidos pendientes o cancelados no alteran la analítica.

## Estadística descriptiva diaria

Para la serie de ventas por día (`analytics_daily_json`):

- Media: suma de ventas / cantidad de días.
- Cuartiles con interpolación lineal sobre la serie ordenada.
- Rango intercuartílico: `IQR = Q3 - Q1`.
- Límite de outliers: `Q3 + 1.5 · IQR`; se listan los días por encima.
- Desvío estándar muestral: `sqrt(Σ(xᵢ - x̄)² / (n - 1))`.
- Coeficiente de variación: `CV = (sd / media) · 100`.

## Punto de reposición

Para productos e insumos se agrupa la demanda diaria de los últimos 30 días:

```text
media       = demanda total / 30
varianza    = (Σx² - 2·media·Σx + 30·media²) / 29
seguridad   = 1.65 · sd · sqrt(lead_time)
reposición  = media · lead_time + seguridad
riesgo      = stock actual - reposición
```

- Productos: `lead_time = 4` días.
- Insumos: `lead_time = 7` días.
- `1.65` corresponde a un nivel de servicio aproximado del 95 %.
- Un ítem es crítico si el stock está por debajo del umbral configurado o por
  debajo del punto de reposición.

## Probabilidad binomial

Se toma la hora con más ventas históricas. Si esa hora tiene `n` ventas, se usan
`n = max(n, 6)` y `k = ceil(n / 2)`. Con `p = 0.25`:

```text
P(X ≥ k) = Σ [ C(n, i) · pⁱ · (1-p)^(n-i) ]   para i = k..n
```

El resultado se muestra como probabilidad y porcentaje de que al menos la mitad
de las ventas de la hora pico sean del sabor promocionado.

## Intervalo de confianza del costo

Para los costos unitarios de los lotes de producción:

```text
media   = Σcᵢ / n
sd      = sqrt(Σ(cᵢ - media)² / (n - 1))
margen  = 1.96 · sd / sqrt(n)
IC 95%  = [max(0, media - margen), media + margen]
```

## Prueba de hipótesis

Contraste de una proporción para el producto estacional:

- `H0: p = 0.40`
- `H1: p > 0.40`
- `p̂ = aceptaciones / degustaciones`
- `z = (p̂ - p0) / sqrt(p0(1-p0)/n)`
- `p-valor = 1 - Φ(z)`, con aproximación normal.
- Se aprueba producción masiva si `p-valor < 0.05` y `p̂ > 0.40`.

Si no hay degustaciones, se usan las ventas del producto estacional en los
últimos 30 días.

## Canasta y correlación

Se eligen los 6 productos más vendidos de los últimos 60 días. Para cada par:

```text
cov(x,y) = (Σxy - Σx·Σy/n) / (n - 1)
corr(x,y) = cov(x,y) / sqrt(var(x)·var(y))
y = b0 + b1·x
b1 = (Σxy - Σx·Σy/n) / (Σx² - Σx·Σx/n)
b0 = ȳ - b1·x̄
```

- `combos`: los 3 pares con mayor correlación positiva y co-ocurrencia.
- `substitutes`: hasta 3 pares con correlación negativa.
- La matriz de correlación se muestra como mapa de calor.
- El dashboard usa la vista compacta (6 productos, 3 combos, 3 sustitutos).
  La página `/inteligencia` usa `/api/analytics/basket` para mostrar la matriz y
  todos los pares, con búsqueda, orden por valores y paginación.

Ejemplo de los datos demo: la correlación entre los dos productos más vendidos
es aproximadamente `0.9846`.

## Categorías

El gráfico de torta usa la facturación por categoría:

```text
valor_categoría = Σ(cantidad vendida · precio unitario)
```

## KPIs del periodo

- Ingresos: suma de `total_amount` de los últimos 30 días.
- Ventas: cantidad de operaciones.
- Unidades: suma de cantidades vendidas.
- Ticket promedio: ingresos / ventas.
- Valor de inventario: `Σ(stock · costo)` de productos activos.
- Clientes y alertas de stock según las tablas locales.

## Analítica de eventos y ferias

`api_events_stats_json` y `analytics_events_summary_json` calculan sobre
eventos cerrados, usando los importes históricos congelados en `Events`:

```text
ingresos        = Σ total_revenue_cents / 100
costo vendido   = Σ total_cogs_cents / 100
pérdidas        = Σ total_loss_cents / 100
ganancia neta   = ingresos - costo vendido - pérdidas
margen neto     = ganancia neta / ingresos · 100
conversión      = unidades vendidas / unidades apartadas · 100
tasa de merma   = unidades perdidas / unidades apartadas · 100
```

Las medidas de centralización y dispersión (media, mediana, rango, desvío
estándar muestral y `CV%`) se calculan dos veces: sobre la ganancia neta por
evento y sobre las unidades vendidas por evento.

La comparativa de canales agrupa `Sales.channel`:

- `LOCAL` se muestra como `SEDE`.
- `FERIA` son ventas vinculadas a un evento.
- `ECOMMERCE` son ventas traídas por la fase de pull.

El campo `series` devuelve, por evento cerrado, `revenue`, `net_profit`,
`sold`, `loss` y `returned` para los gráficos comparativos y la torta de
distribución. El reintegro se calcula como
`allocated_qty - sold_qty - loss_qty` al cerrar el evento.
