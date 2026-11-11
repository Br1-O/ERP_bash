# Prompt de Desarrollo: ERP Analítico, Automatizado y Empresarial para Tienda de Licores Artesanales (Bash + SQLite + Socat)

Actúa como un Arquitecto de Software Senior y Desarrollador DevOps experto en scripting avanzado en Bash, SQLite y arquitecturas minimalistas de alto rendimiento sin dependencias pesadas. Necesito refactorizar, ampliar y estructurar un sistema ERP modular y profesional en Bash para una **tienda de licores artesanales** (producción de lotes propios, gestión de insumos, proveedores, clientes, ventas y auditoría).

El sistema debe integrar rigurosamente los contenidos de la materia **Estadística** (Unidades 1 y 2: Estadística Descriptiva, Medidas de Posición, Dispersión, Probabilidad Binomial, Intervalos de Confianza, Pruebas de Hipótesis, Covarianza y Regresión Lineal) para alimentar un **Dashboard Gerencial, Analítico y Automatizado** dentro de una interfaz web ligera servida nativamente desde Bash con `socat`.

---

## 1. Arquitectura del Sistema, Patrones de Diseño y Organización

El proyecto debe estructurarse estrictamente bajo el patrón **MVC (Modelo-Vista-Controlador)** adaptado a Bash, aplicando las siguientes prácticas profesionales:

* **Patrón Singleton para la Base de Datos (`model/db_singleton.sh`):** Implementar un mecanismo de instancia única para las conexiones a SQLite, garantizando la configuración global de SQLite (modo WAL, `synchronous = NORMAL`, `foreign_keys = ON`) y evitando contenciones o reconexiones redundantes.
* **Transacciones ACID y Atomicidad (`model/transactions.sh`):** Para operaciones complejas (ej: registro de una venta con múltiples ítems o alta de un lote de producción), se deben utilizar transacciones explícitas (`BEGIN TRANSACTION ... COMMIT / ROLLBACK`) para garantizar la integridad referencial y la consistencia del inventario.
* **Triggers de Base de Datos (SQLite):** Crear triggers para automatizar la inserción de registros en el `InventoryJournal` (auditoría) ante eventos `INSERT`, `UPDATE` o `DELETE` en tablas críticas, y para la actualización en tiempo real de stocks post-venta o consumo de insumos.
* **Capa de Negocio / API (`api/`):** Funciones de validación de tipos, reglas de negocio y cálculo estadístico centralizado.
* **Capa de Presentación / Router (`frontend/`):** Vistas modulares servidas vía `socat` con ruteo transparente.

---

## 2. Modelo de Datos Extendido y Normalizado (SQLite)

Diseña y crea las siguientes tablas en SQLite (`shared/data/erp_licores.db`):

1. **`Categories`**: id, name (ej: Licores Macerados, Destilados, Hidromieles, Insumos, Envases).
2. **`Suppliers` (Proveedores)**: id, name, contact_person, phone, email, address.
3. **`Customers` (Clientes)**: id, name, type (Mayorista/Minorista), phone, email.
4. **`Inputs` (Insumos de Producción)**: id, name, category_id, stock, unit (litros, kg, unidades), cost, supplier_id, min_stock_threshold (umbral personalizable de alerta baja).
5. **`Products` (Productos Terminados)**: id, name, category_id, stock, min_production_threshold (umbral para disparar lote artesanal), cost, price, active (0/1).
6. **`Sales` (Ventas)**: id, timestamp, customer_id, total_amount, payment_method.
7. **`SaleItems` (Detalle de Venta)**: id, sale_id, product_id, quantity, unit_price.
8. **`InventoryJournal` (Auditoría de Movimientos)**: id, timestamp, user, action, entity, payload, status.

---

## 3. Automatizaciones, Alertas y Triggers

* **Triggers de Auditoría y Stock:** Triggers automáticos en SQLite que descuenten el stock de `Products` al insertar en `SaleItems`, y registren la transacción en `InventoryJournal`.
* **Alertas de Recompra de Insumos:** Notificación visual crítica en el ERP cuando `Inputs.stock <= Inputs.min_stock_threshold` (o parámetro global de seguridad).
* **Alertas de Manufactura Artesanal:** Notificación de orden de producción sugerida cuando `Products.stock <= Products.min_production_threshold`.

---

## 4. Módulos Estadísticos y Dashboard Analítico (6 Problemas + Subsecciones)

El Dashboard de Administración debe incluir subsecciones navegables mediante pestañas y gráficos interactivos ligeros (Canvas/SVG nativo CSS/JS sin librerías pesadas):

### Subsección 1: Resumen de Ventas y Rendimiento
* **Problema 1 (Estadística Descriptiva & Outliers):** Cuartiles $Q_1, Q_3$ y Rango Intercuartílico ($RIC$). Identificación de días con picos de venta atípicos ($Q_3 + 1.5 \times RIC$).
  - *Visualización:* **Gráfico de Barras** de ventas diarias y resaltado de días atípicos (*outliers*).
* **Problema 3 (Probabilidad Binomial):** Estimación de la probabilidad de alta demanda horaria en picos de atención ($P(X \ge k)$ con $p = 0.25$).
  - *Visualización:* Widget indicador de saturación horaria.

### Subsección 2: Control de Stock, Insumos y Manufactura
* **Problema 2 (Punto de Pedido & Variabilidad):** Media diaria ($\bar{x}$), desviación estándar ($s$) y **Coeficiente de Variación Percentual ($CV\%$)** para calcular el Punto de Pedido y Stock de Seguridad.
  - *Visualización:* Alertas automáticas de insumos/productos críticos.
* **Problema 4 (Intervalos de Confianza de Costos):** Intervalo de confianza al $95\%$ para el costo unitario por lote: $\mu \in \left( \bar{x} \pm Z_{\alpha/2} \frac{\sigma}{\sqrt{n}} \right)$.
  - *Visualización:* Banda de fluctuación de costos de producción.

### Subsección 3: Catálogo, Sabores y Canasta (Productos)
* **Problema 5 (Prueba de Hipótesis para Proporciones):** Contraste $Z$ para evaluar si un nuevo sabor estacional supera el umbral histórico de aceptación ($p_0 = 0.40$).
  - *Visualización:* Veredicto automático de producción masiva.
* **Problema 6 (Covarianza y Regresión Lineal - Canasta):** Covarianza $S_{xy}$ y mínimos cuadrados ($y = \beta_0 + \beta_1 x$) para sugerir **Combos Inteligentes** (ej: Gin + Botánicos) y detectar productos sustitutos.
  - *Visualización:* **Gráfico de Torta** por categorías y matriz de correlación de Pearson.

### Subsección 4: Agenda y Contactos
* Vista ágil para listar, filtrar y acceder a los datos completos de contacto de **Proveedores** y **Clientes**.

---

## 5. Diseño UI/UX y Responsividad (Mejores Prácticas Modernas)

* **UI/UX Profesional:** Interfaz limpia con modo oscuro/claro elegante, inspirada en dashboards de software administrativo moderno (variables CSS3, Flexbox/Grid, tipografía nítida sans-serif, componentes modulares tipo Cards, Badges de estado y animaciones suaves).
* **Totalmente Responsivo:** Diseño *Mobile-First* adapable a dispositivos móviles, tablets y monitores desktop sin romper la disposición de las tablas o formularios.

---

## 6. Requerimientos Técnicos del Servidor (`socat`)

1. **Servidor HTTP Transportable con `socat`**:
   - Implementar la escucha HTTP con `socat TCP-LISTEN:<puerto>,fork,reuseaddr EXEC:"./router.sh"`.
   - Manejo seguro de rutas (`GET /login`, `GET /dashboard`, `GET /contactos`, `POST /api/sales`, etc.), parseo de formularios `POST` / datos JSON y respuesta con código HTTP 200/400/500 según corresponda.
2. **Centralización Analítica (`api/analytics.sh`)**:
   - Todo el cálculo matemático/estadístico debe estar unificado y reutilizable en este archivo, combinando SQLite (agregaciones/consultas) y lógica limpia en Bash/JS embebido.

Por favor, genera la estructura completa de directorios, los scripts modulares con el patrón Singleton, las transacciones SQLite, los Triggers, el motor del servidor HTTP basado en `socat`, y las vistas HTML responsivas con diseño moderno y gráficos integrados.