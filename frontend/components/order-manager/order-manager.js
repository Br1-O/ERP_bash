(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;

    class OrderManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._customers = [];
            this._products = [];
            this._page = 1;
            this._pages = 1;
            this._editing = 0;
            this._currentOrder = null;
            this._requestId = 0;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/order-manager/order-manager.html');
            this._body = this.querySelector('[data-order-body]');
            this._empty = this.querySelector('[data-order-empty]');
            this._count = this.querySelector('[data-order-count]');
            this._search = this.querySelector('[data-order-search]');
            this._statusFilter = this.querySelector('[data-order-status-filter]');
            this._pagination = this.querySelector('[data-order-pagination]');
            this._detailModal = this.querySelector('#order-detail-modal');
            this._formModal = this.querySelector('#order-form-modal');
            this._form = this.querySelector('[data-order-form]');
            this._formError = this.querySelector('[data-order-error]');
            this._customerSelect = this.querySelector('[data-order-customer]');
            this._customerName = this.querySelector('[data-order-customer-name]');
            this._customerType = this.querySelector('[data-order-customer-type]');
            this._customerPhone = this.querySelector('[data-order-customer-phone]');
            this._customerEmail = this.querySelector('[data-order-customer-email]');
            this._saveCustomer = this.querySelector('[data-order-save-customer]');
            this._saveCustomerField = this.querySelector('[data-order-save-customer-field]');
            this._payment = this.querySelector('[data-order-payment]');
            this._state = this.querySelector('[data-order-state]');
            this._discountType = this.querySelector('[data-order-discount-type]');
            this._discountValue = this.querySelector('[data-order-discount-value]');
            this._notes = this.querySelector('[data-order-notes]');
            this._items = this.querySelector('[data-order-items]');
            this._totals = this.querySelector('[data-order-totals]');
            this._invoice = this.querySelector('#order-invoice');

            this._bind();
            await this._loadCatalog();
            await this._loadOrders();
        }

        _bind() {
            this.querySelector('[data-create-order]').addEventListener('click', () => this._openForm());
            this.querySelector('[data-order-add-item]').addEventListener('click', () => {
                this._addItemRow();
                this._renderTotals();
            });
            this.querySelector('[data-order-cancel]').addEventListener('click', () => this._formModal.close());
            this._form.addEventListener('submit', (event) => this._submit(event));
            this._customerSelect.addEventListener('change', () => this._customerChanged());
            this._items.addEventListener('click', (event) => {
                const remove = event.target.closest('[data-order-item-remove]');
                if (remove) {
                    remove.closest('.order-item-row').remove();
                    this._renderTotals();
                }
            });
            this._items.addEventListener('change', (event) => {
                if (event.target.matches('[data-order-item-product]')) {
                    this._productChanged(event.target.closest('.order-item-row'));
                }
                this._renderTotals();
            });
            this._items.addEventListener('input', () => this._renderTotals());
            this._discountType.addEventListener('change', () => this._renderTotals());
            this._discountValue.addEventListener('input', () => this._renderTotals());
            ErpUI.debounceInput(this._search, () => {
                this._page = 1;
                this._loadOrders();
            });
            this._statusFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadOrders();
            });
            this._pagination.addEventListener('page-change', (event) => {
                this._page = event.detail.page;
                this._loadOrders();
            });
            this._body.addEventListener('click', (event) => {
                const row = event.target.closest('[data-order-id]');
                if (row) this._openDetail(Number(row.dataset.orderId));
            });
        }

        async _loadCatalog() {
            try {
                const [contacts, products] = await Promise.all([
                    ErpUI.api('/api/contacts'),
                    ErpUI.api('/api/products')
                ]);
                this._customers = contacts.customers || [];
                this._products = (products || []).filter((product) => Number(product.active) === 1);
                this._customerSelect.innerHTML = '<option value="0">Nuevo cliente / Consumidor final</option>' +
                    this._customers.map((customer) =>
                        `<option value="${Number(customer.id)}">${escape(customer.name)}</option>`).join('');
            } catch (error) {
                ErpUI.toast('No se pudo cargar el catálogo', error.message, 'error');
            }
        }

        _productOptions(selectedId = 0) {
            return '<option value="0">Seleccione un producto…</option>' +
                this._products.map((product) =>
                    `<option value="${Number(product.id)}" ${Number(product.id) === Number(selectedId) ? 'selected' : ''}>${escape(product.name)}${Number(product.is_combo) === 1 ? ' (combo)' : ''}</option>`).join('');
        }

        _findProduct(productId) {
            return this._products.find((product) => Number(product.id) === Number(productId));
        }

        _addItemRow(item = {}) {
            const row = document.createElement('div');
            row.className = 'order-item-row';
            row.innerHTML = `
                <select data-order-item-product>${this._productOptions(item.product_id)}</select>
                <input type="number" min="1" step="1" value="${Number(item.quantity) || 1}" data-order-item-quantity aria-label="Cantidad">
                <input type="number" min="0" step="0.01" value="${item.unit_price != null ? Number(item.unit_price).toFixed(2) : ''}" data-order-item-price placeholder="Precio" aria-label="Precio unitario">
                <button class="btn ghost small" type="button" data-order-item-remove>Quitar</button>
                <div class="order-item-stock" data-order-item-stock></div>`;
            this._items.append(row);
            if (item.product_id) {
                this._updateStockNote(row);
            }
        }

        _productChanged(row) {
            if (!row) return;
            const product = this._findProduct(row.querySelector('[data-order-item-product]').value);
            if (product) {
                row.querySelector('[data-order-item-price]').value = Number(product.price || 0).toFixed(2);
            }
            this._updateStockNote(row);
        }

        _updateStockNote(row) {
            const product = this._findProduct(row.querySelector('[data-order-item-product]').value);
            const note = row.querySelector('[data-order-item-stock]');
            if (!product) {
                note.textContent = '';
                return;
            }
            if (Number(product.is_combo) === 1) {
                note.textContent = `Combo: disponibilidad calculada desde sus componentes (${number(product.stock, 0)}).`;
            } else {
                note.textContent = `Stock disponible: ${number(product.stock, 0)} unidades.`;
            }
        }

        _customerChanged() {
            const customerId = Number(this._customerSelect.value) || 0;
            const customer = this._customers.find((item) => Number(item.id) === customerId);
            this._customerName.value = customer?.name || '';
            this._customerType.value = customer?.type || 'Minorista';
            this._customerPhone.value = customer?.phone || '';
            this._customerEmail.value = customer?.email || '';
        }

        _getItems() {
            return Array.from(this._items.querySelectorAll('.order-item-row'))
                .map((row) => {
                    const productId = Number(row.querySelector('[data-order-item-product]').value) || 0;
                    const product = this._findProduct(productId);
                    const quantity = Number(row.querySelector('[data-order-item-quantity]').value) || 0;
                    const rawPrice = row.querySelector('[data-order-item-price]').value;
                    const unitPrice = rawPrice === '' ? Number(product?.price || 0) : Number(rawPrice);
                    return { product_id: productId, quantity, unit_price: unitPrice };
                })
                .filter((item) => item.product_id > 0);
        }

        _renderTotals() {
            const items = this._getItems();
            const subtotal = items.reduce((sum, item) => sum + item.quantity * item.unit_price, 0);
            const type = this._discountType.value;
            const value = Number(this._discountValue.value) || 0;
            let discount = 0;
            if (type === 'percent') discount = subtotal * Math.min(100, Math.max(0, value)) / 100;
            if (type === 'fixed') discount = Math.min(subtotal, Math.max(0, value));
            const total = Math.max(0, subtotal - discount);
            this._totals.innerHTML = `
                <span>Subtotal <b>${money(subtotal)}</b></span>
                ${discount > 0 ? `<span>Descuento <b>- ${money(discount)}</b></span>` : ''}
                <span class="grand">Total <b>${money(total)}</b></span>`;
        }

        _openForm(order = null) {
            this._editing = order ? Number(order.id) : 0;
            this._form.reset();
            this._formError.hidden = true;
            this._items.innerHTML = '';
            this._saveCustomerField.hidden = Boolean(order);
            this._customerName.disabled = Boolean(order);
            this._customerType.disabled = Boolean(order);
            this._customerPhone.disabled = Boolean(order);
            this._customerEmail.disabled = Boolean(order);
            this.querySelector('[data-order-submit]').textContent = order ? 'Guardar cambios' : 'Crear pedido';
            this._formModal.setTitle(order ? `Editar pedido #${order.id}` : 'Nuevo pedido');

            if (order) {
                this._customerSelect.value = String(Number(order.customer_id) || 0);
                this._customerName.value = order.customer === 'Consumidor final' ? '' : (order.customer || '');
                this._customerType.value = order.customer_type || 'Minorista';
                this._customerPhone.value = order.customer_phone || '';
                this._customerEmail.value = order.customer_email || '';
                this._payment.value = order.payment_method || 'Efectivo';
                this._state.value = order.status || 'pending';
                this._discountType.value = order.discount_type || 'none';
                this._discountValue.value = String(Number(order.discount_value) || 0);
                this._notes.value = order.notes || '';
                (order.items || []).forEach((item) => this._addItemRow(item));
            } else {
                this._customerSelect.value = '0';
                this._customerChanged();
                this._payment.value = 'Efectivo';
                this._state.value = 'pending';
                this._discountType.value = 'none';
                this._discountValue.value = '0';
                this._notes.value = '';
                this._addItemRow();
            }
            if (!this._items.querySelector('.order-item-row')) this._addItemRow();
            this._renderTotals();
            this._formModal.open();
        }

        async _submit(event) {
            event.preventDefault();
            const items = this._getItems();
            this._formError.hidden = true;
            if (!items.length) {
                this._formError.textContent = 'Agregue al menos un producto al pedido.';
                this._formError.hidden = false;
                return;
            }
            if (items.some((item) => item.quantity < 1)) {
                this._formError.textContent = 'Todas las cantidades deben ser mayores o iguales a 1.';
                this._formError.hidden = false;
                return;
            }
            if (items.some((item) => item.unit_price < 0)) {
                this._formError.textContent = 'Los precios no pueden ser negativos.';
                this._formError.hidden = false;
                return;
            }

            const submit = this.querySelector('[data-order-submit]');
            submit.disabled = true;
            const customerId = Number(this._customerSelect.value) || 0;
            const body = {
                customer_id: customerId,
                customer_name: this._customerName.value.trim(),
                customer_type: this._customerType.value,
                customer_phone: this._customerPhone.value.trim(),
                customer_email: this._customerEmail.value.trim(),
                payment_method: this._payment.value,
                notes: this._notes.value.trim(),
                discount_type: this._discountType.value,
                discount_value: Number(this._discountValue.value) || 0,
                status: this._state.value,
                save_customer: this._saveCustomer.checked ? 1 : 0,
                items
            };
            try {
                if (this._editing) {
                    delete body.customer_name;
                    delete body.customer_type;
                    delete body.customer_phone;
                    delete body.customer_email;
                    delete body.save_customer;
                    await ErpUI.api(`/api/orders/${this._editing}`, { method: 'PUT', body });
                    ErpUI.toast('Pedido actualizado', 'Los cambios se guardaron correctamente.');
                } else {
                    await ErpUI.api('/api/orders', { method: 'POST', body });
                    ErpUI.toast('Pedido creado', 'El pedido quedó registrado.');
                }
                this._formModal.close();
                await this._loadCatalog();
                await this._loadOrders();
            } catch (error) {
                this._formError.textContent = error.message;
                this._formError.hidden = false;
            } finally {
                submit.disabled = false;
            }
        }

        async _loadOrders() {
            const requestId = ++this._requestId;
            const params = new URLSearchParams({
                q: this._search.value.trim(),
                status: this._statusFilter.value || 'all',
                page: String(this._page),
                per_page: '8'
            });
            try {
                const payload = await ErpUI.api(`/api/orders?${params}`);
                if (requestId !== this._requestId) return;
                this._page = Number(payload.page) || 1;
                this._pages = Number(payload.pages) || 1;
                this._renderOrders(payload.items || [], payload.total || 0);
            } catch (error) {
                if (requestId !== this._requestId) return;
                this._body.innerHTML = '';
                this._empty.hidden = false;
                this._empty.querySelector('strong').textContent = 'No se pudieron cargar los pedidos';
                this._empty.querySelector('span').textContent = error.message;
            }
        }

        _statusLabel(status) {
            if (status === 'finished') return 'Finalizado';
            if (status === 'cancel') return 'Cancelado';
            return 'Pendiente';
        }

        _renderOrders(items, total) {
            this._count.textContent = `${total} pedido${total === 1 ? '' : 's'}`;
            this._pagination.setData(this._page, this._pages);
            this._empty.hidden = items.length > 0;
            this._body.innerHTML = items.map((order) => `
                <tr class="order-row" data-order-id="${Number(order.id)}">
                    <td>#${Number(order.id)}</td>
                    <td>${escape(ErpUI.formatDateTime(order.date))}</td>
                    <td>${escape(order.customer)}</td>
                    <td>${number(order.items, 0)}</td>
                    <td>${number(order.units, 0)}</td>
                    <td>${money(order.total)}</td>
                    <td><span class="order-status-pill ${escape(order.status)}">${this._statusLabel(order.status)}</span></td>
                </tr>`).join('');
        }

        async _openDetail(orderId) {
            try {
                const order = await ErpUI.api(`/api/orders/${orderId}`);
                this._currentOrder = order;
                const rows = (order.items || []).map((item) => `
                    <tr>
                        <td>${escape(item.product_name)}${Number(item.is_combo) === 1 ? ' <span class="badge badge-soft">Combo</span>' : ''}</td>
                        <td>${number(item.quantity, 0)}</td>
                        <td>${money(item.unit_price)}</td>
                        <td>${money(item.subtotal)}</td>
                    </tr>`).join('');
                const actions = [];
                if (Number(order.stock_applied) === 0) actions.push('<button class="btn primary small" type="button" data-order-action="edit">Editar</button>');
                if (order.status !== 'finished') actions.push('<button class="btn ghost small" type="button" data-order-action="finish">Finalizar</button>');
                if (order.status === 'finished') actions.push('<button class="btn ghost small" type="button" data-order-action="invoice">Facturar / PDF</button>');
                if (order.status !== 'pending') actions.push('<button class="btn ghost small" type="button" data-order-action="reopen">Reabrir</button>');
                if (order.status !== 'cancel') actions.push('<button class="btn ghost small" type="button" data-order-action="cancel">Cancelar</button>');
                if (Number(order.stock_applied) === 0) actions.push('<button class="btn ghost small" type="button" data-order-action="delete">Eliminar</button>');

                this._detailModal.setTitle(`Pedido #${order.id}`);
                this._detailModal.setBody(`
                    <div class="inline-actions">
                        <span class="order-status-pill ${escape(order.status)}">${this._statusLabel(order.status)}</span>
                        <span class="badge badge-soft">${escape(ErpUI.formatDateTime(order.date))}</span>
                    </div>
                    <div class="detail-grid">
                        <div class="detail-metric"><span>Cliente</span><strong>${escape(order.customer)}</strong></div>
                        <div class="detail-metric"><span>Pago</span><strong>${escape(order.payment_method)}</strong></div>
                        <div class="detail-metric"><span>Descuento</span><strong>${money(order.discount)}</strong></div>
                        <div class="detail-metric"><span>Total</span><strong>${money(order.total)}</strong></div>
                    </div>
                    <div class="mini-list-row">
                        <div class="row-main">
                            <strong>${escape(order.customer_phone || order.customer_email || 'Sin datos de contacto')}</strong>
                            <small>${escape(order.customer_email || '')}</small>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table>
                            <thead><tr><th>Producto</th><th>Cantidad</th><th>Precio unitario</th><th>Subtotal</th></tr></thead>
                            <tbody>${rows || '<tr><td colspan="4" class="muted">Sin productos.</td></tr>'}</tbody>
                        </table>
                    </div>
                    ${order.notes ? `<p class="form-note">${escape(order.notes)}</p>` : ''}
                    <div class="order-detail-actions">${actions.join('')}</div>
                `);
                this._detailModal.setFooter('');
                this._detailModal.querySelectorAll('[data-order-action]').forEach((button) => {
                    button.addEventListener('click', () => this._handleAction(button.dataset.orderAction, order));
                });
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el pedido', error.message, 'error');
            }
        }

        async _handleAction(action, order) {
            if (action === 'edit') {
                this._detailModal.close();
                this._openForm(order);
                return;
            }
            if (action === 'invoice') {
                this._detailModal.close();
                await this._invoice.open('order', order.id);
                return;
            }
            if (action === 'delete') {
                if (!window.confirm(`¿Eliminar el pedido #${order.id}? Esta acción no se puede deshacer.`)) return;
                try {
                    await ErpUI.api(`/api/orders/${order.id}`, { method: 'DELETE' });
                    this._detailModal.close();
                    ErpUI.toast('Pedido eliminado', `El pedido #${order.id} fue eliminado.`);
                    await this._loadOrders();
                } catch (error) {
                    ErpUI.toast('No se pudo eliminar', error.message, 'error');
                }
                return;
            }
            const nextStatus = action === 'finish' ? 'finished' : action === 'cancel' ? 'cancel' : 'pending';
            try {
                await ErpUI.api(`/api/orders/${order.id}/status`, {
                    method: 'PUT',
                    body: { status: nextStatus }
                });
                this._detailModal.close();
                ErpUI.toast('Pedido actualizado', `El pedido #${order.id} pasó a ${this._statusLabel(nextStatus).toLowerCase()}.`);
                await this._loadOrders();
            } catch (error) {
                ErpUI.toast('No se pudo cambiar el estado', error.message, 'error');
            }
        }
    }

    customElements.define('erp-order-manager', OrderManager);
})();
