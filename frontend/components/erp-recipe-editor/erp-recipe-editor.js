(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const formatNumber = ErpUI.formatNumber;

    class ErpRecipeEditor extends HTMLElement {
        constructor() {
            super();
            this._meta = { inputs: [], suppliers: [], categories: [] };
            this._items = [];
            this._ready = this._load();
        }

        async _load() {
            this.innerHTML = await ErpUI.fetchText('/components/erp-recipe-editor/erp-recipe-editor.html');
            this._rows = this.querySelector('[data-recipe-rows]');
            this._empty = this.querySelector('[data-recipe-empty]');
            this.querySelector('[data-add-recipe-row]').addEventListener('click', () => this.addRow());
            this.querySelector('[data-quick-save]').addEventListener('click', () => this._createQuickInput());
        }

        async ready() {
            await this._ready;
            return this;
        }

        async setMeta(meta) {
            await this._ready;
            this._meta = {
                inputs: Array.isArray(meta?.inputs) ? meta.inputs.slice() : [],
                suppliers: Array.isArray(meta?.suppliers) ? meta.suppliers.slice() : [],
                categories: Array.isArray(meta?.categories) ? meta.categories.slice() : []
            };
            this._populateQuick();
            this._render();
        }

        async setItems(items) {
            await this._ready;
            this._items = (Array.isArray(items) ? items : []).map((item) => ({
                input_id: Number(item.input_id) || 0,
                input_name: item.input_name || '',
                quantity_per_unit: Number(item.quantity_per_unit) || 0
            }));
            this._render();
        }

        addRow() {
            const used = new Set(this._items.map((item) => Number(item.input_id)));
            const available = this._meta.inputs.find((input) => !used.has(Number(input.id)));
            if (!available) {
                ErpUI.toast('Sin insumos disponibles', 'Cree un insumo nuevo o quite una fila existente.', 'error');
                return;
            }
            this._items.push({ input_id: Number(available.id), input_name: available.name, quantity_per_unit: 1 });
            this._render();
        }

        _populateQuick() {
            const category = this.querySelector('[data-quick-category]');
            const supplier = this.querySelector('[data-quick-supplier]');
            category.innerHTML = this._meta.categories.map((item) =>
                `<option value="${Number(item.id)}">${escape(item.name)}</option>`).join('');
            supplier.innerHTML = '<option value="0">Sin proveedor</option>' + this._meta.suppliers.map((item) =>
                `<option value="${Number(item.id)}">${escape(item.name)}</option>`).join('');
        }

        _inputOptions(selectedId) {
            return this._meta.inputs.map((input) => {
                const selected = Number(input.id) === Number(selectedId) ? 'selected' : '';
                return `<option value="${Number(input.id)}" ${selected}>${escape(input.name)} · ${formatNumber(input.stock)} ${escape(input.unit)}</option>`;
            }).join('');
        }

        _render() {
            if (!this._rows) return;
            this._rows.innerHTML = this._items.map((item, index) => {
                const input = this._meta.inputs.find((candidate) => Number(candidate.id) === Number(item.input_id));
                const unit = input?.unit || '';
                return `
                    <div class="recipe-row" data-recipe-row="${index}">
                        <select data-recipe-input="${index}" aria-label="Insumo">${this._inputOptions(item.input_id)}</select>
                        <input data-recipe-qty="${index}" type="number" min="0.0001" step="0.0001"
                               value="${Number(item.quantity_per_unit) || 1}" aria-label="Cantidad por unidad">
                        <span class="recipe-unit" data-recipe-unit="${index}">${escape(unit)}</span>
                        <button class="icon-button remove-recipe-row" type="button" data-remove-recipe="${index}" aria-label="Quitar insumo">×</button>
                    </div>`;
            }).join('');
            this._empty.hidden = this._items.length > 0;

            this._rows.querySelectorAll('[data-recipe-input]').forEach((select) => {
                select.addEventListener('change', (event) => {
                    const index = Number(event.target.dataset.recipeInput);
                    this._items[index].input_id = Number(event.target.value);
                    const input = this._meta.inputs.find((candidate) => Number(candidate.id) === Number(event.target.value));
                    this._items[index].input_name = input?.name || '';
                    this._render();
                });
            });
            this._rows.querySelectorAll('[data-recipe-qty]').forEach((input) => {
                input.addEventListener('input', (event) => {
                    const index = Number(event.target.dataset.recipeQty);
                    this._items[index].quantity_per_unit = Number(event.target.value) || 0;
                });
            });
            this._rows.querySelectorAll('[data-remove-recipe]').forEach((button) => {
                button.addEventListener('click', (event) => {
                    const index = Number(event.currentTarget.dataset.removeRecipe);
                    this._items.splice(index, 1);
                    this._render();
                });
            });
        }

        getItems() {
            return this._items
                .filter((item) => item.input_id > 0)
                .map((item) => ({ input_id: Number(item.input_id), quantity: Number(item.quantity_per_unit) || 0 }));
        }

        async _createQuickInput() {
            const error = this.querySelector('[data-quick-error]');
            const button = this.querySelector('[data-quick-save]');
            const name = this.querySelector('[data-quick-name]').value.trim();
            const categoryId = Number(this.querySelector('[data-quick-category]').value) || 0;
            const supplierId = Number(this.querySelector('[data-quick-supplier]').value) || 0;
            const unit = this.querySelector('[data-quick-unit]').value.trim() || 'unidades';
            const cost = Number(this.querySelector('[data-quick-cost]').value) || 0;
            const stock = Number(this.querySelector('[data-quick-stock]').value) || 0;

            error.hidden = true;
            if (!name) {
                error.textContent = 'Ingrese un nombre para el insumo.';
                error.hidden = false;
                return;
            }

            button.disabled = true;
            try {
                const payload = await ErpUI.api('/api/inputs', {
                    method: 'POST',
                    body: {
                        name,
                        category_id: categoryId,
                        supplier_id: supplierId,
                        unit,
                        cost,
                        stock,
                        min_threshold: 0
                    }
                });
                const supplier = this._meta.suppliers.find((item) => Number(item.id) === supplierId);
                const input = {
                    id: Number(payload.input_id),
                    name,
                    unit,
                    stock,
                    cost,
                    supplier: supplier?.name || 'Sin proveedor',
                    supplier_id: supplierId
                };
                this._meta.inputs.push(input);
                this._items.push({ input_id: input.id, input_name: input.name, quantity_per_unit: 1 });
                this._render();
                this.querySelector('[data-quick-name]').value = '';
                this.querySelector('[data-quick-cost]').value = '0';
                this.querySelector('[data-quick-stock]').value = '0';
                this.dispatchEvent(new CustomEvent('input-created', { bubbles: true, detail: input }));
                ErpUI.toast('Insumo creado', `${name} ya forma parte de la receta.`);
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                button.disabled = false;
            }
        }
    }

    customElements.define('erp-recipe-editor', ErpRecipeEditor);
})();
