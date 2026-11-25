(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;
    const date = ErpUI.formatDate;

    class EventManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._products = [];
            this._events = [];
            this._page = 1;
            this._pages = 1;
            this._total = 0;
            this._detailEvent = null;
            this._stockEvent = null;
            this._closeEvent = null;
            this._canManage = false;
            this._canMetrics = false;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/event-manager/event-manager.html');
            this._body = this.querySelector('[data-event-body]');
            this._empty = this.querySelector('[data-event-empty]');
            this._count = this.querySelector('[data-event-count]');
            this._search = this.querySelector('[data-event-search]');
            this._statusFilter = this.querySelector('[data-event-status-filter]');
            this._dateFrom = this.querySelector('[data-event-date-from]');
            this._dateTo = this.querySelector('[data-event-date-to]');
            this._pagination = this.querySelector('[data-event-pagination]');
            this._createButton = this.querySelector('[data-event-create]');
            this._detailModal = this.querySelector('#event-detail-modal');
            this._formModal = this.querySelector('#event-form-modal');
            this._form = this.querySelector('[data-event-form]');
            this._formError = this.querySelector('[data-event-error]');
            this._formItems = this.querySelector('[data-event-items]');
            this._stockModal = this.querySelector('#event-stock-modal');
            this._stockForm = this.querySelector('[data-event-stock-form]');
            this._stockError = this.querySelector('[data-event-stock-error]');
            this._stockItems = this.querySelector('[data-event-stock-items]');
            this._stockSummary = this.querySelector('[data-event-stock-summary]');
            this._closeModal = this.querySelector('#event-close-modal');
            this._closeForm = this.querySelector('[data-event-close-form]');
            this._closeError = this.querySelector('[data-event-close-error]');
            this._closeItems = this.querySelector('[data-event-close-items]');
            this._closeSummary = this.querySelector('[data-event-close-summary]');

            const body = document.body;
            this._canManage = body.dataset.canManageStock === '1';
            this._canMetrics = body.dataset.canViewMetrics === '1';
            this._createButton.hidden = !this._canManage;
            this.querySelector('[data-event-stats]').closest('.event-stats-card').hidden = !this._canMetrics;

            this._bind();
            await this._loadProducts();
            await this._loadEvents();
            if (this._canMetrics) await this._loadStats();
        }

        _bind() {
            this._createButton.addEventListener('click', () => this._openCreate());
            this.querySelector('[data-event-add-item]').addEventListener('click', () => this._addFormItemRow());
            this.querySelector('[data-event-cancel]').addEventListener('click', () => this._formModal.close());
            this.querySelector('[data-event-stock-add-row]').addEventListener('click', () => this._addStockItemRow());
            this.querySelector('[data-event-stock-cancel]').addEventListener('click', () => this._stockModal.close());
            this.querySelector('[data-event-close-cancel]').addEventListener('click', () => this._closeModal.close());

            this._form.addEventListener('submit', (event) => this._submitCreate(event));
            this._stockForm.addEventListener('submit', (event) => this._submitStock(event));
            this._closeForm.addEventListener('submit', (event) => this._submitClose(event));
            this._closeItems.addEventListener('input', () => this._updateClosePreview());

            this._formItems.addEventListener('click', (event) => {
                const remove = event.target.closest('[data-event-item-remove]');
                if (!remove) return;
                remove.closest('.event-item-row').remove();
                if (!this._formItems.querySelector('.event-item-row')) this._addFormItemRow();
            });
            this._formItems.addEventListener('change', (event) => {
                if (event.target.matches('[data-event-product]')) this._renderProductHint(event.target.closest('.event-item-row'));
            });
            this._stockItems.addEventListener('click', (event) => {
                const remove = event.target.closest('[data-event-item-remove]');
                if (!remove) return;
                remove.closest('.event-item-row').remove();
                if (!this._stockItems.querySelector('.event-item-row')) this._addStockItemRow();
            });

            ErpUI.debounceInput(this._search, () => {
                this._page = 1;
                this._loadEvents();
            });
            this._statusFilter.addEventListener('change', () => {
                this._page = 1;
                this._loadEvents();
            });
            this._dateFrom.addEventListener('change', () => {
                this._page = 1;
                this._loadEvents();
            });
            this._dateTo.addEventListener('change', () => {
                this._page = 1;
                this._loadEvents();
            });
            this._pagination.addEventListener('page-change', (event) => {
                this._page = event.detail.page;
                this._loadEvents();
            });

            this._body.addEventListener('click', (event) => {
                const action = event.target.closest('[data-event-action]');
                if (action) {
                    event.stopPropagation();
                    this._runAction(action.dataset.eventAction, Number(action.dataset.eventId));
                    return;
                }
                const row = event.target.closest('[data-event-id]');
                if (row) this._openDetail(Number(row.dataset.eventId));
            });
        }

        async _loadProducts() {
            try {
                const products = await ErpUI.api('/api/products');
                this._products = (Array.isArray(products) ? products : [])
                    .filter((product) => Number(product.active) === 1 && Number(product.is_combo) === 0);
            } catch (error) {
                ErpUI.toast('No se pudo cargar el catálogo', error.message, 'error');
            }
        }

        async _loadEvents() {
            const query = new URLSearchParams({
                q: this._search.value.trim(),
                status: this._statusFilter.value,
                page: String(this._page),
                per_page: '10'
            });
            if (this._dateFrom.value) query.set('date_from', this._dateFrom.value);
            if (this._dateTo.value) query.set('date_to', this._dateTo.value);
            try {
                const payload = await ErpUI.api(`/api/events?${query.toString()}`);
                this._events = payload.items || [];
                this._page = Number(payload.page) || 1;
                this._pages = Number(payload.pages) || 1;
                this._total = Number(payload.total) || 0;
                this._renderEvents();
            } catch (error) {
                ErpUI.toast('No se pudieron cargar los eventos', error.message, 'error');
            }
        }

        _statusBadge(status, label) {
            const variant = status === 'active' ? 'badge-success' : status === 'cancelled' ? 'badge-danger' : 'badge-soft';
            return `<span class="badge ${variant}">${escape(label || status)}</span>`;
        }

        _renderEvents() {
            this._count.textContent = `${this._total} ${this._total === 1 ? 'evento' : 'eventos'}`;
            this._empty.hidden = this._events.length > 0;
            this._body.innerHTML = this._events.map((event) => {
                const active = event.status === 'active';
                const actions = [
                    `<button class="btn ghost small" type="button" data-event-action="detail" data-event-id="${Number(event.id)}">Detalle</button>`
                ];
                if (active && this._canManage) {
                    actions.push(`<button class="btn ghost small" type="button" data-event-action="stock" data-event-id="${Number(event.id)}">+ Stock</button>`);
                    actions.push(`<button class="btn ghost small" type="button" data-event-action="close" data-event-id="${Number(event.id)}">Cerrar</button>`);
                    actions.push(`<button class="btn ghost small danger-text" type="button" data-event-action="cancel" data-event-id="${Number(event.id)}">Cancelar</button>`);
                }
                const end = event.end_date ? ` → ${date(event.end_date)}` : '';
                const profitClass = Number(event.net_profit) < 0 ? 'danger-text' : 'positive-text';
                return `<tr data-event-id="${Number(event.id)}">
                    <td>
                        <strong>${escape(event.name)}</strong>
                        <small class="muted block">${escape(event.location || 'Sin ubicación')}</small>
                    </td>
                    <td>${date(event.start_date)}${end}</td>
                    <td>${this._statusBadge(event.status, event.status_label)}</td>
                    <td>${number(event.allocated_units, 0)} <small class="muted">/ ${number(event.returned_units, 0)} dev.</small></td>
                    <td>${number(event.sold_units, 0)} <small class="muted">/ ${number(event.loss_units, 0)} pérd.</small></td>
                    <td>${money(event.revenue)}</td>
                    <td class="${profitClass}">${money(event.net_profit)}</td>
                    <td><div class="inline-actions">${actions.join('')}</div></td>
                </tr>`;
            }).join('');
            this._pagination.setData(this._page, this._pages);
        }

        _runAction(action, id) {
            if (action === 'detail') this._openDetail(id);
            else if (action === 'stock') this._openStock(id);
            else if (action === 'close') this._openClose(id);
            else if (action === 'cancel') this._cancelEvent(id);
        }

        async _loadStats() {
            try {
                const stats = await ErpUI.api('/api/events/stats');
                const events = stats.events || {};
                const financials = stats.financials || {};
                const units = stats.units || {};
                this.querySelector('[data-event-kpi-active]').textContent = number(events.active, 0);
                this.querySelector('[data-event-kpi-total]').textContent = `${number(events.total, 0)} eventos registrados`;
                this.querySelector('[data-event-kpi-revenue]').textContent = money(financials.revenue);
                this.querySelector('[data-event-kpi-profit]').textContent = money(financials.net_profit);
                this.querySelector('[data-event-kpi-loss]').textContent = `Pérdidas: ${money(financials.loss)}`;
                this.querySelector('[data-event-kpi-conversion]').textContent = `${number(units.conversion, 1)}%`;
                this.querySelector('[data-event-kpi-sold]').textContent = `${number(units.sold, 0)} unidades vendidas`;
                this.querySelector('[data-event-closed-badge]').textContent = `${number(events.closed, 0)} cerrados`;
                this._renderChannels(stats.channels || []);
                this._renderStats(stats.net_profit, stats.units_sold);
                this._renderCharts(stats.series || [], units);
            } catch (error) {
                ErpUI.toast('No se pudo cargar la analítica', error.message, 'error');
            }
        }

        _renderChannels(channels) {
            const target = this.querySelector('[data-event-channels]');
            if (!channels.length) {
                target.innerHTML = '<div class="empty-state"><strong>Sin ventas de feria</strong><span>Las ventas asociadas a eventos aparecerán aquí.</span></div>';
                return;
            }
            const max = Math.max(...channels.map((channel) => Number(channel.revenue) || 0), 1);
            target.innerHTML = `<h4>Ventas por canal</h4>${channels.map((channel) => {
                const width = Math.max(2, ((Number(channel.revenue) || 0) / max) * 100);
                return `<div class="event-channel-row">
                    <div class="event-channel-label"><strong>${escape(channel.channel || 'Sin canal')}</strong><span>${number(channel.sales, 0)} ventas · ${money(channel.revenue)}</span></div>
                    <div class="event-channel-track"><span style="width:${width.toFixed(1)}%"></span></div>
                </div>`;
            }).join('')}`;
        }


        _renderCharts(series, units) {
            const profitTarget = this.querySelector('[data-event-profit-chart]');
            const distributionTarget = this.querySelector('[data-event-distribution-chart]');
            if (!profitTarget || !distributionTarget) return;

            if (!series.length) {
                profitTarget.innerHTML = '<div class="empty-state"><strong>Sin eventos cerrados</strong><span>Los comparativos aparecerán al cerrar el primer evento.</span></div>';
                distributionTarget.innerHTML = '';
                return;
            }

            const max = Math.max(...series.flatMap((item) => [Math.abs(Number(item.revenue) || 0), Math.abs(Number(item.net_profit) || 0)]), 1);
            profitTarget.innerHTML = `<h4>Ingresos vs. ganancia neta</h4>${series.map((item) => {
                const revenue = Number(item.revenue) || 0;
                const net = Number(item.net_profit) || 0;
                return `<div class="event-compare-row">
                    <div class="event-compare-label"><strong>${escape(item.name)}</strong><span>${money(net)}</span></div>
                    <div class="event-compare-bars">
                        <span class="event-bar revenue" style="width:${Math.max(1, Math.abs(revenue) / max * 100).toFixed(1)}%" title="Ingresos ${money(revenue)}"></span>
                        <span class="event-bar net ${net < 0 ? 'negative' : ''}" style="width:${Math.max(1, Math.abs(net) / max * 100).toFixed(1)}%" title="Neto ${money(net)}"></span>
                    </div>
                </div>`;
            }).join('')}<div class="event-chart-legend"><span><i class="revenue"></i>Ingresos</span><span><i class="net"></i>Ganancia neta</span></div>`;

            const sold = Number(units.sold) || 0;
            const returned = Number(units.returned) || 0;
            const loss = Number(units.lost) || 0;
            const total = sold + returned + loss;
            if (total <= 0) {
                distributionTarget.innerHTML = '<div class="empty-state"><strong>Sin unidades para distribuir</strong><span>El gráfico se habilitará con stock de eventos cerrados.</span></div>';
                return;
            }
            const soldDeg = sold / total * 360;
            const returnedDeg = returned / total * 360;
            distributionTarget.innerHTML = `<h4>Distribución del stock</h4>
                <div class="event-distribution">
                    <div class="event-pie" style="background:conic-gradient(var(--success) 0deg ${soldDeg.toFixed(2)}deg, var(--warning) ${soldDeg.toFixed(2)}deg ${(soldDeg + returnedDeg).toFixed(2)}deg, var(--danger) ${(soldDeg + returnedDeg).toFixed(2)}deg 360deg)"></div>
                    <ul class="event-pie-legend">
                        <li><i class="sold"></i><span>Vendido</span><strong>${number(sold, 0)}</strong></li>
                        <li><i class="returned"></i><span>Reintegrado</span><strong>${number(returned, 0)}</strong></li>
                        <li><i class="loss"></i><span>Merma</span><strong>${number(loss, 0)}</strong></li>
                    </ul>
                </div>`;
        }

        _renderStats(profit, units) {
            const target = this.querySelector('[data-event-stats]');
            const block = (title, stat) => {
                if (!stat) return '';
                return `<article class="event-stat-block">
                    <h4>${escape(title)}</h4>
                    <dl>
                        <div><dt>Media</dt><dd>${number(stat.mean)}</dd></div>
                        <div><dt>Mediana</dt><dd>${number(stat.median)}</dd></div>
                        <div><dt>Mínimo</dt><dd>${number(stat.min)}</dd></div>
                        <div><dt>Máximo</dt><dd>${number(stat.max)}</dd></div>
                        <div><dt>Desvío</dt><dd>${number(stat.stddev)}</dd></div>
                        <div><dt>CV</dt><dd>${number(stat.cv, 1)}%</dd></div>
                    </dl>
                </article>`;
            };
            target.innerHTML = block('Resultado neto por evento', profit) + block('Unidades vendidas por evento', units);
        }

        _productOptions(selectedId = 0, includeZero = true) {
            const zero = includeZero ? '<option value="0">Seleccione un producto…</option>' : '';
            return zero + this._products.map((product) =>
                `<option value="${Number(product.id)}" ${Number(product.id) === Number(selectedId) ? 'selected' : ''}>${escape(product.name)} — stock ${number(product.stock, 0)}</option>`).join('');
        }

        _findProduct(productId) {
            return this._products.find((product) => Number(product.id) === Number(productId));
        }

        _addFormItemRow() {
            const row = document.createElement('div');
            row.className = 'event-item-row';
            row.innerHTML = `<select data-event-product>${this._productOptions()}</select>
                <input type="number" min="1" step="1" value="1" data-event-quantity aria-label="Cantidad">
                <small class="muted" data-event-product-hint>Seleccione un producto</small>
                <button class="icon-button" type="button" data-event-item-remove aria-label="Quitar">×</button>`;
            this._formItems.append(row);
        }

        _addStockItemRow() {
            const row = document.createElement('div');
            row.className = 'event-item-row';
            row.innerHTML = `<select data-event-product>${this._productOptions()}</select>
                <input type="number" min="1" step="1" value="1" data-event-quantity aria-label="Cantidad">
                <small class="muted" data-event-product-hint>Seleccione un producto</small>
                <button class="icon-button" type="button" data-event-item-remove aria-label="Quitar">×</button>`;
            this._stockItems.append(row);
        }

        _renderProductHint(row) {
            if (!row) return;
            const hint = row.querySelector('[data-event-product-hint]');
            const product = this._findProduct(row.querySelector('[data-event-product]').value);
            hint.textContent = product ? `Stock en tienda: ${number(product.stock, 0)} unidades` : 'Seleccione un producto';
        }

        _collectItems(container) {
            const items = [];
            container.querySelectorAll('.event-item-row').forEach((row) => {
                const productId = Number(row.querySelector('[data-event-product]').value);
                const quantity = Number(row.querySelector('[data-event-quantity]').value);
                if (productId > 0 && Number.isInteger(quantity) && quantity > 0) {
                    items.push({ product_id: productId, quantity });
                }
            });
            return items;
        }

        _today() {
            const now = new Date();
            const offset = now.getTimezoneOffset() * 60000;
            return new Date(now.getTime() - offset).toISOString().slice(0, 10);
        }

        _openCreate() {
            this._form.reset();
            this.querySelector('[data-event-start]').value = this._today();
            this._formItems.innerHTML = '';
            this._formError.hidden = true;
            this._addFormItemRow();
            this._formModal.open();
        }

        async _submitCreate(event) {
            event.preventDefault();
            const items = this._collectItems(this._formItems);
            if (!items.length) {
                this._showError(this._formError, 'Agregue al menos un producto con cantidad.');
                return;
            }
            const submit = this.querySelector('[data-event-submit]');
            submit.disabled = true;
            this._formError.hidden = true;
            try {
                const payload = await ErpUI.api('/api/events', {
                    method: 'POST',
                    body: {
                        name: this.querySelector('[data-event-name]').value.trim(),
                        location: this.querySelector('[data-event-location]').value.trim(),
                        start_date: this.querySelector('[data-event-start]').value,
                        end_date: this.querySelector('[data-event-end]').value,
                        notes: this.querySelector('[data-event-notes]').value.trim(),
                        items
                    }
                });
                this._formModal.close();
                ErpUI.toast('Evento creado', `Se asignó stock al evento #${payload.event_id}.`);
                this._page = 1;
                await Promise.all([this._loadProducts(), this._loadEvents()]);
                if (this._canMetrics) await this._loadStats();
            } catch (error) {
                this._showError(this._formError, error.message);
            } finally {
                submit.disabled = false;
            }
        }

        async _openDetail(id) {
            try {
                const event = await ErpUI.api(`/api/events/${id}`);
                this._detailEvent = event;
                this._detailModal.setTitle(event.name);
                this._detailModal.setBody(this._detailHtml(event));
                this._detailModal.setFooter(this._detailFooter(event));
                this._detailModal.querySelectorAll('[data-modal-close]').forEach((button) => {
                    button.addEventListener('click', () => this._detailModal.close());
                });
                this._detailModal.querySelectorAll('[data-detail-action]').forEach((button) => {
                    button.addEventListener('click', () => {
                        const action = button.dataset.detailAction;
                        this._detailModal.close();
                        if (action === 'stock') this._openStock(id);
                        else if (action === 'close') this._openClose(id);
                        else if (action === 'cancel') this._cancelEvent(id);
                    });
                });
                await this._detailModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo abrir el evento', error.message, 'error');
            }
        }

        _detailHtml(event) {
            const active = event.status === 'active';
            const items = (event.items || []).map((item) => `<tr>
                <td>${escape(item.name)}</td>
                <td>${number(item.allocated, 0)}</td>
                <td>${number(item.sold, 0)}</td>
                <td>${number(item.loss, 0)}</td>
                <td>${number(item.returned, 0)}</td>
                <td>${number(item.available, 0)}</td>
                <td>${money(item.unit_cost)}</td>
            </tr>`).join('');
            const products = (event.products || [])
                .filter((product) => Number(product.available) > 0 || Number(product.is_combo) === 1)
                .map((product) => `<tr>
                    <td>${escape(product.name)}${Number(product.is_combo) === 1 ? ' <span class="badge badge-soft">combo</span>' : ''}</td>
                    <td>${number(product.available, 0)}</td>
                    <td>${money(product.price)}</td>
                </tr>`).join('');
            const sales = (event.sales || []).map((sale) => `<tr>
                <td><span class="badge badge-soft">${escape(sale.invoice_code || '—')}</span></td>
                <td>${escape(sale.timestamp || '—')}</td>
                <td>${escape(sale.payment_method || '—')}</td>
                <td>${escape(sale.order_stage || '—')}</td>
                <td>${money(sale.total)}</td>
            </tr>`).join('');
            const movements = (event.movements || []).map((movement) => `<tr>
                <td>${escape(movement.timestamp || '—')}</td>
                <td>${escape(movement.user || '—')}</td>
                <td>${escape(movement.action || '—')}</td>
                <td>${escape(movement.entity || '—')}</td>
                <td><code class="event-movement-payload">${escape(JSON.stringify(movement.payload || {}))}</code></td>
            </tr>`).join('');
            return `<div class="event-detail">
                <div class="event-detail-meta">
                    <div><span class="muted">Estado</span>${this._statusBadge(event.status, event.status_label)}</div>
                    <div><span class="muted">Fechas</span><strong>${date(event.start_date)}${event.end_date ? ` → ${date(event.end_date)}` : ''}</strong></div>
                    <div><span class="muted">Ubicación</span><strong>${escape(event.location || 'Sin ubicación')}</strong></div>
                    <div><span class="muted">Creado por</span><strong>${escape(event.created_by || '—')}</strong></div>
                </div>
                <div class="event-detail-kpis">
                    <div><span class="muted">Ingresos</span><strong>${money(event.revenue)}</strong></div>
                    <div><span class="muted">Costo vendido</span><strong>${money(event.cogs)}</strong></div>
                    <div><span class="muted">Pérdidas</span><strong>${money(event.loss)}</strong></div>
                    <div><span class="muted">Resultado neto</span><strong class="${Number(event.net_profit) < 0 ? 'danger-text' : 'positive-text'}">${money(event.net_profit)}</strong></div>
                    <div><span class="muted">Ventas</span><strong>${number(event.sales_count, 0)}</strong></div>
                    <div><span class="muted">Unidades vendidas</span><strong>${number(event.sales_units, 0)}</strong></div>
                </div>
                ${event.notes ? `<p class="form-note">${escape(event.notes)}</p>` : ''}
                <h4>Stock del evento</h4>
                <div class="table-responsive"><table>
                    <thead><tr><th>Producto</th><th>Asignado</th><th>Vendido</th><th>Pérdida</th><th>Devuelto</th><th>Disponible</th><th>Costo unit.</th></tr></thead>
                    <tbody>${items || '<tr><td colspan="7">Sin productos asignados.</td></tr>'}</tbody>
                </table></div>
                <h4>Ventas y comprobantes</h4>
                <div class="table-responsive event-detail-scroll"><table>
                    <thead><tr><th>Comprobante</th><th>Fecha</th><th>Pago</th><th>Etapa</th><th>Total</th></tr></thead>
                    <tbody>${sales || '<tr><td colspan="5">Sin ventas registradas.</td></tr>'}</tbody>
                </table></div>
                <h4>Movimientos</h4>
                <div class="table-responsive event-detail-scroll"><table>
                    <thead><tr><th>Fecha</th><th>Usuario</th><th>Acción</th><th>Entidad</th><th>Detalle</th></tr></thead>
                    <tbody>${movements || '<tr><td colspan="5">Sin movimientos.</td></tr>'}</tbody>
                </table></div>
                ${active ? `<h4>Disponibilidad para vender en feria</h4>
                <div class="table-responsive event-detail-scroll"><table>
                    <thead><tr><th>Producto</th><th>Disponible</th><th>Precio</th></tr></thead>
                    <tbody>${products || '<tr><td colspan="3">Sin disponibilidad.</td></tr>'}</tbody>
                </table></div>` : ''}
            </div>`;
        }

        _detailFooter(event) {
            if (event.status !== 'active' || !this._canManage) {
                return '<button class="btn ghost" type="button" data-modal-close>Cerrar</button>';
            }
            return `<button class="btn ghost" type="button" data-modal-close>Cerrar</button>
                <button class="btn ghost" type="button" data-detail-action="stock">+ Stock</button>
                <button class="btn ghost danger-text" type="button" data-detail-action="cancel">Cancelar evento</button>
                <button class="btn primary" type="button" data-detail-action="close">Cerrar evento</button>`;
        }

        async _openStock(id) {
            try {
                const event = await ErpUI.api(`/api/events/${id}`);
                this._stockEvent = event;
                this._stockSummary.textContent = `${event.name} · stock actual: ${number((event.items || []).reduce((sum, item) => sum + Number(item.available || 0), 0), 0)} unidades disponibles.`;
                this._stockItems.innerHTML = '';
                this._stockError.hidden = true;
                this._addStockItemRow();
                await this._stockModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo ampliar el stock', error.message, 'error');
            }
        }

        async _submitStock(event) {
            event.preventDefault();
            if (!this._stockEvent) return;
            const items = this._collectItems(this._stockItems);
            if (!items.length) {
                this._showError(this._stockError, 'Agregue al menos un producto con cantidad.');
                return;
            }
            const submit = this.querySelector('[data-event-stock-submit]');
            submit.disabled = true;
            this._stockError.hidden = true;
            try {
                await ErpUI.api(`/api/events/${this._stockEvent.id}/stock`, { method: 'POST', body: { items } });
                this._stockModal.close();
                ErpUI.toast('Stock ampliado', 'El stock del evento se actualizó correctamente.');
                await Promise.all([this._loadProducts(), this._loadEvents()]);
                if (this._canMetrics) await this._loadStats();
            } catch (error) {
                this._showError(this._stockError, error.message);
            } finally {
                submit.disabled = false;
            }
        }

        async _openClose(id) {
            try {
                const event = await ErpUI.api(`/api/events/${id}`);
                this._closeEvent = event;
                this._closeSummary.textContent = `${event.name} · ${number(event.sales_count, 0)} ventas por ${money(event.revenue)}.`;
                const rows = (event.items || []).map((item) => `<div class="event-close-row" data-close-product="${Number(item.product_id)}">
                    <div>
                        <strong>${escape(item.name)}</strong>
                        <small class="muted block">Disponible al cierre: ${number(item.available, 0)} · Vendido: ${number(item.sold, 0)}</small>
                    </div>
                    <label class="field compact-field">
                        <span>Pérdida</span>
                        <input type="number" min="0" max="${Number(item.available)}" step="1" value="0" data-close-loss>
                    </label>
                </div>`).join('');
                this._closeItems.innerHTML = rows || '<div class="empty-state"><strong>Sin stock asignado</strong><span>El evento se cerrará sin devoluciones.</span></div>';
                this._closeError.hidden = true;
                this._updateClosePreview();
                await this._closeModal.open();
            } catch (error) {
                ErpUI.toast('No se pudo cerrar el evento', error.message, 'error');
            }
        }


        _updateClosePreview() {
            if (!this._closeEvent) return;
            const event = this._closeEvent;
            let extraLoss = 0;
            let remaining = 0;
            (event.items || []).forEach((item) => {
                const row = this._closeItems.querySelector(`[data-close-product="${Number(item.product_id)}"]`);
                const input = row ? row.querySelector('[data-close-loss]') : null;
                const loss = input ? Math.max(0, Number(input.value) || 0) : 0;
                extraLoss += loss * (Number(item.unit_cost) || 0);
                remaining += Math.max(0, Number(item.available) - loss);
            });
            const projectedLoss = (Number(event.loss) || 0) + extraLoss;
            const projectedNet = (Number(event.revenue) || 0) - (Number(event.cogs) || 0) - projectedLoss;
            this._closeSummary.textContent = `${event.name} · Ventas ${money(event.revenue)} · Pérdida proyectada ${money(projectedLoss)} · Sobrante ${number(remaining, 0)} u. · Neto proyectado ${money(projectedNet)}`;
        }

        async _submitClose(event) {
            event.preventDefault();
            if (!this._closeEvent) return;
            const losses = [];
            this._closeItems.querySelectorAll('[data-close-product]').forEach((row) => {
                const quantity = Number(row.querySelector('[data-close-loss]').value);
                if (Number.isInteger(quantity) && quantity > 0) {
                    losses.push({ product_id: Number(row.dataset.closeProduct), quantity });
                }
            });
            const submit = this.querySelector('[data-event-close-submit]');
            const backup = this.querySelector('[data-event-close-backup]');
            submit.disabled = true;
            this._closeError.hidden = true;
            try {
                const payload = await ErpUI.api(`/api/events/${this._closeEvent.id}/close`, {
                    method: 'POST',
                    body: { losses, backup: backup && backup.checked ? 1 : 0 }
                });
                this._closeModal.close();
                const backupNote = payload.backup_path ? ` · Respaldo: ${payload.backup_path}` : '';
                ErpUI.toast('Evento cerrado', `Resultado neto: ${money(payload.net_profit)} · Pérdidas: ${money(payload.loss)}${backupNote}.`);
                await Promise.all([this._loadProducts(), this._loadEvents()]);
                if (this._canMetrics) await this._loadStats();
            } catch (error) {
                this._showError(this._closeError, error.message);
            } finally {
                submit.disabled = false;
            }
        }

        async _cancelEvent(id) {
            if (!window.confirm('¿Cancelar este evento? Solo es posible si no tiene ventas ni pérdidas registradas. Se devolverá todo el stock.')) return;
            try {
                await ErpUI.api(`/api/events/${id}/cancel`, { method: 'POST', body: {} });
                ErpUI.toast('Evento cancelado', 'El stock asignado fue devuelto a la tienda.');
                await Promise.all([this._loadProducts(), this._loadEvents()]);
                if (this._canMetrics) await this._loadStats();
            } catch (error) {
                ErpUI.toast('No se pudo cancelar', error.message, 'error');
            }
        }

        _showError(target, message) {
            target.textContent = message;
            target.hidden = false;
        }
    }

    customElements.define('erp-event-manager', EventManager);
})();
