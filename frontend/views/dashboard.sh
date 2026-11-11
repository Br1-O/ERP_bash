#!/usr/bin/env bash
#
# Vista principal: dashboard analítico con cuatro subsecciones.

[[ -n "${_ERP_VIEW_DASHBOARD_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_DASHBOARD_LOADED=1

view_dashboard_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local active_tab="${3:-resumen}"
    local alerts_count="${4:-0}"
    local data_json="${5:-"{}"}"
    local active_nav="dashboard"
    [[ "${active_tab}" == "agenda" ]] && active_nav="contacts"

    view_layout_start "Dashboard" "${active_nav}" "${active_tab}" "${user}" "${role}" "${alerts_count}"

    cat <<'EOF'
                <div class="dashboard-tabs" role="tablist" aria-label="Subsecciones del dashboard">
                    <button class="tab-button" data-tab-button="resumen">Resumen de ventas</button>
                    <button class="tab-button" data-tab-button="stock">Stock y manufactura</button>
                    <button class="tab-button" data-tab-button="catalogo">Catálogo y canasta</button>
                    <button class="tab-button" data-tab-button="agenda">Agenda y contactos</button>
                </div>

                <section class="tab-panel" data-tab-panel="resumen">
                    <div class="section-heading">
                        <div>
                            <span class="eyebrow">Subsección 1</span>
                            <h2>Resumen de ventas y rendimiento</h2>
                            <p class="muted">Estadística descriptiva, outliers y probabilidad binomial de saturación.</p>
                        </div>
                        <button class="btn primary" id="open-sale-modal" type="button">+ Nueva venta</button>
                    </div>

                    <div class="kpi-grid">
                        <article class="card kpi-card">
                            <span class="kpi-label">Ingresos últimos 30 días</span>
                            <strong class="kpi-value" id="kpi-revenue">$0.00</strong>
                            <span class="kpi-meta" id="kpi-revenue-meta">—</span>
                        </article>
                        <article class="card kpi-card">
                            <span class="kpi-label">Operaciones</span>
                            <strong class="kpi-value" id="kpi-sales">0</strong>
                            <span class="kpi-meta" id="kpi-sales-meta">ticket promedio $0.00</span>
                        </article>
                        <article class="card kpi-card">
                            <span class="kpi-label">Unidades vendidas</span>
                            <strong class="kpi-value" id="kpi-units">0</strong>
                            <span class="kpi-meta" id="kpi-units-meta">productos activos: 0</span>
                        </article>
                        <article class="card kpi-card">
                            <span class="kpi-label">Valor del inventario</span>
                            <strong class="kpi-value" id="kpi-inventory">$0.00</strong>
                            <span class="kpi-meta" id="kpi-inventory-meta">alertas activas: 0</span>
                        </article>
                    </div>

                    <div class="grid-two">
                        <article class="card chart-card">
                            <header class="card-header">
                                <div>
                                    <span class="eyebrow">Problema 1</span>
                                    <h3>Ventas diarias y outliers</h3>
                                </div>
                                <span class="badge badge-soft" id="daily-days">0 días</span>
                            </header>
                            <div class="canvas-wrap tall"><canvas id="daily-chart"></canvas></div>
                            <div class="stat-strip">
                                <span>Media <strong id="daily-mean">$0</strong></span>
                                <span>Q1 <strong id="daily-q1">$0</strong></span>
                                <span>Mediana <strong id="daily-median">$0</strong></span>
                                <span>Q3 <strong id="daily-q3">$0</strong></span>
                                <span>RIC <strong id="daily-iqr">$0</strong></span>
                                <span>Umbral <strong id="daily-threshold">$0</strong></span>
                            </div>
                            <div class="outlier-list" id="outliers-list"></div>
                        </article>

                        <article class="card chart-card">
                            <header class="card-header">
                                <div>
                                    <span class="eyebrow">Problema 3</span>
                                    <h3>Probabilidad de alta demanda</h3>
                                </div>
                                <span class="badge badge-accent">Binomial · p = 0.25</span>
                            </header>
                            <div class="gauge-wrap">
                                <canvas id="binomial-gauge"></canvas>
                                <div class="gauge-center">
                                    <strong id="binomial-percent">0%</strong>
                                    <span>P(X ≥ k)</span>
                                </div>
                            </div>
                            <p class="muted center" id="binomial-text">Calculando escenario de saturación horaria…</p>
                            <div class="stat-strip vertical">
                                <span>Ensayos <strong id="binomial-n">0</strong></span>
                                <span>Éxitos mínimos <strong id="binomial-k">0</strong></span>
                                <span>Hora pico histórica <strong id="binomial-peak">—</strong></span>
                            </div>
                        </article>
                    </div>

                    <div class="grid-two">
                        <article class="card table-card">
                            <header class="card-header">
                                <div>
                                    <span class="eyebrow">Trazabilidad</span>
                                    <h3>Últimas ventas</h3>
                                </div>
                                <span class="badge badge-soft">Tiempo real</span>
                            </header>
                            <div class="table-responsive">
                                <table>
                                    <thead>
                                        <tr><th>Venta</th><th>Cliente</th><th>Pago</th><th>Unidades</th><th>Total</th></tr>
                                    </thead>
                                    <tbody id="recent-sales-body"></tbody>
                                </table>
                            </div>
                        </article>

                        <article class="card">
                            <header class="card-header">
                                <div>
                                    <span class="eyebrow">Auditoría</span>
                                    <h3>Movimientos recientes</h3>
                                </div>
                                <span class="badge badge-soft">InventoryJournal</span>
                            </header>
                            <div class="timeline" id="journal-list"></div>
                        </article>
                    </div>
                </section>

                <section class="tab-panel" data-tab-panel="stock">
                    <div class="section-heading">
                        <div>
                            <span class="eyebrow">Subsección 2</span>
                            <h2>Control de stock, insumos y manufactura</h2>
                            <p class="muted">Punto de pedido, variabilidad, intervalo de confianza y alertas automáticas.</p>
                        </div>
                        <span class="badge badge-danger" id="stock-alert-count">0 alertas</span>
                    </div>

                    <div class="grid-two">
                        <article class="card">
                            <header class="card-header">
                                <div><span class="eyebrow">Recompra</span><h3>Insumos críticos</h3></div>
                                <span class="badge badge-warning">Stock ≤ umbral</span>
                            </header>
                            <div class="alert-list" id="input-alerts"></div>
                        </article>
                        <article class="card">
                            <header class="card-header">
                                <div><span class="eyebrow">Manufactura</span><h3>Órdenes sugeridas</h3></div>
                                <span class="badge badge-accent">Producto terminado</span>
                            </header>
                            <div class="alert-list" id="product-alerts"></div>
                        </article>
                    </div>

                    <article class="card table-card">
                        <header class="card-header">
                            <div>
                                <span class="eyebrow">Problema 2</span>
                                <h3>Punto de pedido y coeficiente de variación</h3>
                            </div>
                            <span class="badge badge-soft">Lead time 4 días · z = 1.65</span>
                        </header>
                        <div class="table-responsive">
                            <table>
                                <thead>
                                    <tr>
                                        <th>Producto</th><th>Stock</th><th>Media diaria</th><th>Desv. estándar</th>
                                        <th>CV%</th><th>Stock seguridad</th><th>Punto de pedido</th><th>Riesgo</th>
                                    </tr>
                                </thead>
                                <tbody id="reorder-products-body"></tbody>
                            </table>
                        </div>
                    </article>

                    <div class="grid-two">
                        <article class="card table-card">
                            <header class="card-header">
                                <div><span class="eyebrow">Insumos</span><h3>Reposición sugerida</h3></div>
                                <span class="badge badge-soft">Lead time 7 días</span>
                            </header>
                            <div class="table-responsive">
                                <table>
                                    <thead>
                                        <tr><th>Insumo</th><th>Stock</th><th>Media diaria</th><th>CV%</th><th>Punto de pedido</th><th>Estado</th></tr>
                                    </thead>
                                    <tbody id="reorder-inputs-body"></tbody>
                                </table>
                            </div>
                        </article>

                        <article class="card chart-card">
                            <header class="card-header">
                                <div>
                                    <span class="eyebrow">Problema 4</span>
                                    <h3>IC 95% del costo unitario por lote</h3>
                                </div>
                                <span class="badge badge-accent">Z = 1.96</span>
                            </header>
                            <div class="canvas-wrap"><canvas id="cost-ci-chart"></canvas></div>
                            <div class="stat-strip vertical" id="cost-ci-stats"></div>
                        </article>
                    </div>
                </section>

                <section class="tab-panel" data-tab-panel="catalogo">
                    <div class="section-heading">
                        <div>
                            <span class="eyebrow">Subsección 3</span>
                            <h2>Catálogo, sabores y canasta</h2>
                            <p class="muted">Prueba Z de proporciones, covarianza, regresión y combos inteligentes.</p>
                        </div>
                    </div>

                    <div class="grid-two">
                        <article class="card chart-card">
                            <header class="card-header">
                                <div><span class="eyebrow">Canasta</span><h3>Ventas por categoría</h3></div>
                                <span class="badge badge-soft">Participación</span>
                            </header>
                            <div class="canvas-wrap pie"><canvas id="category-pie"></canvas></div>
                            <div class="legend" id="category-legend"></div>
                        </article>

                        <article class="card hypothesis-card" id="hypothesis-card">
                            <header class="card-header">
                                <div>
                                    <span class="eyebrow">Problema 5</span>
                                    <h3>Prueba de hipótesis de aceptación</h3>
                                </div>
                                <span class="badge badge-accent">α = 0.05</span>
                            </header>
                            <span class="hypothesis-product" id="hypothesis-product">Sabor estacional</span>
                            <h4 class="hypothesis-verdict" id="hypothesis-verdict">Calculando…</h4>
                            <div class="hypothesis-grid" id="hypothesis-stats"></div>
                            <p class="muted" id="hypothesis-note">H₀: p ≤ 0.40 · H₁: p &gt; 0.40</p>
                        </article>
                    </div>

                    <div class="grid-two">
                        <article class="card">
                            <header class="card-header">
                                <div>
                                    <span class="eyebrow">Problema 6</span>
                                    <h3>Matriz de correlación de Pearson</h3>
                                </div>
                                <span class="badge badge-soft" id="basket-sales-count">0 ventas</span>
                            </header>
                            <div class="matrix-scroll"><div class="correlation-matrix" id="correlation-matrix"></div></div>
                        </article>

                        <article class="card">
                            <header class="card-header">
                                <div><span class="eyebrow">Sugerencias</span><h3>Combos inteligentes</h3></div>
                                <span class="badge badge-success">Regresión</span>
                            </header>
                            <div class="combo-list" id="combos-list"></div>
                            <h4 class="subsection-title">Productos sustitutos</h4>
                            <div class="combo-list" id="substitutes-list"></div>
                        </article>
                    </div>

                    <article class="card table-card">
                        <header class="card-header">
                            <div><span class="eyebrow">Catálogo</span><h3>Productos y disponibilidad</h3></div>
                            <span class="badge badge-soft" id="catalog-count">0 productos</span>
                        </header>
                        <div class="table-responsive">
                            <table>
                                <thead>
                                    <tr><th>Producto</th><th>Categoría</th><th>Stock</th><th>Costo</th><th>Precio</th><th>Estado</th></tr>
                                </thead>
                                <tbody id="products-table-body"></tbody>
                            </table>
                        </div>
                    </article>
                </section>

                <section class="tab-panel" data-tab-panel="agenda">
                    <div class="section-heading">
                        <div>
                            <span class="eyebrow">Subsección 4</span>
                            <h2>Agenda y contactos</h2>
                            <p class="muted">Proveedores y clientes con datos completos, búsqueda y filtros ágiles.</p>
                        </div>
                        <label class="search-field">
                            <span>Buscar</span>
                            <input type="search" id="contact-search" placeholder="Nombre, email o contacto…">
                        </label>
                    </div>

                    <div class="grid-two">
                        <article class="card">
                            <header class="card-header">
                                <div><span class="eyebrow">Abastecimiento</span><h3>Proveedores</h3></div>
                                <span class="badge badge-soft" id="supplier-count">0</span>
                            </header>
                            <div class="contact-list" id="suppliers-list"></div>
                        </article>
                        <article class="card">
                            <header class="card-header">
                                <div><span class="eyebrow">Comercial</span><h3>Clientes</h3></div>
                                <span class="badge badge-soft" id="customer-count">0</span>
                            </header>
                            <div class="contact-list" id="customers-list"></div>
                        </article>
                    </div>
                </section>

                <div class="modal-backdrop" id="sale-modal" hidden>
                    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="sale-modal-title">
                        <header class="modal-header">
                            <div>
                                <span class="eyebrow">Operación atómica</span>
                                <h2 id="sale-modal-title">Registrar nueva venta</h2>
                            </div>
                            <button class="icon-button" id="close-sale-modal" aria-label="Cerrar">×</button>
                        </header>
                        <div class="modal-body">
                            <div class="form-grid">
                                <label class="field">
                                    <span>Cliente</span>
                                    <select id="sale-customer"></select>
                                </label>
                                <label class="field">
                                    <span>Método de pago</span>
                                    <select id="sale-payment">
                                        <option value="Efectivo">Efectivo</option>
                                        <option value="Transferencia">Transferencia</option>
                                        <option value="Tarjeta">Tarjeta</option>
                                    </select>
                                </label>
                            </div>

                            <div class="sale-items-head">
                                <span>Detalle de la venta</span>
                                <button class="btn ghost small" id="add-sale-item" type="button">+ Agregar ítem</button>
                            </div>
                            <div class="sale-items" id="sale-items"></div>

                            <div class="sale-total">
                                <span>Total estimado</span>
                                <strong id="sale-total">$0.00</strong>
                            </div>
                            <p class="form-error" id="sale-error" hidden></p>
                        </div>
                        <footer class="modal-footer">
                            <button class="btn ghost" id="cancel-sale" type="button">Cancelar</button>
                            <button class="btn primary" id="submit-sale" type="button">Registrar venta</button>
                        </footer>
                    </div>
                </div>
EOF

    view_layout_end "${data_json}"
}
