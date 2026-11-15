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
            this._orderGroups = [];
            this._orderMessage = '';
            this._page = 1;
            this._pages = 1;
            this._requestId = 0;
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
            this._generateButton = this.querySelector('[data-generate-order]');
            this._purchaseBody = this.querySelector('[data-purchase-body]');
            this._purchaseEmpty = this.querySelector('[data-purchase-empty]');
            this._purchaseCount = this.querySelector('[data-purchase-count]');
            this._search = this.querySelector('[data-purchase-search]');
            this._supplierFilter = this.querySelector('[data-purchase-supplier-filter]');
            this._pagination = this.querySelector('[data-purchase-pagination]');
            this._orderModal = this.querySelector('#order-modal');
            this._orderContent = this.querySelector('[data-order-content]');
            this._orderError = this.querySelector('[data-order-error]');
            this._detailModal = this.querySelector('#purchase-detail-modal');
            this._invoice = this.querySelector('#purchase-invoice');

            this._bind();
            await this._loadMeta();
            await this._loadRecommendations();
            await this._loadPurchases();
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
                if (event.target.closest('[data-copy-reco-phone]')) {
                    event.stopPropagation();
                    ErpUI.copyText(event.target.closest('[data-copy-reco-phone]').dataset.copyRecoPhone, 'Teléfono');
                }
            });
            this._generateButton.addEventListener('click', () => this._generateOrder());
            this.querySelector('[data-order-cancel]').addEventListener('click', () => this._orderModal.close());
            this.querySelector('[data-copy-order]').addEventListener('click', () => ErpUI.copyText(this._orderMessage, 'Mensaje de pedido'));
            this.querySelector('[data-register-order]').addEventListener('click', () => this._registerOrder());
            ErpUI.debounceInput(this._search, () => {
                this._page = 1;
                this._loadPurchases();
            });
            this._supplierFilter.addEventListener('change', () => {
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
                this._renderRecommendations();
            } catch (error) {
                this._recommendationList.innerHTML = '';
                this._recommendationEmpty.hidden = false;
                this._recommendationEmpty.querySelector('strong').textContent = 'No se pudieron calcular las recomendaciones';
                this._recommendationEmpty.querySelector('span').textContent = error.message;
            }
        }

        _renderRecommendations() {
            const items = this._recommendations || [];
            this._recommendationCount.textContent = `${items.length} insumo${items.length === 1 ? '' : 's'}`;
            this._recommendationEmpty.hidden = items.length > 0;
            if (!items.length) {
                this._recommendationList.innerHTML = '';
                this._generateButton.disabled = true;
                return;
            }
            this._recommendationList.innerHTML = items.map((item) => {
                const canOrder = Number(item.supplier_id) > 0;
                const lastBuy = item.last_purchase ? ErpUI.formatDate(item.last_purchase) : 'sin compras previas';
                return `
                    <article class="recommendation-card" data-reco-id="${Number(item.id)}">
                        <header>
                            <input type="checkbox" data-reco-check ${canOrder ? '' : 'disabled'} aria-label="Seleccionar ${escape(item.name)}">
                            <div class="reco-main">
                                <strong>${escape(item.name)}</strong>
                                <small>${escape(item.supplier)}${item.phone ? ` · ${escape(item.phone)}` : ''}</small>
                            </div>
                            ${item.phone ? `<button class="btn ghost small" type="button" data-copy-reco-phone="${escape(item.phone)}">Copiar teléfono</button>` : ''}
                        </header>
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
                const item = this._recommendations.find((candidate) => Number(candidate.id) === Number(card.dataset.recoId));
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
                ErpUI.toast('Compra registrada', `${created} compra${created === 1 ? '' : 's'} registrada${created === 1 ? '' : 's'} y stock actualizado.`);
                await this._loadRecommendations();
                await this._loadPurchases();
            } catch (requestError) {
                if (created > 0) {
                    this._orderModal.close();
                    ErpUI.toast('Compra parcial', `${created} compra(s) registradas antes del error: ${requestError.message}`, 'error');
                    await this._loadRecommendations();
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
            this._purchaseCount.textContent = `${total} compra${total === 1 ? '' : 's'}`;
            this._pagination.setData(this._page, this._pages);
            this._purchaseEmpty.hidden = items.length > 0;
            this._purchaseBody.innerHTML = items.map((purchase) => `
                <tr class="purchase-row" data-purchase-id="${Number(purchase.id)}">
                    <td>#${Number(purchase.id)}</td>
                    <td>${escape(ErpUI.formatDateTime(purchase.date))}</td>
                    <td>${escape(purchase.supplier)}</td>
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
                this._detailModal.setTitle(`Compra #${purchase.id}`);
                this._detailModal.setBody(`
                    <div class="detail-grid">
                        <div class="detail-metric"><span>Proveedor</span><strong>${escape(purchase.supplier)}</strong></div>
                        <div class="detail-metric"><span>Fecha</span><strong>${escape(ErpUI.formatDateTime(purchase.date))}</strong></div>
                        <div class="detail-metric"><span>Total</span><strong>${money(purchase.total)}</strong></div>
                        <div class="detail-metric"><span>Estado</span><strong>${escape(purchase.status)}</strong></div>
                    </div>
                    <div class="mini-list-row">
                        <div class="row-main">
                            <strong>${escape(purchase.contact || 'Sin contacto')}</strong>
                            <small>${escape(purchase.phone || 'Sin teléfono')} · ${escape(purchase.email || 'Sin email')}</small>
                        </div>
                        ${purchase.phone ? `<button class="btn ghost small" type="button" data-copy-purchase-phone="${escape(purchase.phone)}">Copiar teléfono</button>` : ''}
                    </div>
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
                        <button class="btn ghost small" type="button" data-purchase-invoice>Facturar / PDF</button>
                    </div>
                `);
                this._detailModal.setFooter('');
                const copyPhone = this._detailModal.querySelector('[data-copy-purchase-phone]');
                if (copyPhone) copyPhone.addEventListener('click', () => ErpUI.copyText(copyPhone.dataset.copyPurchasePhone, 'Teléfono'));
                this._detailModal.querySelector('[data-copy-purchase-message]').addEventListener('click', () => ErpUI.copyText(purchase.message, 'Mensaje de pedido'));
                this._detailModal.querySelector('[data-purchase-invoice]').addEventListener('click', () => {
                    this._detailModal.close();
                    this._invoice.open('purchase', purchase.id);
                });
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir la compra', error.message, 'error');
            }
        }
    }

    customElements.define('erp-purchase-manager', PurchaseManager);
})();
