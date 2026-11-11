# 🍷 ERP Analítico & Gestor de Licores Artesanales

Un sistema ERP (Enterprise Resource Planning) profesional, ligero y transportable diseñado en **Bash** sobre una base de datos **SQLite**, servido nativamente a la web mediante **`socat`** y con soporte de interfaz de consola CLI/TUI (`whiptail`).

Este sistema fue desarrollado como Proyecto Integrador y Trabajo Final para la materia **Estadística** (Tecnicatura Superior en Análisis de Sistemas, ISFT N° 151), integrando herramientas de estadística descriptiva e inferencial aplicadas a la toma de decisiones estratégicas en una tienda de licores artesanales (producción de destilados, gin, hidromiel, macerados e insumos).

---

## 📸 Descripción General

El proyecto adopta una filosofía de **cero dependencias pesadas** (sin Node.js o servidores pesados como Apache/Nginx). Todo el ciclo de vida del software —desde el modelado de datos en SQLite con transacciones y triggers hasta el ruteo HTTP y la generación de componentes web dinámicos con gráficos SVG— ocurre dentro del ecosistema nativo de Linux y scripts Bash.

### Características Principales del ERP:
- **Gestión de Stock e Insumos:** Control diferencial entre productos terminados y materia prima/insumos de producción.
- **Alertas Automáticas de Recompra y Manufactura:** Disparo de notificaciones críticas en tiempo real cuando el stock cae por debajo del umbral mínimo personalizable.
- **Agenda de Contactos:** Directorio centralizado de proveedores e historia de clientes (minoristas y mayoristas).
- **Auditoría de Operaciones (`InventoryJournal`):** Trazabilidad completa de acciones mediante triggers automatizados en la base de datos.
- **Servidor HTTP integrado con `socat`:** Ruteo de peticiones `GET` y `POST` con servidor liviano y seguro.
- **Dashboard Estadístico Multisección:** Renderizado de gráficos de barras, gráficos de torta y widgets con KPIs clave sin librerías externas.

---

## 📊 Módulos Estadísticos & KPIs (6 Problemas Aplicados)

El ERP cuenta con un motor analítico centralizado (`api/analytics.sh`) que aplica rigurosamente los temas de la materia:

### 1. Estadística Descriptiva y Detección de Outliers (Ventas Diarias)
* **Teoría:** Cuartiles ($Q_1, Q_3$), Mediana y Rango Intercuartílico ($RIC = Q_3 - Q_1$).
* **Aplicación:** Identificación analítica de días atípicos de alta demanda (eventos, ferias o festividades) mediante el umbral $Q_3 + 1.5 \times RIC$ para no distorsionar las proyecciones de reposición habituales.
* **KPI / Visualización:** Gráfico de caja (*Box-plot*) e histograma de ventas diarias.

### 2. Control de Stock de Seguridad por Variabilidad de la Demanda
* **Teoría:** Desviación estándar muestral ($s$), Media ($\bar{x}$) y Coeficiente de Variación Percentual ($CV\% = \frac{s}{\bar{x}} \times 100$).
* **Aplicación:** Medición de la dispersión en la demanda diaria de insumos críticos (ej. botellas de vidrio, alcohol base). Permite ajustar dinámicamente el **Punto de Pedido** y el **Stock de Seguridad** en función de la volatilidad del consumo.
* **KPI / Visualización:** Indicador de volatilidad $CV\%$ y badges de alerta temprana.

### 3. Estimación de Demanda con Distribución Binomial
* **Teoría:** Variable aleatoria discreta Binomial $P(X = k) = \binom{n}{k} p^k (1-p)^{n-k}$.
* **Aplicación:** Con una probabilidad histórica de compra $p = 0.25$ por cliente entrante, se calcula la probabilidad acumulada de quiebre o alta concurrencia $P(X \ge k)$ ante la llegada de un grupo de $n$ clientes en horas pico.
* **KPI / Visualización:** Widget de probabilidad de saturación de stock en barra de atención.

### 4. Estimación de Costos por Intervalos de Confianza
* **Teoría:** Intervalo de confianza al 95% para la media poblacional con varianza conocida o muestral:
  $$\mu \in \left( \bar{x} \pm Z_{\alpha/2} \frac{\sigma}{\sqrt{n}} \right)$$
* **Aplicación:** Estimación del costo real por lote de maceración o destilación a partir de muestras de lotes anteriores, permitiendo fijar precios de venta con márgenes de ganancia garantizados.
* **KPI / Visualización:** Banda de confianza del costo unitario y margen neto proyectado.

### 5. Contraste de Hipótesis para Validación de Nuevos Sabores
* **Teoría:** Prueba de hipótesis para la proporción ($Z$-Test para proporciones).
  - $H_0: p \le 0.40$ (La receta no supera el estándar histórico de aceptación)
  - $H_1: p > 0.40$ (La receta tiene una aceptación comercialmente significativa)
* **Aplicación:** Evaluación de pruebas a ciegas/degustaciones de un nuevo licor estacional (ej: *Licor de Calafate*) con $\alpha = 0.05$.
* **KPI / Visualización:** Veredicto automático (*"Aprobado para producción masiva"* / *"En observación"*).

### 6. Covarianza y Regresión Lineal para Análisis de Canasta (Combos & Sustitutos)
* **Teoría:** Covarianza muestral $S_{xy}$, Coeficiente de correlación de Pearson ($r$) y Modelo de Regresión Lineal por Mínimos Cuadrados ($y = \beta_0 + \beta_1 x$).
* **Aplicación:** Identificación de productos complementarios ($S_{xy} > 0$) para la sugerencia automática de **Combos Cross-selling** (ej: Gin + Botánicos/Tónica) y la detección de productos sustitutos en caso de faltantes.
* **KPI / Visualización:** Gráfico de Torta de ventas por categoría y recomendador de combos.

---

## 🏗️ Arquitectura y Patrones de Diseño

El sistema está organizado bajo un patrón **MVC (Modelo-Vista-Controlador)** adaptado a scripts Bash:

```
ERP_bash/
├── config.sh                   # Configuración global e importación de submódulos
├── main.sh                     # Punto de entrada principal (Switch CLI/TUI/HTTP)
├── router.sh                   # Router HTTP invocado por socat
├── model/                      # CAPA DE DATOS (MODEL)
│   ├── db_singleton.sh         # Patrón Singleton para conexión SQLite
│   ├── schema.sql              # Creación de tablas, índices y triggers
│   └── transactions.sh         # Funciones de transacciones ACID (compras/ventas)
├── api/                        # CAPA DE NEGOCIO Y LÓGICA (CONTROLLER)
│   ├── analytics.sh            # Motor de cálculos estadísticos (Problemas 1 a 6)
│   ├── auth_api.sh             # Autenticación y hashing de contraseñas (SHA-256)
│   ├── inventory_api.sh        # Lógica CRUD y validación de inventario
│   └── sales_api.sh            # Procesamiento atómico de ventas
├── frontend/                   # CAPA DE PRESENTACIÓN (VISTA)
│   ├── html_generators.sh      # Plantillas HTML5, CSS3 responsive y SVG gráficos
│   ├── tui_handlers.sh         # Interfaces en consola con Whiptail
│   └── cli_handlers.sh         # Interfaces de texto puro (Fallback CLI)
└── shared/data/                # ALMACENAMIENTO PERSISTENTE
    └── erp_licores.db          # Base de datos SQLite (Modo WAL)
```

### Principios Destacados:
1. **Singleton SQLite:** Función unificada de conexión que garantiza pragmas optimizados (`journal_mode = WAL`, `foreign_keys = ON`, `synchronous = NORMAL`).
2. **Transacciones ACID:** Operaciones complejas de venta (`Sales` + `SaleItems` + actualización de stock) encapsuladas entre `BEGIN TRANSACTION` y `COMMIT` / `ROLLBACK`.
3. **Triggers en SQLite:** Disparo de eventos automáticos para poblar el `InventoryJournal` de auditoría y descontar stock automáticamente tras cada venta.

---

## 🌐 Rutas HTTP Servidas (`socat`)

Cuando el servidor está activo (puerto predeterminado `:8080`), gestiona las siguientes rutas:

| Ruta | Método | Descripción |
| :--- | :---: | :--- |
| `/login` | `GET` / `POST` | Autenticación de usuario con hash SHA-256 |
| `/menu` | `GET` | Panel de navegación principal |
| `/dashboard` | `GET` | Dashboard estadístico completo con subsecciones navegables |
| `/contactos` | `GET` | Directorio interactivo de Clientes y Proveedores |
| `/productos` | `GET` / `POST` | Gestión de inventario de productos terminados |
| `/insumos` | `GET` / `POST` | Control y alertas de insumos de producción |
| `/ventas` | `GET` / `POST` | Registro atómico de ventas y facturación |
| `/journal` | `GET` | Auditoría de movimientos y logs del sistema |

---

## 🛠️ Requisitos e Instalación

### Requisitos Previos
El sistema se ejecuta en cualquier distribución de Linux o entorno POSIX (WSL2 en Windows, macOS con coreutils). Requiere los siguientes paquetes básicos:

- **Bash** (v4.0 o superior)
- **SQLite3**
- **Socat** (para el servidor web HTTP)
- **Whiptail** (opcional, para el modo TUI interactivo en terminal)

En sistemas basados en Debian/Ubuntu:
```bash
sudo apt update
sudo apt install -y bash sqlite3 socat whiptail
```

### Instalación y Uso

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/Br1-O/ERP_bash.git
   cd ERP_bash
   ```

2. **Dar permisos de ejecución:**
   ```bash
   chmod +x main.sh router.sh
   ```

3. **Ejecutar el sistema en modo Interfaz Gráfica de Terminal (TUI por defecto):**
   ```bash
   ./main.sh
   ```

4. **Ejecutar en modo CLI tradicional (Consola interactiva):**
   ```bash
   ./main.sh cli
   ```

5. **Acceso Web:**
   Una vez dentro del menú (o activando la opción 7 de servidor HTTP), abre tu navegador e ingresa a:
   ```
   http://localhost:8080/login
   ```

---

## ✒️ Autor y Licencia

- **Desarrollado por:** Bruno ([Br1-O](https://github.com/Br1-O))
- **Materia:** Estadística — 2do Año Tecnicatura Superior en Análisis de Sistemas.
- **Licencia:** MIT. Libre uso para fines educativos y comerciales.
