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

    function renderRecentSales() {
        const body = $('recent-sales-body');
        if (!body) return;
        const sales = ERP.recent_sales || [];
        if (!sales.length) {
            body.innerHTML = '<tr><td colspan="5"><div class="empty-state">Sin ventas registradas.</div></td></tr>';
            return;
        }
        body.innerHTML = sales.map((sale) => `
            <tr>
                <td class="mono">#${escapeHtml(sale.id)}</td>
                <td>${escapeHtml(sale.customer)}</td>
                <td><span class="badge badge-soft">${escapeHtml(sale.payment)}</span></td>
                <td>${fmtNumber(sale.units, 0)}</td>
                <td class="text-right positive">${fmtMoney(sale.total)}</td>
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
                    <div class="alert-row">
                        <span class="alert-icon">!</span>
                        <div>
                            <strong>${escapeHtml(item.name)}</strong>
                            <small>Umbral ${fmtNumber(item.threshold)} ${escapeHtml(item.unit)} · déficit ${fmtNumber(item.deficit)} ${escapeHtml(item.unit)}</small>
                        </div>
                        <span class="alert-value">${fmtNumber(item.stock)} ${escapeHtml(item.unit)}</span>
                    </div>
                `).join('');
            }
        }

        if (productContainer) {
            if (!alerts.products.length) {
                productContainer.innerHTML = '<div class="empty-state"><strong>Producción al día</strong><span>Ningún producto requiere lote urgente.</span></div>';
            } else {
                productContainer.innerHTML = alerts.products.map((item) => `
                    <div class="alert-row">
                        <span class="alert-icon">↺</span>
                        <div>
                            <strong>${escapeHtml(item.name)}</strong>
                            <small>Mínimo de producción ${fmtNumber(item.threshold)} u. · faltan ${fmtNumber(item.deficit)} u.</small>
                        </div>
                        <span class="alert-value">${fmtNumber(item.stock)} u.</span>
                    </div>
                `).join('');
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
        body.innerHTML = rows.map((item) => `
            <tr>
                <td>${escapeHtml(item.name)}</td>
                <td>${fmtNumber(item.stock)}</td>
                <td>${fmtNumber(item.mean, 3)}</td>
                <td>${fmtNumber(item.sd, 3)}</td>
                <td>${fmtPct(item.cv, 1)}</td>
                <td>${fmtNumber(item.safety, 2)}</td>
                <td>${fmtNumber(item.reorder, 2)}</td>
                <td><span class="badge ${item.critical ? 'badge-danger' : 'badge-success'}">${item.critical ? 'Reponer' : 'Cubierto'}</span></td>
            </tr>
        `).join('');
    }

    function renderReorderInputs() {
        const body = $('reorder-inputs-body');
        if (!body) return;
        const rows = ERP.reorder_inputs || [];
        if (!rows.length) {
            body.innerHTML = '<tr><td colspan="6"><div class="empty-state">Sin datos de consumo.</div></td></tr>';
            return;
        }
        body.innerHTML = rows.map((item) => `
            <tr>
                <td>${escapeHtml(item.name)}</td>
                <td>${fmtNumber(item.stock)} ${escapeHtml(item.unit)}</td>
                <td>${fmtNumber(item.mean, 3)}</td>
                <td>${fmtPct(item.cv, 1)}</td>
                <td><span class="badge badge-soft">${fmtNumber(item.reorder, 2)}</span></td>
                <td><span class="badge ${item.critical ? 'badge-danger' : 'badge-success'}">${item.critical ? 'Reponer' : 'Cubierto'}</span></td>
            </tr>
        `).join('');
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
                ? basket.combos.map((combo) => `
                    <div class="combo-card">
                        <strong>${escapeHtml(combo.a_name)} + ${escapeHtml(combo.b_name)}</strong>
                        <span class="combo-equation">y = ${fmtNumber(combo.intercept, 2)} + ${fmtNumber(combo.slope, 2)} · x</span>
                        <div class="combo-meta">
                            <span>r = ${fmtNumber(combo.corr, 2)}</span>
                            <span>${fmtNumber(combo.cooccurrence, 0)} ventas conjuntas</span>
                        </div>
                    </div>
                `).join('')
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

    function renderCatalog() {
        const body = $('products-table-body');
        if (!body) return;
        const products = ERP.products || [];
        text('catalog-count', `${fmtNumber(products.length, 0)} productos`);
        if (!products.length) {
            body.innerHTML = '<tr><td colspan="6"><div class="empty-state">Sin productos en el catálogo.</div></td></tr>';
            return;
        }
        body.innerHTML = products.map((product) => {
            const badge = Number(product.seasonal) === 1
                ? '<span class="badge badge-accent">Estacional</span>'
                : '<span class="badge badge-success">Activo</span>';
            return `
                <tr>
                    <td>${escapeHtml(product.name)}</td>
                    <td>${escapeHtml(product.category)}</td>
                    <td>${fmtNumber(product.stock)} u.</td>
                    <td>${fmtMoney(product.cost)}</td>
                    <td>${fmtMoney(product.price)}</td>
                    <td>${badge}</td>
                </tr>
            `;
        }).join('');
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

        const options = (ERP.products || []).filter((product) => Number(product.stock) > 0).map((product) => {
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
            lineTotal.textContent = fmtMoney(price * value);
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

    function updateSaleTotal() {
        const total = Array.from(document.querySelectorAll('#sale-items .sale-item-row')).reduce((sum, row) => {
            const select = row.querySelector('.sale-product');
            const quantity = row.querySelector('.sale-quantity');
            const option = select?.selectedOptions[0];
            const price = Number(option?.dataset.price) || 0;
            return sum + price * (Number(quantity?.value) || 0);
        }, 0);
        text('sale-total', fmtMoney(total));
    }

    function addSaleItem(defaultId) {
        const container = $('sale-items');
        if (!container) return;
        const firstAvailable = (ERP.products || []).find((product) => Number(product.stock) > 0);
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

        if (button) {
            button.disabled = true;
            button.textContent = 'Registrando…';
        }
        if (error) error.hidden = true;

        try {
            const response = await fetch('/api/sales', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ customer_id: customerId, payment_method: payment, items })
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

    function initSaleModal() {
        const modal = $('sale-modal');
        if (!modal) return;

        $('open-sale-modal')?.addEventListener('click', openSaleModal);
        $('close-sale-modal')?.addEventListener('click', closeSaleModal);
        $('cancel-sale')?.addEventListener('click', closeSaleModal);
        $('add-sale-item')?.addEventListener('click', () => addSaleItem());
        $('submit-sale')?.addEventListener('click', submitSale);

        modal.addEventListener('click', (event) => {
            if (event.target === modal) closeSaleModal();
        });

        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && !modal.hidden) closeSaleModal();
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
        initContacts();
        initSidebar();

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

    if (ERP) {
        initDashboard();
    }
})();
