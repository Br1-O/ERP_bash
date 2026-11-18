(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;
    const dateTime = ErpUI.formatDateTime;

    const entityRefs = {
        Products: 'product',
        Inputs: 'input',
        Customers: 'customer',
        Suppliers: 'supplier',
        Sales: 'sale',
        SaleItems: 'sale',
        Purchases: 'purchase',
        PurchaseItems: 'purchase',
        ProductRecipe: 'product',
        ProductRecipeStep: 'product',
        ComboItems: 'product',
        ProductionBatches: 'product',
        ProductionInputs: 'input'
    };

    const primaryKeys = {
        product: ['id', 'product_id', 'combo_id', 'component_id'],
        input: ['id', 'input_id'],
        customer: ['id', 'customer_id'],
        supplier: ['id', 'supplier_id'],
        sale: ['sale_id'],
        purchase: ['purchase_id']
    };

    const payloadRefs = {
        product_id: 'product',
        component_id: 'product',
        combo_id: 'product',
        input_id: 'input',
        customer_id: 'customer',
        supplier_id: 'supplier',
        sale_id: 'sale',
        purchase_id: 'purchase'
    };

    const refLabels = {
        product: 'Producto',
        input: 'Insumo',
        customer: 'Cliente',
        supplier: 'Proveedor',
        sale: 'Venta/pedido',
        purchase: 'Compra',
        user: 'Usuario'
    };

    function parsePayload(payload) {
        return String(payload || '')
            .split(';')
            .map((part) => {
                const index = part.indexOf('=');
                if (index === -1) return [part.trim(), ''];
                return [part.slice(0, index).trim(), part.slice(index + 1).trim()];
            })
            .filter(([key]) => key);
    }

    class AuditManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._page = 1;
            this._pages = 1;
            this._requestId = 0;
            this._entries = new Map();
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/audit-manager/audit-manager.html');
            this._body = this.querySelector('[data-audit-body]');
            this._empty = this.querySelector('[data-audit-empty]');
            this._count = this.querySelector('[data-audit-count]');
            this._search = this.querySelector('[data-audit-search]');
            this._pagination = this.querySelector('[data-audit-pagination]');
            this._entryModal = this.querySelector('#audit-entry-modal');
            this._entityModal = this.querySelector('#audit-entity-modal');
            this._bind();
            await this._load();
        }

        _bind() {
            ErpUI.debounceInput(this._search, () => {
                this._page = 1;
                this._load();
            });
            this._pagination.addEventListener('page-change', (event) => {
                this._page = event.detail.page;
                this._load();
            });
            this._body.addEventListener('click', (event) => {
                const reference = event.target.closest('[data-audit-ref]');
                if (reference) {
                    this._openReference(reference.dataset.auditRef);
                    return;
                }
                const entryButton = event.target.closest('[data-audit-entry]');
                if (entryButton) {
                    this._openEntry(Number(entryButton.dataset.auditEntry));
                    return;
                }
                const row = event.target.closest('[data-audit-id]');
                if (row) this._openEntry(Number(row.dataset.auditId));
            });
        }

        async _load() {
            const requestId = ++this._requestId;
            const params = new URLSearchParams({
                q: this._search.value.trim(),
                page: String(this._page),
                per_page: '12'
            });
            try {
                const payload = await ErpUI.api(`/api/audit?${params}`);
                if (requestId !== this._requestId) return;
                this._page = Number(payload.page) || 1;
                this._pages = Number(payload.pages) || 1;
                this._render(payload.items || [], payload.total || 0);
            } catch (error) {
                if (requestId !== this._requestId) return;
                this._body.innerHTML = '';
                this._empty.hidden = false;
                this._empty.querySelector('strong').textContent = 'No se pudo cargar la auditoría';
                this._empty.querySelector('span').textContent = error.message;
            }
        }

        _statusClass(status) {
            if (status === 'DONE') return 'badge-success';
            if (status === 'ERROR' || status === 'FAILED') return 'badge-danger';
            return 'badge-warning';
        }

        _stageLabel(status) {
            const labels = {
                draft: 'Borrador',
                pending: 'Pendiente',
                preparing: 'En preparación',
                confirmed: 'Confirmado',
                paid: 'Pagado',
                delivered: 'Entregado',
                cancel: 'Anulado'
            };
            return labels[status] || status || '—';
        }

        _refForPayloadKey(entity, key) {
            if (key === 'id' && entityRefs[entity]) return entityRefs[entity];
            return payloadRefs[key] || '';
        }

        _refLabel(type, id) {
            return `${refLabels[type] || type} #${id}`;
        }

        _userLink(username) {
            const name = username || 'sistema';
            if (name === 'sistema') return '<span class="audit-chip">sistema</span>';
            return `<button class="audit-link" type="button" data-audit-ref="user:${escape(name)}">${escape(name)}</button>`;
        }

        _referenceChips(entry) {
            const references = [];
            const seen = new Set();
            parsePayload(entry.payload).forEach(([key, value]) => {
                if (!value) return;
                const type = this._refForPayloadKey(entry.entity, key);
                if (!type) return;
                const ref = `${type}:${value}`;
                if (seen.has(ref)) return;
                seen.add(ref);
                references.push(`<button class="audit-ref" type="button" data-audit-ref="${escape(ref)}">${escape(this._refLabel(type, value))}</button>`);
            });
            return references.length
                ? references.join('')
                : '<span class="audit-chip">Sin referencias</span>';
        }

        _primaryReference(entry) {
            const type = entityRefs[entry.entity];
            if (!type) return null;
            const pairs = parsePayload(entry.payload);
            const keys = primaryKeys[type] || ['id'];
            for (const key of keys) {
                const match = pairs.find(([name, value]) => name === key && value);
                if (match) return { type, id: match[1] };
            }
            return null;
        }

        _render(items, total) {
            this._entries.clear();
            items.forEach((entry) => this._entries.set(Number(entry.id), entry));
            this._count.textContent = `${total} movimiento${total === 1 ? '' : 's'}`;
            this._pagination.setData(this._page, this._pages);
            this._empty.hidden = items.length > 0;
            this._body.innerHTML = items.map((entry) => {
                const primary = this._primaryReference(entry);
                const entity = primary
                    ? `<button class="audit-link" type="button" data-audit-ref="${escape(`${primary.type}:${primary.id}`)}">${escape(entry.entity)}</button>`
                    : escape(entry.entity);
                return `
                    <tr data-audit-id="${Number(entry.id)}">
                        <td>${escape(dateTime(entry.timestamp))}</td>
                        <td>${this._userLink(entry.user)}</td>
                        <td><strong>${escape(entry.action)}</strong></td>
                        <td>${entity}</td>
                        <td><div class="audit-ref-list">${this._referenceChips(entry)}</div></td>
                        <td><span class="badge ${this._statusClass(entry.status)}">${escape(entry.status)}</span></td>
                        <td>
                            <span class="audit-payload" title="${escape(entry.payload || 'Sin detalle')}">${escape(entry.payload || 'Sin detalle')}</span>
                            <button class="btn ghost small audit-detail-button" type="button" data-audit-entry="${Number(entry.id)}">Ver detalle</button>
                        </td>
                    </tr>`;
            }).join('');
        }

        async _openEntry(entryId) {
            const entry = this._entries.get(entryId);
            if (!entry) return;
            const pairs = parsePayload(entry.payload);
            const payloadText = pairs.length
                ? pairs.map(([key, value]) => `${key}: ${value}`).join('\n')
                : 'Sin detalle adicional.';
            const payloadTable = pairs.length
                ? pairs.map(([key, value]) => `<tr><td>${escape(key)}</td><td>${escape(value)}</td></tr>`).join('')
                : '<tr><td colspan="2" class="muted">Sin detalle adicional.</td></tr>';

            this._entryModal.setTitle(`Movimiento #${entry.id}`);
            this._entryModal.setBody(`
                <div class="inline-actions">
                    <span class="badge badge-soft">${escape(entry.action)}</span>
                    <span class="badge ${this._statusClass(entry.status)}">${escape(entry.status)}</span>
                    <span class="badge badge-soft">${escape(dateTime(entry.timestamp))}</span>
                </div>
                <div class="audit-entry-meta">
                    <div class="detail-metric"><span>Usuario</span><strong>${this._userLink(entry.user)}</strong></div>
                    <div class="detail-metric"><span>Entidad</span><strong>${escape(entry.entity)}</strong></div>
                    <div class="detail-metric"><span>Acción</span><strong>${escape(entry.action)}</strong></div>
                    <div class="detail-metric"><span>Estado</span><strong>${escape(entry.status)}</strong></div>
                </div>
                <h4 class="detail-section-title">Referencias</h4>
                <div class="audit-ref-list">${this._referenceChips(entry)}</div>
                <h4 class="detail-section-title">Detalle del payload</h4>
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Campo</th><th>Valor</th></tr></thead>
                        <tbody>${payloadTable}</tbody>
                    </table>
                </div>
                <div class="audit-entry-payload">${escape(payloadText)}</div>
                <details class="audit-raw-payload">
                    <summary>Ver payload original</summary>
                    <pre>${escape(entry.payload || 'Sin payload')}</pre>
                </details>
            `);
            this._entryModal.setFooter('');
            this._entryModal.querySelectorAll('[data-audit-ref]').forEach((button) => {
                button.addEventListener('click', () => {
                    this._entryModal.close();
                    this._openReference(button.dataset.auditRef);
                });
            });
            await this._entryModal.open();
        }

        async _openReference(ref) {
            const separator = String(ref || '').indexOf(':');
            if (separator === -1) return;
            const type = ref.slice(0, separator);
            const id = ref.slice(separator + 1);
            if (!id) return;

            if (type === 'product') {
                const detail = document.querySelector('erp-product-detail');
                if (detail && typeof detail.open === 'function') {
                    await customElements.whenDefined('erp-product-detail');
                    detail.open(Number(id));
                    return;
                }
                this._showEntity(`Producto #${id}`, `<a class="btn primary small" href="/inventario?product=${Number(id)}">Abrir en inventario</a>`);
                return;
            }

            if (type === 'user') {
                try {
                    const user = await ErpUI.api(`/api/users?username=${encodeURIComponent(id)}`);
                    this._renderUser(user);
                } catch (error) {
                    this._showEntity(`Usuario ${id}`, `<div class="audit-empty-detail">${escape(error.message)}</div>`);
                }
                return;
            }

            const endpoints = {
                input: `/api/inputs/${Number(id)}`,
                supplier: `/api/suppliers/${Number(id)}`,
                customer: `/api/customers/${Number(id)}`,
                sale: `/api/orders/${Number(id)}`,
                purchase: `/api/purchases/${Number(id)}`
            };
            if (!endpoints[type]) return;

            try {
                const data = await ErpUI.api(endpoints[type]);
                if (type === 'input') this._renderInput(data);
                if (type === 'supplier') this._renderSupplier(data);
                if (type === 'customer') this._renderCustomer(data);
                if (type === 'sale') this._renderSale(data);
                if (type === 'purchase') this._renderPurchase(data);
            } catch (error) {
                this._showEntity('No se pudo abrir el detalle', `<div class="audit-empty-detail">${escape(error.message)}</div>`);
            }
        }

        async _showEntity(title, body) {
            this._entityModal.setTitle(title);
            this._entityModal.setBody(body);
            this._entityModal.setFooter('');
            await this._entityModal.open();
        }

        _renderUser(user) {
            this._showEntity(`Usuario ${user.username}`, `
                <div class="detail-grid">
                    <div class="detail-metric"><span>Usuario</span><strong>${escape(user.username)}</strong></div>
                    <div class="detail-metric"><span>Rol</span><strong>${escape(user.role)}</strong></div>
                    <div class="detail-metric"><span>ID</span><strong>#${Number(user.id)}</strong></div>
                    <div class="detail-metric"><span>Creado</span><strong>${escape(dateTime(user.created_at))}</strong></div>
                </div>
                <p class="form-note">Ficha de usuario asociada a los movimientos de auditoría.</p>
            `);
        }

        _renderInput(input) {
            const products = (input.products || []).map((product) => `
                <tr>
                    <td>${escape(product.name)}</td>
                    <td>${number(product.quantity_per_unit, 4)}</td>
                </tr>`).join('');
            const purchases = (input.purchases || []).map((purchase) => `
                <tr>
                    <td>#${Number(purchase.id)}</td>
                    <td>${escape(dateTime(purchase.date))}</td>
                    <td>${escape(purchase.supplier)}</td>
                    <td>${number(purchase.quantity)} ${escape(input.unit)}</td>
                    <td>${money(purchase.unit_cost)}</td>
                </tr>`).join('');
            this._showEntity(`Insumo ${input.name}`, `
                <div class="detail-grid">
                    <div class="detail-metric"><span>Stock</span><strong>${number(input.stock)} ${escape(input.unit)}</strong></div>
                    <div class="detail-metric"><span>Umbral</span><strong>${number(input.min_threshold)} ${escape(input.unit)}</strong></div>
                    <div class="detail-metric"><span>Costo</span><strong>${money(input.cost)}</strong></div>
                    <div class="detail-metric"><span>Proveedor</span><strong>${escape(input.supplier || 'Sin proveedor')}</strong></div>
                </div>
                <h4 class="detail-section-title">Productos que usan este insumo</h4>
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Producto</th><th>Por unidad</th></tr></thead>
                        <tbody>${products || '<tr><td colspan="2" class="muted">Sin productos asociados.</td></tr>'}</tbody>
                    </table>
                </div>
                <h4 class="detail-section-title">Últimas compras</h4>
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Compra</th><th>Fecha</th><th>Proveedor</th><th>Cantidad</th><th>Costo</th></tr></thead>
                        <tbody>${purchases || '<tr><td colspan="5" class="muted">Sin compras registradas.</td></tr>'}</tbody>
                    </table>
                </div>
            `);
        }

        _renderSupplier(supplier) {
            const inputs = (supplier.inputs || []).map((input) => `
                <tr>
                    <td>${escape(input.name)}</td>
                    <td>${number(input.stock)} ${escape(input.unit)}</td>
                    <td>${money(input.cost)}</td>
                    <td>${number(input.min_threshold)} ${escape(input.unit)}</td>
                </tr>`).join('');
            this._showEntity(`Proveedor ${supplier.name}`, `
                <div class="detail-grid">
                    <div class="detail-metric"><span>Contacto</span><strong>${escape(supplier.contact || '—')}</strong></div>
                    <div class="detail-metric"><span>Teléfono</span><strong>${escape(supplier.phone || '—')}</strong></div>
                    <div class="detail-metric"><span>Compras</span><strong>${number(supplier.purchases, 0)}</strong></div>
                    <div class="detail-metric"><span>Total comprado</span><strong>${money(supplier.total)}</strong></div>
                </div>
                <div class="mini-list-row">
                    <div class="row-main">
                        <strong>${escape(supplier.email || 'Sin email')}</strong>
                        <small>${escape(supplier.address || 'Sin dirección')}</small>
                    </div>
                </div>
                <h4 class="detail-section-title">Insumos que vende</h4>
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Insumo</th><th>Stock</th><th>Costo</th><th>Umbral</th></tr></thead>
                        <tbody>${inputs || '<tr><td colspan="4" class="muted">Sin insumos asociados.</td></tr>'}</tbody>
                    </table>
                </div>
            `);
        }

        _renderCustomer(customer) {
            const sales = (customer.recent_sales || []).map((sale) => `
                <tr>
                    <td>#${Number(sale.id)}</td>
                    <td>${escape(dateTime(sale.date))}</td>
                    <td>${escape(sale.order_type === 'direct' ? 'Venta directa' : 'Pedido')}</td>
                    <td>${money(sale.total)}</td>
                    <td>${escape(this._stageLabel(sale.status))}</td>
                </tr>`).join('');
            this._showEntity(`Cliente ${customer.name}`, `
                <div class="detail-grid">
                    <div class="detail-metric"><span>Tipo</span><strong>${escape(customer.type)}</strong></div>
                    <div class="detail-metric"><span>Compras</span><strong>${number(customer.purchases, 0)}</strong></div>
                    <div class="detail-metric"><span>Total</span><strong>${money(customer.total)}</strong></div>
                    <div class="detail-metric"><span>Teléfono</span><strong>${escape(customer.phone || '—')}</strong></div>
                </div>
                <div class="mini-list-row">
                    <div class="row-main">
                        <strong>${escape(customer.email || 'Sin email')}</strong>
                        <small>${escape(customer.phone || 'Sin teléfono')}</small>
                    </div>
                </div>
                <h4 class="detail-section-title">Últimas ventas</h4>
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Registro</th><th>Fecha</th><th>Tipo</th><th>Total</th><th>Estado</th></tr></thead>
                        <tbody>${sales || '<tr><td colspan="5" class="muted">Sin ventas registradas.</td></tr>'}</tbody>
                    </table>
                </div>
            `);
        }

        _renderSale(sale) {
            const typeLabel = sale.order_type === 'direct' ? 'Venta directa' : 'Pedido';
            const rows = (sale.items || []).map((item) => `
                <tr>
                    <td>${escape(item.product_name)}</td>
                    <td>${number(item.quantity, 0)}</td>
                    <td>${money(item.unit_price)}</td>
                    <td>${money(item.subtotal)}</td>
                </tr>`).join('');
            this._showEntity(`${typeLabel} #${sale.id}`, `
                <div class="inline-actions">
                    <span class="badge ${sale.order_type === 'direct' ? 'badge-accent' : 'badge-soft'}">${typeLabel}</span>
                    <span class="badge badge-soft">${escape(dateTime(sale.date))}</span>
                </div>
                <div class="detail-grid">
                    <div class="detail-metric"><span>Cliente</span><strong>${escape(sale.customer)}</strong></div>
                    <div class="detail-metric"><span>Pago</span><strong>${escape(sale.payment_method)}</strong></div>
                    <div class="detail-metric"><span>Estado</span><strong>${escape(this._stageLabel(sale.status))}</strong></div>
                    <div class="detail-metric"><span>Total</span><strong>${money(sale.total)}</strong></div>
                </div>
                ${sale.cancel_reason ? `
                <div class="detail-grid">
                    <div class="detail-metric"><span>Motivo de anulación</span><strong>${escape(sale.cancel_reason)}</strong></div>
                    <div class="detail-metric"><span>Anulada por</span><strong>${escape(sale.cancelled_by || '—')}</strong></div>
                    <div class="detail-metric"><span>Autorizada por</span><strong>${escape(sale.cancel_authorized_by || '—')}</strong></div>
                    <div class="detail-metric"><span>Fecha de anulación</span><strong>${escape(dateTime(sale.cancelled_at))}</strong></div>
                </div>` : ''}
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Producto</th><th>Cantidad</th><th>Precio unitario</th><th>Subtotal</th></tr></thead>
                        <tbody>${rows || '<tr><td colspan="4" class="muted">Sin productos.</td></tr>'}</tbody>
                    </table>
                </div>
            `);
        }

        _renderPurchase(purchase) {
            const rows = (purchase.items || []).map((item) => `
                <tr>
                    <td>${escape(item.input_name)}</td>
                    <td>${number(item.quantity)} ${escape(item.unit)}</td>
                    <td>${money(item.unit_cost)}</td>
                    <td>${money(item.subtotal)}</td>
                </tr>`).join('');
            this._showEntity(`Compra #${purchase.id}`, `
                <div class="detail-grid">
                    <div class="detail-metric"><span>Proveedor</span><strong>${escape(purchase.supplier)}</strong></div>
                    <div class="detail-metric"><span>Fecha</span><strong>${escape(dateTime(purchase.date))}</strong></div>
                    <div class="detail-metric"><span>Estado</span><strong>${escape(purchase.status)}</strong></div>
                    <div class="detail-metric"><span>Total</span><strong>${money(purchase.total)}</strong></div>
                </div>
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Insumo</th><th>Cantidad</th><th>Costo unitario</th><th>Subtotal</th></tr></thead>
                        <tbody>${rows || '<tr><td colspan="4" class="muted">Sin insumos.</td></tr>'}</tbody>
                    </table>
                </div>
            `);
        }
    }

    customElements.define('erp-audit-manager', AuditManager);
})();
