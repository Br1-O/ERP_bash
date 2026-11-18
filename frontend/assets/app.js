(() => {
    'use strict';

    const dataElement = document.getElementById('erp-data');
    let ERP = null;
    try {
        ERP = dataElement ? JSON.parse(dataElement.textContent) : null;
    } catch (error) {
        console.error('No se pudo leer el payload del dashboard', error);
    }

    const palette = ['#d7a64a', '#4cc9a2', '#6ba7e6', '#e8b04b', '#e66b6b', '#9a8cf0', '#e88ac0'];
    const money = new Intl.NumberFormat('es-AR', {
        style: 'currency',
        currency: 'ARS',
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
    const number = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 2 });

    const $ = (id) => document.getElementById(id);
    const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

    function escapeHtml(value) {
        const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
        return String(value ?? '').replace(/[&<>"']/g, (character) => map[character]);
    }

    function text(id, value) {
        const element = $(id);
        if (element) element.textContent = value;
    }

    function fmtMoney(value) {
        return money.format(Number(value) || 0);
    }

    function fmtNumber(value, digits = 2) {
        const numeric = Number(value) || 0;
        return numeric.toLocaleString('es-AR', { maximumFractionDigits: digits });
    }

    function fmtPct(value, digits = 1) {
        return `${(Number(value) || 0).toFixed(digits)}%`;
    }

    function fmtPValue(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric)) return '—';
        if (numeric < 0.0001) return '< 0.0001';
        return numeric.toFixed(4);
    }

    function shortDate(value) {
        if (!value) return '';
        const date = new Date(`${value}T00:00:00`);
        if (Number.isNaN(date.getTime())) return value;
        return date.toLocaleDateString('es-AR', { day: '2-digit', month: 'short' });
    }

    function shortHour(value) {
        if (!value || value === '--') return '—';
        return `${value}:00`;
    }

    function normalize(value) {
        return String(value ?? '')
            .toLowerCase()
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '');
    }

    function withAlpha(color, alpha) {
        if (!color) return `rgba(215, 166, 74, ${alpha})`;
        if (color.startsWith('#')) {
            let hex = color.slice(1);
            if (hex.length === 3) hex = hex.split('').map((part) => part + part).join('');
            const numeric = parseInt(hex, 16);
            if (!Number.isNaN(numeric)) {
                const r = (numeric >> 16) & 255;
                const g = (numeric >> 8) & 255;
                const b = numeric & 255;
                return `rgba(${r}, ${g}, ${b}, ${alpha})`;
            }
        }
        if (color.startsWith('rgb(')) {
            return color.replace('rgb(', 'rgba(').replace(')', `, ${alpha})`);
        }
        return color;
    }

    function prepareCanvas(canvas) {
        const rect = canvas.getBoundingClientRect();
        const width = Math.max(1, rect.width);
        const height = Math.max(1, rect.height);
        const dpr = window.devicePixelRatio || 1;
        canvas.width = Math.round(width * dpr);
        canvas.height = Math.round(height * dpr);
        const context = canvas.getContext('2d');
        context.setTransform(dpr, 0, 0, dpr, 0, 0);
        return { context, width, height };
    }

    function emptyCanvas(context, width, height, message) {
        context.clearRect(0, 0, width, height);
        context.fillStyle = cssVar('--text-dim');
        context.font = '13px ' + cssVar('--font');
        context.textAlign = 'center';
        context.fillText(message || 'Sin datos disponibles', width / 2, height / 2);
        context.textAlign = 'start';
    }

    function roundedRect(context, x, y, width, height, radius) {
        const r = Math.min(radius, width / 2, height / 2);
        context.beginPath();
        context.moveTo(x + r, y);
        context.arcTo(x + width, y, x + width, y + height, r);
        context.arcTo(x + width, y + height, x, y + height, r);
        context.arcTo(x, y + height, x, y, r);
        context.arcTo(x, y, x + width, y, r);
        context.closePath();
    }

    function drawBarChart(canvas, daily) {
        if (!canvas) return;
        const { context, width, height } = prepareCanvas(canvas);
        const labels = daily.labels || [];
        const values = daily.values || [];

        if (!labels.length) {
            emptyCanvas(context, width, height, 'Aún no hay ventas registradas');
            return;
        }

        const outlierDates = new Set((daily.outliers || []).map((item) => item.date));
        const padding = { left: 48, right: 14, top: 14, bottom: 36 };
        const chartWidth = width - padding.left - padding.right;
        const chartHeight = height - padding.top - padding.bottom;
        const max = Math.max(...values, 1);
        const exponent = Math.floor(Math.log10(max));
        const base = Math.pow(10, Math.max(0, exponent));
        const normalized = max / base;
        const multiplier = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10;
        const niceMax = multiplier * base;

        const textColor = cssVar('--text-dim');
        const borderColor = cssVar('--border');
        const accent = cssVar('--accent');
        const danger = cssVar('--danger');

        context.clearRect(0, 0, width, height);
        context.font = '11px ' + cssVar('--font');
        context.textAlign = 'right';
        context.textBaseline = 'middle';

        for (let tick = 0; tick <= 4; tick++) {
            const y = padding.top + chartHeight - (chartHeight * tick / 4);
            context.strokeStyle = borderColor;
            context.lineWidth = 1;
            context.beginPath();
            context.moveTo(padding.left, y);
            context.lineTo(width - padding.right, y);
            context.stroke();

            context.fillStyle = textColor;
            context.fillText('$' + new Intl.NumberFormat('es-AR', { notation: 'compact', maximumFractionDigits: 1 }).format(niceMax * tick / 4), padding.left - 8, y);
        }

        const slot = chartWidth / labels.length;
        const barWidth = Math.max(2, Math.min(26, slot * 0.62));
        const labelStep = Math.ceil(labels.length / Math.max(4, Math.floor(chartWidth / 70)));

        labels.forEach((label, index) => {
            const value = Number(values[index]) || 0;
            const barHeight = (value / niceMax) * chartHeight;
            const x = padding.left + slot * index + (slot - barWidth) / 2;
            const y = padding.top + chartHeight - barHeight;

            context.fillStyle = outlierDates.has(label) ? danger : withAlpha(accent, 0.82);
            roundedRect(context, x, y, barWidth, Math.max(1, barHeight), Math.min(5, barWidth / 2));
            context.fill();

            if (index % labelStep === 0 || index === labels.length - 1) {
                context.save();
                context.fillStyle = textColor;
                context.textAlign = 'center';
                context.textBaseline = 'top';
                context.fillText(shortDate(label), x + barWidth / 2, padding.top + chartHeight + 8);
                context.restore();
            }
        });

        context.fillStyle = textColor;
        context.textAlign = 'center';
        context.textBaseline = 'top';
        context.font = '10px ' + cssVar('--font');
        context.fillText('Días con barras rojas superan Q3 + 1,5 × RIC', width / 2, height - 12);
        context.textAlign = 'start';
    }

    function drawGauge(canvas, probability) {
        if (!canvas) return;
        const { context, width, height } = prepareCanvas(canvas);
        const probabilityValue = Math.max(0, Math.min(1, Number(probability) || 0));
        const centerX = width / 2;
        const centerY = height * 0.60;
        const radius = Math.min(width / 2 - 24, height * 0.52);
        const start = Math.PI * 0.75;
        const end = Math.PI * 2.25;

        context.clearRect(0, 0, width, height);
        context.lineCap = 'round';
        context.lineWidth = 15;

        context.strokeStyle = cssVar('--surface-muted');
        context.beginPath();
        context.arc(centerX, centerY, radius, start, end);
        context.stroke();

        const danger = cssVar('--danger');
        const accent = cssVar('--accent');
        context.strokeStyle = probabilityValue >= 0.5 ? danger : accent;
        context.beginPath();
        context.arc(centerX, centerY, radius, start, start + (end - start) * probabilityValue);
        context.stroke();

        context.lineWidth = 1;
        for (let tick = 0; tick <= 4; tick++) {
            const angle = start + ((end - start) * tick / 4);
            const inner = radius + 13;
            const outer = radius + 19;
            context.strokeStyle = cssVar('--border-strong');
            context.beginPath();
            context.moveTo(centerX + Math.cos(angle) * inner, centerY + Math.sin(angle) * inner);
            context.lineTo(centerX + Math.cos(angle) * outer, centerY + Math.sin(angle) * outer);
            context.stroke();
        }
    }

    function drawCostChart(canvas, cost) {
        if (!canvas) return;
        const { context, width, height } = prepareCanvas(canvas);
        const labels = cost.labels || [];
        const values = (cost.values || []).map(Number);

        if (!labels.length) {
            emptyCanvas(context, width, height, 'Sin lotes de producción registrados');
            return;
        }

        const padding = { left: 48, right: 16, top: 18, bottom: 34 };
        const chartWidth = width - padding.left - padding.right;
        const chartHeight = height - padding.top - padding.bottom;
        const minValue = Math.min(Number(cost.lower) || 0, ...values);
        const maxValue = Math.max(Number(cost.upper) || 0, ...values);
        const span = Math.max(1, maxValue - minValue);
        const minY = Math.max(0, minValue - span * 0.15);
        const maxY = maxValue + span * 0.15;
        const accent = cssVar('--accent');
        const textColor = cssVar('--text-dim');
        const borderColor = cssVar('--border');

        const yFor = (value) => padding.top + chartHeight - ((value - minY) / (maxY - minY)) * chartHeight;

        context.clearRect(0, 0, width, height);
        context.font = '11px ' + cssVar('--font');
        context.textAlign = 'right';
        context.textBaseline = 'middle';

        for (let tick = 0; tick <= 3; tick++) {
            const value = minY + ((maxY - minY) * tick / 3);
            const y = yFor(value);
            context.strokeStyle = borderColor;
            context.beginPath();
            context.moveTo(padding.left, y);
            context.lineTo(width - padding.right, y);
            context.stroke();
            context.fillStyle = textColor;
            context.fillText('$' + Number(value).toFixed(0), padding.left - 8, y);
        }

        const upperY = yFor(Number(cost.upper) || 0);
        const lowerY = yFor(Number(cost.lower) || 0);
        context.fillStyle = withAlpha(accent, 0.11);
        context.fillRect(padding.left, upperY, chartWidth, lowerY - upperY);

        context.strokeStyle = withAlpha(accent, 0.45);
        context.setLineDash([5, 5]);
        context.beginPath();
        context.moveTo(padding.left, upperY);
        context.lineTo(width - padding.right, upperY);
        context.moveTo(padding.left, lowerY);
        context.lineTo(width - padding.right, lowerY);
        context.stroke();
        context.setLineDash([]);

        const meanY = yFor(Number(cost.mean) || 0);
        context.strokeStyle = accent;
        context.lineWidth = 1.5;
        context.beginPath();
        context.moveTo(padding.left, meanY);
        context.lineTo(width - padding.right, meanY);
        context.stroke();

        const step = chartWidth / Math.max(1, values.length - 1);
        const labelStep = Math.ceil(labels.length / Math.max(3, Math.floor(chartWidth / 80)));

        context.strokeStyle = cssVar('--text-soft');
        context.lineWidth = 1.5;
        context.beginPath();
        values.forEach((value, index) => {
            const x = padding.left + step * index;
            const y = yFor(value);
            if (index === 0) context.moveTo(x, y);
            else context.lineTo(x, y);
        });
        context.stroke();

        values.forEach((value, index) => {
            const x = padding.left + step * index;
            const y = yFor(value);
            context.fillStyle = accent;
            context.beginPath();
            context.arc(x, y, 3.5, 0, Math.PI * 2);
            context.fill();

            if (index % labelStep === 0 || index === values.length - 1) {
                context.fillStyle = textColor;
                context.textAlign = 'center';
                context.textBaseline = 'top';
                context.fillText(shortDate(labels[index]), x, padding.top + chartHeight + 8);
            }
        });
        context.textAlign = 'start';
    }

    function drawCategoryPie(canvas, categories) {
        if (!canvas) return;
        const { context, width, height } = prepareCanvas(canvas);
        const labels = categories.labels || [];
        const values = (categories.values || []).map(Number);
        const total = values.reduce((sum, value) => sum + value, 0);

        if (!labels.length || total <= 0) {
            emptyCanvas(context, width, height, 'Sin ventas por categoría');
            return;
        }

        const centerX = width / 2;
        const centerY = height / 2;
        const radius = Math.min(width, height) / 2 - 16;
        const innerRadius = radius * 0.58;
        let angle = -Math.PI / 2;

        context.clearRect(0, 0, width, height);
        values.forEach((value, index) => {
            const slice = (value / total) * Math.PI * 2;
            context.beginPath();
            context.moveTo(centerX, centerY);
            context.arc(centerX, centerY, radius, angle, angle + slice);
            context.closePath();
            context.fillStyle = palette[index % palette.length];
            context.fill();
            context.strokeStyle = cssVar('--surface');
            context.lineWidth = 3;
            context.stroke();
            angle += slice;
        });

        context.fillStyle = cssVar('--surface');
        context.beginPath();
        context.arc(centerX, centerY, innerRadius, 0, Math.PI * 2);
        context.fill();

        context.fillStyle = cssVar('--text');
        context.textAlign = 'center';
        context.textBaseline = 'middle';
        context.font = '700 16px ' + cssVar('--font');
        context.fillText(fmtMoney(total), centerX, centerY - 6);
        context.fillStyle = cssVar('--text-dim');
        context.font = '11px ' + cssVar('--font');
        context.fillText('ingresos', centerX, centerY + 12);
        context.textAlign = 'start';
    }

    function renderLegend(categories) {
        const container = $('category-legend');
        if (!container) return;
        container.innerHTML = '';
        (categories.labels || []).forEach((label, index) => {
            const item = document.createElement('span');
            item.className = 'legend-item';
            item.innerHTML = `<span class="legend-dot" style="background:${palette[index % palette.length]}"></span>${escapeHtml(label)} · ${fmtMoney((categories.values || [])[index])}`;
            container.appendChild(item);
        });
    }

    function renderKpis() {
        const kpis = ERP.kpis || {};
        text('kpi-revenue', fmtMoney(kpis.revenue));
        text('kpi-revenue-meta', `Valor de inventario ${fmtMoney(kpis.inventory_value)}`);
        text('kpi-sales', fmtNumber(kpis.sales_count, 0));
        text('kpi-sales-meta', `Ticket promedio ${fmtMoney(kpis.avg_ticket)}`);
        text('kpi-units', fmtNumber(kpis.units, 0));
        text('kpi-units-meta', `Productos activos: ${fmtNumber(kpis.active_products, 0)}`);
        text('kpi-inventory', fmtMoney(kpis.inventory_value));
        text('kpi-inventory-meta', `Clientes: ${fmtNumber(kpis.customers, 0)} · Alertas: ${fmtNumber(kpis.low_stock_count, 0)}`);
    }

    function renderDailyStats() {
        const daily = ERP.daily || { stats: {}, outliers: [] };
        const stats = daily.stats || {};
        text('daily-days', `${fmtNumber(stats.days, 0)} días`);
        text('daily-mean', fmtMoney(stats.mean));
        text('daily-median', fmtMoney(stats.median));
        text('daily-q1', fmtMoney(stats.q1));
        text('daily-q3', fmtMoney(stats.q3));
        text('daily-iqr', fmtMoney(stats.iqr));
        text('daily-threshold', fmtMoney(stats.threshold));

        const container = $('outliers-list');
        if (!container) return;
        container.innerHTML = '';
        const outliers = daily.outliers || [];
        if (!outliers.length) {
            container.innerHTML = '<span class="outlier-chip" style="background:var(--success-soft);color:var(--success)">Sin picos atípicos en el período</span>';
            return;
        }
        outliers.forEach((item) => {
            const chip = document.createElement('span');
            chip.className = 'outlier-chip';
            chip.textContent = `${shortDate(item.date)} · ${fmtMoney(item.value)}`;
            container.appendChild(chip);
        });
    }

    function renderBinomial() {
        const binomial = ERP.binomial || {};
        const probability = Number(binomial.probability) || 0;
        text('binomial-percent', fmtPct(probability * 100, 1));
        text('binomial-n', fmtNumber(binomial.n, 0));
        text('binomial-k', fmtNumber(binomial.k, 0));
        text('binomial-peak', shortHour(binomial.peak_hour));
        text('binomial-text', probability >= 0.5
            ? 'El escenario de saturación es probable: refuerce personal y stock en la franja pico.'
            : 'La probabilidad de saturación horaria es contenida con la capacidad actual.');
    }

    function stageLabel(status) {
        const labels = {
            draft: 'Borrador', pending: 'Pendiente', preparing: 'En preparación',
            confirmed: 'Confirmado', paid: 'Pagado', delivered: 'Entregado', cancel: 'Anulado'
        };
        return labels[status] || status || '—';
    }

    function renderRecentSales() {
        const body = $('recent-sales-body');
        if (!body) return;
        const sales = ERP.recent_sales || [];
        if (!sales.length) {
            body.innerHTML = '<tr><td colspan="6"><div class="empty-state">Sin ventas registradas.</div></td></tr>';
            return;
        }
        body.innerHTML = sales.map((sale) => `
            <tr>
                <td class="mono">#${escapeHtml(sale.id)}<br><small class="muted">${escapeHtml(sale.order_type === 'direct' ? 'Venta directa' : 'Pedido')} · ${escapeHtml(stageLabel(sale.status))}</small></td>
                <td>${escapeHtml(sale.customer)}</td>
                <td><span class="badge badge-soft">${escapeHtml(sale.payment)}</span></td>
                <td>${fmtNumber(sale.units, 0)}</td>
                <td class="text-right positive">${fmtMoney(sale.total)}</td>
                <td><button class="btn ghost small" type="button" data-void-sale="${Number(sale.id)}" data-void-type="${escapeHtml(sale.order_type)}">Anular</button></td>
            </tr>
        `).join('');
    }

    function renderJournal() {
        const container = $('journal-list');
        if (!container) return;
        const entries = ERP.journal || [];
        if (!entries.length) {
            container.innerHTML = '<div class="empty-state">Sin movimientos auditados.</div>';
            return;
        }
        container.innerHTML = entries.map((entry) => `
            <div class="timeline-item">
                <strong>${escapeHtml(entry.action)} · ${escapeHtml(entry.entity)}</strong>
                <time>${escapeHtml(entry.timestamp)}</time>
                <p>${escapeHtml(entry.payload || 'Sin detalle')}</p>
            </div>
        `).join('');
    }

    function renderAlerts() {
        const alerts = ERP.alerts || { inputs: [], products: [], count: 0 };
        const inputContainer = $('input-alerts');
        const productContainer = $('product-alerts');
        const stockBadge = $('stock-alert-count');
        const alertBadge = $('alert-count');

        if (alertBadge) alertBadge.textContent = fmtNumber(alerts.count, 0);
        if (stockBadge) stockBadge.textContent = `${fmtNumber(alerts.count, 0)} alertas`;

        if (inputContainer) {
            if (!alerts.inputs.length) {
                inputContainer.innerHTML = '<div class="empty-state"><strong>Insumos en nivel seguro</strong><span>No hay recompras críticas por ahora.</span></div>';
            } else {
                inputContainer.innerHTML = alerts.inputs.map((item) => `
                    <a class="alert-row alert-link" href="/compras?input=${Number(item.id)}" title="Preparar pedido de ${escapeHtml(item.name)}">
                        <span class="alert-icon">!</span>
                        <div>
                            <strong>${escapeHtml(item.name)}</strong>
                            <small>Umbral ${fmtNumber(item.threshold)} ${escapeHtml(item.unit)} · déficit ${fmtNumber(item.deficit)} ${escapeHtml(item.unit)}</small>
                        </div>
                        <span class="alert-value">${fmtNumber(item.stock)} ${escapeHtml(item.unit)}</span>
                    </a>
                `).join('');
            }
        }

        if (productContainer) {
            if (!alerts.products.length) {
                productContainer.innerHTML = '<div class="empty-state"><strong>Producción al día</strong><span>Ningún producto requiere lote urgente.</span></div>';
            } else {
                productContainer.innerHTML = alerts.products.map((item) => {
                    const combo = Number(item.is_combo) === 1;
                    const href = combo
                        ? `/inventario?product=${Number(item.id)}`
                        : `/inventario?product=${Number(item.id)}&produce=1`;
                    const detail = combo
                        ? `Disponibles ${fmtNumber(item.stock)} u. · faltan ${fmtNumber(item.deficit)} u.`
                        : `Mínimo de producción ${fmtNumber(item.threshold)} u. · faltan ${fmtNumber(item.deficit)} u.`;
                    return `
                        <a class="alert-row alert-link" href="${href}" title="${combo ? 'Ver componentes del combo' : 'Registrar producción'}">
                            <span class="alert-icon">↺</span>
                            <div>
                                <strong>${escapeHtml(item.name)}</strong>
                                <small>${detail}</small>
                            </div>
                            <span class="alert-value">${fmtNumber(item.stock)} u.</span>
                        </a>`;
                }).join('');
            }
        }
    }

    function renderReorderProducts() {
        const body = $('reorder-products-body');
        if (!body) return;
        const rows = ERP.reorder_products || [];
        if (!rows.length) {
            body.innerHTML = '<tr><td colspan="8"><div class="empty-state">Sin datos de demanda.</div></td></tr>';
            return;
        }
        body.innerHTML = rows.map((item) => {
            const combo = Number(item.is_combo) === 1;
            const href = combo
                ? `/inventario?product=${Number(item.id)}`
                : `/inventario?product=${Number(item.id)}&produce=1`;
            return `
                <tr class="clickable-row" data-href="${href}">
                    <td><a class="table-link" href="${href}">${escapeHtml(item.name)}</a></td>
                    <td>${fmtNumber(item.stock)}</td>
                    <td>${fmtNumber(item.mean, 3)}</td>
                    <td>${fmtNumber(item.sd, 3)}</td>
                    <td>${fmtPct(item.cv, 1)}</td>
                    <td>${fmtNumber(item.safety, 2)}</td>
                    <td>${fmtNumber(item.reorder, 2)}</td>
                    <td><span class="badge ${item.critical ? 'badge-danger' : 'badge-success'}">${item.critical ? 'Reponer' : 'Cubierto'}</span></td>
                </tr>`;
        }).join('');
    }

    function renderReorderInputs() {
        const body = $('reorder-inputs-body');
        if (!body) return;
        const rows = ERP.reorder_inputs || [];
        if (!rows.length) {
            body.innerHTML = '<tr><td colspan="6"><div class="empty-state">Sin datos de consumo.</div></td></tr>';
            return;
        }
        body.innerHTML = rows.map((item) => {
            const href = `/compras?input=${Number(item.id)}`;
            return `
                <tr class="clickable-row" data-href="${href}">
                    <td><a class="table-link" href="${href}">${escapeHtml(item.name)}</a></td>
                    <td>${fmtNumber(item.stock)} ${escapeHtml(item.unit)}</td>
                    <td>${fmtNumber(item.mean, 3)}</td>
                    <td>${fmtPct(item.cv, 1)}</td>
                    <td><span class="badge badge-soft">${fmtNumber(item.reorder, 2)}</span></td>
                    <td><span class="badge ${item.critical ? 'badge-danger' : 'badge-success'}">${item.critical ? 'Reponer' : 'Cubierto'}</span></td>
                </tr>`;
        }).join('');
    }

    function renderCostStats() {
        const cost = ERP.cost_ci || {};
        const container = $('cost-ci-stats');
        if (!container) return;
        container.innerHTML = `
            <span>Lotes analizados <strong>${fmtNumber(cost.n, 0)}</strong></span>
            <span>Costo medio <strong>${fmtMoney(cost.mean)}</strong></span>
            <span>Desv. estándar <strong>${fmtMoney(cost.sd)}</strong></span>
            <span>Margen de error <strong>${fmtMoney(cost.margin)}</strong></span>
            <span>Intervalo <strong>${fmtMoney(cost.lower)} — ${fmtMoney(cost.upper)}</strong></span>
        `;
    }

    function renderHypothesis() {
        const hypothesis = ERP.hypothesis || {};
        const card = $('hypothesis-card');
        text('hypothesis-product', hypothesis.product || 'Sabor estacional');
        const verdict = $('hypothesis-verdict');
        if (verdict) {
            verdict.textContent = hypothesis.verdict || 'Sin datos';
            verdict.classList.toggle('approved', Boolean(hypothesis.approved));
            verdict.classList.toggle('rejected', !hypothesis.approved);
        }
        if (card) {
            card.classList.toggle('approved', Boolean(hypothesis.approved));
        }

        const stats = $('hypothesis-stats');
        if (stats) {
            stats.innerHTML = `
                <div class="metric"><span>p̂ observada</span><strong>${fmtPct((Number(hypothesis.phat) || 0) * 100, 1)}</strong></div>
                <div class="metric"><span>Muestra n</span><strong>${fmtNumber(hypothesis.n, 0)}</strong></div>
                <div class="metric"><span>Aceptaciones</span><strong>${fmtNumber(hypothesis.successes, 0)}</strong></div>
                <div class="metric"><span>Estadístico Z</span><strong>${fmtNumber(hypothesis.z, 2)}</strong></div>
                <div class="metric"><span>p-valor</span><strong>${fmtPValue(hypothesis.pvalue)}</strong></div>
                <div class="metric"><span>p₀ histórico</span><strong>${fmtPct((Number(hypothesis.p0) || 0.4) * 100, 0)}</strong></div>
            `;
        }

        const note = $('hypothesis-note');
        if (note) {
            note.innerHTML = hypothesis.approved
                ? 'Se rechaza H₀: la aceptación supera significativamente el 40% histórico.'
                : 'No se rechaza H₀: la evidencia aún no supera el umbral de aceptación.';
        }
    }

    function renderMatrix() {
        const container = $('correlation-matrix');
        if (!container) return;
        const basket = ERP.basket || { products: [], matrix: [] };
        const products = basket.products || [];
        const matrix = basket.matrix || [];

        text('basket-sales-count', `${fmtNumber(basket.sales_count, 0)} ventas`);

        if (products.length < 2) {
            container.innerHTML = '<div class="empty-state">Se necesitan al menos dos productos con ventas para calcular la canasta.</div>';
            container.style.gridTemplateColumns = '1fr';
            return;
        }

        const size = products.length + 1;
        container.style.gridTemplateColumns = `minmax(110px, 1.5fr) repeat(${products.length}, minmax(56px, 1fr))`;
        container.innerHTML = '';

        const headerCorner = document.createElement('div');
        headerCorner.className = 'matrix-cell header';
        headerCorner.textContent = 'Producto';
        container.appendChild(headerCorner);

        products.forEach((product) => {
            const cell = document.createElement('div');
            cell.className = 'matrix-cell header';
            cell.title = product.name;
            cell.textContent = product.name.split(' ').slice(0, 2).join(' ');
            container.appendChild(cell);
        });

        products.forEach((rowProduct, rowIndex) => {
            const header = document.createElement('div');
            header.className = 'matrix-cell header';
            header.title = rowProduct.name;
            header.textContent = rowProduct.name.split(' ').slice(0, 2).join(' ');
            container.appendChild(header);

            products.forEach((columnProduct, columnIndex) => {
                const value = Number(matrix[rowIndex] && matrix[rowIndex][columnIndex]) || 0;
                const cell = document.createElement('div');
                cell.className = 'matrix-cell' + (rowIndex === columnIndex ? ' diagonal' : '');
                cell.textContent = value.toFixed(2);
                cell.title = `${rowProduct.name} ↔ ${columnProduct.name}: r = ${value.toFixed(2)}`;
                if (rowIndex !== columnIndex) {
                    cell.style.background = value >= 0
                        ? `rgba(76, 201, 162, ${0.08 + Math.abs(value) * 0.45})`
                        : `rgba(230, 107, 107, ${0.08 + Math.abs(value) * 0.45})`;
                }
                container.appendChild(cell);
            });
        });
    }

    function renderCombos() {
        const combos = $('combos-list');
        const substitutes = $('substitutes-list');
        const basket = ERP.basket || { combos: [], substitutes: [] };

        if (combos) {
            combos.innerHTML = (basket.combos || []).length
                ? basket.combos.map((combo) => {
                    const canCreate = Number(combo.a_id) > 0 && Number(combo.b_id) > 0;
                    return `
                    <div class="combo-card">
                        <div class="combo-card-header">
                            <strong>${escapeHtml(combo.a_name)} + ${escapeHtml(combo.b_name)}</strong>
                            ${canCreate ? `<button class="btn primary small" type="button" data-combo-create
                                data-a-id="${Number(combo.a_id)}" data-b-id="${Number(combo.b_id)}"
                                data-a-name="${escapeHtml(combo.a_name)}" data-b-name="${escapeHtml(combo.b_name)}">Crear combo</button>` : ''}
                        </div>
                        <span class="combo-equation">y = ${fmtNumber(combo.intercept, 2)} + ${fmtNumber(combo.slope, 2)} · x</span>
                        <div class="combo-meta">
                            <span>r = ${fmtNumber(combo.corr, 2)}</span>
                            <span>${fmtNumber(combo.cooccurrence, 0)} ventas conjuntas</span>
                        </div>
                    </div>
                `;
                }).join('')
                : '<div class="empty-state">Aún no se detectan combinaciones positivas.</div>';
        }

        if (substitutes) {
            substitutes.innerHTML = (basket.substitutes || []).length
                ? basket.substitutes.map((item) => `
                    <div class="combo-card">
                        <strong>${escapeHtml(item.a_name)} ↔ ${escapeHtml(item.b_name)}</strong>
                        <div class="combo-meta">
                            <span>r = ${fmtNumber(item.corr, 2)}</span>
                            <span>cov = ${fmtNumber(item.cov, 2)}</span>
                        </div>
                    </div>
                `).join('')
                : '<div class="empty-state">Sin sustitutos marcados en la canasta actual.</div>';
        }
    }

    const catalogState = {
        search: '',
        category: '',
        status: 'active',
        page: 1,
        pageSize: 8
    };

    function catalogRows() {
        const term = normalize(catalogState.search);
        const rows = (ERP.products || []).filter((product) => {
            const isCombo = Number(product.is_combo) === 1;
            if (catalogState.category && String(product.category_id) !== String(catalogState.category)) return false;
            if (term && !normalize(`${product.name} ${product.category}`).includes(term)) return false;
            if (catalogState.status === 'active' && Number(product.active) !== 1) return false;
            if (catalogState.status === 'inactive' && Number(product.active) === 1) return false;
            if (catalogState.status === 'low' && !(Number(product.stock) <= Number(product.min_threshold))) return false;
            if (catalogState.status === 'combos' && !isCombo) return false;
            return true;
        });
        rows.sort((a, b) => String(a.name).localeCompare(String(b.name), 'es'));
        return rows;
    }

    function renderCatalog() {
        const body = $('products-table-body');
        if (!body) return;
        const rows = catalogRows();
        const pages = Math.max(1, Math.ceil(rows.length / catalogState.pageSize));
        catalogState.page = Math.min(Math.max(1, catalogState.page), pages);
        const start = (catalogState.page - 1) * catalogState.pageSize;
        const visible = rows.slice(start, start + catalogState.pageSize);

        text('catalog-count', `${fmtNumber(rows.length, 0)} producto${rows.length === 1 ? '' : 's'}`);
        const empty = $('catalog-empty');
        if (empty) empty.hidden = rows.length > 0;
        const pagination = $('catalog-pagination');
        if (pagination && typeof pagination.setData === 'function') pagination.setData(catalogState.page, pages);

        if (!visible.length) {
            body.innerHTML = '';
            return;
        }
        body.innerHTML = visible.map((product) => {
            const isCombo = Number(product.is_combo) === 1;
            const inactive = Number(product.active) === 0;
            let badge = '<span class="badge badge-success">Activo</span>';
            if (inactive) badge = '<span class="badge badge-danger">Inactivo</span>';
            else if (Number(product.seasonal) === 1) badge = '<span class="badge badge-accent">Estacional</span>';
            const comboBadge = isCombo ? '<span class="badge badge-accent">Combo</span>' : '';
            return `
                <tr>
                    <td><a class="table-link" href="/inventario?product=${Number(product.id)}"
                           data-product-open="${Number(product.id)}">${escapeHtml(product.name)}</a> ${comboBadge}</td>
                    <td>${escapeHtml(product.category)}</td>
                    <td>${fmtNumber(product.stock)} u.</td>
                    <td>${fmtMoney(product.cost)}</td>
                    <td>${fmtMoney(product.price)}</td>
                    <td>${badge}</td>
                </tr>
            `;
        }).join('');
    }

    function initCatalog() {
        const search = $('catalog-search');
        const category = $('catalog-category');
        const status = $('catalog-state');
        const body = $('products-table-body');
        if (!body) return;

        if (category) {
            const seen = new Map();
            (ERP.products || []).forEach((product) => {
                const id = String(product.category_id || '');
                if (!id || seen.has(id)) return;
                seen.set(id, product.category || 'Sin categoría');
            });
            const options = Array.from(seen.entries())
                .sort((a, b) => String(a[1]).localeCompare(String(b[1]), 'es'))
                .map(([id, name]) => `<option value="${escapeHtml(id)}">${escapeHtml(name)}</option>`)
                .join('');
            category.insertAdjacentHTML('beforeend', options);
        }

        if (search) {
            search.addEventListener('input', () => {
                catalogState.search = search.value;
                catalogState.page = 1;
                renderCatalog();
            });
        }
        category?.addEventListener('change', () => {
            catalogState.category = category.value;
            catalogState.page = 1;
            renderCatalog();
        });
        status?.addEventListener('change', () => {
            catalogState.status = status.value;
            catalogState.page = 1;
            renderCatalog();
        });
        $('catalog-pagination')?.addEventListener('page-change', (event) => {
            catalogState.page = event.detail.page;
            renderCatalog();
        });
        body.addEventListener('click', (event) => {
            const link = event.target.closest('[data-product-open]');
            if (!link) return;
            const detail = document.querySelector('erp-product-detail');
            if (!detail || typeof detail.open !== 'function') return;
            event.preventDefault();
            detail.open(link.dataset.productOpen);
        });
    }

    function initComboActions() {
        const list = $('combos-list');
        if (!list) return;
        list.addEventListener('click', (event) => {
            const button = event.target.closest('[data-combo-create]');
            if (!button) return;
            const builder = document.querySelector('erp-combo-builder');
            if (!builder || typeof builder.open !== 'function') {
                toast('Creador no disponible', 'No se pudo abrir el creador de combos.', 'error');
                return;
            }
            builder.open({
                products: [
                    { id: Number(button.dataset.aId), name: button.dataset.aName, quantity: 1 },
                    { id: Number(button.dataset.bId), name: button.dataset.bName, quantity: 1 }
                ]
            });
        });
        document.addEventListener('erp:combo-created', async () => {
            try {
                ERP.products = await ErpUI.api('/api/products');
                renderCatalog();
            } catch (error) {}
        });
    }

    function renderContacts(searchTerm = '') {
        const suppliersContainer = $('suppliers-list');
        const customersContainer = $('customers-list');
        if (!suppliersContainer || !customersContainer) return;

        const term = normalize(searchTerm);
        const suppliers = (ERP.suppliers || []).filter((supplier) => {
            const haystack = normalize([supplier.name, supplier.contact, supplier.phone, supplier.email, supplier.address].join(' '));
            return haystack.includes(term);
        });
        const customers = (ERP.customers || []).filter((customer) => {
            const haystack = normalize([customer.name, customer.phone, customer.email, customer.type].join(' '));
            return haystack.includes(term);
        });

        text('supplier-count', fmtNumber(suppliers.length, 0));
        text('customer-count', fmtNumber(customers.length, 0));

        suppliersContainer.innerHTML = suppliers.length
            ? suppliers.map((supplier) => `
                <div class="contact-card">
                    <header>
                        <strong>${escapeHtml(supplier.name)}</strong>
                        <span class="badge badge-soft">${fmtNumber(supplier.inputs, 0)} insumos</span>
                    </header>
                    <div class="contact-meta">
                        <span>${escapeHtml(supplier.contact || 'Sin contacto')}</span>
                        <span>${escapeHtml(supplier.phone || 'Sin teléfono')}</span>
                        <span>${escapeHtml(supplier.email || 'Sin email')}</span>
                        <span>${escapeHtml(supplier.address || 'Sin dirección')}</span>
                    </div>
                </div>
            `).join('')
            : '<div class="empty-state">No se encontraron proveedores.</div>';

        customersContainer.innerHTML = customers.length
            ? customers.map((customer) => `
                <div class="contact-card">
                    <header>
                        <strong>${escapeHtml(customer.name)}</strong>
                        <span class="badge ${customer.type === 'Mayorista' ? 'badge-accent' : 'badge-soft'}">${escapeHtml(customer.type)}</span>
                    </header>
                    <div class="contact-meta">
                        <span>${escapeHtml(customer.phone || 'Sin teléfono')}</span>
                        <span>${escapeHtml(customer.email || 'Sin email')}</span>
                        <span>${fmtNumber(customer.purchases, 0)} compras</span>
                        <span>${fmtMoney(customer.total)} acumulados</span>
                    </div>
                </div>
            `).join('')
            : '<div class="empty-state">No se encontraron clientes.</div>';
    }

    let activeTab = 'resumen';
    const chartRenderers = {
        resumen: () => {
            drawBarChart($('daily-chart'), ERP.daily || {});
            drawGauge($('binomial-gauge'), (ERP.binomial || {}).probability);
        },
        stock: () => drawCostChart($('cost-ci-chart'), ERP.cost_ci || {}),
        catalogo: () => drawCategoryPie($('category-pie'), ERP.categories || {})
    };

    function renderTabCharts(tab) {
        if (!ERP) return;
        const renderer = chartRenderers[tab];
        if (renderer) {
            window.requestAnimationFrame(() => {
                try {
                    renderer();
                } catch (error) {
                    console.error('Error dibujando gráficos', error);
                }
            });
        }
    }

    function setTab(tab, updateHash = true) {
        const panels = document.querySelectorAll('[data-tab-panel]');
        const buttons = document.querySelectorAll('[data-tab-button]');
        let found = false;
        panels.forEach((panel) => {
            const match = panel.dataset.tabPanel === tab;
            panel.classList.toggle('active', match);
            if (match) found = true;
        });
        if (!found) return;

        buttons.forEach((button) => {
            button.classList.toggle('active', button.dataset.tabButton === tab);
        });
        activeTab = tab;
        if (updateHash) {
            const hash = tab === 'resumen' ? '' : `#${tab}`;
            history.replaceState(null, '', `${location.pathname}${location.search}${hash}`);
        }
        renderTabCharts(tab);
        $('sidebar')?.classList.remove('open');
    }

    function initTabs() {
        const panels = document.querySelectorAll('[data-tab-panel]');
        if (!panels.length) return;

        document.querySelectorAll('[data-tab-button]').forEach((button) => {
            button.addEventListener('click', () => setTab(button.dataset.tabButton));
        });

        const initial = document.body.dataset.activeTab || 'resumen';
        const hash = location.hash.replace('#', '');
        const allowed = ['resumen', 'stock', 'catalogo', 'agenda'];
        setTab(allowed.includes(hash) ? hash : initial, false);

        window.addEventListener('hashchange', () => {
            const next = location.hash.replace('#', '');
            if (allowed.includes(next)) setTab(next, false);
        });
    }

    function toast(title, message, type = 'success') {
        const stack = $('toast-stack');
        if (!stack) return;
        const element = document.createElement('div');
        element.className = 'toast' + (type === 'error' ? ' error' : '');
        element.innerHTML = `<strong>${escapeHtml(title)}</strong>${escapeHtml(message)}`;
        stack.appendChild(element);
        window.setTimeout(() => {
            element.style.opacity = '0';
            element.style.transform = 'translateX(12px)';
            element.style.transition = 'opacity 0.2s ease, transform 0.2s ease';
            window.setTimeout(() => element.remove(), 220);
        }, 4200);
    }

    function saleItemRow(productId) {
        const row = document.createElement('div');
        row.className = 'sale-item-row';

        const options = (ERP.products || []).filter((product) =>
            Number(product.active) === 1 && Number(product.stock) > 0).map((product) => {
            const selected = String(product.id) === String(productId) ? ' selected' : '';
            return `<option value="${product.id}" data-price="${Number(product.price) || 0}" data-stock="${Number(product.stock) || 0}"${selected}>${escapeHtml(product.name)} · ${fmtMoney(product.price)} · ${fmtNumber(product.stock)} u.</option>`;
        }).join('');

        row.innerHTML = `
            <label class="field">
                <span>Producto</span>
                <select class="sale-product">${options}</select>
            </label>
            <label class="field">
                <span>Cantidad</span>
                <input type="number" class="sale-quantity" min="1" step="1" value="1">
            </label>
            <span class="line-total">$0.00</span>
            <button type="button" class="icon-button remove-item" aria-label="Quitar ítem">×</button>
        `;

        const select = row.querySelector('.sale-product');
        const quantity = row.querySelector('.sale-quantity');
        const lineTotal = row.querySelector('.line-total');
        const remove = row.querySelector('.remove-item');

        const update = () => {
            const option = select.selectedOptions[0];
            const price = Number(option?.dataset.price) || 0;
            const stock = Number(option?.dataset.stock) || 1;
            let value = Number(quantity.value) || 0;
            if (value > stock) {
                value = stock;
                quantity.value = String(stock);
            }
            const priceCents = window.ErpBilling?.Money.toCents(price) || 0;
            lineTotal.textContent = window.ErpBilling
                ? window.ErpBilling.Money.formatCents(priceCents * value)
                : fmtMoney(price * value);
            updateSaleTotal();
        };

        select.addEventListener('change', update);
        quantity.addEventListener('input', update);
        remove.addEventListener('click', () => {
            const container = $('sale-items');
            if (container && container.children.length > 1) {
                row.remove();
            } else {
                toast('Venta incompleta', 'La venta debe conservar al menos un ítem.', 'error');
            }
            updateSaleTotal();
        });

        update();
        return row;
    }

    function saleTotals() {
        const billing = window.ErpBilling;
        const subtotalCents = Array.from(document.querySelectorAll('#sale-items .sale-item-row')).reduce((sum, row) => {
            const select = row.querySelector('.sale-product');
            const quantity = row.querySelector('.sale-quantity');
            const option = select?.selectedOptions[0];
            const priceCents = billing.Money.toCents(option?.dataset.price) || 0;
            return sum + priceCents * (Number(quantity?.value) || 0);
        }, 0);
        const type = $('sale-discount-type')?.value || 'none';
        const rawValue = $('sale-discount-value')?.value || '0';
        const result = billing.apply(type, subtotalCents, rawValue);
        return { billing, subtotalCents, type, rawValue, result };
    }

    function syncDiscountFields() {
        const type = $('sale-discount-type')?.value || 'none';
        const field = $('sale-discount-value-field');
        const input = $('sale-discount-value');
        const strategy = window.ErpBilling?.strategies?.[type];
        if (field) field.hidden = type === 'none';
        if (input) {
            input.disabled = type === 'none';
            if (type === 'none') input.value = '0';
        }
        const label = $('sale-discount-value-label');
        if (label) label.textContent = strategy?.valueLabel || 'Valor del descuento';
        updateSaleTotal();
    }

    function updateSaleTotal() {
        const billing = window.ErpBilling;
        if (!billing) return;
        const { subtotalCents, type, result } = saleTotals();
        const discountRow = $('sale-discount-row');
        const discountLabel = $('sale-discount-label');
        text('sale-subtotal', billing.Money.formatCents(subtotalCents));
        if (discountRow) discountRow.hidden = type === 'none';
        if (discountLabel && type === 'percent') {
            discountLabel.textContent = 'Descuento porcentual';
        } else if (discountLabel) {
            discountLabel.textContent = 'Descuento';
        }
        text('sale-discount', result ? `-${billing.Money.formatCents(result.discountCents)}` : '—');
        text('sale-total', result ? billing.Money.formatCents(result.totalCents) : '—');
    }

    function addSaleItem(defaultId) {
        const container = $('sale-items');
        if (!container) return;
        const firstAvailable = (ERP.products || []).find((product) =>
            Number(product.active) === 1 && Number(product.stock) > 0);
        if (!firstAvailable) {
            toast('Sin stock', 'No hay productos disponibles para vender.', 'error');
            return;
        }
        container.appendChild(saleItemRow(defaultId || firstAvailable.id));
        updateSaleTotal();
    }

    function openSaleModal() {
        if (!ERP) return;
        const modal = $('sale-modal');
        const customerSelect = $('sale-customer');
        const items = $('sale-items');
        const error = $('sale-error');
        if (!modal || !customerSelect || !items) return;

        customerSelect.innerHTML = '<option value="0">Consumidor final</option>' + (ERP.customers || []).map((customer) =>
            `<option value="${customer.id}">${escapeHtml(customer.name)} · ${escapeHtml(customer.type)}</option>`
        ).join('');

        items.innerHTML = '';
        error.hidden = true;
        error.textContent = '';
        if ($('sale-discount-type')) $('sale-discount-type').value = 'none';
        if ($('sale-discount-value')) $('sale-discount-value').value = '0';
        syncDiscountFields();
        modal.hidden = false;
        addSaleItem();
        customerSelect.focus();
    }

    function closeSaleModal() {
        const modal = $('sale-modal');
        if (modal) modal.hidden = true;
    }

    async function submitSale() {
        const button = $('submit-sale');
        const error = $('sale-error');
        const customerId = Number($('sale-customer')?.value) || 0;
        const payment = $('sale-payment')?.value || 'Efectivo';
        const rows = Array.from(document.querySelectorAll('#sale-items .sale-item-row'));

        const items = rows.map((row) => ({
            product_id: Number(row.querySelector('.sale-product')?.value) || 0,
            quantity: Number(row.querySelector('.sale-quantity')?.value) || 0
        })).filter((item) => item.product_id > 0 && item.quantity > 0);

        if (!items.length) {
            if (error) {
                error.textContent = 'Agregue al menos un producto con cantidad válida.';
                error.hidden = false;
            }
            return;
        }

        const totals = saleTotals();
        if (!totals.result) {
            if (error) {
                error.textContent = 'El descuento ingresado no es válido para el subtotal de la venta.';
                error.hidden = false;
            }
            return;
        }

        if (button) {
            button.disabled = true;
            button.textContent = 'Registrando…';
        }
        if (error) error.hidden = true;

        try {
            const response = await fetch('/api/sales', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    customer_id: customerId,
                    payment_method: payment,
                    discount_type: totals.type,
                    discount_value: totals.type === 'none' ? '0' : totals.rawValue,
                    items
                })
            });

            if (response.status === 401) {
                window.location.href = '/login';
                return;
            }

            const payload = await response.json().catch(() => ({}));
            if (!response.ok || !payload.ok) {
                throw new Error(payload.error || 'No se pudo registrar la venta.');
            }

            closeSaleModal();
            toast('Venta registrada', `Venta #${payload.sale_id} por ${fmtMoney(payload.total)}. Actualizando panel…`);
            window.setTimeout(() => window.location.reload(), 900);
        } catch (requestError) {
            if (error) {
                error.textContent = requestError.message;
                error.hidden = false;
            }
        } finally {
            if (button) {
                button.disabled = false;
                button.textContent = 'Registrar venta';
            }
        }
    }

    let voidSale = null;

    function openVoidModal(sale) {
        const modal = $('void-sale-modal');
        if (!modal || !sale) return;
        voidSale = sale;
        $('void-sale-summary').textContent = `Se anulará ${sale.order_type === 'direct' ? 'la venta' : 'el pedido'} #${sale.id} por ${fmtMoney(sale.total)}. El stock se restituirá automáticamente si estaba aplicado.`;
        $('void-sale-reason').value = '';
        $('void-sale-pin').value = '';
        const error = $('void-sale-error');
        error.hidden = true;
        error.textContent = '';
        modal.hidden = false;
        window.setTimeout(() => $('void-sale-reason')?.focus(), 60);
    }

    function closeVoidModal() {
        const modal = $('void-sale-modal');
        if (modal) modal.hidden = true;
        voidSale = null;
    }

    async function submitVoidSale() {
        if (!voidSale) return;
        const reason = ($('void-sale-reason')?.value || '').trim();
        const pin = $('void-sale-pin')?.value || '';
        const error = $('void-sale-error');
        const button = $('submit-void-sale');
        if (reason.length < 3 || reason.length > 300) {
            error.textContent = 'El motivo debe tener entre 3 y 300 caracteres.';
            error.hidden = false;
            return;
        }
        if (!pin) {
            error.textContent = 'Ingrese el PIN de autorización.';
            error.hidden = false;
            return;
        }
        button.disabled = true;
        button.textContent = 'Anulando…';
        error.hidden = true;
        try {
            const endpoint = voidSale.order_type === 'direct'
                ? `/api/sales/${voidSale.id}/cancel`
                : `/api/orders/${voidSale.id}/cancel`;
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ reason, pin })
            });
            if (response.status === 401) {
                window.location.href = '/login';
                return;
            }
            const payload = await response.json().catch(() => ({}));
            if (!response.ok || !payload.ok) {
                throw new Error(payload.error || 'No se pudo anular la operación.');
            }
            const cancelledId = voidSale.id;
            closeVoidModal();
            toast('Operación anulada', `El registro #${cancelledId} quedó anulado y auditado.`);
            window.setTimeout(() => window.location.reload(), 900);
        } catch (requestError) {
            error.textContent = requestError.message;
            error.hidden = false;
        } finally {
            button.disabled = false;
            button.textContent = 'Anular venta';
        }
    }

    function initVoidModal() {
        const modal = $('void-sale-modal');
        if (!modal) return;
        $('close-void-sale-modal')?.addEventListener('click', closeVoidModal);
        $('cancel-void-sale')?.addEventListener('click', closeVoidModal);
        $('submit-void-sale')?.addEventListener('click', submitVoidSale);
        modal.addEventListener('click', (event) => {
            if (event.target === modal) closeVoidModal();
        });
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && !modal.hidden) closeVoidModal();
        });
        document.addEventListener('click', (event) => {
            const button = event.target.closest('[data-void-sale]');
            if (!button) return;
            const sale = (ERP?.recent_sales || []).find((item) => Number(item.id) === Number(button.dataset.voidSale));
            if (sale) openVoidModal(sale);
        });
    }

    function initSaleModal() {
        const modal = $('sale-modal');
        if (!modal) return;

        $('open-sale-modal')?.addEventListener('click', openSaleModal);
        $('close-sale-modal')?.addEventListener('click', closeSaleModal);
        $('cancel-sale')?.addEventListener('click', closeSaleModal);
        $('add-sale-item')?.addEventListener('click', () => addSaleItem());
        $('submit-sale')?.addEventListener('click', submitSale);
        $('sale-discount-type')?.addEventListener('change', syncDiscountFields);
        $('sale-discount-value')?.addEventListener('input', updateSaleTotal);

        modal.addEventListener('click', (event) => {
            if (event.target === modal) closeSaleModal();
        });

        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && !modal.hidden) closeSaleModal();
        });
    }

    function syncError(message) {
        const error = $('sync-error');
        if (!error) return;
        error.textContent = message || '';
        error.hidden = !message;
    }

    function syncAppend(statusElement, tag, className, value) {
        const element = document.createElement(tag);
        if (className) element.className = className;
        element.textContent = value;
        statusElement.appendChild(element);
        return element;
    }

    function renderSyncStatus(status) {
        const box = $('sync-status');
        if (!box) return;
        box.replaceChildren();
        box.className = 'sync-status';

        if (!status || !status.configured) {
            syncAppend(box, 'strong', '', 'Sin configurar');
            syncAppend(box, 'span', 'sync-detail', 'Guardá la URL del endpoint PostgreSQL para habilitar la sincronización.');
            return;
        }

        syncAppend(box, 'strong', '', `Endpoint configurado${status.token_configured ? ' · token guardado' : ''}`);
        syncAppend(box, 'span', 'sync-detail', status.endpoint || '');

        if (status.last_at) {
            box.classList.add(status.last_status === 'ok' ? 'is-ok' : 'is-error');
            syncAppend(box, 'span', '', `Última sincronización: ${status.last_at} · ${status.last_status === 'ok' ? 'correcta' : 'con error'}`);
            if (status.last_message) syncAppend(box, 'span', 'sync-detail', status.last_message);
        } else {
            syncAppend(box, 'span', 'sync-detail', 'Todavía no se envió ningún snapshot desde este equipo.');
        }
    }

    async function syncFetchStatus() {
        const response = await fetch('/api/sync/status', { headers: { Accept: 'application/json' } });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(payload.error || 'No se pudo consultar el estado de sincronización.');
        renderSyncStatus(payload);
        return payload;
    }

    async function syncSaveConfiguration(showSuccess = true) {
        const urlInput = $('sync-url');
        const tokenInput = $('sync-token');
        if (!urlInput) return false;

        const url = urlInput.value.trim();
        if (!url) {
            syncError('Ingresá la URL del endpoint PostgreSQL.');
            return false;
        }

        const response = await fetch('/api/sync/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
            body: JSON.stringify({ url, token: tokenInput ? tokenInput.value.trim() : '' })
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(payload.error || 'No se pudo guardar la configuración.');

        if (tokenInput) tokenInput.value = '';
        syncError('');
        if (showSuccess) toast('Sincronización configurada', payload.message || 'La URL fue guardada. Actualizando estado…');
        await syncFetchStatus();
        return true;
    }

    function initSync() {
        const openButton = $('open-sync-modal');
        const modal = $('sync-modal');
        if (!openButton || !modal) return;

        const open = async () => {
            syncError('');
            modal.hidden = false;
            const statusBox = $('sync-status');
            if (statusBox) {
                statusBox.className = 'sync-status';
                statusBox.textContent = 'Consultando estado…';
            }
            try {
                const status = await syncFetchStatus();
                const urlInput = $('sync-url');
                if (urlInput && status.endpoint) urlInput.value = status.endpoint;
            } catch (error) {
                syncError(error.message);
            }
        };

        const close = () => {
            modal.hidden = true;
        };

        openButton.addEventListener('click', open);
        $('close-sync-modal')?.addEventListener('click', close);
        $('cancel-sync')?.addEventListener('click', close);
        modal.addEventListener('click', (event) => {
            if (event.target === modal) close();
        });
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && !modal.hidden) close();
        });

        $('save-sync-config')?.addEventListener('click', async (event) => {
            const button = event.currentTarget;
            button.disabled = true;
            try {
                await syncSaveConfiguration();
            } catch (error) {
                syncError(error.message);
                toast('No se pudo guardar', error.message, 'error');
            } finally {
                button.disabled = false;
            }
        });

        $('run-sync')?.addEventListener('click', async (event) => {
            const button = event.currentTarget;
            button.disabled = true;
            const label = button.textContent;
            button.textContent = 'Sincronizando…';
            syncError('');
            try {
                await syncSaveConfiguration(false);
                const response = await fetch('/api/sync/push', {
                    method: 'POST',
                    headers: { Accept: 'application/json' }
                });
                const payload = await response.json().catch(() => ({}));
                if (!response.ok) throw new Error(payload.error || 'No se pudo sincronizar.');
                toast('Sincronización completada', payload.message || 'El snapshot fue enviado a PostgreSQL.');
                await syncFetchStatus();
            } catch (error) {
                syncError(error.message);
                toast('Sincronización con error', error.message, 'error');
                try {
                    await syncFetchStatus();
                } catch (statusError) { /* conservar el error original */ }
            } finally {
                button.disabled = false;
                button.textContent = label;
            }
        });
    }

    function initTheme() {
        const button = $('theme-toggle');
        if (!button) return;
        button.addEventListener('click', () => {
            const current = document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
            const next = current === 'light' ? 'dark' : 'light';
            document.documentElement.dataset.theme = next;
            try {
                localStorage.setItem('erp-theme', next);
            } catch (error) { /* almacenamiento no disponible */ }
            if (ERP) {
                renderTabCharts(activeTab);
            }
        });
    }

    function initSidebar() {
        $('menu-toggle')?.addEventListener('click', () => {
            $('sidebar')?.classList.toggle('open');
        });
        document.querySelectorAll('.sidebar .nav-link').forEach((link) => {
            link.addEventListener('click', () => $('sidebar')?.classList.remove('open'));
        });
    }

    function initContacts() {
        const search = $('contact-search');
        if (!search) return;
        search.addEventListener('input', () => renderContacts(search.value));
    }

    function initRowLinks() {
        document.addEventListener('click', (event) => {
            const row = event.target.closest('[data-href]');
            if (!row || event.target.closest('a, button, input, select, textarea, label')) return;
            window.location.href = row.dataset.href;
        });
    }

    function initDashboard() {
        renderKpis();
        renderDailyStats();
        renderBinomial();
        renderRecentSales();
        renderJournal();
        renderAlerts();
        renderReorderProducts();
        renderReorderInputs();
        renderCostStats();
        renderHypothesis();
        renderMatrix();
        renderCombos();
        renderCatalog();
        renderLegend(ERP.categories || {});
        renderContacts();

        initTabs();
        initSaleModal();
        initVoidModal();
        initContacts();
        initRowLinks();
        initCatalog();
        initComboActions();

        let resizeTimer = null;
        window.addEventListener('resize', () => {
            window.clearTimeout(resizeTimer);
            resizeTimer = window.setTimeout(() => renderTabCharts(activeTab), 160);
        });

        document.addEventListener('erp:refresh', () => {
            renderTabCharts(activeTab);
        });
    }

    initTheme();
    initSidebar();
    initSync();

    if (ERP) {
        initDashboard();
    }
})();
