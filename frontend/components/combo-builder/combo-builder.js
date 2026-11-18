(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const number = ErpUI.formatNumber;

    class ComboBuilder extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._ready = null;
            this._products = [];
            this._categories = [];
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._ready = this._load();
        }

        async _load() {
            this.innerHTML = await ErpUI.fetchText('/components/combo-builder/combo-builder.html');
            this._modal = this.querySelector('#combo-builder-modal');
            this._form = this.querySelector('[data-combo-builder-form]');
            this._name = this.querySelector('[data-combo-builder-name]');
            this._category = this.querySelector('[data-combo-builder-category]');
            this._threshold = this.querySelector('[data-combo-builder-threshold]');
            this._cost = this.querySelector('[data-combo-builder-cost]');
            this._price = this.querySelector('[data-combo-builder-price]');
            this._description = this.querySelector('[data-combo-builder-description]');
            this._rows = this.querySelector('[data-combo-builder-rows]');
            this._error = this.querySelector('[data-combo-builder-error]');
            this._submit = this.querySelector('[data-combo-builder-submit]');

            this._form.addEventListener('submit', (event) => this._save(event));
            this.querySelector('[data-combo-builder-cancel]').addEventListener('click', () => this._modal.close());
            this.querySelector('[data-combo-builder-add]').addEventListener('click', () => this._addRow());
            this._rows.addEventListener('click', (event) => {
                const remove = event.target.closest('[data-combo-builder-remove]');
                if (remove) remove.closest('[data-combo-builder-row]').remove();
            });
        }

        async open(options = {}) {
            await this._ready;
            await this._modal.ready();
            try {
                await this._loadData();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el creador de combos', error.message, 'error');
                return;
            }

            this._form.reset();
            this._error.hidden = true;
            this._submit.disabled = false;
            this._populateCategories();

            const requested = (options.products || [])
                .map((item) => ({
                    id: Number(item.id) || 0,
                    quantity: Math.max(1, Number(item.quantity) || 1)
                }))
                .filter((item) => item.id > 0);
            const available = new Set(this._products.map((product) => Number(product.id)));
            const selected = requested.filter((item) => available.has(item.id));
            if (!selected.length && this._products.length) {
                selected.push({ id: Number(this._products[0].id), quantity: 1 });
            }
            this._renderRows(selected);

            const first = this._findProduct(selected[0]?.id);
            const defaultName = options.name || this._suggestName(selected);
            this._name.value = defaultName;
            this._category.value = String(options.categoryId || first?.category_id || this._categories[0]?.id || '');
            this._threshold.value = String(options.min_threshold || 5);
            this._description.value = options.description || '';
            const totals = this._suggestedTotals(selected);
            this._cost.value = totals.cost.toFixed(2);
            this._price.value = totals.price.toFixed(2);
            this._modal.setTitle(options.title || 'Crear combo inteligente');
            await this._modal.open();
        }

        async _loadData() {
            const products = await ErpUI.api('/api/products');
            let meta = { categories: [] };
            try {
                meta = await ErpUI.api('/api/inventory/meta');
            } catch (error) {
                meta = { categories: [] };
            }
            this._products = (products || []).filter((product) =>
                Number(product.active) === 1 && Number(product.is_combo) !== 1);
            this._categories = Array.isArray(meta.categories) && meta.categories.length
                ? meta.categories
                : this._fallbackCategories();
        }

        _fallbackCategories() {
            const categories = new Map();
            (this._products || []).forEach((product) => {
                const id = Number(product.category_id);
                if (id > 0 && !categories.has(id)) categories.set(id, product.category);
            });
            return Array.from(categories, ([id, name]) => ({ id, name }));
        }

        _populateCategories() {
            this._category.innerHTML = (this._categories || [])
                .map((category) => `<option value="${Number(category.id)}">${escape(category.name)}</option>`)
                .join('');
        }

        _findProduct(productId) {
            return (this._products || []).find((product) => Number(product.id) === Number(productId));
        }

        _productOptions(selectedId = 0) {
            return (this._products || []).map((product) =>
                `<option value="${Number(product.id)}" ${Number(product.id) === Number(selectedId) ? 'selected' : ''}>${escape(product.name)}</option>`)
                .join('');
        }

        _addRow(component = {}) {
            if (!this._products.length) {
                ErpUI.toast('Sin productos', 'No hay productos activos para incluir en el combo.', 'error');
                return;
            }
            const row = document.createElement('div');
            row.className = 'combo-builder-row';
            row.dataset.comboBuilderRow = '';
            row.innerHTML = `
                <select data-combo-builder-product aria-label="Producto">${this._productOptions(component.id)}</select>
                <input type="number" min="1" step="1" value="${Math.max(1, Number(component.quantity) || 1)}" data-combo-builder-quantity aria-label="Cantidad">
                <button class="btn ghost small" type="button" data-combo-builder-remove>Quitar</button>`;
            this._rows.append(row);
        }

        _renderRows(items = []) {
            this._rows.innerHTML = '';
            (items || []).forEach((item) => this._addRow(item));
            if (!this._rows.children.length) this._addRow();
        }

        _getComponents() {
            const rows = Array.from(this._rows.querySelectorAll('[data-combo-builder-row]'));
            const components = rows.map((row) => ({
                component_product_id: Number(row.querySelector('[data-combo-builder-product]').value) || 0,
                quantity: Number(row.querySelector('[data-combo-builder-quantity]').value) || 0
            })).filter((item) => item.component_product_id > 0);
            const ids = components.map((item) => item.component_product_id);
            if (new Set(ids).size !== ids.length) {
                throw new Error('El combo tiene productos duplicados.');
            }
            if (!components.length) {
                throw new Error('Agregue al menos un producto al combo.');
            }
            if (components.some((item) => !Number.isInteger(item.quantity) || item.quantity < 1)) {
                throw new Error('Las cantidades deben ser enteros mayores o iguales a 1.');
            }
            return components;
        }

        _suggestName(items) {
            const names = (items || [])
                .map((item) => this._findProduct(item.id)?.name)
                .filter(Boolean);
            if (!names.length) return 'Combo nuevo';
            const visible = names.length > 3 ? names.slice(0, 2).concat('…') : names;
            return `Combo ${visible.join(' + ')}`.slice(0, 80);
        }

        _suggestedTotals(items) {
            let cost = 0;
            let price = 0;
            (items || []).forEach((item) => {
                const product = this._findProduct(item.id);
                if (!product) return;
                cost += Number(product.cost) * item.quantity;
                price += Number(product.price) * item.quantity;
            });
            return { cost, price };
        }

        async _save(event) {
            event.preventDefault();
            this._error.hidden = true;
            let components = [];
            try {
                components = this._getComponents();
            } catch (error) {
                this._error.textContent = error.message;
                this._error.hidden = false;
                return;
            }

            const name = this._name.value.trim();
            const categoryId = Number(this._category.value) || 0;
            const threshold = Number(this._threshold.value) || 0;
            const cost = Number(this._cost.value) || 0;
            const price = Number(this._price.value) || 0;
            const description = this._description.value.trim();
            if (!name) {
                this._error.textContent = 'Ingrese el nombre del combo.';
                this._error.hidden = false;
                return;
            }
            if (!(categoryId > 0)) {
                this._error.textContent = 'Seleccione una categoría.';
                this._error.hidden = false;
                return;
            }
            if (!Number.isInteger(threshold) || threshold < 0) {
                this._error.textContent = 'El umbral debe ser un entero mayor o igual a cero.';
                this._error.hidden = false;
                return;
            }
            if (cost < 0 || price < 0) {
                this._error.textContent = 'El costo y el precio no pueden ser negativos.';
                this._error.hidden = false;
                return;
            }

            this._submit.disabled = true;
            try {
                const payload = await ErpUI.api('/api/products', {
                    method: 'POST',
                    body: {
                        name,
                        category_id: categoryId,
                        stock: 0,
                        min_threshold: threshold,
                        cost,
                        price,
                        seasonal: 0,
                        consume_recipe: 0,
                        is_combo: 1,
                        recipe_description: description,
                        steps_text: '',
                        items: [],
                        components
                    }
                });
                this._modal.close();
                ErpUI.toast('Combo creado', `${name} está disponible con ${number(components.length, 0)} productos.`);
                this.dispatchEvent(new CustomEvent('erp:combo-created', {
                    bubbles: true,
                    detail: { product_id: payload.product_id, name }
                }));
            } catch (error) {
                this._error.textContent = error.message;
                this._error.hidden = false;
            } finally {
                this._submit.disabled = false;
            }
        }
    }

    customElements.define('erp-combo-builder', ComboBuilder);
})();
