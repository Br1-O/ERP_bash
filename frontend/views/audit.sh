#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_AUDIT_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_AUDIT_LOADED=1

view_audit_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/erp-pagination/erp-pagination.css">
    <link rel="stylesheet" href="/components/product-detail/product-detail.css">
    <link rel="stylesheet" href="/components/audit-manager/audit-manager.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/erp-modal/erp-modal.js" defer></script>
    <script src="/components/erp-pagination/erp-pagination.js" defer></script>
    <script src="/components/product-detail/product-detail.js" defer></script>
    <script src="/components/audit-manager/audit-manager.js" defer></script>
EOF
)

    view_layout_start "Auditoría" "audit" "auditoria" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'EOF'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Trazabilidad</span>
                        <h2>Auditoría completa del sistema</h2>
                        <p class="muted">Consulte todos los movimientos registrados en InventoryJournal, con usuario, acción, entidad, estado y detalle completo.</p>
                    </div>
                </section>

                <erp-audit-manager></erp-audit-manager>
                <erp-product-detail></erp-product-detail>
EOF

    view_layout_end
}
