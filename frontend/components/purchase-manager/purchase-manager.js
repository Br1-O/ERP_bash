(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;

    class PurchaseManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._meta = null;
            this._view = 'recommendations';
            this._recommendations = [];
            this._displayedRecommendations = [];
            this._draft = null;
            this._orderGroups = [];
            this._orderMessage = '';
            this._page = 1;
            this._pages = 1;
            this._requestId = 0;
            this._purchaseFormEditing = 0;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/purchase-manager/purchase-manager.html');
            this._recommendationPanel = this.querySelector('[data-recommendations-panel]');
            this._historyPanel = this.querySelector('[data-history-panel]');
            this._historyActions = this.querySelector('[data-history-actions]');
            this._recommendationList = this.querySelector('[data-recommendation-list]');
            this._recommendationEmpty = this.querySelector('[data-recommendation-empty]');
            this._recommendationCount = this.querySelector('[data-recommendation-count]');
            this._draftBanner = this.querySelector('[data-draft-banner]');
            this._draftTitle = this.querySelector('[data-draft-title]');
            this._draftSubtitle = this.querySelector('[data-draft-subtitle]');
            this._generateButton = this.querySelector('[data-generate-order]');
            this._purchaseBody = this.querySelector('[data-purchase-body]');
            this._purchaseEmpty = this.querySelector('[data-purchase-empty]');
            this._purchaseCount = this.querySelector('[data-purchase-count]');
            this._search = this.querySelector('[data-purchase-search]');
            this._supplierFilter = this.querySelector('[data-purchase-supplier-filter]');
            this._statusFilter = this.querySelector('[data-purchase-status-filter]');
            this._pagination = this.querySelector('[data-purchase-pagination]');
            this._orderModal = this.querySelector('#order-modal');
            this._orderContent = this.querySelector('[data-order-content]');
            this._orderError = this.querySelector('[data-order-error]');
            this._detailModal = this.querySelector('#purchase-detail-modal');
            this._invoice = this.querySelector('#purchase-invoice');
            this._purchaseFormModal = this.querySelector('#purchase-form-modal');
            this._purchaseForm = this.querySelector('[data-purchase-form]');
            this._purchaseFormSupplier = this.querySelector('[data-purchase-form-supplier]');
            this._purchaseFormNotes = this.querySelector('[data-purchase-form-notes]');
            this._purchaseFormItems = this.querySelector('[data-purchase-form-items]');
            this._purchaseFormTotal = this.querySelector('[data-purchase-form-total]');
            this._purchaseFormError = this.querySelector('[data-purchase-form-error]');
            this._purchaseFormSubmit = this.querySelector('[data-purchase-form-submit]');

            this._bind();
            await this._loadMeta();
            await this._loadRecommendations();
            await this._loadPurchases();
            await this._handleDeepLink();
        }

        _bind() {
            this.querySelectorAll('[data-purchase-view]').forEach((button) => {
                button.addEventListener('click', () => this._switchView(button.dataset.purchaseView));
            });
            this._recommendationList.addEventListener('change', (event) => {
                const card = event.target.closest('[data-reco-id]');
                if (!card) return;
                card.classList.toggle('selected', event.target.checked);
                this._syncGenerateButton();
            });
            this._recommendationList.addEventListener('click', (event) => {
                const copy = event.target.closest('[data-copy-reco-phone]');
                if (copy) {
                    event.stopPropagation();
                    ErpUI.copyText(copy.dataset.copyRecoPhone, 'Teléfono');
                    return;
                }
                const open = event.target.closest('[data-reco-open]');
                if (open) this._startDraft(Number(open.dataset.recoOpen));
            });
            this._draftBanner.addEventListener('click', (event) => {
                if (event.target.closest('[data-draft-clear]')) this._clearDraft();
            });
            this._generateButton.addEventListener('click', () => this._generateOrder());
            this.querySelector('[data-order-cancel]').addEventListener('click', () => this._orderModal.close());
            this.querySelector('[data-copy-order]').addEventListener('click', () => ErpUI.copyText(this._orderMessage, 'Mensaje de pedido'));
            this.querySelector('[data-register-order]').addEventListener('click', () => this._registerOrder());
            this.querySelector('[data-create-purchase]').addEventListener('click', () => this._openPurchaseForm());
            this.querySelector('[data-purchase-form-cancel]').addEventListener('click', () => this._purchaseFormModal.close());
            this.querySelector('[data-purchase-form-add-item]').addEventListener('click', () => this._addPurchaseItemRow());
            this._purchaseForm.addEventListener('submit', (event) => this._submitPurchaseForm(event));
            this._purchaseFormItems.addEventListener('change', (event) => {
                const row = event.target.closest('.purchase-item-row');
                if (row && event.target.matches('[data-purchase-item-input]')) this._purchaseItemChanged(row);
            });
            this._purchaseFormItems.addEventListener('input', (event) => {
                const row = event.target.closest('.purchase-item-row');
                if (row) this._updatePurchaseLine(row);
            });
            this._purchaseFormItems.addEventListener('click', (event) => {
                const remove = event.target.closest('[data-purchase-item-remove]');
                if (!remove) return;
                remove.closest('.purchase-item-row')?.remove();
                this._renderPurchaseFormTotals();
            });
            ErpUI.debounceInput(this._search, () => {
                this._page = 1;
                this._loadPurchases();
            });
            this._supplierFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadPurchases();
            });
            this._statusFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadPurchases();
            });
            this._pagination.addEventListener('page-change', (event) => {
                this._page = event.detail.page;
                this._loadPurchases();
            });
            this._purchaseBody.addEventListener('click', (event) => {
                const row = event.target.closest('[data-purchase-id]');
                if (row) this._openPurchaseDetail(Number(row.dataset.purchaseId));
            });
        }

        async _loadMeta() {
            try {
                this._meta = await ErpUI.api('/api/inventory/meta');
                this._supplierFilter.innerHTML = '<option value="0">Todos</option>' +
                    (this._meta.suppliers || []).map((supplier) =>
                        `<option value="${Number(supplier.id)}">${escape(supplier.name)}</option>`).join('');
            } catch (error) {
                ErpUI.toast('No se pudo cargar proveedores', error.message, 'error');
            }
        }

        _statusLabel(status) {
            if (status === 'finished') return 'Finalizado';
            if (status === 'processing') return 'En proceso';
            return 'Pendiente';
        }

        _purchaseInputOptions(selectedId = 0) {
            return '<option value="0">Seleccione un insumo…</option>' +
                (this._meta?.inputs || []).map((input) => {
                    const selected = Number(input.id) === Number(selectedId) ? ' selected' : '';
                    return `<option value="${Number(input.id)}" data-cost="${Number(input.cost) || 0}"${selected}>${escape(input.name)} · ${escape(input.unit)} · stock ${number(input.stock)}</option>`;
                }).join('');
        }

        _addPurchaseItemRow(item = null) {
            const inputs = this._meta?.inputs || [];
            if (!inputs.length) {
                ErpUI.toast('Sin insumos', 'No hay insumos activos para agregar al pedido.', 'error');
                return;
            }
            const selectedId = Number(item?.input_id) || Number(inputs[0].id);
            const selected = inputs.find((input) => Number(input.id) === selectedId) || inputs[0];
            const quantity = Number(item?.quantity) || Math.max(1, Number(selected.min_threshold) || 1);
            const unitCost = item?.unit_cost != null ? Number(item.unit_cost) : (Number(selected.cost) || 0);
            const row = document.createElement('div');
            row.className = 'purchase-item-row';
            row.innerHTML = `
                <label class="field">
                    <span>Insumo</span>
                    <select data-purchase-item-input>${this._purchaseInputOptions(selected.id)}</select>
                </label>
                <label class="field">
                    <span>Cantidad</span>
                    <input type="number" min="0.01" step="0.01" value="${quantity}" data-purchase-item-quantity>
                </label>
                <label class="field">
                    <span>Costo unitario</span>
                    <input type="number" min="0" step="0.01" value="${unitCost.toFixed(2)}" data-purchase-item-cost>
                </label>
                <span class="line-total">$0.00</span>
                <button class="icon-button remove-item" type="button" data-purchase-item-remove aria-label="Quitar insumo">×</button>`;
            this._purchaseFormItems.append(row);
            this._updatePurchaseLine(row);
        }

        _purchaseItemChanged(row) {
            const select = row.querySelector('[data-purchase-item-input]');
            const cost = row.querySelector('[data-purchase-item-cost]');
            const option = select?.selectedOptions[0];
            if (option) cost.value = Number(option.dataset.cost || 0).toFixed(2);
            this._updatePurchaseLine(row);
        }

        _updatePurchaseLine(row) {
            const quantity = Number(row.querySelector('[data-purchase-item-quantity]')?.value) || 0;
            const unitCost = Number(row.querySelector('[data-purchase-item-cost]')?.value) || 0;
            const lineTotal = row.querySelector('.line-total');
            const billing = window.ErpBilling;
            const cents = (billing?.Money.toCents(unitCost) || Math.round(unitCost * 100)) * quantity;
            lineTotal.textContent = billing
                ? billing.Money.formatCents(cents)
                : money(cents / 100);
            this._renderPurchaseFormTotals();
        }

        _renderPurchaseFormTotals() {
            const billing = window.ErpBilling;
            let cents = 0;
            this._purchaseFormItems.querySelectorAll('.purchase-item-row').forEach((row) => {
                const quantity = Number(row.querySelector('[data-purchase-item-quantity]')?.value) || 0;
                const unitCost = Number(row.querySelector('[data-purchase-item-cost]')?.value) || 0;
                cents += (billing?.Money.toCents(unitCost) || Math.round(unitCost * 100)) * quantity;
            });
            this._purchaseFormTotal.textContent = billing
                ? billing.Money.formatCents(cents)
                : money(cents / 100);
        }

        _purchaseFormPayload() {
            const supplierId = Number(this._purchaseFormSupplier.value) || 0;
            const items = Array.from(this._purchaseFormItems.querySelectorAll('.purchase-item-row'))
                .map((row) => ({
                    input_id: Number(row.querySelector('[data-purchase-item-input]')?.value) || 0,
                    quantity: Number(row.querySelector('[data-purchase-item-quantity]')?.value) || 0,
                    unit_cost: Number(row.querySelector('[data-purchase-item-cost]')?.value) || 0
                }))
                .filter((item) => item.input_id > 0);
            return {
                supplierId,
                notes: this._purchaseFormNotes.value.trim(),
                items
            };
        }

        async _openPurchaseForm(purchase = null) {
            if (purchase && Number(purchase.stock_applied) === 1) {
                ErpUI.toast('Pedido finalizado', 'Reabra el pedido antes de modificarlo.', 'error');
                return;
            }
            const suppliers = this._meta?.suppliers || [];
            const inputs = this._meta?.inputs || [];
            if (!suppliers.length) {
                ErpUI.toast('Sin proveedores', 'Registre un proveedor activo antes de crear un pedido.', 'error');
                return;
            }
            if (!inputs.length) {
                ErpUI.toast('Sin insumos', 'Registre insumos activos antes de crear un pedido.', 'error');
                return;
            }

            this._purchaseForm.reset();
            this._purchaseFormEditing = purchase ? Number(purchase.id) : 0;
            this._purchaseFormSupplier.innerHTML = '<option value="0">Seleccione un proveedor…</option>' +
                suppliers.map((supplier) =>
                    `<option value="${Number(supplier.id)}">${escape(supplier.name)}</option>`).join('');
            this._purchaseFormNotes.value = purchase?.notes || '';
            this._purchaseFormItems.innerHTML = '';
            this._purchaseFormError.hidden = true;
            this._purchaseFormSubmit.disabled = false;

            if (purchase) {
                this._purchaseFormSupplier.value = String(Number(purchase.supplier_id) || 0);
                (purchase.items || []).forEach((item) => this._addPurchaseItemRow(item));
                this._purchaseFormModal.setTitle(`Editar pedido #${purchase.id}`);
                this._purchaseFormSubmit.textContent = 'Guardar cambios';
            } else {
                this._addPurchaseItemRow();
                this._purchaseFormModal.setTitle('Nuevo pedido');
                this._purchaseFormSubmit.textContent = 'Crear pedido';
            }

            this._renderPurchaseFormTotals();
            this._purchaseFormModal.open();
            this._purchaseFormSupplier.focus();
        }

        async _submitPurchaseForm(event) {
            event.preventDefault();
            const { supplierId, notes, items } = this._purchaseFormPayload();
            this._purchaseFormError.hidden = true;

            if (supplierId <= 0) {
                this._purchaseFormError.textContent = 'Seleccione un proveedor.';
                this._purchaseFormError.hidden = false;
                return;
            }
            if (!items.length) {
                this._purchaseFormError.textContent = 'Agregue al menos un insumo al pedido.';
                this._purchaseFormError.hidden = false;
                return;
            }
            if (items.some((item) => !(item.quantity > 0) || !(item.unit_cost >= 0))) {
                this._purchaseFormError.textContent = 'Revise las cantidades y los costos unitarios.';
                this._purchaseFormError.hidden = false;
                return;
            }

            const editingId = this._purchaseFormEditing;
            this._purchaseFormSubmit.disabled = true;
            this._purchaseFormSubmit.textContent = editingId ? 'Guardando…' : 'Creando…';
            try {
                await ErpUI.api(editingId ? `/api/purchases/${editingId}` : '/api/purchases', {
                    method: editingId ? 'PUT' : 'POST',
                    body: {
                        supplier_id: supplierId,
                        notes,
                        items
                    }
                });
                this._purchaseFormModal.close();
                this._purchaseFormEditing = 0;
                ErpUI.toast(
                    editingId ? 'Pedido actualizado' : 'Pedido creado',
                    editingId ? 'Los cambios del pedido fueron guardados.' : 'El pedido quedó pendiente; el stock se aplicará al finalizarlo.'
                );
                await this._loadPurchases();
            } catch (error) {
                this._purchaseFormError.textContent = error.message;
                this._purchaseFormError.hidden = false;
            } finally {
                this._purchaseFormSubmit.disabled = false;
                this._purchaseFormSubmit.textContent = editingId ? 'Guardar cambios' : 'Crear pedido';
            }
        }

        async _setPurchaseStatus(purchase, status) {
            const label = this._statusLabel(status);
            if (status === 'finished') {
                if (!window.confirm(`¿Finalizar el pedido #${purchase.id}? Se sumará el stock de los insumos.`)) return;
            } else if (Number(purchase.stock_applied) === 1) {
                if (!window.confirm(`¿Reabrir el pedido #${purchase.id}? Se descontará el stock recibido y podría fallar si ya fue consumido.`)) return;
            }
            try {
                await ErpUI.api(`/api/purchases/${purchase.id}/status`, {
                    method: 'PUT',
                    body: { status }
                });
                this._detailModal.close();
                ErpUI.toast('Estado actualizado', `El pedido #${purchase.id} quedó en “${label}”.`);
                await this._loadPurchases();
                await this._loadRecommendations();
            } catch (error) {
                ErpUI.toast('No se pudo cambiar el estado', error.message, 'error');
            }
        }

        async _deletePurchase(purchase) {
            if (!window.confirm(`¿Eliminar el pedido #${purchase.id}? Esta acción no se puede deshacer.`)) return;
            try {
                await ErpUI.api(`/api/purchases/${purchase.id}`, { method: 'DELETE' });
                this._detailModal.close();
                ErpUI.toast('Pedido eliminado', `El pedido #${purchase.id} fue eliminado.`);
                await this._loadPurchases();
            } catch (error) {
                ErpUI.toast('No se pudo eliminar', error.message, 'error');
            }
        }

        _switchView(view) {
            this._view = view === 'history' ? 'history' : 'recommendations';
            this.querySelectorAll('[data-purchase-view]').forEach((button) => {
                button.classList.toggle('active', button.dataset.purchaseView === this._view);
            });
            this._recommendationPanel.hidden = this._view !== 'recommendations';
            this._historyPanel.hidden = this._view !== 'history';
            this._historyActions.hidden = this._view !== 'history';
        }

        async _loadRecommendations() {
            this._recommendationList.innerHTML = '<div class="empty-state"><strong>Calculando reposición…</strong></div>';
            try {
                this._recommendations = await ErpUI.api('/api/recommendations');
                this._displayedRecommendations = this._recommendations;
                this._draft = null;
                this._draftBanner.hidden = true;
                this._renderRecommendations();
            } catch (error) {
                this._recommendationList.innerHTML = '';
                this._recommendationEmpty.hidden = false;
                this._recommendationEmpty.querySelector('strong').textContent = 'No se pudieron calcular las recomendaciones';
                this._recommendationEmpty.querySelector('span').textContent = error.message;
            }
        }

        _renderRecommendations() {
            const items = this._displayedRecommendations || [];
            const draft = this._draft;
            this._recommendationCount.textContent = draft
                ? `${items.length} insumo${items.length === 1 ? '' : 's'} de ${draft.supplierName}`
                : `${items.length} insumo${items.length === 1 ? '' : 's'}`;
            this._recommendationEmpty.hidden = items.length > 0;
            if (!items.length) {
                this._recommendationList.innerHTML = '';
                this._generateButton.disabled = true;
                return;
            }
            this._recommendationList.innerHTML = items.map((item) => {
                const canOrder = Number(item.supplier_id) > 0;
                const lastBuy = item.last_purchase ? ErpUI.formatDate(item.last_purchase) : 'sin compras previas';
                const selected = item._draftSelected ? 'checked' : '';
                const extra = item._draftExtra
                    ? '<span class="badge badge-soft">Otro insumo del proveedor</span>'
                    : '';
                return `
                    <article class="recommendation-card ${item._draftSelected ? 'selected' : ''}" data-reco-id="${Number(item.id)}">
                        <header>
                            <input type="checkbox" data-reco-check ${selected} ${canOrder ? '' : 'disabled'} aria-label="Seleccionar ${escape(item.name)}">
                            <div class="reco-main">
                                <strong>${escape(item.name)}</strong>
                                <small>${escape(item.supplier)}${item.phone ? ` · ${escape(item.phone)}` : ''}</small>
                            </div>
                            <div class="inline-actions">
                                ${item.phone ? `<button class="btn ghost small" type="button" data-copy-reco-phone="${escape(item.phone)}">Copiar teléfono</button>` : ''}
                                <button class="btn ghost small" type="button" data-reco-open="${Number(item.id)}">Pedir</button>
                            </div>
                        </header>
                        ${extra}
                        <div class="reco-meta">
                            <span>Stock <b>${number(item.stock)} ${escape(item.unit)}</b></span>
                            <span>Proyección 14d <b>${number(item.projected_14d)}</b></span>
                            <span>Última compra <b>${number(item.last_quantity)}</b> · ${escape(lastBuy)}</span>
                        </div>
                        <div class="reco-qty">
                            <input type="number" min="0.01" step="0.01" value="${Number(item.recommended).toFixed(2)}" data-reco-qty aria-label="Cantidad recomendada">
                            <span>${escape(item.unit)} sugeridos</span>
                        </div>
                    </article>`;
            }).join('');
            this._syncGenerateButton();
        }

        async _handleDeepLink() {
            const inputId = Number(new URLSearchParams(window.location.search).get('input'));
            if (!inputId) return;
            await this._startDraft(inputId);
        }

        async _startDraft(inputId) {
            const target = (this._recommendations || []).find((item) => Number(item.id) === inputId);
            if (!target) {
                ErpUI.toast('Insumo no disponible', 'La recomendación ya no está vigente.', 'error');
                return;
            }
            const supplierId = Number(target.supplier_id);
            if (!(supplierId > 0)) {
                ErpUI.toast('Sin proveedor', `${target.name} no tiene un proveedor asociado.`, 'error');
                return;
            }

            let supplier = null;
            try {
                supplier = await ErpUI.api(`/api/suppliers/${supplierId}`);
            } catch (error) {
                ErpUI.toast('No se pudo cargar el proveedor', error.message, 'error');
                return;
            }

            const known = new Map((this._recommendations || []).map((item) => [Number(item.id), item]));
            const items = (supplier.inputs || []).map((input) => {
                const existing = known.get(Number(input.id));
                if (existing) return { ...existing };
                const need = Math.max(0, Number(input.min_threshold) - Number(input.stock));
                return {
                    id: Number(input.id),
                    name: input.name,
                    unit: input.unit,
                    stock: Number(input.stock),
                    min_threshold: Number(input.min_threshold),
                    cost: Number(input.cost),
                    supplier: supplier.name,
                    supplier_id: supplierId,
                    contact: supplier.contact || '',
                    phone: supplier.phone || '',
                    email: supplier.email || '',
                    avg_daily: 0,
                    projected_14d: 0,
                    need,
                    recommended: Math.max(1, need),
                    last_quantity: 0,
                    last_unit_cost: Number(input.cost),
                    last_purchase: '',
                    days_left: 0,
                    _draftExtra: true
                };
            });

            if (!items.some((item) => Number(item.id) === inputId)) {
                items.push({ ...target });
            }
            items.sort((a, b) => {
                if (Number(a.id) === inputId) return -1;
                if (Number(b.id) === inputId) return 1;
                return String(a.name).localeCompare(String(b.name), 'es');
            });

            this._draft = { inputId, supplierId, supplierName: supplier.name };
            this._displayedRecommendations = items.map((item) => ({
                ...item,
                _draftSelected: Number(item.id) === inputId,
                _draftExtra: Number(item.id) !== inputId
            }));
            this._draftTitle.textContent = supplier.name;
            this._draftSubtitle.textContent = `${items.length} insumo${items.length === 1 ? '' : 's'} activo${items.length === 1 ? '' : 's'} de este proveedor. El insumo solicitado ya está seleccionado.`;
            this._draftBanner.hidden = false;
            this._switchView('recommendations');
            this._renderRecommendations();
            this._recommendationPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }

        _clearDraft() {
            this._draft = null;
            this._displayedRecommendations = this._recommendations;
            this._draftBanner.hidden = true;
            this._renderRecommendations();
            window.history.replaceState({}, '', '/compras');
        }

        _syncGenerateButton() {
            const selected = this._recommendationList.querySelectorAll('[data-reco-check]:checked').length;
            this._generateButton.disabled = selected === 0;
            this._generateButton.textContent = selected
                ? `Generar pedido (${selected})`
                : 'Generar pedido';
        }

        _generateOrder() {
            const selected = Array.from(this._recommendationList.querySelectorAll('[data-reco-check]:checked'));
            if (!selected.length) return;
            const groups = new Map();

            selected.forEach((checkbox) => {
                const card = checkbox.closest('[data-reco-id]');
                const item = this._displayedRecommendations.find((candidate) => Number(candidate.id) === Number(card.dataset.recoId));
                if (!item) return;
                const quantity = Number(card.querySelector('[data-reco-qty]').value) || 0;
                if (quantity <= 0) return;
                const supplierId = Number(item.supplier_id);
                if (!groups.has(supplierId)) {
                    groups.set(supplierId, {
                        supplier_id: supplierId,
                        supplier: item.supplier,
                        contact: item.contact || '',
                        phone: item.phone || '',
                        email: item.email || '',
                        items: []
                    });
                }
                groups.get(supplierId).items.push({ ...item, order_quantity: quantity });
            });

            this._orderGroups = Array.from(groups.values());
            if (!this._orderGroups.length) {
                ErpUI.toast('Cantidades inválidas', 'Revise las cantidades seleccionadas.', 'error');
                return;
            }

            this._orderMessage = this._orderGroups.map((group) => {
                const header = [`Pedido a ${group.supplier}`];
                if (group.contact) header.push(`Contacto: ${group.contact}`);
                if (group.phone) header.push(`Teléfono: ${group.phone}`);
                const lines = group.items.map((item) =>
                    `- ${number(item.order_quantity)} ${item.unit} de ${item.name} (última compra: ${number(item.last_quantity)})`);
                return `${header.join('\n')}\n${lines.join('\n')}`;
            }).join('\n\n');

            this._orderError.hidden = true;
            this._orderContent.innerHTML = this._orderGroups.map((group) => `
                <div class="order-block">
                    <h4>${escape(group.supplier)}</h4>
                    <div class="order-contact">${escape(group.contact || 'Sin contacto')} · ${escape(group.phone || 'Sin teléfono')} · ${escape(group.email || 'Sin email')}</div>
                    <ul>${group.items.map((item) =>
                        `<li>${number(item.order_quantity)} ${escape(item.unit)} de ${escape(item.name)} — ${money((Number(item.last_unit_cost) || Number(item.cost)) * Number(item.order_quantity))}</li>`).join('')}</ul>
                </div>`).join('') +
                `<label class="field"><span>Mensaje para copiar</span>
                    <textarea class="order-message" readonly>${escape(this._orderMessage)}</textarea>
                </label>`;

            this._orderModal.setTitle('Pedido generado');
            this._orderModal.open();
        }

        async _registerOrder() {
            if (!this._orderGroups.length) return;
            const button = this.querySelector('[data-register-order]');
            const error = this._orderError;
            let created = 0;
            button.disabled = true;
            error.hidden = true;
            try {
                for (const group of this._orderGroups) {
                    await ErpUI.api('/api/purchases', {
                        method: 'POST',
                        body: {
                            supplier_id: group.supplier_id,
                            notes: 'Pedido generado desde reposición sugerida',
                            items: group.items.map((item) => ({
                                input_id: item.id,
                                quantity: item.order_quantity,
                                unit_cost: Number(item.last_unit_cost) || Number(item.cost) || 0
                            }))
                        }
                    });
                    created += 1;
                }
                this._orderModal.close();
                ErpUI.toast('Pedido creado', `${created} pedido${created === 1 ? '' : 's'} creado${created === 1 ? '' : 's'} en estado pendiente.`);
                await this._loadPurchases();
            } catch (requestError) {
                if (created > 0) {
                    this._orderModal.close();
                    ErpUI.toast('Pedido parcial', `${created} pedido(s) creados antes del error: ${requestError.message}`, 'error');
                    await this._loadPurchases();
                } else {
                    error.textContent = requestError.message;
                    error.hidden = false;
                }
            } finally {
                button.disabled = false;
            }
        }

        async _loadPurchases() {
            const requestId = ++this._requestId;
            const params = new URLSearchParams({
                q: this._search.value.trim(),
                supplier: this._supplierFilter.value || '0',
                status: this._statusFilter.value || 'all',
                page: String(this._page),
                per_page: '8'
            });
            try {
                const payload = await ErpUI.api(`/api/purchases?${params}`);
                if (requestId !== this._requestId) return;
                this._page = Number(payload.page) || 1;
                this._pages = Number(payload.pages) || 1;
                this._renderPurchases(payload.items || [], payload.total || 0);
            } catch (error) {
                if (requestId !== this._requestId) return;
                this._purchaseBody.innerHTML = '';
                this._purchaseEmpty.hidden = false;
                this._purchaseEmpty.querySelector('strong').textContent = 'No se pudo cargar el historial';
                this._purchaseEmpty.querySelector('span').textContent = error.message;
            }
        }

        _renderPurchases(items, total) {
            this._purchaseCount.textContent = `${total} pedido${total === 1 ? '' : 's'}`;
            this._pagination.setData(this._page, this._pages);
            this._purchaseEmpty.hidden = items.length > 0;
            this._purchaseBody.innerHTML = items.map((purchase) => `
                <tr class="purchase-row" data-purchase-id="${Number(purchase.id)}">
                    <td>#${Number(purchase.id)}</td>
                    <td>${escape(ErpUI.formatDateTime(purchase.date))}</td>
                    <td>${escape(purchase.supplier)}</td>
                    <td><span class="purchase-status-pill ${escape(purchase.status)}">${this._statusLabel(purchase.status)}</span></td>
                    <td>${number(purchase.items, 0)}</td>
                    <td>${number(purchase.units)}</td>
                    <td>${money(purchase.total)}</td>
                </tr>`).join('');
        }

        async _openPurchaseDetail(purchaseId) {
            try {
                const purchase = await ErpUI.api(`/api/purchases/${purchaseId}`);
                const rows = (purchase.items || []).map((item) => `
                    <tr>
                        <td>${escape(item.input_name)}</td>
                        <td>${number(item.quantity)} ${escape(item.unit)}</td>
                        <td>${money(item.unit_cost)}</td>
                        <td>${money(item.subtotal)}</td>
                    </tr>`).join('');
                const stockApplied = Number(purchase.stock_applied) === 1;
                const actions = [];
                if (!stockApplied) actions.push('<button class="btn primary small" type="button" data-purchase-action="edit">Editar</button>');
                if (purchase.status === 'pending') {
                    actions.push('<button class="btn ghost small" type="button" data-purchase-status="processing">Iniciar proceso</button>');
                    actions.push('<button class="btn ghost small" type="button" data-purchase-status="finished">Finalizar</button>');
                } else if (purchase.status === 'processing') {
                    actions.push('<button class="btn ghost small" type="button" data-purchase-status="pending">Volver a pendiente</button>');
                    actions.push('<button class="btn ghost small" type="button" data-purchase-status="finished">Finalizar</button>');
                } else {
                    actions.push('<button class="btn ghost small" type="button" data-purchase-status="processing">Reabrir</button>');
                }
                if (!stockApplied) actions.push('<button class="btn ghost small" type="button" data-purchase-action="delete">Eliminar</button>');
                if (purchase.status === 'finished') actions.push('<button class="btn ghost small" type="button" data-purchase-action="invoice">Facturar / PDF</button>');

                this._detailModal.setTitle(`Pedido #${purchase.id}`);
                this._detailModal.setBody(`
                    <div class="inline-actions">
                        <span class="purchase-status-pill ${escape(purchase.status)}">${this._statusLabel(purchase.status)}</span>
                        <span class="badge badge-soft">${stockApplied ? 'Stock aplicado' : 'Stock pendiente'}</span>
                        <span class="badge badge-soft">${escape(ErpUI.formatDateTime(purchase.date))}</span>
                    </div>
                    <div class="detail-grid">
                        <div class="detail-metric"><span>Proveedor</span><strong>${escape(purchase.supplier)}</strong></div>
                        <div class="detail-metric"><span>Total estimado</span><strong>${money(purchase.total)}</strong></div>
                        <div class="detail-metric"><span>Insumos</span><strong>${(purchase.items || []).length}</strong></div>
                        <div class="detail-metric"><span>Creado por</span><strong>${escape(purchase.created_by || '—')}</strong></div>
                    </div>
                    <div class="mini-list-row">
                        <div class="row-main">
                            <strong>${escape(purchase.contact || 'Sin contacto')}</strong>
                            <small>${escape(purchase.phone || 'Sin teléfono')} · ${escape(purchase.email || 'Sin email')}</small>
                        </div>
                        ${purchase.phone ? `<button class="btn ghost small" type="button" data-copy-purchase-phone="${escape(purchase.phone)}">Copiar teléfono</button>` : ''}
                    </div>
                    ${purchase.notes ? `<p class="form-note"><b>Nota:</b> ${escape(purchase.notes)}</p>` : ''}
                    <div class="table-responsive">
                        <table>
                            <thead><tr><th>Insumo</th><th>Cantidad</th><th>Costo unitario</th><th>Subtotal</th></tr></thead>
                            <tbody>${rows}</tbody>
                        </table>
                    </div>
                    <label class="field"><span>Mensaje de pedido</span>
                        <textarea class="order-message" readonly>${escape(purchase.message)}</textarea>
                    </label>
                    <div class="detail-actions">
                        <button class="btn ghost small" type="button" data-copy-purchase-message>Copiar mensaje</button>
                        ${actions.join('')}
                    </div>
                `);
                this._detailModal.setFooter('');
                const copyPhone = this._detailModal.querySelector('[data-copy-purchase-phone]');
                if (copyPhone) copyPhone.addEventListener('click', () => ErpUI.copyText(copyPhone.dataset.copyPurchasePhone, 'Teléfono'));
                this._detailModal.querySelector('[data-copy-purchase-message]').addEventListener('click', () => ErpUI.copyText(purchase.message, 'Mensaje de pedido'));
                this._detailModal.querySelector('[data-purchase-action="edit"]')?.addEventListener('click', () => {
                    this._detailModal.close();
                    this._openPurchaseForm(purchase);
                });
                this._detailModal.querySelector('[data-purchase-action="delete"]')?.addEventListener('click', () => this._deletePurchase(purchase));
                this._detailModal.querySelector('[data-purchase-action="invoice"]')?.addEventListener('click', () => {
                    this._detailModal.close();
                    this._invoice.open('purchase', purchase.id);
                });
                this._detailModal.querySelectorAll('[data-purchase-status]').forEach((button) => {
                    button.addEventListener('click', () => this._setPurchaseStatus(purchase, button.dataset.purchaseStatus));
                });
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el pedido', error.message, 'error');
            }
        }
    }

    customElements.define('erp-purchase-manager', PurchaseManager);
})();
