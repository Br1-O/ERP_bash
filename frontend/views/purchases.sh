#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_PURCHASES_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_PURCHASES_LOADED=1

view_purchases_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/erp-pagination/erp-pagination.css">
    <link rel="stylesheet" href="/components/invoice-generator/invoice-generator.css">
    <link rel="stylesheet" href="/components/purchase-manager/purchase-manager.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/erp-modal/erp-modal.js" defer></script>
    <script src="/components/erp-pagination/erp-pagination.js" defer></script>
    <script src="/components/invoice-generator/invoice-generator.js" defer></script>
    <script src="/components/purchase-manager/purchase-manager.js" defer></script>
EOF
)

    view_layout_start "Compras y reposición" "purchases" "compras" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'EOF'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Abastecimiento</span>
                        <h2>Reposición inteligente e historial de compras</h2>
                        <p class="muted">Combine la última compra y la proyección de ventas para generar un pedido listo para enviar al proveedor.</p>
                    </div>
                </section>

                <erp-purchase-manager></erp-purchase-manager>
EOF

    view_layout_end
}
