(() => {
    'use strict';

    class ErpPagination extends HTMLElement {
        constructor() {
            super();
            this._page = 1;
            this._pages = 1;
            this._ready = this._load();
        }

        async _load() {
            this.innerHTML = await ErpUI.fetchText('/components/erp-pagination/erp-pagination.html');
            this._status = this.querySelector('[data-page-status]');
            this._prev = this.querySelector('[data-page-prev]');
            this._next = this.querySelector('[data-page-next]');
            this._prev.addEventListener('click', () => this._go(this._page - 1));
            this._next.addEventListener('click', () => this._go(this._page + 1));
            this._render();
        }

        setData(page, pages) {
            this._page = Math.max(1, Number(page) || 1);
            this._pages = Math.max(1, Number(pages) || 1);
            this._render();
        }

        _render() {
            if (!this._status) return;
            this._status.textContent = `Página ${this._page} de ${this._pages}`;
            this._prev.disabled = this._page <= 1;
            this._next.disabled = this._page >= this._pages;
        }

        _go(page) {
            if (page < 1 || page > this._pages || page === this._page) return;
            this.dispatchEvent(new CustomEvent('page-change', {
                bubbles: true,
                detail: { page }
            }));
        }
    }

    customElements.define('erp-pagination', ErpPagination);
})();
