(() => {
    'use strict';

    const currency = new Intl.NumberFormat('es-AR', {
        style: 'currency',
        currency: 'ARS',
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });

    const Money = Object.freeze({
        toCents(value) {
            let raw = String(value ?? '').trim().replace(/\s+/g, '');
            if (raw.includes(',') && !raw.includes('.')) raw = raw.replace(',', '.');
            const match = raw.match(/^(-?)(\d{1,12})(?:\.(\d*))?$/);
            if (!match) return null;
            const fraction = (match[3] || '').padEnd(3, '0');
            let cents = Number(match[2]) * 100 + Number(fraction.slice(0, 2));
            if (Number(fraction[2]) >= 5) cents += 1;
            return match[1] === '-' ? -cents : cents;
        },
        fromCents(cents) {
            const value = Number(cents) || 0;
            const sign = value < 0 ? '-' : '';
            const absolute = Math.abs(Math.round(value));
            return `${sign}${Math.floor(absolute / 100)}.${String(absolute % 100).padStart(2, '0')}`;
        },
        formatCents(cents) {
            return currency.format((Number(cents) || 0) / 100);
        }
    });

    const strategies = Object.freeze({
        none: {
            label: 'Sin descuento',
            valueLabel: '',
            calculate() {
                return { discountCents: 0, value: 0 };
            }
        },
        percent: {
            label: 'Porcentaje',
            valueLabel: '% de descuento',
            calculate(subtotalCents, value) {
                const basisPoints = Money.toCents(value);
                if (basisPoints === null || basisPoints < 0 || basisPoints > 10000) return null;
                return {
                    discountCents: Math.round((subtotalCents * basisPoints) / 10000),
                    value: basisPoints / 100
                };
            }
        },
        fixed: {
            label: 'Monto fijo',
            valueLabel: 'Monto a descontar',
            calculate(subtotalCents, value) {
                const discountCents = Money.toCents(value);
                if (discountCents === null || discountCents < 0 || discountCents > subtotalCents) return null;
                return { discountCents, value: discountCents / 100 };
            }
        }
    });

    function apply(type, subtotalCents, value) {
        const strategy = strategies[type] || strategies.none;
        const result = strategy.calculate(Math.max(0, Number(subtotalCents) || 0), value);
        if (!result) return null;
        return {
            discountCents: Math.min(result.discountCents, subtotalCents),
            totalCents: Math.max(0, subtotalCents - result.discountCents),
            value: result.value
        };
    }

    window.ErpBilling = Object.freeze({ Money, strategies, apply });
})();
