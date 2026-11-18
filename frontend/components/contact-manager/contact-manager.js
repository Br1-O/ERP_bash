(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;

    class ContactManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._contacts = { suppliers: [], customers: [] };
            this._editingSupplier = 0;
            this._editingCustomer = 0;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/contact-manager/contact-manager.html');
            this._search = this.querySelector('[data-contact-search]');
            this._supplierList = this.querySelector('[data-suppliers-list]');
            this._customerList = this.querySelector('[data-customers-list]');
            this._supplierEmpty = this.querySelector('[data-suppliers-empty]');
            this._customerEmpty = this.querySelector('[data-customers-empty]');
            this._supplierCount = this.querySelector('[data-supplier-count]');
            this._customerCount = this.querySelector('[data-customer-count]');
            this._detailModal = this.querySelector('#contact-detail-modal');
            this._supplierModal = this.querySelector('#supplier-modal');
            this._customerModal = this.querySelector('#customer-modal');

            this._bind();
            await this._loadContacts();
        }

        _bind() {
            ErpUI.debounceInput(this._search, () => this._loadContacts());
            this._supplierList.addEventListener('click', (event) => {
                const copy = event.target.closest('[data-copy-contact-phone]');
                if (copy) {
                    event.stopPropagation();
                    ErpUI.copyText(copy.dataset.copyContactPhone, 'Teléfono');
                    return;
                }
                const card = event.target.closest('[data-supplier-id]');
                if (card) this._openSupplier(Number(card.dataset.supplierId));
            });
            this._customerList.addEventListener('click', (event) => {
                const copy = event.target.closest('[data-copy-contact-phone]');
                if (copy) {
                    event.stopPropagation();
                    ErpUI.copyText(copy.dataset.copyContactPhone, 'Teléfono');
                    return;
                }
                const card = event.target.closest('[data-customer-id]');
                if (card) this._openCustomer(Number(card.dataset.customerId));
            });
            this.querySelector('[data-create-supplier]').addEventListener('click', () => this._openSupplierForm());
            this.querySelector('[data-create-customer]').addEventListener('click', () => this._openCustomerForm());
            this.querySelector('[data-supplier-form]').addEventListener('submit', (event) => this._submitSupplier(event));
            this.querySelector('[data-customer-form]').addEventListener('submit', (event) => this._submitCustomer(event));
            this.querySelector('[data-supplier-cancel]').addEventListener('click', () => this._supplierModal.close());
            this.querySelector('[data-customer-cancel]').addEventListener('click', () => this._customerModal.close());
        }

        async _loadContacts() {
            try {
                const contacts = await ErpUI.api(`/api/contacts?q=${encodeURIComponent(this._search.value.trim())}`);
                this._contacts = contacts;
                this._renderSuppliers(contacts.suppliers || []);
                this._renderCustomers(contacts.customers || []);
            } catch (error) {
                ErpUI.toast('No se pudieron cargar los contactos', error.message, 'error');
            }
        }

        _renderSuppliers(suppliers) {
            this._supplierCount.textContent = String(suppliers.length);
            this._supplierEmpty.hidden = suppliers.length > 0;
            this._supplierList.innerHTML = suppliers.map((supplier) => `
                <article class="contact-card" data-supplier-id="${Number(supplier.id)}">
                    <header>
                        <div>
                            <strong>${escape(supplier.name)}</strong>
                            <div class="muted" style="font-size:.7rem">${escape(supplier.contact || 'Sin contacto')}</div>
                        </div>
                        ${supplier.phone ? `<button class="btn ghost small" type="button" data-copy-contact-phone="${escape(supplier.phone)}">Copiar teléfono</button>` : ''}
                    </header>
                    <div class="contact-meta">
                        <span>${escape(supplier.phone || 'Sin teléfono')}</span>
                        <span>${escape(supplier.email || 'Sin email')}</span>
                        <span>${Number(supplier.inputs) || 0} insumos</span>
                    </div>
                    <p class="supplies-line" style="margin-top:7px"><strong>Vende:</strong> ${escape(supplier.supplies || 'Sin insumos asociados')}</p>
                </article>`).join('');
        }

        _renderCustomers(customers) {
            this._customerCount.textContent = String(customers.length);
            this._customerEmpty.hidden = customers.length > 0;
            this._customerList.innerHTML = customers.map((customer) => `
                <article class="contact-card" data-customer-id="${Number(customer.id)}">
                    <header>
                        <div>
                            <strong>${escape(customer.name)}</strong>
                            <div class="muted" style="font-size:.7rem">${escape(customer.type)}</div>
                        </div>
                        ${customer.phone ? `<button class="btn ghost small" type="button" data-copy-contact-phone="${escape(customer.phone)}">Copiar teléfono</button>` : ''}
                    </header>
                    <div class="contact-meta">
                        <span>${escape(customer.phone || 'Sin teléfono')}</span>
                        <span>${escape(customer.email || 'Sin email')}</span>
                        <span>${Number(customer.purchases) || 0} compras · ${money(customer.total)}</span>
                    </div>
                </article>`).join('');
        }

        async _openSupplier(supplierId) {
            try {
                const supplier = await ErpUI.api(`/api/suppliers/${supplierId}`);
                const rows = (supplier.inputs || []).map((input) => `
                    <tr>
                        <td>${escape(input.name)}</td>
                        <td>${number(input.stock)} ${escape(input.unit)}</td>
                        <td>${money(input.cost)}</td>
                        <td>${number(input.min_threshold)} ${escape(input.unit)}</td>
                    </tr>`).join('');
                this._detailModal.setTitle(supplier.name);
                this._detailModal.setBody(`
                    <div class="detail-grid">
                        <div class="detail-metric"><span>Contacto</span><strong>${escape(supplier.contact || '—')}</strong></div>
                        <div class="detail-metric"><span>Teléfono</span><strong>${escape(supplier.phone || '—')}</strong></div>
                        <div class="detail-metric"><span>Compras</span><strong>${Number(supplier.purchases) || 0}</strong></div>
                        <div class="detail-metric"><span>Total comprado</span><strong>${money(supplier.total)}</strong></div>
                    </div>
                    <div class="mini-list-row">
                        <div class="row-main">
                            <strong>${escape(supplier.email || 'Sin email')}</strong>
                            <small>${escape(supplier.address || 'Sin dirección')} · última compra ${escape(ErpUI.formatDateTime(supplier.last_purchase))}</small>
                        </div>
                        <div class="inline-actions">
                            <button class="btn primary small" type="button" data-edit-supplier>Editar</button>
                            <button class="btn ghost small" type="button" data-delete-supplier>Eliminar</button>
                            ${supplier.phone ? `<button class="btn ghost small" type="button" data-copy-detail-phone="${escape(supplier.phone)}">Copiar teléfono</button>` : ''}
                            ${supplier.phone ? `<a class="btn ghost small" href="tel:${escape(supplier.phone)}">Llamar</a>` : ''}
                            ${supplier.email ? `<a class="btn ghost small" href="mailto:${escape(supplier.email)}">Escribir</a>` : ''}
                        </div>
                    </div>
                    <h4 class="detail-section-title">Insumos que vende</h4>
                    <div class="table-responsive">
                        <table>
                            <thead><tr><th>Insumo</th><th>Stock</th><th>Costo</th><th>Umbral</th></tr></thead>
                            <tbody>${rows || '<tr><td colspan="4" class="muted">Sin insumos asociados.</td></tr>'}</tbody>
                        </table>
                    </div>
                `);
                this._detailModal.setFooter('');
                const copy = this._detailModal.querySelector('[data-copy-detail-phone]');
                if (copy) copy.addEventListener('click', () => ErpUI.copyText(copy.dataset.copyDetailPhone, 'Teléfono'));
                this._detailModal.querySelector('[data-edit-supplier]')?.addEventListener('click', () => {
                    this._detailModal.close();
                    this._openSupplierForm(supplier);
                });
                this._detailModal.querySelector('[data-delete-supplier]')?.addEventListener('click', () => this._deleteSupplier(supplier));
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el proveedor', error.message, 'error');
            }
        }

        _openCustomer(customerId) {
            const customer = (this._contacts.customers || []).find((item) => Number(item.id) === Number(customerId));
            if (!customer) return;
            this._detailModal.setTitle(customer.name);
            this._detailModal.setBody(`
                <div class="detail-grid">
                    <div class="detail-metric"><span>Tipo</span><strong>${escape(customer.type)}</strong></div>
                    <div class="detail-metric"><span>Compras</span><strong>${Number(customer.purchases) || 0}</strong></div>
                    <div class="detail-metric"><span>Total</span><strong>${money(customer.total)}</strong></div>
                    <div class="detail-metric"><span>Teléfono</span><strong>${escape(customer.phone || '—')}</strong></div>
                </div>
                <div class="mini-list-row">
                    <div class="row-main">
                        <strong>${escape(customer.email || 'Sin email')}</strong>
                        <small>${escape(customer.phone || 'Sin teléfono')}</small>
                    </div>
                    <div class="inline-actions">
                        <button class="btn primary small" type="button" data-edit-customer>Editar</button>
                        <button class="btn ghost small" type="button" data-delete-customer>Eliminar</button>
                        ${customer.phone ? `<button class="btn ghost small" type="button" data-copy-detail-phone="${escape(customer.phone)}">Copiar teléfono</button>` : ''}
                        ${customer.phone ? `<a class="btn ghost small" href="tel:${escape(customer.phone)}">Llamar</a>` : ''}
                        ${customer.email ? `<a class="btn ghost small" href="mailto:${escape(customer.email)}">Escribir</a>` : ''}
                    </div>
                </div>
            `);
            this._detailModal.setFooter('');
            const copy = this._detailModal.querySelector('[data-copy-detail-phone]');
            if (copy) copy.addEventListener('click', () => ErpUI.copyText(copy.dataset.copyDetailPhone, 'Teléfono'));
            this._detailModal.querySelector('[data-edit-customer]')?.addEventListener('click', () => {
                this._detailModal.close();
                this._openCustomerForm(customer);
            });
            this._detailModal.querySelector('[data-delete-customer]')?.addEventListener('click', () => this._deleteCustomer(customer));
            this._detailModal.open();
        }

        _openSupplierForm(supplier = null) {
            const form = this.querySelector('[data-supplier-form]');
            const submit = this.querySelector('[data-supplier-submit]');
            this._editingSupplier = supplier ? Number(supplier.id) : 0;
            form.reset();
            this.querySelector('[data-supplier-error]').hidden = true;
            if (supplier) {
                this.querySelector('[data-supplier-name]').value = supplier.name || '';
                this.querySelector('[data-supplier-contact]').value = supplier.contact || '';
                this.querySelector('[data-supplier-phone]').value = supplier.phone || '';
                this.querySelector('[data-supplier-email]').value = supplier.email || '';
                this.querySelector('[data-supplier-address]').value = supplier.address || '';
                this._supplierModal.setTitle('Editar proveedor');
                submit.textContent = 'Guardar cambios';
            } else {
                this._supplierModal.setTitle('Nuevo proveedor');
                submit.textContent = 'Crear proveedor';
            }
            this._supplierModal.open();
        }

        _openCustomerForm(customer = null) {
            const form = this.querySelector('[data-customer-form]');
            const submit = this.querySelector('[data-customer-submit]');
            this._editingCustomer = customer ? Number(customer.id) : 0;
            form.reset();
            this.querySelector('[data-customer-error]').hidden = true;
            if (customer) {
                this.querySelector('[data-customer-name]').value = customer.name || '';
                this.querySelector('[data-customer-type]').value = customer.type || 'Minorista';
                this.querySelector('[data-customer-phone]').value = customer.phone || '';
                this.querySelector('[data-customer-email]').value = customer.email || '';
                this._customerModal.setTitle('Editar cliente');
                submit.textContent = 'Guardar cambios';
            } else {
                this._customerModal.setTitle('Nuevo cliente');
                submit.textContent = 'Crear cliente';
            }
            this._customerModal.open();
        }

        async _deleteSupplier(supplier) {
            if (!window.confirm(`¿Eliminar al proveedor "${supplier.name}"? Se ocultará de la agenda y sus compras se conservarán.`)) return;
            try {
                await ErpUI.api(`/api/suppliers/${supplier.id}`, { method: 'DELETE' });
                this._detailModal.close();
                ErpUI.toast('Proveedor eliminado', `"${supplier.name}" se ocultó de la agenda.`);
                await this._loadContacts();
            } catch (error) {
                ErpUI.toast('No se pudo eliminar', error.message, 'error');
            }
        }

        async _deleteCustomer(customer) {
            if (!window.confirm(`¿Eliminar al cliente "${customer.name}"? Se ocultará de la agenda y sus ventas se conservarán.`)) return;
            try {
                await ErpUI.api(`/api/customers/${customer.id}`, { method: 'DELETE' });
                this._detailModal.close();
                ErpUI.toast('Cliente eliminado', `"${customer.name}" se ocultó de la agenda.`);
                await this._loadContacts();
            } catch (error) {
                ErpUI.toast('No se pudo eliminar', error.message, 'error');
            }
        }

        async _submitSupplier(event) {
            event.preventDefault();
            const error = this.querySelector('[data-supplier-error]');
            const button = this.querySelector('[data-supplier-submit]');
            error.hidden = true;
            button.disabled = true;
            const editingId = this._editingSupplier;
            const name = this.querySelector('[data-supplier-name]').value.trim();
            try {
                const payload = await ErpUI.api(editingId ? `/api/suppliers/${editingId}` : '/api/suppliers', {
                    method: editingId ? 'PUT' : 'POST',
                    body: {
                        name,
                        contact: this.querySelector('[data-supplier-contact]').value.trim(),
                        phone: this.querySelector('[data-supplier-phone]').value.trim(),
                        email: this.querySelector('[data-supplier-email]').value.trim(),
                        address: this.querySelector('[data-supplier-address]').value.trim()
                    }
                });
                this._supplierModal.close();
                this._editingSupplier = 0;
                ErpUI.toast(
                    editingId ? 'Proveedor actualizado' : 'Proveedor creado',
                    editingId ? `"${name}" fue actualizado.` : `Proveedor #${payload.supplier_id} agregado a la agenda.`
                );
                await this._loadContacts();
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                button.disabled = false;
            }
        }

        async _submitCustomer(event) {
            event.preventDefault();
            const error = this.querySelector('[data-customer-error]');
            const button = this.querySelector('[data-customer-submit]');
            error.hidden = true;
            button.disabled = true;
            const editingId = this._editingCustomer;
            const name = this.querySelector('[data-customer-name]').value.trim();
            try {
                const payload = await ErpUI.api(editingId ? `/api/customers/${editingId}` : '/api/customers', {
                    method: editingId ? 'PUT' : 'POST',
                    body: {
                        name,
                        type: this.querySelector('[data-customer-type]').value,
                        phone: this.querySelector('[data-customer-phone]').value.trim(),
                        email: this.querySelector('[data-customer-email]').value.trim()
                    }
                });
                this._customerModal.close();
                this._editingCustomer = 0;
                ErpUI.toast(
                    editingId ? 'Cliente actualizado' : 'Cliente creado',
                    editingId ? `"${name}" fue actualizado.` : `Cliente #${payload.customer_id} agregado a la agenda.`
                );
                await this._loadContacts();
            } catch (requestError) {
                error.textContent = requestError.message;
                error.hidden = false;
            } finally {
                button.disabled = false;
            }
        }
    }

    customElements.define('erp-contact-manager', ContactManager);
})();
