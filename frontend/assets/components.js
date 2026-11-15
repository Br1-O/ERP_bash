(() => {
    'use strict';

    const money = new Intl.NumberFormat('es-AR', {
        style: 'currency',
        currency: 'ARS',
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
    const number = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 2 });

    function escapeHtml(value) {
        const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
        return String(value ?? '').replace(/[&<>"']/g, (character) => map[character]);
    }

    function formatMoney(value) {
        return money.format(Number(value) || 0);
    }

    function formatNumber(value, digits = 2) {
        const numeric = Number(value) || 0;
        return numeric.toLocaleString('es-AR', { maximumFractionDigits: digits });
    }

    function formatDate(value) {
        if (!value) return '—';
        const date = new Date(String(value).replace(' ', 'T'));
        if (Number.isNaN(date.getTime())) return value;
        return date.toLocaleDateString('es-AR', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    function formatDateTime(value) {
        if (!value) return '—';
        const date = new Date(String(value).replace(' ', 'T'));
        if (Number.isNaN(date.getTime())) return value;
        return date.toLocaleString('es-AR', {
            day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit'
        });
    }

    async function api(path, options = {}) {
        const config = { ...options, headers: { ...(options.headers || {}) } };
        if (config.body && typeof config.body !== 'string') {
            config.headers['Content-Type'] = 'application/json';
            config.body = JSON.stringify(config.body);
        }
        const response = await fetch(path, config);
        if (response.status === 401) {
            window.location.href = '/login';
            throw new Error('Sesión expirada.');
        }
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || payload.ok === false) {
            throw new Error(payload.error || `La operación falló (${response.status}).`);
        }
        return payload;
    }

    async function fetchText(path) {
        const response = await fetch(path);
        if (!response.ok) throw new Error(`No se pudo cargar ${path}`);
        return response.text();
    }

    function toast(title, message, type = 'success') {
        const stack = document.getElementById('toast-stack');
        if (!stack) return;
        const element = document.createElement('div');
        element.className = `toast ${type === 'error' ? 'error' : ''}`;
        element.innerHTML = `<strong>${escapeHtml(title)}</strong><span>${escapeHtml(message || '')}</span>`;
        stack.append(element);
        window.setTimeout(() => element.remove(), 4200);
    }

    async function copyText(value, label = 'Texto') {
        const content = String(value ?? '');
        let copied = false;
        try {
            await navigator.clipboard.writeText(content);
            copied = true;
        } catch (error) {
            const area = document.createElement('textarea');
            area.value = content;
            area.setAttribute('readonly', '');
            area.style.position = 'fixed';
            area.style.opacity = '0';
            document.body.append(area);
            area.select();
            copied = document.execCommand('copy');
            area.remove();
        }
        if (copied) toast('Copiado', `${label} copiado al portapapeles.`);
        else toast('No se pudo copiar', 'Seleccione el texto manualmente.', 'error');
        return copied;
    }

    function debounce(callback, delay = 250) {
        let timer = 0;
        return (...args) => {
            window.clearTimeout(timer);
            timer = window.setTimeout(() => callback(...args), delay);
        };
    }

    function escapeAttribute(value) {
        return escapeHtml(value);
    }

    function debounceInput(input, callback, delay = 250) {
        if (!input) return;
        input.addEventListener('input', debounce(callback, delay));
    }

    function cleanText(value) {
        return String(value ?? '').trim();
    }

    window.ErpUI = {
        escapeHtml,
        escapeAttribute,
        formatMoney,
        formatNumber,
        formatDate,
        formatDateTime,
        api,
        fetchText,
        toast,
        copyText,
        debounce,
        debounceInput,
        cleanText
    };
})();
