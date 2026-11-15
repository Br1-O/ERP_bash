(() => {
    'use strict';

    class ErpModal extends HTMLElement {
        constructor() {
            super();
            this._ready = this._load();
        }

        async _load() {
            const children = Array.from(this.children);
            this.innerHTML = await ErpUI.fetchText('/components/erp-modal/erp-modal.html');
            this._backdrop = this.querySelector('[data-modal-backdrop]');
            this._card = this.querySelector('.erp-modal-card');
            this._title = this.querySelector('[data-modal-title]');
            this._body = this.querySelector('[data-modal-body]');
            this._footer = this.querySelector('[data-modal-footer]');

            const footerContent = children.filter((child) => child.hasAttribute('data-modal-footer'));
            const bodyContent = children.filter((child) => !child.hasAttribute('data-modal-footer'));
            if (footerContent.length) {
                this._footer.innerHTML = '';
                footerContent.forEach((child) => this._footer.append(child));
            }
            bodyContent.forEach((child) => this._body.append(child));

            const title = this.getAttribute('title');
            if (title) this.setTitle(title);
            if (this.getAttribute('size') === 'wide') this._card.classList.add('modal-wide');
            if (this.hasAttribute('hide-footer')) this._footer.hidden = true;

            this.querySelectorAll('[data-modal-close]').forEach((button) => {
                button.addEventListener('click', () => this.close());
            });
            this._backdrop.addEventListener('click', (event) => {
                if (event.target === this._backdrop) this.close();
            });
            document.addEventListener('keydown', (event) => {
                if (event.key === 'Escape' && this._backdrop && !this._backdrop.hidden) this.close();
            });
        }

        async ready() {
            await this._ready;
            return this;
        }

        setTitle(value) {
            if (this._title) this._title.textContent = value;
        }

        setBody(html) {
            if (this._body) this._body.innerHTML = html;
        }

        setFooter(html) {
            if (!this._footer) return;
            this._footer.hidden = !html;
            if (html) this._footer.innerHTML = html;
        }

        async open() {
            await this._ready;
            if (!this._backdrop) return;
            this._backdrop.hidden = false;
            document.body.classList.add('erp-modal-open');
            const focusable = this._body?.querySelector('input, select, textarea, button');
            if (focusable) window.setTimeout(() => focusable.focus(), 60);
        }

        close() {
            if (!this._backdrop) return;
            this._backdrop.hidden = true;
            document.body.classList.remove('erp-modal-open');
            this.dispatchEvent(new CustomEvent('modal-close', { bubbles: true }));
        }

        get isOpen() {
            return Boolean(this._backdrop && !this._backdrop.hidden);
        }
    }

    customElements.define('erp-modal', ErpModal);
})();
