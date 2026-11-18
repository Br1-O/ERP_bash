(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const number = ErpUI.formatNumber;
    const PAGE_SIZE = 6;

    const state = {
        basket: null,
        matrixTerm: '',
        matrixSort: 'volume',
        comboTerm: '',
        comboSort: 'corr_desc',
        comboPage: 1,
        substituteTerm: '',
        substituteSort: 'corr_asc',
        substitutePage: 1
    };

    const $ = (id) => document.getElementById(id);

    function normalize(value) {
        return String(value ?? '')
            .toLowerCase()
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '');
    }

    function pageItems(items, page, size = PAGE_SIZE) {
        const pages = Math.max(1, Math.ceil(items.length / size));
        const current = Math.min(Math.max(1, Number(page) || 1), pages);
        return {
            items: items.slice((current - 1) * size, current * size),
            page: current,
            pages
        };
    }

    function updatePagination(element, page, pages) {
        if (element && typeof element.setData === 'function') element.setData(page, pages);
    }

    function sortedMatrixProducts() {
        const products = (state.basket?.products || []).slice();
        const term = normalize(state.matrixTerm);
        const filtered = term
            ? products.filter((product) => normalize(product.name).includes(term))
            : products;
        if (state.matrixSort === 'name') {
            filtered.sort((a, b) => String(a.name).localeCompare(String(b.name), 'es'));
        } else if (state.matrixSort === 'name_desc') {
            filtered.sort((a, b) => String(b.name).localeCompare(String(a.name), 'es'));
        } else {
            filtered.sort((a, b) => (Number(b.units) || 0) - (Number(a.units) || 0));
        }
        return filtered;
    }

    function renderMatrix() {
        const container = $('insights-matrix');
        const empty = $('insights-matrix-empty');
        if (!container) return;
        const basket = state.basket || { products: [], matrix: [], sales_count: 0 };
        const original = basket.products || [];
        const matrix = basket.matrix || [];
        const products = sortedMatrixProducts();
        const count = $('insights-matrix-count');
        if (count) count.textContent = `${products.length} producto${products.length === 1 ? '' : 's'}`;
        const sales = $('insights-sales-count');
        if (sales) sales.textContent = `${number(basket.sales_count, 0)} ventas`;

        if (products.length < 2) {
            container.innerHTML = '';
            container.style.gridTemplateColumns = '1fr';
            if (empty) empty.hidden = false;
            return;
        }
        if (empty) empty.hidden = true;

        const sourceIndex = new Map(original.map((product, index) => [Number(product.id), index]));
        container.style.gridTemplateColumns = `minmax(145px, 1.6fr) repeat(${products.length}, minmax(60px, 1fr))`;
        container.innerHTML = '';

        const corner = document.createElement('div');
        corner.className = 'matrix-cell header sticky-corner';
        corner.textContent = 'Producto';
        container.appendChild(corner);

        products.forEach((product) => {
            const cell = document.createElement('div');
            cell.className = 'matrix-cell header sticky-top';
            cell.title = product.name;
            cell.textContent = product.name.split(' ').slice(0, 2).join(' ');
            container.appendChild(cell);
        });

        products.forEach((rowProduct) => {
            const rowIndex = sourceIndex.get(Number(rowProduct.id));
            const header = document.createElement('div');
            header.className = 'matrix-cell header sticky-left';
            header.title = rowProduct.name;
            header.textContent = rowProduct.name.split(' ').slice(0, 2).join(' ');
            container.appendChild(header);

            products.forEach((columnProduct) => {
                const columnIndex = sourceIndex.get(Number(columnProduct.id));
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

    function comboRows() {
        const term = normalize(state.comboTerm);
        const rows = (state.basket?.combos || []).filter((combo) => {
            if (!term) return true;
            return normalize(`${combo.a_name} ${combo.b_name}`).includes(term);
        });
        const sort = state.comboSort;
        rows.sort((a, b) => {
            if (sort === 'corr_asc') return Number(a.corr) - Number(b.corr);
            if (sort === 'cooc_desc') return Number(b.cooccurrence) - Number(a.cooccurrence);
            if (sort === 'cooc_asc') return Number(a.cooccurrence) - Number(b.cooccurrence);
            if (sort === 'name') return String(a.a_name).localeCompare(String(b.a_name), 'es');
            return Number(b.corr) - Number(a.corr);
        });
        return rows;
    }

    function substituteRows() {
        const term = normalize(state.substituteTerm);
        const rows = (state.basket?.substitutes || []).filter((item) => {
            if (!term) return true;
            return normalize(`${item.a_name} ${item.b_name}`).includes(term);
        });
        const sort = state.substituteSort;
        rows.sort((a, b) => {
            if (sort === 'corr_desc') return Number(b.corr) - Number(a.corr);
            if (sort === 'cov_asc') return Number(a.cov) - Number(b.cov);
            if (sort === 'cov_desc') return Number(b.cov) - Number(a.cov);
            if (sort === 'name') return String(a.a_name).localeCompare(String(b.a_name), 'es');
            return Number(a.corr) - Number(b.corr);
        });
        return rows;
    }

    function comboCard(combo) {
        return `
            <div class="combo-card">
                <div class="combo-card-header">
                    <strong>${escape(combo.a_name)} + ${escape(combo.b_name)}</strong>
                    <button class="btn primary small" type="button" data-combo-create
                            data-a-id="${Number(combo.a_id)}" data-b-id="${Number(combo.b_id)}"
                            data-a-name="${escape(combo.a_name)}" data-b-name="${escape(combo.b_name)}">Crear combo</button>
                </div>
                <span class="combo-equation">y = ${number(combo.intercept, 2)} + ${number(combo.slope, 2)} · x</span>
                <div class="combo-meta">
                    <span>r = ${number(combo.corr, 2)}</span>
                    <span>${number(combo.cooccurrence, 0)} ventas conjuntas</span>
                </div>
            </div>`;
    }

    function renderCombos() {
        const container = $('insights-combos');
        const empty = $('insights-combos-empty');
        if (!container) return;
        const rows = comboRows();
        const paged = pageItems(rows, state.comboPage);
        state.comboPage = paged.page;
        const count = $('insights-combos-count');
        if (count) count.textContent = `${rows.length} combo${rows.length === 1 ? '' : 's'}`;
        if (empty) empty.hidden = rows.length > 0;
        container.innerHTML = paged.items.map(comboCard).join('');
        updatePagination($('insights-combos-pagination'), paged.page, paged.pages);
    }

    function substituteCard(item) {
        return `
            <div class="combo-card">
                <strong>${escape(item.a_name)} ↔ ${escape(item.b_name)}</strong>
                <div class="combo-meta">
                    <span>r = ${number(item.corr, 2)}</span>
                    <span>cov = ${number(item.cov, 2)}</span>
                </div>
            </div>`;
    }

    function renderSubstitutes() {
        const container = $('insights-substitutes');
        const empty = $('insights-substitutes-empty');
        if (!container) return;
        const rows = substituteRows();
        const paged = pageItems(rows, state.substitutePage);
        state.substitutePage = paged.page;
        const count = $('insights-substitutes-count');
        if (count) count.textContent = `${rows.length} par${rows.length === 1 ? '' : 'es'}`;
        if (empty) empty.hidden = rows.length > 0;
        container.innerHTML = paged.items.map(substituteCard).join('');
        updatePagination($('insights-substitutes-pagination'), paged.page, paged.pages);
    }

    function openCombo(button) {
        const builder = document.querySelector('erp-combo-builder');
        if (!builder) {
            ErpUI.toast('Creador no disponible', 'No se pudo abrir el creador de combos.', 'error');
            return;
        }
        builder.open({
            products: [
                { id: Number(button.dataset.aId), name: button.dataset.aName, quantity: 1 },
                { id: Number(button.dataset.bId), name: button.dataset.bName, quantity: 1 }
            ]
        });
    }

    function bind() {
        const matrixSearch = $('insights-matrix-search');
        const combosSearch = $('insights-combos-search');
        const substitutesSearch = $('insights-substitutes-search');
        if (matrixSearch) {
            ErpUI.debounceInput(matrixSearch, () => {
                state.matrixTerm = matrixSearch.value;
                renderMatrix();
            });
        }
        if (combosSearch) {
            ErpUI.debounceInput(combosSearch, () => {
                state.comboTerm = combosSearch.value;
                state.comboPage = 1;
                renderCombos();
            });
        }
        if (substitutesSearch) {
            ErpUI.debounceInput(substitutesSearch, () => {
                state.substituteTerm = substitutesSearch.value;
                state.substitutePage = 1;
                renderSubstitutes();
            });
        }

        $('insights-matrix-sort')?.addEventListener('change', (event) => {
            state.matrixSort = event.target.value;
            renderMatrix();
        });
        $('insights-combos-sort')?.addEventListener('change', (event) => {
            state.comboSort = event.target.value;
            state.comboPage = 1;
            renderCombos();
        });
        $('insights-substitutes-sort')?.addEventListener('change', (event) => {
            state.substituteSort = event.target.value;
            state.substitutePage = 1;
            renderSubstitutes();
        });
        $('insights-combos-pagination')?.addEventListener('page-change', (event) => {
            state.comboPage = event.detail.page;
            renderCombos();
        });
        $('insights-substitutes-pagination')?.addEventListener('page-change', (event) => {
            state.substitutePage = event.detail.page;
            renderSubstitutes();
        });
        $('insights-combos')?.addEventListener('click', (event) => {
            const button = event.target.closest('[data-combo-create]');
            if (button) openCombo(button);
        });
    }

    async function load() {
        try {
            state.basket = await ErpUI.api('/api/analytics/basket');
            renderMatrix();
            renderCombos();
            renderSubstitutes();
        } catch (error) {
            const empty = $('insights-matrix-empty');
            if (empty) {
                empty.hidden = false;
                empty.querySelector('strong').textContent = 'No se pudo cargar el análisis';
                empty.querySelector('span').textContent = error.message;
            }
        }
    }

    bind();
    load();
})();
