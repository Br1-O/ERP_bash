(() => {
    'use strict';

    const escape = ErpUI.escapeHtml;
    const money = ErpUI.formatMoney;
    const number = ErpUI.formatNumber;

    const WIN_ANSI_SPECIAL = {
        '€': 0x80, '‚': 0x82, 'ƒ': 0x83, '„': 0x84, '…': 0x85, '†': 0x86, '‡': 0x87,
        'ˆ': 0x88, '‰': 0x89, 'Š': 0x8a, '‹': 0x8b, 'Œ': 0x8c, 'Ž': 0x8e, '‘': 0x91,
        '’': 0x92, '“': 0x93, '”': 0x94, '•': 0x95, '–': 0x96, '—': 0x97, '˜': 0x98,
        '™': 0x99, 'š': 0x9a, '›': 0x9b, 'œ': 0x9c, 'ž': 0x9e, 'Ÿ': 0x9f
    };

    function winAnsi(value) {
        let output = '';
        for (const character of String(value ?? '')) {
            const code = character.codePointAt(0);
            if (Object.prototype.hasOwnProperty.call(WIN_ANSI_SPECIAL, character)) {
                output += String.fromCharCode(WIN_ANSI_SPECIAL[character]);
            } else if (code >= 32 && code <= 255) {
                output += String.fromCharCode(code);
            } else if (character === '\t') {
                output += '    ';
            } else {
                output += '?';
            }
        }
        return output;
    }

    function pdfString(value) {
        return '(' + winAnsi(value).replace(/[\\()]/g, (match) => '\\' + match) + ')';
    }

    function truncate(value, max) {
        const text = String(value ?? '');
        return text.length > max ? `${text.slice(0, max - 1)}…` : text;
    }

    function moneyText(value) {
        return money(Number(value) || 0);
    }

    class InvoiceGenerator extends HTMLElement {
        constructor() {
            super();
            this._started = false;
            this._invoice = null;
        }

        connectedCallback() {
            if (this._started) return;
            this._started = true;
            this._init();
        }

        async _init() {
            this.innerHTML = await ErpUI.fetchText('/components/invoice-generator/invoice-generator.html');
            this._modal = this.querySelector('#invoice-modal');
            this._preview = this.querySelector('[data-invoice-preview]');
            this._error = this.querySelector('[data-invoice-error]');
            this.querySelector('[data-invoice-close]').addEventListener('click', () => this._modal.close());
            this.querySelector('[data-invoice-pdf]').addEventListener('click', () => this._download());
            this.querySelector('[data-invoice-print]').addEventListener('click', () => this._print());
        }

        async open(type, id) {
            this._error.hidden = true;
            this._preview.innerHTML = '<div class="empty-state"><strong>Generando comprobante…</strong></div>';
            this._modal.setTitle('Comprobante');
            await this._modal.open();
            const path = type === 'purchase'
                ? `/api/invoices/purchases/${Number(id)}`
                : `/api/invoices/orders/${Number(id)}`;
            try {
                this._invoice = await ErpUI.api(path);
                this._renderPreview();
                this._modal.setTitle(`${this._invoice.type === 'purchase' ? 'Compra' : 'Pedido'} ${this._invoice.number}`);
            } catch (error) {
                this._invoice = null;
                this._preview.innerHTML = '';
                this._error.textContent = error.message;
                this._error.hidden = false;
            }
        }

        _party() {
            const document = this._invoice.document;
            if (this._invoice.type === 'purchase') {
                return {
                    label: 'Proveedor',
                    name: document.supplier,
                    lines: [document.contact, document.phone, document.email].filter(Boolean)
                };
            }
            return {
                label: 'Cliente',
                name: document.customer,
                lines: [document.customer_type, document.customer_phone, document.customer_email].filter(Boolean)
            };
        }

        _items() {
            return (this._invoice.document.items || []).map((item) => ({
                name: this._invoice.type === 'purchase' ? item.input_name : item.product_name,
                quantity: Number(item.quantity) || 0,
                unit: this._invoice.type === 'purchase' ? item.unit : 'unidades',
                unitPrice: Number(this._invoice.type === 'purchase' ? item.unit_cost : item.unit_price) || 0,
                subtotal: Number(item.subtotal) || 0
            }));
        }

        _renderPreview() {
            const invoice = this._invoice;
            const business = invoice.business || {};
            const document = invoice.document || {};
            const party = this._party();
            const rows = this._items().map((item) => `
                <tr>
                    <td>${escape(item.name)}</td>
                    <td>${number(item.quantity)} ${escape(item.unit)}</td>
                    <td>${money(item.unitPrice)}</td>
                    <td>${money(item.subtotal)}</td>
                </tr>`).join('');
            const discount = Number(document.discount) || 0;
            const totals = invoice.type === 'purchase'
                ? `<div class="invoice-total"><span>Total</span><strong>${money(document.total)}</strong></div>`
                : `<div class="invoice-total"><span>Subtotal</span><strong>${money(document.subtotal)}</strong></div>
                   ${discount > 0 ? `<div class="invoice-total"><span>Descuento</span><strong>- ${money(discount)}</strong></div>` : ''}
                   <div class="invoice-total grand"><span>Total</span><strong>${money(document.total)}</strong></div>`;
            const socials = [business.instagram, business.facebook, business.phone, business.email, business.website]
                .filter(Boolean).map((value) => `<span>${escape(value)}</span>`).join('');
            this._preview.innerHTML = `
                <div class="invoice-sheet">
                    <header class="invoice-header">
                        <div>
                            <span class="eyebrow">Comprobante</span>
                            <h3>${escape(business.name || 'Negocio')}</h3>
                            <p>${socials || 'Sin datos de contacto configurados'}</p>
                        </div>
                        <div class="invoice-number">
                            <strong>${escape(invoice.number)}</strong>
                            <span>${escape(ErpUI.formatDateTime(document.date))}</span>
                            <span class="badge badge-soft">${escape(document.status || '')}</span>
                        </div>
                    </header>
                    <div class="invoice-party">
                        <span>${escape(party.label)}</span>
                        <strong>${escape(party.name || 'Consumidor final')}</strong>
                        <small>${escape(party.lines.join(' · '))}</small>
                    </div>
                    <div class="table-responsive">
                        <table class="invoice-table">
                            <thead><tr><th>Descripción</th><th>Cantidad</th><th>Precio unitario</th><th>Subtotal</th></tr></thead>
                            <tbody>${rows || '<tr><td colspan="4" class="muted">Sin ítems.</td></tr>'}</tbody>
                        </table>
                    </div>
                    <div class="invoice-totals">${totals}</div>
                    <div class="invoice-footer">
                        <span>Pago: ${escape(document.payment_method || '—')}</span>
                        ${document.notes ? `<span>Notas: ${escape(document.notes)}</span>` : ''}
                    </div>
                </div>`;
        }

        _addText(page, x, y, text, font = 'F1', size = 9) {
            page.push({ type: 'text', x, y, text: String(text), font, size });
        }

        _addLine(page, x1, y1, x2, y2) {
            page.push({ type: 'line', x1, y1, x2, y2 });
        }

        _pageHeader(page, continued) {
            const invoice = this._invoice;
            const business = invoice.business || {};
            const document = invoice.document || {};
            const party = this._party();
            this._addText(page, 50, 800, business.name || 'Negocio', 'F2', 16);
            this._addText(page, 50, 783, [business.instagram, business.facebook].filter(Boolean).join(' · '), 'F1', 8);
            this._addText(page, 50, 771, [business.phone, business.email, business.website].filter(Boolean).join(' · '), 'F1', 8);
            this._addText(page, 390, 800, `${invoice.type === 'purchase' ? 'Compra' : 'Pedido'} ${invoice.number}`, 'F2', 11);
            this._addText(page, 390, 785, `Fecha: ${ErpUI.formatDateTime(document.date)}`, 'F1', 8);
            this._addText(page, 390, 773, `Estado: ${document.status || '—'}`, 'F1', 8);
            if (continued) this._addText(page, 390, 761, 'Continuación de ítems', 'F1', 8);
            this._addLine(page, 50, 752, 545, 752);
            this._addText(page, 50, 738, party.label, 'F2', 8);
            this._addText(page, 50, 725, party.name || 'Consumidor final', 'F1', 10);
            this._addText(page, 50, 713, party.lines.join(' · '), 'F1', 8);
            this._addLine(page, 50, 702, 545, 702);
            this._addText(page, 50, 688, 'Descripción', 'F2', 8);
            this._addText(page, 330, 688, 'Cantidad', 'F2', 8);
            this._addText(page, 410, 688, 'Precio unit.', 'F2', 8);
            this._addText(page, 490, 688, 'Subtotal', 'F2', 8);
            this._addLine(page, 50, 681, 545, 681);
            return 670;
        }

        _buildPdf() {
            const invoice = this._invoice;
            const document = invoice.document || {};
            const items = this._items();
            const pages = [];
            let page = [];
            pages.push(page);
            let y = this._pageHeader(page, false);

            items.forEach((item) => {
                if (y < 130) {
                    page = [];
                    pages.push(page);
                    y = this._pageHeader(page, true);
                }
                this._addText(page, 50, y, truncate(item.name, 52), 'F1', 9);
                this._addText(page, 330, y, `${number(item.quantity)} ${item.unit}`, 'F1', 9);
                this._addText(page, 410, y, moneyText(item.unitPrice), 'F1', 9);
                this._addText(page, 490, y, moneyText(item.subtotal), 'F1', 9);
                y -= 14;
            });

            if (y < 110) {
                page = [];
                pages.push(page);
                y = this._pageHeader(page, true);
            }

            y -= 8;
            this._addLine(page, 390, y + 6, 545, y + 6);
            if (invoice.type === 'purchase') {
                this._addText(page, 390, y - 8, 'Total', 'F2', 10);
                this._addText(page, 490, y - 8, moneyText(document.total), 'F2', 10);
                y -= 26;
            } else {
                this._addText(page, 390, y - 8, 'Subtotal', 'F1', 9);
                this._addText(page, 490, y - 8, moneyText(document.subtotal), 'F1', 9);
                y -= 18;
                const discount = Number(document.discount) || 0;
                if (discount > 0) {
                    this._addText(page, 390, y, 'Descuento', 'F1', 9);
                    this._addText(page, 490, y, `- ${moneyText(discount)}`, 'F1', 9);
                    y -= 18;
                }
                this._addText(page, 390, y, 'Total', 'F2', 10);
                this._addText(page, 490, y, moneyText(document.total), 'F2', 10);
                y -= 24;
            }

            this._addText(page, 50, Math.max(70, y), `Pago: ${document.payment_method || '—'}`, 'F1', 8);
            if (document.notes) {
                this._addText(page, 50, Math.max(58, y - 12), truncate(`Notas: ${document.notes}`, 110), 'F1', 8);
            }
            this._addText(page, 50, 40, `Documento generado por Aurea ERP · ${invoice.number}`, 'F1', 7);

            return this._serializePdf(pages);
        }

        _serializePdf(pages) {
            const pageCount = pages.length;
            const objects = [];
            const fontRegularId = 3;
            const fontBoldId = 4;
            const firstPageId = 5;

            objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
            const kids = [];
            for (let index = 0; index < pageCount; index++) {
                kids.push(`${firstPageId + index * 2} 0 R`);
            }
            objects[2] = `<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pageCount} >>`;
            objects[fontRegularId] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
            objects[fontBoldId] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';

            pages.forEach((page, index) => {
                const pageId = firstPageId + index * 2;
                const contentId = pageId + 1;
                let content = '0.5 w 0.6 0.6 0.6 RG\n';
                page.filter((element) => element.type === 'line').forEach((element) => {
                    content += `${element.x1} ${element.y1} m ${element.x2} ${element.y2} l S\n`;
                });
                content += '0 0 0 rg BT\n';
                page.filter((element) => element.type === 'text').forEach((element) => {
                    content += `/${element.font} ${element.size} Tf 1 0 0 1 ${element.x} ${element.y} Tm ${pdfString(element.text)} Tj\n`;
                });
                content += 'ET\n';
                objects[pageId] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 ${fontRegularId} 0 R /F2 ${fontBoldId} 0 R >> >> /Contents ${contentId} 0 R >>`;
                objects[contentId] = `<< /Length ${content.length} >>\nstream\n${content}endstream`;
            });

            let pdf = '%PDF-1.4\n';
            const offsets = [0];
            for (let id = 1; id < objects.length; id++) {
                if (!objects[id]) continue;
                offsets[id] = pdf.length;
                pdf += `${id} 0 obj\n${objects[id]}\nendobj\n`;
            }
            const xrefOffset = pdf.length;
            pdf += `xref\n0 ${objects.length}\n0000000000 65535 f \n`;
            for (let id = 1; id < objects.length; id++) {
                if (!objects[id]) continue;
                pdf += `${String(offsets[id]).padStart(10, '0')} 00000 n \n`;
            }
            pdf += `trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
            return pdf;
        }

        _download() {
            if (!this._invoice) return;
            const pdf = this._buildPdf();
            const bytes = new Uint8Array(pdf.length);
            for (let index = 0; index < pdf.length; index++) {
                bytes[index] = pdf.charCodeAt(index) & 0xff;
            }
            const blob = new Blob([bytes], { type: 'application/pdf' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = `${this._invoice.number}.pdf`;
            document.body.append(link);
            link.click();
            link.remove();
            window.setTimeout(() => URL.revokeObjectURL(url), 1000);
            ErpUI.toast('PDF generado', `Se descargó ${this._invoice.number}.pdf.`);
        }

        _print() {
            if (!this._invoice) return;
            const printWindow = window.open('', '_blank');
            if (!printWindow) {
                ErpUI.toast('No se pudo imprimir', 'Habilite las ventanas emergentes del navegador.', 'error');
                return;
            }
            printWindow.document.write(`<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>${escape(this._invoice.number)}</title><style>
                body{font-family:Arial,Helvetica,sans-serif;color:#1f1b16;margin:32px}
                h3{margin:0 0 4px;font-size:22px}
                .invoice-header{display:flex;justify-content:space-between;gap:24px;border-bottom:2px solid #c9973f;padding-bottom:14px}
                .invoice-number{text-align:right}
                .badge{display:inline-block;padding:2px 6px;border:1px solid #bbb;border-radius:6px;font-size:11px;margin-top:4px}
                .invoice-party{margin:16px 0;padding:10px 12px;background:#f7f2e8;border-radius:8px}
                .invoice-party span{display:block;font-size:11px;text-transform:uppercase;color:#777}
                table{width:100%;border-collapse:collapse;margin-top:12px;font-size:12px}
                th,td{padding:6px 8px;border-bottom:1px solid #ddd;text-align:left}
                th:last-child,td:last-child,th:nth-child(3),td:nth-child(3){text-align:right}
                .invoice-totals{margin-top:14px;margin-left:auto;width:240px}
                .invoice-total{display:flex;justify-content:space-between;padding:4px 0;font-size:12px}
                .invoice-total.grand{border-top:1px solid #333;font-size:15px;font-weight:bold;margin-top:4px;padding-top:8px}
                .invoice-footer{margin-top:26px;border-top:1px solid #ddd;padding-top:10px;font-size:11px;color:#666;display:flex;flex-direction:column;gap:4px}
            </style></head><body>${this._preview.innerHTML}</body></html>`);
            printWindow.document.close();
            printWindow.focus();
            printWindow.print();
        }
    }

    customElements.define('erp-invoice-generator', InvoiceGenerator);
})();
