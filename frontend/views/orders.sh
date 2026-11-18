#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_ORDERS_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_ORDERS_LOADED=1

view_orders_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/erp-pagination/erp-pagination.css">
    <link rel="stylesheet" href="/components/invoice-generator/invoice-generator.css">
    <link rel="stylesheet" href="/components/order-manager/order-manager.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/erp-modal/erp-modal.js" defer></script>
    <script src="/components/erp-pagination/erp-pagination.js" defer></script>
    <script src="/components/invoice-generator/invoice-generator.js" defer></script>
    <script src="/components/order-manager/order-manager.js" defer></script>
EOF
)

    view_layout_start "Ventas y pedidos" "orders" "ventas" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'EOF'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Atención al cliente</span>
                        <h2>Ventas, pedidos y facturación</h2>
                        <p class="muted">Registre ventas directas y pedidos, consulte estados y stock, y genere comprobantes para operaciones finalizadas.</p>
                    </div>
                </section>

                <erp-order-manager></erp-order-manager>
EOF

    view_layout_end
}
