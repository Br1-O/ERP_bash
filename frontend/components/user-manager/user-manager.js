(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;

    class UserManager extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._users = [];
            this._editing = '';
            this._pinUser = '';
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/user-manager/user-manager.html');
            this._body = this.querySelector('[data-user-body]');
            this._empty = this.querySelector('[data-user-empty]');
            this._count = this.querySelector('[data-user-count]');
            this._formModal = this.querySelector('#user-form-modal');
            this._pinModal = this.querySelector('#user-pin-modal');
            this._form = this.querySelector('[data-user-form]');
            this._formError = this.querySelector('[data-user-error]');
            this._username = this.querySelector('[data-user-username]');
            this._password = this.querySelector('[data-user-password]');
            this._passwordField = this.querySelector('[data-user-password-field]');
            this._role = this.querySelector('[data-user-role]');
            this._active = this.querySelector('[data-user-active]');
            this._activeField = this.querySelector('[data-user-active-field]');
            this._metrics = this.querySelector('[data-user-metrics]');
            this._stock = this.querySelector('[data-user-stock]');
            this._pin = this.querySelector('[data-user-pin]');
            this._pinField = this.querySelector('[data-user-pin-field]');
            this._pinHelp = this.querySelector('[data-user-pin-help]');
            this._submit = this.querySelector('[data-user-submit]');
            this._pinForm = this.querySelector('[data-user-pin-form]');
            this._pinNew = this.querySelector('[data-user-pin-new]');
            this._pinError = this.querySelector('[data-user-pin-error]');
            this._pinSummary = this.querySelector('[data-user-pin-summary]');
            this._pinSubmit = this.querySelector('[data-user-pin-submit]');

            this.querySelector('[data-create-user]').addEventListener('click', () => this._openForm());
            this.querySelector('[data-user-cancel]').addEventListener('click', () => this._formModal.close());
            this.querySelector('[data-user-pin-cancel]').addEventListener('click', () => this._pinModal.close());
            this._role.addEventListener('change', () => this._syncRole());
            this._form.addEventListener('submit', (event) => this._save(event));
            this._pinForm.addEventListener('submit', (event) => this._savePin(event));
            this._body.addEventListener('click', (event) => {
                const edit = event.target.closest('[data-edit-user]');
                if (edit) {
                    const user = this._users.find((item) => item.username === edit.dataset.editUser);
                    if (user) this._openForm(user);
                    return;
                }
                const pin = event.target.closest('[data-pin-user]');
                if (pin) this._openPin(pin.dataset.pinUser);
            });
            await this._load();
        }

        async _load() {
            try {
                const payload = await ErpUI.api('/api/users');
                this._users = payload.items || [];
                this._render();
            } catch (error) {
                this._body.innerHTML = '';
                this._empty.hidden = false;
                this._empty.querySelector('strong').textContent = 'No se pudieron cargar los usuarios';
                this._empty.querySelector('span').textContent = error.message;
            }
        }

        _roleLabel(role) {
            if (role === 'admin') return 'Administrador';
            if (role === 'supervisor') return 'Supervisor';
            return 'Vendedor';
        }

        _render() {
            this._count.textContent = `${this._users.length} usuario${this._users.length === 1 ? '' : 's'}`;
            this._empty.hidden = this._users.length > 0;
            this._body.innerHTML = this._users.map((user) => {
                const admin = user.role === 'admin';
                const canPin = admin || user.role === 'supervisor';
                return `
                <tr>
                    <td><strong>${escape(user.username)}</strong></td>
                    <td><span class="badge badge-soft">${this._roleLabel(user.role)}</span></td>
                    <td><span class="user-permission ${Number(user.can_view_metrics) === 1 ? 'on' : 'off'}">${Number(user.can_view_metrics) === 1 ? 'Sí' : 'No'}</span></td>
                    <td><span class="user-permission ${Number(user.can_manage_stock) === 1 ? 'on' : 'off'}">${Number(user.can_manage_stock) === 1 ? 'Sí' : 'No'}</span></td>
                    <td><span class="user-permission ${Number(user.has_pin) === 1 ? 'on' : 'off'}">${Number(user.has_pin) === 1 ? 'Configurado' : 'Sin PIN'}</span></td>
                    <td><span class="user-permission ${Number(user.active) === 1 ? 'on' : 'off'}">${Number(user.active) === 1 ? 'Activa' : 'Inactiva'}</span></td>
                    <td>
                        <div class="user-actions">
                            ${admin ? '' : `<button class="btn ghost small" type="button" data-edit-user="${escape(user.username)}">Editar</button>`}
                            ${canPin ? `<button class="btn ghost small" type="button" data-pin-user="${escape(user.username)}">Cambiar PIN</button>` : ''}
                        </div>
                    </td>
                </tr>`;
            }).join('');
        }

        _syncRole() {
            const role = this._role.value;
            const supervisor = role === 'supervisor';
            this._metrics.disabled = !supervisor;
            this._stock.disabled = !supervisor;
            if (!supervisor) {
                this._metrics.checked = false;
                this._stock.checked = false;
            }
            this._pinField.hidden = role === 'vendedor';
            this._pin.disabled = role === 'vendedor';
            if (role === 'vendedor') this._pin.value = '';
            this._pin.required = supervisor && !this._editing;
            this._pinHelp.textContent = supervisor
                ? 'Obligatorio para supervisores. Se usa al anular ventas o pedidos.'
                : 'Los vendedores no tienen PIN de anulación.';
        }

        async _openForm(user = null) {
            this._editing = user ? user.username : '';
            this._form.reset();
            this._formError.hidden = true;
            this._passwordField.hidden = Boolean(user);
            this._password.disabled = Boolean(user);
            this._username.disabled = Boolean(user);
            this._username.value = user?.username || '';
            this._role.value = user?.role || 'vendedor';
            this._activeField.hidden = !user;
            this._active.checked = user ? Number(user.active) === 1 : true;
            this._metrics.checked = user ? Number(user.can_view_metrics) === 1 : false;
            this._stock.checked = user ? Number(user.can_manage_stock) === 1 : false;
            this._pin.value = '';
            this._pin.required = false;
            this._submit.textContent = user ? 'Guardar cambios' : 'Crear usuario';
            this._syncRole();
            await this._formModal.ready();
            this._formModal.setTitle(user ? `Editar ${user.username}` : 'Nuevo usuario');
            this._formModal.open();
        }

        async _save(event) {
            event.preventDefault();
            this._formError.hidden = true;
            this._submit.disabled = true;
            const body = {
                role: this._role.value,
                active: this._active.checked ? 1 : 0,
                can_view_metrics: this._metrics.checked ? 1 : 0,
                can_manage_stock: this._stock.checked ? 1 : 0,
                pin: this._pin.value
            };
            try {
                if (this._editing) {
                    await ErpUI.api(`/api/users/${encodeURIComponent(this._editing)}`, { method: 'PUT', body });
                    ErpUI.toast('Usuario actualizado', 'Los permisos se guardaron.');
                } else {
                    body.username = this._username.value.trim();
                    body.password = this._password.value;
                    await ErpUI.api('/api/users', { method: 'POST', body });
                    ErpUI.toast('Usuario creado', 'La cuenta quedó registrada.');
                }
                this._formModal.close();
                await this._load();
            } catch (error) {
                this._formError.textContent = error.message;
                this._formError.hidden = false;
            } finally {
                this._submit.disabled = false;
            }
        }

        async _openPin(username) {
            this._pinUser = username;
            this._pinForm.reset();
            this._pinError.hidden = true;
            this._pinSummary.textContent = `Defina un nuevo PIN para ${username}.`;
            await this._pinModal.ready();
            this._pinModal.setTitle(`Cambiar PIN · ${username}`);
            this._pinModal.open();
        }

        async _savePin(event) {
            event.preventDefault();
            this._pinError.hidden = true;
            this._pinSubmit.disabled = true;
            try {
                await ErpUI.api(`/api/users/${encodeURIComponent(this._pinUser)}/pin`, {
                    method: 'PUT',
                    body: { pin: this._pinNew.value }
                });
                this._pinModal.close();
                ErpUI.toast('PIN actualizado', `El PIN de ${this._pinUser} quedó configurado.`);
                await this._load();
            } catch (error) {
                this._pinError.textContent = error.message;
                this._pinError.hidden = false;
            } finally {
                this._pinSubmit.disabled = false;
            }
        }
    }

    customElements.define('erp-user-manager', UserManager);
})();
