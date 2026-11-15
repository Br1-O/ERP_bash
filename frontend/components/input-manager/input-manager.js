(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;

    class InputManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._meta = null;
            this._page = 1;
            this._pages = 1;
            this._editing = null;
            this._currentInput = null;
            this._requestId = 0;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/input-manager/input-manager.html');
            this._grid = this.querySelector('[data-input-grid]');
            this._empty = this.querySelector('[data-input-empty]');
            this._count = this.querySelector('[data-input-count]');
            this._search = this.querySelector('[data-input-search]');
            this._supplierFilter = this.querySelector('[data-input-supplier-filter]');
            this._stateFilter = this.querySelector('[data-input-state]');
            this._pagination = this.querySelector('[data-input-pagination]');
            this._formModal = this.querySelector('#input-modal');
            this._detailModal = this.querySelector('#input-detail-modal');
            this._restockModal = this.querySelector('#restock-modal');
            this._form = this.querySelector('[data-input-form]');
            this._formError = this.querySelector('[data-input-error]');
            this._restockForm = this.querySelector('[data-restock-form]');
            this._restockError = this.querySelector('[data-restock-error]');

            this._bind();
            await this._loadMeta();
            await this._loadInputs();
        }

        _bind() {
            this.querySelector('[data-create-input]').addEventListener('click', () => this._openForm());
            ErpUI.debounceInput(this._search, () => {
                this._page = 1;
                this._loadInputs();
            });
            this._supplierFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadInputs();
            });
            this._stateFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadInputs();
            });
            this._pagination.addEventListener('page-change', (event) => {
                this._page = event.detail.page;
                this._loadInputs();
            });
            this._grid.addEventListener('click', (event) => {
                const card = event.target.closest('[data-input-id]');
                if (card) this._openDetail(Number(card.dataset.inputId));
            });
            this._form.addEventListener('submit', (event) => this._submitForm(event));
            this.querySelector('[data-input-cancel]').addEventListener('click', () => this._formModal.close());
            this._restockForm.addEventListener('submit', (event) => this._submitRestock(event));
            this.querySelector('[data-restock-cancel]').addEventListener('click', () => this._restockModal.close());
        }

        async _loadMeta() {
            try {
                this._meta = await ErpUI.api('/api/inventory/meta');
                this._populateMetaOptions();
            } catch (error) {
                ErpUI.toast('No se pudo cargar el catálogo', error.message, 'error');
            }
        }

        _populateMetaOptions() {
            const categories = this._meta?.categories || [];
            const suppliers = this._meta?.suppliers || [];
            const currentFilter = this._supplierFilter.value || '0';
            this._supplierFilter.innerHTML = '<option value="0">Todos</option>' +
                suppliers.map((supplier) => `<option value="${Number(supplier.id)}">${escape(supplier.name)}</option>`).join('');
            this._supplierFilter.value = currentFilter;

            this.querySelector('[data-input-category]').innerHTML = categories.map((category) =>
                `<option value="${Number(category.id)}">${escape(category.name)}</option>`).join('');
            this.querySelector('[data-input-supplier]').innerHTML = '<option value="0">Sin proveedor</option>' +
                suppliers.map((supplier) => `<option value="${Number(supplier.id)}">${escape(supplier.name)}</option>`).join('');
        }

        async _loadInputs() {
            const requestId = ++this._requestId;
            const params = new URLSearchParams({
                q: this._search.value.trim(),
                supplier: this._supplierFilter.value || '0',
                state: this._stateFilter.value || 'active',
                page: String(this._page),
                per_page: '8'
            });
            this._grid.innerHTML = '<div class="empty-state"><strong>Cargando insumos…</strong></div>';
            try {
                const payload = await ErpUI.api(`/api/inventory/inputs?${params}`);
                if (requestId !== this._requestId) return;
                this._page = Number(payload.page) || 1;
                this._pages = Number(payload.pages) || 1;
                this._render(payload.items || [], payload.total || 0);
            } catch (error) {
                if (requestId !== this._requestId) return;
                this._grid.innerHTML = '';
                this._empty.hidden = false;
                this._empty.querySelector('strong').textContent = 'No se pudieron cargar los insumos';
                this._empty.querySelector('span').textContent = error.message;
            }
        }

        _render(items, total) {
            this._count.textContent = `${total} insumo${total === 1 ? '' : 's'}`;
            this._pagination.setData(this._page, this._pages);
            this._empty.hidden = items.length > 0;
            if (!items.length) {
                this._grid.innerHTML = '';
                this._empty.querySelector('strong').textContent = 'No hay insumos para mostrar';
                this._empty.querySelector('span').textContent = 'Ajuste los filtros o cree un insumo nuevo.';
                return;
            }
            this._grid.innerHTML = items.map((input) => {
                const stateLabel = input.state === 'bajo' ? 'Stock bajo' : input.state === 'inactivo' ? 'Inactivo' : 'Disponible';
                return `
                    <article class="entity-card" data-input-id="${Number(input.id)}">
                        <header>
                            <div>
                                <strong>${escape(input.name)}</strong>
                                <div class="muted" style="font-size:.7rem">${escape(input.supplier)}</div>
                            </div>
                            <span class="state-pill ${escape(input.state)}">${stateLabel}</span>
                        </header>
                        <div class="card-metrics">
                            <span>Stock <b>${number(input.stock)} ${escape(input.unit)}</b></span>
                            <span>Costo <b>${money(input.cost)}</b></span>
                            <span>Recetas <b>${Number(input.recipe_uses) || 0}</b></span>
                        </div>
                        <p class="supplies-line"><strong>Umbral mínimo:</strong> ${number(input.min_threshold)} ${escape(input.unit)}</p>
                    </article>`;
            }).join('');
        }

        async _openDetail(inputId) {
            try {
                const input = await ErpUI.api(`/api/inputs/${inputId}`);
                this._currentInput = input;
                const products = (input.products || []).map((product) => `
                    <div class="mini-list-row">
                        <div class="row-main"><strong>${escape(product.name)}</strong>
                            <small>${number(product.quantity_per_unit, 4)} ${escape(input.unit)} por unidad</small>
                        </div>
                    </div>`).join('');
                const purchases = (input.purchases || []).map((purchase) => `
                    <div class="mini-list-row">
                        <div class="row-main"><strong>${number(purchase.quantity)} ${escape(input.unit)}</strong>
                            <small>${escape(purchase.supplier)} · ${ErpUI.formatDateTime(purchase.date)}</small>
                        </div>
                        <span class="badge badge-soft">${money(purchase.unit_cost)}</span>
                    </div>`).join('');
                const phone = input.phone || '';
                const email = input.email || '';

                this._detailModal.setTitle(input.name);
                this._detailModal.setBody(`
                    <div class="detail-grid">
                        <div class="detail-metric"><span>Stock</span><strong>${number(input.stock)} ${escape(input.unit)}</strong></div>
                        <div class="detail-metric"><span>Umbral</span><strong>${number(input.min_threshold)} ${escape(input.unit)}</strong></div>
                        <div class="detail-metric"><span>Costo</span><strong>${money(input.cost)}</strong></div>
                        <div class="detail-metric"><span>Recetas</span><strong>${(input.products || []).length}</strong></div>
                    </div>
                    <h4 class="detail-section-title">Proveedor</h4>
                    <div class="mini-list-row">
                        <div class="row-main">
                            <strong>${escape(input.supplier)}</strong>
                            <small>${escape(input.contact || 'Sin contacto')} · ${escape(phone || 'Sin teléfono')} · ${escape(email || 'Sin email')}</small>
                        </div>
                        <div class="inline-actions">
                            ${phone ? `<button class="btn ghost small copy-phone" type="button" data-copy-phone="${escape(phone)}">Copiar teléfono</button>` : ''}
                            ${phone ? `<a class="btn ghost small" href="tel:${escape(phone)}">Llamar</a>` : ''}
                            ${email ? `<a class="btn ghost small" href="mailto:${escape(email)}">Escribir</a>` : ''}
                        </div>
                    </div>
                    <h4 class="detail-section-title">Productos que usan este insumo</h4>
                    <div class="mini-list">${products || '<div class="mini-list-row"><div class="row-main"><small>Sin productos asociados.</small></div></div>'}</div>
                    <h4 class="detail-section-title">Últimas compras</h4>
                    <div class="mini-list">${purchases || '<div class="mini-list-row"><div class="row-main"><small>Sin compras registradas.</small></div></div>'}</div>
                    <div class="detail-actions">
                        <button class="btn primary small" type="button" data-input-action="edit">Editar insumo</button>
                        <button class="btn ghost small" type="button" data-input-action="restock">Reponer stock</button>
                        <button class="btn ghost small" type="button" data-input-action="delete">Eliminar</button>
                    </div>
                `);
                this._detailModal.setFooter('');
                this._detailModal.querySelectorAll('[data-copy-phone]').forEach((button) => {
                    button.addEventListener('click', () => ErpUI.copyText(button.dataset.copyPhone, 'Teléfono'));
                });
                this._detailModal.querySelectorAll('[data-input-action]').forEach((button) => {
                    button.addEventListener('click', () => {
                        const action = button.dataset.inputAction;
                        this._detailModal.close();
                        if (action === 'edit') this._openForm(input);
                        if (action === 'restock') this._openRestock(input);
                        if (action === 'delete') this._deleteInput(input);
                    });
                });
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el insumo', error.message, 'error');
            }
        }

        async _openForm(input = null) {
            this._editing = input ? Number(input.id) : 0;
            this._form.reset();
            this._formError.hidden = true;
            this.querySelector('[data-input-active-field]').hidden = !input;
            this.querySelector('[data-input-active]').checked = input ? input.active == 1 : true;
            this.querySelector('[data-input-submit]').textContent = input ? 'Guardar cambios' : 'Crear insumo';

            if (input) {
                this.querySelector('[data-input-name]').value = input.name || '';
                this.querySelector('[data-input-category]').value = String(input.category_id || '');
                this.querySelector('[data-input-supplier]').value = String(input.supplier_id || '0');
                this.querySelector('[data-input-unit]').value = input.unit || 'unidades';
                this.querySelector('[data-input-stock]').value = String(input.stock || 0);
                this.querySelector('[data-input-cost]').value = String(input.cost || 0);
                this.querySelector('[data-input-threshold]').value = String(input.min_threshold || 0);
            }
            this._formModal.setTitle(input ? `Editar ${input.name}` : 'Nuevo insumo');
            await this._formModal.open();
        }

        async _submitForm(event) {
            event.preventDefault();
            const error = this._formError;
            const submit = this.querySelector('[data-input-submit]');
            error.hidden = true;
            const body = {
                name: this.querySelector('[data-input-name]').value.trim(),
                category_id: Number(this.querySelector('[data-input-category]').value) || 0,
                supplier_id: Number(this.querySelector('[data-input-supplier]').value) || 0,
                unit: this.querySelector('[data-input-unit]').value.trim() || 'unidades',
                stock: Number(this.querySelector('[data-input-stock]').value) || 0,
                cost: Number(this.querySelector('[data-input-cost]').value) || 0,
                min_threshold: Number(this.querySelector('[data-input-threshold]').value) || 0
            };
            if (!body.name) {
                error.textContent = 'Ingrese el nombre del insumo.';
                error.hidden = false;
                return;
            }
            submit.disabled = true;
            try {
                if (this._editing) {
                    body.active = this.querySelector('[data-input-active]').checked ? 1 : 0;
                    await ErpUI.api(`/api/inputs/${this._editing}`, { method: 'PUT', body });
                    ErpUI.toast('Insumo actualizado', `${body.name} se guardó correctamente.`);
                } else {
                    await ErpUI.api('/api/inputs', { method: 'POST', body });
                    ErpUI.toast('Insumo creado', `${body.name} ya está disponible.`);
                }
                this._formModal.close();
                await this._loadMeta();
                await this._loadInputs();
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                submit.disabled = false;
            }
        }

        async _openRestock(input) {
            this._currentInput = input;
            this._restockForm.reset();
            this._restockError.hidden = true;
            this.querySelector('[data-restock-quantity]').value = '1';
            this._restockModal.setTitle(`Reponer ${input.name}`);
            await this._restockModal.open();
        }

        async _submitRestock(event) {
            event.preventDefault();
            if (!this._currentInput) return;
            const error = this._restockError;
            const submit = this.querySelector('[data-restock-submit]');
            const quantity = Number(this.querySelector('[data-restock-quantity]').value) || 0;
            error.hidden = true;
            submit.disabled = true;
            try {
                await ErpUI.api('/api/inputs/restock', {
                    method: 'POST',
                    body: { input_id: this._currentInput.id, quantity }
                });
                this._restockModal.close();
                ErpUI.toast('Stock repuesto', `${this._currentInput.name}: +${number(quantity)} ${this._currentInput.unit}.`);
                await this._loadInputs();
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                submit.disabled = false;
            }
        }

        async _deleteInput(input) {
            if (!window.confirm(`¿Eliminar ${input.name}? El insumo quedará inactivo y conservará su historial.`)) return;
            try {
                await ErpUI.api(`/api/inputs/${input.id}`, { method: 'DELETE' });
                ErpUI.toast('Insumo eliminado', `${input.name} quedó inactivo.`);
                await this._loadInputs();
            } catch (error) {
                ErpUI.toast('No se pudo eliminar', error.message, 'error');
            }
        }
    }

    customElements.define('erp-input-manager', InputManager);
})();
