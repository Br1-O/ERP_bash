(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;

    class ProductDetail extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._ready = null;
            this._product = null;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._ready = this._load();
        }

        async _load() {
            this.innerHTML = await ErpUI.fetchText('/components/product-detail/product-detail.html');
            this._modal = this.querySelector('#dashboard-product-detail');
        }

        async open(productId) {
            await this._ready;
            await this._modal.ready();
            try {
                const product = await ErpUI.api(`/api/products/${Number(productId)}`);
                this._product = product;
                this._render(product);
                await this._modal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el producto', error.message, 'error');
            }
        }

        _render(product) {
            const recipe = product.recipe || [];
            const recipeRows = recipe.length ? recipe.map((item) => `
                <tr>
                    <td>${escape(item.input_name)}</td>
                    <td>${number(item.quantity_per_unit, 4)} ${escape(item.unit)}</td>
                    <td>${number(item.input_stock)} ${escape(item.unit)}</td>
                    <td>${escape(item.supplier)}</td>
                </tr>`).join('') : '<tr><td colspan="4" class="muted">Sin receta asociada.</td></tr>';
            const combo = product.combo || [];
            const comboRows = combo.length ? combo.map((item) => `
                <tr>
                    <td>${escape(item.component_name)}</td>
                    <td>${number(item.quantity, 0)}</td>
                    <td>${number(item.stock, 0)}</td>
                </tr>`).join('') : '<tr><td colspan="3" class="muted">Sin componentes asociados.</td></tr>';
            const steps = product.recipe_steps || [];
            const stepsHtml = steps.length
                ? `<ol class="recipe-steps">${steps.map((step) => `<li>${escape(step)}</li>`).join('')}</ol>`
                : '<p class="muted">Sin pasos registrados.</p>';
            const descriptionHtml = product.recipe_description
                ? `<p class="recipe-description">${escape(product.recipe_description)}</p>`
                : '<p class="muted">Sin descripción de receta.</p>';
            const isCombo = Number(product.is_combo) === 1;
            const displayStock = isCombo ? product.available_stock : product.stock;
            const productionAction = isCombo
                ? ''
                : `<a class="btn primary small" href="/inventario?product=${Number(product.id)}&produce=1">Registrar producción</a>`;
            const comboAction = isCombo
                ? ''
                : `<button class="btn ghost small" type="button" data-product-detail-action="combo">Crear combo con este producto</button>`;

            this._modal.setTitle(product.name);
            this._modal.setBody(`
                <div class="inline-actions">
                    <span class="badge badge-soft">${escape(product.category)}</span>
                    <span class="state-pill ${product.active == 1 ? 'ok' : 'inactive'}">${product.active == 1 ? 'Activo' : 'Inactivo'}</span>
                    ${product.seasonal == 1 ? '<span class="badge badge-accent">Estacional</span>' : ''}
                    ${isCombo ? '<span class="badge badge-accent">Combo</span>' : ''}
                </div>
                <div class="detail-grid">
                    <div class="detail-metric"><span>${isCombo ? 'Disponibles' : 'Stock'}</span><strong>${number(displayStock, 0)} unidades</strong></div>
                    <div class="detail-metric"><span>Producción posible</span><strong>${number(product.max_producible, 0)} unidades</strong></div>
                    <div class="detail-metric"><span>Costo</span><strong>${money(product.cost)}</strong></div>
                    <div class="detail-metric"><span>Precio</span><strong>${money(product.price)}</strong></div>
                </div>
                ${isCombo ? `
                    <h4 class="detail-section-title">Componentes del combo</h4>
                    <div class="table-responsive">
                        <table>
                            <thead><tr><th>Producto</th><th>Cantidad</th><th>Stock actual</th></tr></thead>
                            <tbody>${comboRows}</tbody>
                        </table>
                    </div>
                    ${product.recipe_description ? `<h4 class="detail-section-title">Descripción</h4><p class="recipe-description">${escape(product.recipe_description)}</p>` : ''}` : `
                    <h4 class="detail-section-title">Descripción de la receta</h4>
                    ${descriptionHtml}
                    <h4 class="detail-section-title">Pasos de preparación</h4>
                    ${stepsHtml}
                    <h4 class="detail-section-title">Insumos de la receta</h4>
                    <div class="table-responsive">
                        <table>
                            <thead><tr><th>Insumo</th><th>Por unidad</th><th>Stock actual</th><th>Proveedor</th></tr></thead>
                            <tbody>${recipeRows}</tbody>
                        </table>
                    </div>`}
                <div class="detail-actions">
                    <a class="btn ghost small" href="/inventario?product=${Number(product.id)}">Abrir en inventario</a>
                    ${productionAction}
                    ${comboAction}
                </div>
            `);
            this._modal.setFooter('');
            this._modal.querySelectorAll('[data-product-detail-action="combo"]').forEach((button) => {
                button.addEventListener('click', () => {
                    this._modal.close();
                    const builder = document.querySelector('erp-combo-builder');
                    if (!builder) {
                        ErpUI.toast('Creador no disponible', 'No se pudo abrir el creador de combos.', 'error');
                        return;
                    }
                    builder.open({
                        products: [{ id: Number(product.id), name: product.name, quantity: 1 }],
                        title: `Crear combo con ${product.name}`
                    });
                });
            });
        }
    }

    customElements.define('erp-product-detail', ProductDetail);
})();
