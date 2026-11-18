#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_INSIGHTS_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_INSIGHTS_LOADED=1

view_insights_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/erp-pagination/erp-pagination.css">
    <link rel="stylesheet" href="/components/combo-builder/combo-builder.css">
EOF
)

    view_layout_start "Inteligencia de canasta" "insights" "inteligencia" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'EOF'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Análisis de canasta</span>
                        <h2>Combos inteligentes, correlación y sustitutos</h2>
                        <p class="muted">Explore la matriz completa de Pearson, todas las combinaciones positivas y los productos sustitutos detectados en los últimos 60 días.</p>
                    </div>
                    <span class="badge badge-soft" id="insights-sales-count">0 ventas</span>
                </section>

                <article class="card insights-card">
                    <header class="card-header">
                        <div>
                            <span class="eyebrow">Problema 6</span>
                            <h3>Matriz de correlación de Pearson</h3>
                        </div>
                        <span class="badge badge-soft" id="insights-matrix-count">0 productos</span>
                    </header>
                    <div class="manager-filters insights-filters">
                        <label class="search-field">
                            <span>Buscar producto</span>
                            <input type="search" id="insights-matrix-search" placeholder="Filtrar filas y columnas…">
                        </label>
                        <label class="field compact-field">
                            <span>Ordenar</span>
                            <select id="insights-matrix-sort">
                                <option value="volume">Volumen de ventas</option>
                                <option value="name">Nombre A-Z</option>
                                <option value="name_desc">Nombre Z-A</option>
                            </select>
                        </label>
                    </div>
                    <div class="matrix-scroll insights-matrix-scroll">
                        <div class="correlation-matrix" id="insights-matrix"></div>
                    </div>
                    <div class="empty-state" id="insights-matrix-empty" hidden>
                        <strong>Sin productos para mostrar</strong>
                        <span>Ajuste la búsqueda o registre ventas para calcular correlaciones.</span>
                    </div>
                </article>

                <div class="insights-grid">
                    <article class="card insights-card">
                        <header class="card-header">
                            <div>
                                <span class="eyebrow">Sugerencias</span>
                                <h3>Combos inteligentes</h3>
                            </div>
                            <span class="badge badge-success" id="insights-combos-count">0 combos</span>
                        </header>
                        <div class="manager-filters insights-filters">
                            <label class="search-field">
                                <span>Buscar</span>
                                <input type="search" id="insights-combos-search" placeholder="Producto A o B…">
                            </label>
                            <label class="field compact-field">
                                <span>Ordenar</span>
                                <select id="insights-combos-sort">
                                    <option value="corr_desc">Mayor r</option>
                                    <option value="corr_asc">Menor r</option>
                                    <option value="cooc_desc">Más ventas conjuntas</option>
                                    <option value="cooc_asc">Menos ventas conjuntas</option>
                                    <option value="name">Nombre A-Z</option>
                                </select>
                            </label>
                        </div>
                        <div class="combo-list" id="insights-combos"></div>
                        <div class="empty-state" id="insights-combos-empty" hidden>
                            <strong>Sin combos positivos</strong>
                            <span>No hay pares con correlación positiva y ventas conjuntas.</span>
                        </div>
                        <erp-pagination id="insights-combos-pagination"></erp-pagination>
                    </article>

                    <article class="card insights-card">
                        <header class="card-header">
                            <div>
                                <span class="eyebrow">Canasta</span>
                                <h3>Productos sustitutos</h3>
                            </div>
                            <span class="badge badge-soft" id="insights-substitutes-count">0 pares</span>
                        </header>
                        <div class="manager-filters insights-filters">
                            <label class="search-field">
                                <span>Buscar</span>
                                <input type="search" id="insights-substitutes-search" placeholder="Producto A o B…">
                            </label>
                            <label class="field compact-field">
                                <span>Ordenar</span>
                                <select id="insights-substitutes-sort">
                                    <option value="corr_asc">Mayor sustitución</option>
                                    <option value="corr_desc">Menor sustitución</option>
                                    <option value="cov_asc">Menor covarianza</option>
                                    <option value="cov_desc">Mayor covarianza</option>
                                    <option value="name">Nombre A-Z</option>
                                </select>
                            </label>
                        </div>
                        <div class="combo-list" id="insights-substitutes"></div>
                        <div class="empty-state" id="insights-substitutes-empty" hidden>
                            <strong>Sin sustitutos</strong>
                            <span>No hay pares con correlación negativa en el período.</span>
                        </div>
                        <erp-pagination id="insights-substitutes-pagination"></erp-pagination>
                    </article>
                </div>

                <erp-combo-builder></erp-combo-builder>

                <script src="/assets/components.js"></script>
                <script src="/components/erp-modal/erp-modal.js"></script>
                <script src="/components/erp-pagination/erp-pagination.js"></script>
                <script src="/components/combo-builder/combo-builder.js"></script>
                <script src="/assets/insights.js"></script>
EOF

    view_layout_end
}
