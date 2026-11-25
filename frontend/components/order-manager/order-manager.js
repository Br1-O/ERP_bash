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
            this._events = [];
            this._saleEventProducts = [];
            this._orderEventProducts = [];
            this._saleEventId = 0;
            this._orderEventId = 0;
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
            this._orderChannel = this.querySelector('[data-order-channel]');
            this._orderChannelField = this.querySelector('[data-order-channel-field]');
            this._orderEventField = this.querySelector('[data-order-event-field]');
            this._orderEvent = this.querySelector('[data-order-event]');
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
            this._saleModal = this.querySelector('#sale-form-modal');
            this._saleForm = this.querySelector('[data-sale-form]');
            this._saleCustomer = this.querySelector('[data-sale-customer]');
            this._saleChannel = this.querySelector('[data-sale-channel]');
            this._saleEventField = this.querySelector('[data-sale-event-field]');
            this._saleEvent = this.querySelector('[data-sale-event]');
            this._salePayment = this.querySelector('[data-sale-payment]');
            this._saleDiscountType = this.querySelector('[data-sale-discount-type]');
            this._saleDiscountValue = this.querySelector('[data-sale-discount-value]');
            this._saleDiscountValueField = this.querySelector('[data-sale-discount-value-field]');
            this._saleDiscountValueLabel = this.querySelector('[data-sale-discount-value-label]');
            this._saleItems = this.querySelector('[data-sale-items]');
            this._saleSubtotal = this.querySelector('[data-sale-subtotal]');
            this._saleDiscountRow = this.querySelector('[data-sale-discount-row]');
            this._saleDiscountLabel = this.querySelector('[data-sale-discount-label]');
            this._saleDiscount = this.querySelector('[data-sale-discount]');
            this._saleTotal = this.querySelector('[data-sale-total]');
            this._saleError = this.querySelector('[data-sale-error]');
            this._saleSubmit = this.querySelector('[data-sale-submit]');
            this._cancelModal = this.querySelector('#cancel-order-modal');
            this._cancelForm = this.querySelector('[data-cancel-form]');
            this._cancelSummary = this.querySelector('[data-cancel-summary]');
            this._cancelReason = this.querySelector('[data-cancel-reason]');
            this._cancelPin = this.querySelector('[data-cancel-pin]');
            this._cancelError = this.querySelector('[data-cancel-error]');
            this._cancelSubmit = this.querySelector('[data-cancel-submit]');

            this._bind();
            await this._loadCatalog();
            await this._loadOrders();
        }

        _bind() {
            this.querySelector('[data-create-sale]').addEventListener('click', () => this._openSaleForm());
            this.querySelector('[data-create-order]').addEventListener('click', () => this._openForm());
            this._saleChannel.addEventListener('change', () => this._syncSaleChannel());
            this._saleEvent.addEventListener('change', () => this._saleEventChanged());
            this._orderChannel.addEventListener('change', () => this._syncOrderChannel());
            this._orderEvent.addEventListener('change', () => this._orderEventChanged());
            this._saleForm.addEventListener('submit', (event) => this._submitSale(event));
            this.querySelector('[data-sale-add-item]').addEventListener('click', () => {
                this._addSaleItemRow();
                this._renderSaleTotals();
            });
            this.querySelector('[data-sale-cancel]').addEventListener('click', () => this._saleModal.close());
            this._saleDiscountType.addEventListener('change', () => this._syncSaleDiscount());
            this._saleDiscountValue.addEventListener('input', () => this._renderSaleTotals());
            this._saleItems.addEventListener('click', (event) => {
                const remove = event.target.closest('[data-sale-item-remove]');
                if (remove) {
                    remove.closest('.sale-item-row').remove();
                    if (!this._saleItems.querySelector('.sale-item-row')) this._addSaleItemRow();
                    this._renderSaleTotals();
                }
            });
            this._saleItems.addEventListener('change', (event) => {
                if (event.target.matches('[data-sale-item-product]')) {
                    this._saleProductChanged(event.target.closest('.sale-item-row'));
                }
                this._renderSaleTotals();
            });
            this._saleItems.addEventListener('input', () => this._renderSaleTotals());
            this.querySelector('[data-order-add-item]').addEventListener('click', () => {
                this._addItemRow();
                this._renderTotals();
            });
            this.querySelector('[data-order-cancel]').addEventListener('click', () => this._formModal.close());
            this.querySelector('[data-cancel-close]').addEventListener('click', () => this._cancelModal.close());
            this._cancelForm.addEventListener('submit', (event) => this._submitCancel(event));
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
                const [contacts, products, eventsPayload] = await Promise.all([
                    ErpUI.api('/api/contacts'),
                    ErpUI.api('/api/products'),
                    ErpUI.api('/api/events/active').catch(() => ({ items: [] }))
                ]);
                this._customers = contacts.customers || [];
                this._products = (products || []).filter((product) => Number(product.active) === 1);
                this._events = eventsPayload.items || [];
                this._customerSelect.innerHTML = '<option value="0">Nuevo cliente / Consumidor final</option>' +
                    this._customers.map((customer) =>
                        `<option value="${Number(customer.id)}">${escape(customer.name)}</option>`).join('');
            } catch (error) {
                ErpUI.toast('No se pudo cargar el catálogo', error.message, 'error');
            }
        }

        _productOptions(selectedId = 0) {
            return '<option value="0">Seleccione un producto…</option>' +
                this._orderAvailableProducts().map((product) =>
                    `<option value="${Number(product.id)}" ${Number(product.id) === Number(selectedId) ? 'selected' : ''}>${escape(product.name)}${Number(product.is_combo) === 1 ? ' (combo)' : ''} · ${number(product.stock, 0)} u.</option>`).join('');
        }

        _findOrderProduct(productId) {
            return this._orderAvailableProducts().find((product) => Number(product.id) === Number(productId))
                || this._findProduct(productId);
        }

        _findProduct(productId) {
            return this._products.find((product) => Number(product.id) === Number(productId));
        }

        _eventOptions(selectedId = 0) {
            if (!this._events.length) {
                return '<option value="0">No hay eventos activos</option>';
            }
            return '<option value="0">Seleccione un evento…</option>' + this._events.map((event) =>
                `<option value="${Number(event.id)}" ${Number(event.id) === Number(selectedId) ? 'selected' : ''}>${escape(event.name)} · ${escape(event.location || 'Sin ubicación')}</option>`).join('');
        }

        _syncSaleChannel() {
            const fair = this._saleChannel.value === 'FERIA';
            this._saleEventField.hidden = !fair;
            if (!fair) {
                this._saleEventId = 0;
                this._saleEventProducts = [];
                this._saleEvent.value = '0';
                this._refreshSaleRows();
                return;
            }
            this._saleEvent.innerHTML = this._eventOptions(this._saleEventId);
            if (!this._events.length) {
                ErpUI.toast('Sin eventos activos', 'Cree un evento para registrar ventas de feria.', 'error');
                this._saleChannel.value = 'LOCAL';
                this._saleEventField.hidden = true;
                this._saleEventId = 0;
                this._refreshSaleRows();
                return;
            }
            if (!this._saleEventId && this._events.length === 1) {
                this._saleEventId = Number(this._events[0].id);
                this._saleEvent.value = String(this._saleEventId);
            }
            this._saleEventChanged();
        }

        async _saleEventChanged() {
            const eventId = Number(this._saleEvent.value) || 0;
            this._saleEventId = eventId;
            if (!eventId) {
                this._saleEventProducts = [];
                this._refreshSaleRows();
                return;
            }
            try {
                const event = await ErpUI.api(`/api/events/${eventId}`);
                this._saleEventProducts = (event.products || []).map((product) => ({
                    ...product,
                    stock: Number(product.available) || 0
                }));
                this._refreshSaleRows();
            } catch (error) {
                this._saleEventProducts = [];
                this._refreshSaleRows();
                ErpUI.toast('No se pudo cargar el evento', error.message, 'error');
            }
        }

        _saleAvailableProducts() {
            if (this._saleEventId > 0) {
                return this._saleEventProducts.filter((product) => Number(product.stock) > 0);
            }
            return this._products.filter((product) =>
                Number(product.active) === 1 && Number(product.stock) > 0);
        }

        _refreshSaleRows() {
            this._saleItems.innerHTML = '';
            this._addSaleItemRow();
            this._renderSaleTotals();
        }

        _syncOrderChannel() {
            const fair = this._orderChannel.value === 'FERIA';
            this._orderEventField.hidden = !fair;
            if (!fair) {
                this._orderEventId = 0;
                this._orderEventProducts = [];
                this._orderEvent.value = '0';
                this._refreshOrderRows();
                return;
            }
            this._orderEvent.innerHTML = this._eventOptions(this._orderEventId);
            if (!this._events.length) {
                ErpUI.toast('Sin eventos activos', 'Cree un evento para registrar pedidos de feria.', 'error');
                this._orderChannel.value = 'LOCAL';
                this._orderEventField.hidden = true;
                this._orderEventId = 0;
                return;
            }
            if (!this._orderEventId && this._events.length === 1) {
                this._orderEventId = Number(this._events[0].id);
                this._orderEvent.value = String(this._orderEventId);
            }
            this._orderEventChanged();
        }

        async _orderEventChanged() {
            const eventId = Number(this._orderEvent.value) || 0;
            this._orderEventId = eventId;
            if (!eventId) {
                this._orderEventProducts = [];
                this._refreshOrderRows();
                return;
            }
            try {
                const event = await ErpUI.api(`/api/events/${eventId}`);
                this._orderEventProducts = (event.products || []).map((product) => ({
                    ...product,
                    stock: Number(product.available) || 0
                }));
            } catch (error) {
                this._orderEventProducts = [];
                ErpUI.toast('No se pudo cargar el evento', error.message, 'error');
            }
            this._refreshOrderRows();
        }

        _refreshOrderRows() {
            const rows = Array.from(this._items.querySelectorAll('.order-item-row')).map((row) => ({
                product_id: Number(row.querySelector('[data-order-item-product]').value) || 0,
                quantity: Number(row.querySelector('[data-order-item-quantity]').value) || 1,
                unit_price: row.querySelector('[data-order-item-price]').value
            }));
            if (!rows.length) return;
            this._items.innerHTML = '';
            rows.forEach((item) => this._addItemRow(item));
            this._renderTotals();
        }

        _orderAvailableProducts() {
            if (this._orderEventId > 0) return this._orderEventProducts;
            return this._products.filter((product) => Number(product.active) === 1);
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
            const product = this._findOrderProduct(row.querySelector('[data-order-item-product]').value);
            if (product) {
                row.querySelector('[data-order-item-price]').value = Number(product.price || 0).toFixed(2);
            }
            this._updateStockNote(row);
        }

        _updateStockNote(row) {
            const product = this._findOrderProduct(row.querySelector('[data-order-item-product]').value);
            const note = row.querySelector('[data-order-item-stock]');
            if (!product) {
                note.textContent = '';
                return;
            }
            const scope = this._orderEventId > 0 ? 'Disponible en el evento' : 'Stock disponible';
            if (Number(product.is_combo) === 1) {
                note.textContent = `Combo: disponibilidad calculada desde sus componentes (${number(product.stock, 0)}).`;
            } else {
                note.textContent = `${scope}: ${number(product.stock, 0)} unidades.`;
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

        _saleProductOptions(selectedId = 0) {
            const available = this._saleAvailableProducts();
            return '<option value="0">Seleccione un producto…</option>' + available.map((product) => {
                const selected = Number(product.id) === Number(selectedId) ? ' selected' : '';
                return `<option value="${Number(product.id)}" data-price="${Number(product.price) || 0}" data-stock="${Number(product.stock) || 0}"${selected}>${escape(product.name)}${Number(product.is_combo) === 1 ? ' (combo)' : ''} · ${money(product.price)} · ${number(product.stock)} u.</option>`;
            }).join('');
        }

        _addSaleItemRow(productId = 0) {
            const available = this._saleAvailableProducts();
            if (!available.length) {
                ErpUI.toast('Sin stock', this._saleEventId > 0 ? 'El evento no tiene stock disponible para vender.' : 'No hay productos disponibles para vender.', 'error');
                return;
            }
            const selectedId = Number(productId) || Number(available[0].id);
            const row = document.createElement('div');
            row.className = 'sale-item-row';
            row.innerHTML = `
                <label class="field">
                    <span>Producto</span>
                    <select data-sale-item-product>${this._saleProductOptions(selectedId)}</select>
                </label>
                <label class="field">
                    <span>Cantidad</span>
                    <input type="number" min="1" step="1" value="1" data-sale-item-quantity>
                </label>
                <span class="line-total">$0.00</span>
                <button type="button" class="icon-button remove-item" data-sale-item-remove aria-label="Quitar ítem">×</button>`;
            this._saleItems.append(row);
            this._updateSaleLine(row);
        }

        _saleProductChanged(row) {
            if (!row) return;
            const select = row.querySelector('[data-sale-item-product]');
            const quantity = row.querySelector('[data-sale-item-quantity]');
            const stock = Number(select.selectedOptions[0]?.dataset.stock) || 0;
            if (Number(quantity.value) > stock) quantity.value = String(stock);
            this._updateSaleLine(row);
        }

        _updateSaleLine(row) {
            const select = row.querySelector('[data-sale-item-product]');
            const quantity = row.querySelector('[data-sale-item-quantity]');
            const lineTotal = row.querySelector('.line-total');
            const option = select?.selectedOptions[0];
            const price = Number(option?.dataset.price) || 0;
            const stock = Number(option?.dataset.stock) || 1;
            let value = Number(quantity?.value) || 0;
            if (value > stock) {
                value = stock;
                quantity.value = String(stock);
            }
            const billing = window.ErpBilling;
            lineTotal.textContent = billing
                ? billing.Money.formatCents((billing.Money.toCents(price) || 0) * value)
                : money(price * value);
        }

        _saleTotals() {
            const billing = window.ErpBilling;
            let subtotalCents = 0;
            let subtotal = 0;
            this._saleItems.querySelectorAll('.sale-item-row').forEach((row) => {
                const option = row.querySelector('[data-sale-item-product]')?.selectedOptions[0];
                const quantity = Number(row.querySelector('[data-sale-item-quantity]')?.value) || 0;
                const price = Number(option?.dataset.price) || 0;
                if (billing) {
                    subtotalCents += (billing.Money.toCents(price) || 0) * quantity;
                } else {
                    subtotal += price * quantity;
                }
            });
            const type = this._saleDiscountType.value || 'none';
            const rawValue = this._saleDiscountValue.value || '0';
            if (billing) {
                return { billing, subtotalCents, type, rawValue, result: billing.apply(type, subtotalCents, rawValue) };
            }
            const fallbackSubtotal = Math.max(0, subtotal);
            return {
                billing: null,
                subtotalCents: Math.round(fallbackSubtotal * 100),
                type,
                rawValue,
                result: { discountCents: 0, totalCents: Math.round(fallbackSubtotal * 100) }
            };
        }

        _syncSaleDiscount() {
            const type = this._saleDiscountType.value || 'none';
            const strategy = window.ErpBilling?.strategies?.[type];
            this._saleDiscountValueField.hidden = type === 'none';
            this._saleDiscountValue.disabled = type === 'none';
            if (type === 'none') this._saleDiscountValue.value = '0';
            this._saleDiscountValueLabel.textContent = strategy?.valueLabel || 'Valor del descuento';
            this._renderSaleTotals();
        }

        _renderSaleTotals() {
            const totals = this._saleTotals();
            const billing = totals.billing;
            this._saleSubtotal.textContent = billing
                ? billing.Money.formatCents(totals.subtotalCents)
                : money(totals.subtotalCents / 100);
            this._saleDiscountRow.hidden = totals.type === 'none';
            this._saleDiscountLabel.textContent = totals.type === 'percent' ? 'Descuento porcentual' : 'Descuento';
            this._saleDiscount.textContent = totals.result
                ? `-${billing ? billing.Money.formatCents(totals.result.discountCents) : money(totals.result.discountCents / 100)}`
                : '—';
            this._saleTotal.textContent = totals.result
                ? (billing ? billing.Money.formatCents(totals.result.totalCents) : money(totals.result.totalCents / 100))
                : '—';
        }

        async _refreshActiveEvents() {
            try {
                const payload = await ErpUI.api('/api/events/active');
                this._events = payload.items || [];
            } catch (error) {
                this._events = [];
            }
        }

        async _openSaleForm() {
            await this._refreshActiveEvents();
            this._saleForm.reset();
            this._saleCustomer.innerHTML = '<option value="0">Consumidor final</option>' +
                (this._customers || []).map((customer) =>
                    `<option value="${Number(customer.id)}">${escape(customer.name)} · ${escape(customer.type)}</option>`).join('');
            this._saleChannel.value = 'LOCAL';
            this._saleEvent.innerHTML = this._eventOptions();
            this._saleEventField.hidden = true;
            this._saleEventId = 0;
            this._saleEventProducts = [];
            this._salePayment.value = 'Efectivo';
            this._saleDiscountType.value = 'none';
            this._saleDiscountValue.value = '0';
            this._saleItems.innerHTML = '';
            this._saleError.hidden = true;
            this._saleError.textContent = '';
            this._saleSubmit.disabled = false;
            this._saleSubmit.textContent = 'Registrar venta';
            this._saleModal.setTitle('Nueva venta');
            this._syncSaleDiscount();
            this._addSaleItemRow();
            this._renderSaleTotals();
            if (!this._saleAvailableProducts().length) {
                this._saleError.textContent = 'No hay productos con stock disponible para vender.';
                this._saleError.hidden = false;
            }
            this._saleModal.open();
            this._saleCustomer.focus();
        }

        async _submitSale(event) {
            event.preventDefault();
            const items = Array.from(this._saleItems.querySelectorAll('.sale-item-row'))
                .map((row) => ({
                    product_id: Number(row.querySelector('[data-sale-item-product]')?.value) || 0,
                    quantity: Number(row.querySelector('[data-sale-item-quantity]')?.value) || 0
                }))
                .filter((item) => item.product_id > 0 && item.quantity > 0);

            this._saleError.hidden = true;
            if (!items.length) {
                this._saleError.textContent = 'Agregue al menos un producto con cantidad válida.';
                this._saleError.hidden = false;
                return;
            }
            if (this._saleChannel.value === 'FERIA' && !this._saleEventId) {
                this._saleError.textContent = 'Seleccione un evento activo para la venta de feria.';
                this._saleError.hidden = false;
                return;
            }

            const totals = this._saleTotals();
            if (!totals.result) {
                this._saleError.textContent = 'El descuento ingresado no es válido para el subtotal de la venta.';
                this._saleError.hidden = false;
                return;
            }

            this._saleSubmit.disabled = true;
            this._saleSubmit.textContent = 'Registrando…';
            try {
                const payload = await ErpUI.api('/api/sales', {
                    method: 'POST',
                    body: {
                        customer_id: Number(this._saleCustomer.value) || 0,
                        payment_method: this._salePayment.value || 'Efectivo',
                        discount_type: totals.type,
                        discount_value: totals.type === 'none' ? '0' : totals.rawValue,
                        event_id: this._saleChannel.value === 'FERIA' ? this._saleEventId : 0,
                        items
                    }
                });
                this._saleModal.close();
                ErpUI.toast('Venta registrada', `Venta #${payload.sale_id} por ${money(payload.total)}.`);
                await this._loadCatalog();
                await this._loadOrders();
            } catch (error) {
                this._saleError.textContent = error.message;
                this._saleError.hidden = false;
            } finally {
                this._saleSubmit.disabled = false;
                this._saleSubmit.textContent = 'Registrar venta';
            }
        }

        _getItems() {
            return Array.from(this._items.querySelectorAll('.order-item-row'))
                .map((row) => {
                    const productId = Number(row.querySelector('[data-order-item-product]').value) || 0;
                    const product = this._findOrderProduct(productId);
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

        async _openForm(order = null) {
            if (!order) await this._refreshActiveEvents();
            this._editing = order ? Number(order.id) : 0;
            this._form.reset();
            this._formError.hidden = true;
            this._items.innerHTML = '';
            this._orderChannelField.hidden = Boolean(order);
            this._orderEventField.hidden = true;
            this._orderChannel.value = 'LOCAL';
            this._orderEventId = 0;
            this._orderEventProducts = [];
            this._orderEvent.innerHTML = this._eventOptions();
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
                this._state.innerHTML = this._stateOptions(order);
                this._state.value = order.status || 'pending';
                this._discountType.value = order.discount_type || 'none';
                this._discountValue.value = String(Number(order.discount_value) || 0);
                this._notes.value = order.notes || '';
                (order.items || []).forEach((item) => this._addItemRow(item));
            } else {
                this._customerSelect.value = '0';
                this._customerChanged();
                this._payment.value = 'Efectivo';
                this._state.innerHTML = this._stateOptions();
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
            if (!this._editing && this._orderChannel.value === 'FERIA' && !this._orderEventId) {
                this._formError.textContent = 'Seleccione un evento activo para el pedido de feria.';
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
                event_id: !this._editing && this._orderChannel.value === 'FERIA' ? this._orderEventId : 0,
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
                this._empty.querySelector('strong').textContent = 'No se pudieron cargar las ventas y pedidos';
                this._empty.querySelector('span').textContent = error.message;
            }
        }

        _statusLabel(status) {
            const labels = {
                draft: 'Borrador',
                pending: 'Pendiente',
                preparing: 'En preparación',
                confirmed: 'Confirmado',
                paid: 'Pagado',
                delivered: 'Entregado',
                cancel: 'Anulado',
                finished: 'Finalizado'
            };
            return labels[status] || status || 'Pendiente';
        }

        _stockLabel(order) {
            if (order.status === 'cancel') return 'Registro anulado';
            return Number(order.stock_applied) === 1 ? 'Stock aplicado' : 'Stock sin aplicar';
        }

        _stateOptions(order) {
            const transitions = {
                draft: ['pending', 'preparing', 'confirmed'],
                pending: ['preparing', 'confirmed'],
                preparing: ['confirmed'],
                confirmed: ['paid', 'delivered'],
                paid: ['delivered']
            };
            const initial = ['draft', 'pending', 'preparing', 'confirmed'];
            const stages = order ? [order.status, ...(transitions[order.status] || [])] : initial;
            return [...new Set(stages)].map((stage) =>
                `<option value="${stage}">${this._statusLabel(stage)}</option>`).join('');
        }

        _typeLabel(type) {
            return type === 'direct' ? 'Venta directa' : 'Pedido';
        }

        _renderOrders(items, total) {
            this._count.textContent = `${total} registro${total === 1 ? '' : 's'}`;
            this._pagination.setData(this._page, this._pages);
            this._empty.hidden = items.length > 0;
            this._body.innerHTML = items.map((order) => {
                const typeLabel = this._typeLabel(order.order_type);
                const typeClass = order.order_type === 'direct' ? 'badge-accent' : 'badge-soft';
                const channelLabel = order.channel === 'FERIA'
                    ? `Feria${order.event_name ? ` · ${escape(order.event_name)}` : ''}`
                    : 'Local';
                return `
                <tr class="order-row" data-order-id="${Number(order.id)}">
                    <td>#${Number(order.id)}</td>
                    <td><span class="badge ${typeClass}">${typeLabel}</span>
                        <small class="order-stock-note">${channelLabel}</small></td>
                    <td>${escape(ErpUI.formatDateTime(order.date))}</td>
                    <td>${escape(order.customer)}</td>
                    <td>${number(order.items, 0)}</td>
                    <td>${number(order.units, 0)}</td>
                    <td>${money(order.total)}</td>
                    <td>
                        <span class="order-status-pill ${escape(order.status)}">${this._statusLabel(order.status)}</span>
                        <small class="order-stock-note">${this._stockLabel(order)}</small>
                    </td>
                </tr>`;
            }).join('');
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
                const orderType = order.order_type === 'direct' ? 'direct' : 'order';
                const isOrder = orderType === 'order';
                const typeLabel = this._typeLabel(orderType);
                const actions = [];
                const early = ['draft', 'pending', 'preparing'].includes(order.status);
                const final = ['paid', 'delivered'].includes(order.status);
                if (isOrder && early) {
                    actions.push('<button class="btn primary small" type="button" data-order-action="edit">Editar</button>');
                }
                if (isOrder && order.status === 'draft') {
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:pending">Marcar pendiente</button>');
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:preparing">En preparación</button>');
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:confirmed">Confirmar pedido</button>');
                } else if (isOrder && order.status === 'pending') {
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:preparing">En preparación</button>');
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:confirmed">Confirmar pedido</button>');
                } else if (isOrder && order.status === 'preparing') {
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:confirmed">Confirmar pedido</button>');
                } else if (isOrder && order.status === 'confirmed') {
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:paid">Marcar pagado</button>');
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:delivered">Marcar entregado</button>');
                } else if (isOrder && order.status === 'paid') {
                    actions.push('<button class="btn ghost small" type="button" data-order-action="stage:delivered">Marcar entregado</button>');
                }
                if (order.status !== 'cancel') {
                    actions.push('<button class="btn ghost small" type="button" data-order-action="cancel">Anular</button>');
                }
                if (final || (order.order_type === 'direct' && order.status === 'delivered')) {
                    actions.push('<button class="btn ghost small" type="button" data-order-action="invoice">Facturar / PDF</button>');
                }

                this._detailModal.setTitle(`${typeLabel} #${order.id}`);
                this._detailModal.setBody(`
                    <div class="inline-actions">
                        <span class="badge ${isOrder ? 'badge-soft' : 'badge-accent'}">${typeLabel}</span>
                        <span class="order-status-pill ${escape(order.status)}">${this._statusLabel(order.status)}</span>
                        <span class="badge ${order.channel === 'FERIA' ? 'badge-accent' : 'badge-soft'}">${order.channel === 'FERIA' ? `Feria${order.event_name ? ` · ${escape(order.event_name)}` : ''}` : 'Local'}</span>
                        <span class="badge badge-soft">${escape(this._stockLabel(order))}</span>
                        <span class="badge badge-soft">${escape(ErpUI.formatDateTime(order.date))}</span>
                    </div>
                    ${order.status === 'cancel' ? `
                    <div class="cancel-detail">
                        <strong>Registro anulado</strong>
                        <p>${escape(order.cancel_reason || 'Sin motivo registrado.')}</p>
                        <small>Anulado por ${escape(order.cancelled_by || '—')} · Autorizado por ${escape(order.cancel_authorized_by || '—')} · ${escape(ErpUI.formatDateTime(order.cancelled_at))}</small>
                    </div>` : ''}
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
                    ${isOrder ? '' : '<p class="form-note">Venta registrada desde el punto de venta. Este registro es de solo lectura; puede anularse con motivo y PIN o facturarse cuando esté entregado.</p>'}
                    <div class="order-detail-actions">${actions.join('')}</div>
                `);
                this._detailModal.setFooter('');
                this._detailModal.querySelectorAll('[data-order-action]').forEach((button) => {
                    button.addEventListener('click', () => this._handleAction(button.dataset.orderAction, order));
                });
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el registro', error.message, 'error');
            }
        }

        async _handleAction(action, order) {
            if (action === 'invoice') {
                this._detailModal.close();
                await this._invoice.open(order.order_type === 'direct' ? 'sale' : 'order', order.id);
                return;
            }
            if (action === 'cancel') {
                this._openCancel(order);
                return;
            }
            if (order.order_type === 'direct') {
                ErpUI.toast('Registro de solo lectura', 'Las ventas directas no se editan desde este listado.', 'error');
                return;
            }
            if (action === 'edit') {
                this._detailModal.close();
                this._openForm(order);
                return;
            }
            if (action.startsWith('stage:')) {
                const nextStage = action.slice(6);
                try {
                    await ErpUI.api(`/api/orders/${order.id}/status`, {
                        method: 'PUT',
                        body: { status: nextStage }
                    });
                    this._detailModal.close();
                    ErpUI.toast('Pedido actualizado', `El pedido #${order.id} pasó a ${this._statusLabel(nextStage).toLowerCase()}.`);
                    await this._loadOrders();
                } catch (error) {
                    ErpUI.toast('No se pudo cambiar el estado', error.message, 'error');
                }
            }
        }

        async _openCancel(order) {
            this._cancelOrder = order;
            this._cancelForm.reset();
            this._cancelError.hidden = true;
            this._cancelError.textContent = '';
            this._cancelSummary.textContent = `Se anulará ${order.order_type === 'direct' ? 'la venta' : 'el pedido'} #${order.id} por ${money(order.total)}. El stock se restituirá automáticamente si estaba aplicado.`;
            await this._cancelModal.ready();
            this._cancelModal.setTitle(`Anular ${order.order_type === 'direct' ? 'venta' : 'pedido'} #${order.id}`);
            this._cancelModal.open();
            window.setTimeout(() => this._cancelReason.focus(), 80);
        }

        async _submitCancel(event) {
            event.preventDefault();
            const order = this._cancelOrder;
            if (!order) return;
            this._cancelError.hidden = true;
            this._cancelSubmit.disabled = true;
            this._cancelSubmit.textContent = 'Anulando…';
            try {
                const endpoint = order.order_type === 'direct'
                    ? `/api/sales/${order.id}/cancel`
                    : `/api/orders/${order.id}/cancel`;
                await ErpUI.api(endpoint, {
                    method: 'POST',
                    body: { reason: this._cancelReason.value.trim(), pin: this._cancelPin.value }
                });
                this._cancelModal.close();
                this._detailModal.close();
                ErpUI.toast('Registro anulado', `La operación #${order.id} fue anulada y quedó en auditoría.`);
                await this._loadOrders();
            } catch (error) {
                this._cancelError.textContent = error.message;
                this._cancelError.hidden = false;
            } finally {
                this._cancelSubmit.disabled = false;
                this._cancelSubmit.textContent = 'Anular registro';
            }
        }
    }

    customElements.define('erp-order-manager', OrderManager);
})();
