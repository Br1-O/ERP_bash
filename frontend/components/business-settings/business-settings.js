(() => {
    'use strict';

    class BusinessSettings extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._admin = false;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/business-settings/business-settings.html');
            this._admin = (this.getAttribute('role') || '').toLowerCase() === 'admin';
            this._form = this.querySelector('[data-business-form]');
            this._error = this.querySelector('[data-business-error]');
            this._submit = this.querySelector('[data-business-submit]');
            this._state = this.querySelector('[data-business-state]');
            this._form.addEventListener('submit', (event) => this._save(event));
            if (!this._admin) {
                this._form.querySelectorAll('input, button').forEach((input) => { input.disabled = true; });
                this._state.textContent = 'Solo lectura';
            }
            await this._load();
        }

        async _load() {
            try {
                const data = await ErpUI.api('/api/business-info');
                this.querySelector('[data-business-name]').value = data.name || '';
                this.querySelector('[data-business-instagram]').value = data.instagram || '';
                this.querySelector('[data-business-facebook]').value = data.facebook || '';
                this.querySelector('[data-business-phone]').value = data.phone || '';
                this.querySelector('[data-business-email]').value = data.email || '';
                this.querySelector('[data-business-website]').value = data.website || '';
                if (this._admin) this._state.textContent = 'Editable';
            } catch (error) {
                this._state.textContent = 'Error';
                this._error.textContent = error.message;
                this._error.hidden = false;
            }
        }

        async _save(event) {
            event.preventDefault();
            if (!this._admin) return;
            this._error.hidden = true;
            this._submit.disabled = true;
            try {
                await ErpUI.api('/api/business-info', {
                    method: 'PUT',
                    body: {
                        name: this.querySelector('[data-business-name]').value.trim(),
                        instagram: this.querySelector('[data-business-instagram]').value.trim(),
                        facebook: this.querySelector('[data-business-facebook]').value.trim(),
                        phone: this.querySelector('[data-business-phone]').value.trim(),
                        email: this.querySelector('[data-business-email]').value.trim(),
                        website: this.querySelector('[data-business-website]').value.trim()
                    }
                });
                ErpUI.toast('Configuración guardada', 'Los datos del negocio se actualizaron.');
                this._state.textContent = 'Guardado';
            } catch (error) {
                this._error.textContent = error.message;
                this._error.hidden = false;
            } finally {
                this._submit.disabled = false;
            }
        }
    }

    customElements.define('erp-business-settings', BusinessSettings);
})();
