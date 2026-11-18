(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;

    class ProductManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._meta = null;
            this._page = 1;
            this._pages = 1;
            this._currentProduct = null;
            this._editing = null;
            this._requestId = 0;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/product-manager/product-manager.html');
            this._grid = this.querySelector('[data-product-grid]');
            this._empty = this.querySelector('[data-product-empty]');
            this._count = this.querySelector('[data-product-count]');
            this._search = this.querySelector('[data-product-search]');
            this._categoryFilter = this.querySelector('[data-product-category]');
            this._stateFilter = this.querySelector('[data-product-state]');
            this._pagination = this.querySelector('[data-product-pagination]');
            this._formModal = this.querySelector('#product-modal');
            this._detailModal = this.querySelector('#product-detail-modal');
            this._stockModal = this.querySelector('#stock-modal');
            this._form = this.querySelector('[data-product-form]');
            this._formError = this.querySelector('[data-product-error]');
            this._recipeEditor = this.querySelector('#product-recipe-editor');
            this._recipeFields = this.querySelector('[data-product-recipe-fields]');
            this._comboFields = this.querySelector('[data-product-combo-fields]');
            this._comboRows = this.querySelector('[data-combo-rows]');
            this._comboCheck = this.querySelector('[data-product-combo]');
            this._recipeDescription = this.querySelector('[data-product-recipe-description]');
            this._steps = this.querySelector('[data-product-steps]');
            this._stockForm = this.querySelector('[data-stock-form]');
            this._stockError = this.querySelector('[data-stock-error]');
            this._productionModal = this.querySelector('#production-modal');
            this._productionForm = this.querySelector('[data-production-form]');
            this._productionError = this.querySelector('[data-production-error]');
            this._productionInputs = this.querySelector('[data-production-inputs]');
            this._productionProduct = null;
            this._catalog = [];

            this._bind();
            await this._loadMeta();
            await this._loadProductCatalog();
            await this._loadProducts();
            await this._handleDeepLink();
        }

        _bind() {
            this.querySelector('[data-create-product]').addEventListener('click', () => this._openForm());
            ErpUI.debounceInput(this._search, () => {
                this._page = 1;
                this._loadProducts();
            });
            this._categoryFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadProducts();
            });
            this._stateFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadProducts();
            });
            this._pagination.addEventListener('page-change', (event) => {
                this._page = event.detail.page;
                this._loadProducts();
            });
            this._grid.addEventListener('click', (event) => {
                const card = event.target.closest('[data-product-id]');
                if (card) this._openDetail(Number(card.dataset.productId));
            });
            this._form.addEventListener('submit', (event) => this._submitForm(event));
            this.querySelector('[data-product-cancel]').addEventListener('click', () => this._formModal.close());
            this._stockForm.addEventListener('submit', (event) => this._submitStock(event));
            this.querySelector('[data-stock-cancel]').addEventListener('click', () => this._stockModal.close());
            this.querySelector('[data-stock-consume]').addEventListener('change', () => this._renderConsumption());
            this.querySelector('[data-stock-quantity]').addEventListener('input', () => this._renderConsumption());
            this.querySelector('[data-stock-mode]').addEventListener('change', () => this._renderConsumption());
            this._productionForm.addEventListener('submit', (event) => this._submitProduction(event));
            this.querySelector('[data-production-cancel]').addEventListener('click', () => this._productionModal.close());
            this.querySelector('[data-production-quantity]').addEventListener('input', () => this._renderProductionInputs());
            this._recipeEditor.addEventListener('input-created', () => {
                this._loadMeta(true);
            });
            this._comboCheck.addEventListener('change', () => this._toggleComboFields());
            this.querySelector('[data-combo-add]').addEventListener('click', () => this._addComboRow());
            this._comboRows.addEventListener('click', (event) => {
                const remove = event.target.closest('[data-combo-remove]');
                if (remove) remove.closest('.combo-row').remove();
            });
        }

        async _loadProductCatalog() {
            try {
                this._catalog = await ErpUI.api('/api/products');
            } catch (error) {
                this._catalog = [];
            }
        }

        _toggleComboFields() {
            const isCombo = this._comboCheck.checked;
            this._recipeFields.hidden = isCombo;
            this._comboFields.hidden = !isCombo;
            this.querySelector('[data-product-consume-field]').hidden = isCombo || Boolean(this._editing);
            this.querySelector('[data-product-stock-field]').hidden = isCombo || Boolean(this._editing);
        }

        _comboOptions(selectedId = 0) {
            const currentId = Number(this._editing) || 0;
            return (this._catalog || [])
                .filter((product) => Number(product.active) === 1)
                .filter((product) => Number(product.is_combo) !== 1)
                .filter((product) => Number(product.id) !== currentId)
                .map((product) => `<option value="${Number(product.id)}" ${Number(product.id) === Number(selectedId) ? 'selected' : ''}>${escape(product.name)}</option>`)
                .join('');
        }

        _addComboRow(component = {}) {
            const row = document.createElement('div');
            row.className = 'combo-row';
            row.innerHTML = `
                <select data-combo-product>${this._comboOptions(component.component_product_id)}</select>
                <input type="number" min="1" step="1" value="${Number(component.quantity) || 1}" data-combo-quantity aria-label="Cantidad">
                <button class="btn ghost small" type="button" data-combo-remove>Quitar</button>`;
            this._comboRows.append(row);
        }

        _renderComboRows(components = []) {
            this._comboRows.innerHTML = '';
            (components || []).forEach((component) => this._addComboRow(component));
        }

        _getComboItems() {
            const rows = Array.from(this._comboRows.querySelectorAll('.combo-row'));
            const items = rows.map((row) => ({
                component_product_id: Number(row.querySelector('[data-combo-product]').value) || 0,
                quantity: Number(row.querySelector('[data-combo-quantity]').value) || 0
            })).filter((item) => item.component_product_id > 0);
            const ids = items.map((item) => item.component_product_id);
            if (new Set(ids).size !== ids.length) {
                throw new Error('El combo tiene componentes duplicados.');
            }
            if (items.some((item) => item.quantity < 1)) {
                throw new Error('Las cantidades de los componentes deben ser mayores o iguales a 1.');
            }
            return items;
        }

        async _loadMeta(quiet = false) {
            try {
                this._meta = await ErpUI.api('/api/inventory/meta');
                this._populateFilters();
                if (!quiet) await this._recipeEditor.ready();
                await this._recipeEditor.setMeta(this._meta);
            } catch (error) {
                ErpUI.toast('No se pudo cargar el catálogo', error.message, 'error');
            }
        }

        _populateFilters() {
            const categories = this._meta?.categories || [];
            this._categoryFilter.innerHTML = '<option value="0">Todas</option>' +
                categories.map((category) => `<option value="${Number(category.id)}">${escape(category.name)}</option>`).join('') +
                '<option value="combos">Combos</option>';
            this.querySelector('[data-product-form-category]').innerHTML = categories.map((category) =>
                `<option value="${Number(category.id)}">${escape(category.name)}</option>`).join('');
        }

        async _loadProducts() {
            const requestId = ++this._requestId;
            const params = new URLSearchParams({
                q: this._search.value.trim(),
                category: this._categoryFilter.value || '0',
                state: this._stateFilter.value || 'active',
                page: String(this._page),
                per_page: '8'
            });
            this._grid.innerHTML = '<div class="empty-state"><strong>Cargando productos…</strong></div>';
            try {
                const payload = await ErpUI.api(`/api/inventory/products?${params}`);
                if (requestId !== this._requestId) return;
                this._page = Number(payload.page) || 1;
                this._pages = Number(payload.pages) || 1;
                this._render(payload.items || [], payload.total || 0);
            } catch (error) {
                if (requestId !== this._requestId) return;
                this._grid.innerHTML = '';
                this._empty.hidden = false;
                this._empty.querySelector('strong').textContent = 'No se pudieron cargar los productos';
                this._empty.querySelector('span').textContent = error.message;
            }
        }

        _render(items, total) {
            this._count.textContent = `${total} producto${total === 1 ? '' : 's'}`;
            this._pagination.setData(this._page, this._pages);
            this._empty.hidden = items.length > 0;
            if (!items.length) {
                this._grid.innerHTML = '';
                this._empty.querySelector('strong').textContent = 'No hay productos para mostrar';
                this._empty.querySelector('span').textContent = 'Ajuste los filtros o cree un producto nuevo.';
                return;
            }
            this._grid.innerHTML = items.map((product) => {
                const stateLabel = product.state === 'bajo' ? 'Stock bajo' : product.state === 'inactivo' ? 'Inactivo' : 'Disponible';
                const supplies = product.supplies || (product.is_combo ? 'Combo de productos' : 'Sin receta asociada');
                return `
                    <article class="product-card" data-product-id="${Number(product.id)}">
                        <header>
                            <div>
                                <strong>${escape(product.name)}</strong>
                                <div class="muted" style="font-size:.7rem">${escape(product.category)}${product.is_combo ? ' · Combo' : ''}</div>
                            </div>
                            <span class="state-pill ${escape(product.state)}">${stateLabel}</span>
                        </header>
                        <div class="card-metrics">
                            <span>Stock <b>${number(product.stock, 0)}</b></span>
                            <span>Precio <b>${money(product.price)}</b></span>
                            <span>${product.is_combo ? 'Componentes' : 'Receta'} <b>${product.is_combo ? '—' : (Number(product.recipe_count) || 0)}</b></span>
                        </div>
                        <p class="supplies-line"><strong>${product.is_combo ? 'Detalle' : 'Insumos'}:</strong> ${escape(supplies)}</p>
                    </article>`;
            }).join('');
        }

        async _openDetail(productId) {
            try {
                const product = await ErpUI.api(`/api/products/${productId}`);
                this._currentProduct = product;
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
                const displayStock = product.is_combo == 1 ? product.available_stock : product.stock;
                const stockAction = product.is_combo == 1
                    ? ''
                    : '<button class="btn ghost small" type="button" data-detail-action="stock">Actualizar stock</button>';
                const productionAction = product.is_combo == 1
                    ? ''
                    : '<button class="btn primary small" type="button" data-detail-action="produce">Registrar producción</button>';

                this._detailModal.setTitle(product.name);
                this._detailModal.setBody(`
                    <div class="inline-actions">
                        <span class="badge badge-soft">${escape(product.category)}</span>
                        <span class="state-pill ${product.active == 1 ? 'ok' : 'inactive'}">${product.active == 1 ? 'Activo' : 'Inactivo'}</span>
                        ${product.seasonal == 1 ? '<span class="badge badge-accent">Estacional</span>' : ''}
                        ${product.is_combo == 1 ? '<span class="badge badge-accent">Combo</span>' : ''}
                    </div>
                    <div class="detail-grid">
                        <div class="detail-metric"><span>${product.is_combo == 1 ? 'Disponibles' : 'Stock'}</span><strong>${number(displayStock, 0)} unidades</strong></div>
                        <div class="detail-metric"><span>Producción posible</span><strong>${number(product.max_producible, 0)} unidades</strong></div>
                        <div class="detail-metric"><span>Costo</span><strong>${money(product.cost)}</strong></div>
                        <div class="detail-metric"><span>Precio</span><strong>${money(product.price)}</strong></div>
                    </div>
                    ${product.is_combo == 1 ? `
                        <h4 class="detail-section-title">Componentes del combo</h4>
                        <div class="table-responsive">
                            <table>
                                <thead><tr><th>Producto</th><th>Cantidad</th><th>Stock actual</th></tr></thead>
                                <tbody>${comboRows}</tbody>
                            </table>
                        </div>` : `
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
                        <button class="btn primary small" type="button" data-detail-action="edit">Editar producto</button>
                        ${productionAction}
                        ${stockAction}
                        <button class="btn ghost small" type="button" data-detail-action="delete">Eliminar</button>
                    </div>
                `);
                this._detailModal.setFooter('');
                this._detailModal.querySelectorAll('[data-detail-action]').forEach((button) => {
                    button.addEventListener('click', () => {
                        const action = button.dataset.detailAction;
                        this._detailModal.close();
                        if (action === 'edit') this._openForm(product);
                        if (action === 'stock') this._openStock(product);
                        if (action === 'produce') this._openProduction(product);
                        if (action === 'delete') this._deleteProduct(product);
                    });
                });
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el producto', error.message, 'error');
            }
        }

        async _openForm(product = null) {
            this._editing = product ? Number(product.id) : 0;
            this._form.reset();
            this._formError.hidden = true;
            await this._loadProductCatalog();
            this.querySelector('[data-product-stock-field]').hidden = Boolean(product);
            this.querySelector('[data-product-active-field]').hidden = !product;
            this.querySelector('[data-product-consume-field]').hidden = Boolean(product);
            this.querySelector('[data-product-active]').checked = product ? product.active == 1 : true;
            this.querySelector('[data-product-consume]').checked = false;
            this._comboCheck.checked = product ? product.is_combo == 1 : false;
            this._recipeDescription.value = product?.recipe_description || '';
            this._steps.value = (product?.recipe_steps || []).join('\n');
            this._renderComboRows(product?.combo || []);
            this.querySelector('[data-product-submit]').textContent = product ? 'Guardar cambios' : 'Crear producto';

            if (product) {
                this.querySelector('[data-product-name]').value = product.name || '';
                this.querySelector('[data-product-form-category]').value = String(product.category_id || '');
                this.querySelector('[data-product-stock]').value = String(product.stock || 0);
                this.querySelector('[data-product-cost]').value = String(product.cost || 0);
                this.querySelector('[data-product-price]').value = String(product.price || 0);
                this.querySelector('[data-product-threshold]').value = String(product.min_threshold || 0);
                this.querySelector('[data-product-seasonal]').checked = product.seasonal == 1;
            }

            await this._recipeEditor.ready();
            await this._recipeEditor.setMeta(this._meta || {});
            await this._recipeEditor.setItems(product?.is_combo == 1 ? [] : (product?.recipe || []));
            this._toggleComboFields();
            this._formModal.setTitle(product ? `Editar ${product.name}` : 'Nuevo producto');
            await this._formModal.open();
        }

        async _submitForm(event) {
            event.preventDefault();
            const error = this._formError;
            const submit = this.querySelector('[data-product-submit]');
            error.hidden = true;
            const isCombo = this._comboCheck.checked;
            let items = [];
            let components = [];
            try {
                components = isCombo ? this._getComboItems() : [];
            } catch (comboError) {
                error.textContent = comboError.message;
                error.hidden = false;
                return;
            }
            if (isCombo && !components.length) {
                error.textContent = 'Agregue al menos un componente al combo.';
                error.hidden = false;
                return;
            }
            if (!isCombo) {
                items = this._recipeEditor.getItems();
                if (items.some((item) => !(item.quantity > 0))) {
                    error.textContent = 'Todas las cantidades de la receta deben ser mayores que cero.';
                    error.hidden = false;
                    return;
                }
                const ids = items.map((item) => item.input_id);
                if (new Set(ids).size !== ids.length) {
                    error.textContent = 'La receta tiene insumos duplicados. Quite una de las filas repetidas.';
                    error.hidden = false;
                    return;
                }
            }

            const body = {
                name: this.querySelector('[data-product-name]').value.trim(),
                category_id: Number(this.querySelector('[data-product-form-category]').value) || 0,
                min_threshold: Number(this.querySelector('[data-product-threshold]').value) || 0,
                cost: Number(this.querySelector('[data-product-cost]').value) || 0,
                price: Number(this.querySelector('[data-product-price]').value) || 0,
                seasonal: this.querySelector('[data-product-seasonal]').checked ? 1 : 0,
                is_combo: isCombo ? 1 : 0,
                recipe_description: isCombo ? '' : this._recipeDescription.value.trim(),
                steps_text: isCombo ? '' : this._steps.value.trim(),
                items,
                components
            };
            if (!body.name) {
                error.textContent = 'Ingrese el nombre del producto.';
                error.hidden = false;
                return;
            }

            submit.disabled = true;
            try {
                if (this._editing) {
                    body.active = this.querySelector('[data-product-active]').checked ? 1 : 0;
                    await ErpUI.api(`/api/products/${this._editing}`, { method: 'PUT', body });
                    ErpUI.toast('Producto actualizado', `${body.name} se guardó correctamente.`);
                } else {
                    body.stock = isCombo ? 0 : (Number(this.querySelector('[data-product-stock]').value) || 0);
                    body.consume_recipe = isCombo ? 0 : (this.querySelector('[data-product-consume]').checked ? 1 : 0);
                    await ErpUI.api('/api/products', { method: 'POST', body });
                    ErpUI.toast('Producto creado', `${body.name} ya está disponible.`);
                }
                this._formModal.close();
                await this._loadMeta(true);
                await this._loadProducts();
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                submit.disabled = false;
            }
        }

        async _handleDeepLink() {
            const params = new URLSearchParams(window.location.search);
            const productId = Number(params.get('product'));
            if (!productId) return;
            try {
                const product = await ErpUI.api(`/api/products/${productId}`);
                if (params.get('produce') === '1' && Number(product.is_combo) !== 1) {
                    await this._openProduction(product);
                } else {
                    await this._openDetail(productId);
                    if (params.get('produce') === '1') {
                        ErpUI.toast('Combo', 'El stock del combo se calcula desde sus componentes.', 'error');
                    }
                }
                window.history.replaceState({}, '', '/inventario');
            } catch (error) {
                ErpUI.toast('No se pudo abrir el producto', error.message, 'error');
            }
        }

        async _openProduction(product, quantity = null) {
            if (Number(product.is_combo) === 1) {
                ErpUI.toast('Combo', 'El stock del combo se calcula desde sus componentes.', 'error');
                return;
            }
            this._productionProduct = product;
            this._productionForm.reset();
            this._productionError.hidden = true;
            const deficit = Math.ceil((Number(product.min_threshold) || 0) - (Number(product.stock) || 0));
            this.querySelector('[data-production-quantity]').value = String(quantity || Math.max(1, deficit));
            this.querySelector('[data-production-cost]').value = String(Number(product.cost) || 0);
            this.querySelector('[data-production-notes]').value = '';
            this.querySelector('[data-production-note]').textContent =
                `Stock actual: ${number(product.stock, 0)} unidades. Los insumos de la receta se descuentan al registrar el lote.`;
            this._renderProductionInputs();
            this._productionModal.setTitle(`Registrar producción · ${product.name}`);
            await this._productionModal.open();
        }

        _renderProductionInputs() {
            const product = this._productionProduct;
            if (!product) return;
            const quantity = Math.max(0, Number(this.querySelector('[data-production-quantity]').value) || 0);
            const recipe = product.recipe || [];
            if (!recipe.length) {
                this._productionInputs.innerHTML = '<p class="form-note">Este producto no tiene receta asociada; el lote solo suma stock.</p>';
                return;
            }
            this._productionInputs.innerHTML = recipe.map((item) => {
                const total = Number(item.quantity_per_unit) * quantity;
                const insufficient = Number(item.input_stock) < total;
                return `
                    <div class="stock-consumption-row" data-production-row="${Number(item.input_id)}">
                        <div>
                            <strong>${escape(item.input_name)}</strong>
                            <small style="display:block;color:var(--text-dim)">${number(item.quantity_per_unit, 4)} ${escape(item.unit)} por unidad</small>
                        </div>
                        <input type="number" min="0" step="0.0001" value="${total.toFixed(4)}" data-production-input-qty>
                        <small class="${insufficient ? 'negative' : ''}">${escape(item.unit)}${insufficient ? ' · insuficiente' : ''}</small>
                    </div>`;
            }).join('');
        }

        async _submitProduction(event) {
            event.preventDefault();
            if (!this._productionProduct) return;
            const error = this._productionError;
            const submit = this.querySelector('[data-production-submit]');
            const quantity = Number(this.querySelector('[data-production-quantity]').value) || 0;
            const unitCost = Number(this.querySelector('[data-production-cost]').value) || 0;
            const notes = this.querySelector('[data-production-notes]').value.trim();
            error.hidden = true;

            if (!Number.isInteger(quantity) || quantity <= 0) {
                error.textContent = 'Ingrese una cantidad entera mayor que cero.';
                error.hidden = false;
                return;
            }
            if (unitCost < 0) {
                error.textContent = 'El costo unitario no puede ser negativo.';
                error.hidden = false;
                return;
            }

            const items = Array.from(this._productionInputs.querySelectorAll('[data-production-row]')).map((row) => ({
                input_id: Number(row.dataset.productionRow),
                quantity: Number(row.querySelector('[data-production-input-qty]').value) || 0
            }));
            if ((this._productionProduct.recipe || []).length && items.some((item) => !(item.quantity > 0))) {
                error.textContent = 'Las cantidades de insumos deben ser mayores que cero.';
                error.hidden = false;
                return;
            }

            submit.disabled = true;
            try {
                const payload = await ErpUI.api('/api/production', {
                    method: 'POST',
                    body: {
                        product_id: Number(this._productionProduct.id),
                        quantity,
                        unit_cost: unitCost,
                        notes,
                        items
                    }
                });
                this._productionModal.close();
                ErpUI.toast('Producción registrada', `${this._productionProduct.name}: lote #${payload.batch_id} con ${number(quantity, 0)} unidades.`);
                await this._loadMeta(true);
                await this._loadProducts();
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                submit.disabled = false;
            }
        }

        async _openStock(product) {
            if (product.is_combo == 1) {
                ErpUI.toast('Combo', 'El stock del combo se calcula desde sus componentes.', 'error');
                return;
            }
            this._currentProduct = product;
            this._stockForm.reset();
            this._stockError.hidden = true;
            this.querySelector('[data-stock-quantity]').value = '1';
            this.querySelector('[data-stock-mode]').value = 'add';
            const consume = this.querySelector('[data-stock-consume]');
            consume.checked = (product.recipe || []).length > 0;
            consume.disabled = (product.recipe || []).length === 0;
            this.querySelector('[data-stock-note]').textContent =
                `Stock actual: ${number(product.stock, 0)} unidades. La receta se descuenta solo al agregar unidades.`;
            this._renderConsumption();
            this._stockModal.setTitle(`Actualizar stock · ${product.name}`);
            await this._stockModal.open();
        }

        _renderConsumption() {
            if (!this._currentProduct) return;
            const container = this.querySelector('[data-stock-consumption]');
            const consume = this.querySelector('[data-stock-consume]').checked;
            const quantity = Number(this.querySelector('[data-stock-quantity]').value) || 0;
            const mode = this.querySelector('[data-stock-mode]').value;
            const current = Number(this._currentProduct.stock) || 0;
            const delta = mode === 'set' ? quantity - current : quantity;
            const recipe = this._currentProduct.recipe || [];

            container.hidden = !consume || !recipe.length || delta <= 0;
            if (container.hidden) {
                container.innerHTML = '';
                return;
            }
            container.innerHTML = recipe.map((item) => {
                const total = Number(item.quantity_per_unit) * delta;
                return `
                    <div class="stock-consumption-row" data-consumption-row="${Number(item.input_id)}" data-unit="${escape(item.unit)}">
                        <div>
                            <strong>${escape(item.input_name)}</strong>
                            <small style="display:block;color:var(--text-dim)">${number(item.quantity_per_unit, 4)} ${escape(item.unit)} por unidad</small>
                        </div>
                        <input type="number" min="0" step="0.0001" value="${total.toFixed(4)}" data-consumption-qty>
                        <small>${escape(item.unit)}</small>
                    </div>`;
            }).join('');
        }

        async _submitStock(event) {
            event.preventDefault();
            if (!this._currentProduct) return;
            const error = this._stockError;
            const submit = this.querySelector('[data-stock-submit]');
            const quantity = Number(this.querySelector('[data-stock-quantity]').value) || 0;
            const mode = this.querySelector('[data-stock-mode]').value;
            const consume = this.querySelector('[data-stock-consume]').checked;
            error.hidden = true;

            if (mode === 'add' && quantity <= 0) {
                error.textContent = 'Ingrese una cantidad mayor que cero.';
                error.hidden = false;
                return;
            }

            const items = [];
            if (consume) {
                this._stockModal.querySelectorAll('[data-consumption-row]').forEach((row) => {
                    items.push({
                        input_id: Number(row.dataset.consumptionRow),
                        quantity: Number(row.querySelector('[data-consumption-qty]').value) || 0
                    });
                });
            }

            submit.disabled = true;
            try {
                const payload = await ErpUI.api(`/api/products/${this._currentProduct.id}/stock`, {
                    method: 'POST',
                    body: {
                        quantity,
                        mode,
                        consume_recipe: consume ? 1 : 0,
                        items
                    }
                });
                this._stockModal.close();
                ErpUI.toast('Stock actualizado', `${this._currentProduct.name}: ${number(payload.stock, 0)} unidades disponibles.`);
                await this._loadMeta(true);
                await this._loadProducts();
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                submit.disabled = false;
            }
        }

        async _deleteProduct(product) {
            if (!window.confirm(`¿Eliminar ${product.name}? El producto quedará inactivo y no se borrará su historial.`)) return;
            try {
                await ErpUI.api(`/api/products/${product.id}`, { method: 'DELETE' });
                ErpUI.toast('Producto eliminado', `${product.name} quedó inactivo.`);
                await this._loadProducts();
            } catch (error) {
                ErpUI.toast('No se pudo eliminar', error.message, 'error');
            }
        }
    }

    customElements.define('erp-product-manager', ProductManager);
})();
