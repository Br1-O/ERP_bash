#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_INVENTORY_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_INVENTORY_LOADED=1

view_inventory_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/erp-pagination/erp-pagination.css">
    <link rel="stylesheet" href="/components/erp-recipe-editor/erp-recipe-editor.css">
    <link rel="stylesheet" href="/components/product-manager/product-manager.css">
    <link rel="stylesheet" href="/components/input-manager/input-manager.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/erp-modal/erp-modal.js" defer></script>
    <script src="/components/erp-pagination/erp-pagination.js" defer></script>
    <script src="/components/erp-recipe-editor/erp-recipe-editor.js" defer></script>
    <script src="/components/product-manager/product-manager.js" defer></script>
    <script src="/components/input-manager/input-manager.js" defer></script>
EOF
)

    view_layout_start "Inventario y recetas" "inventory" "inventario" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'EOF'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Gestión de inventario</span>
                        <h2>Productos, insumos y recetas</h2>
                        <p class="muted">Cree productos, actualice stock, asocie recetas y administre cada insumo con su proveedor.</p>
                    </div>
                </section>

                <erp-product-manager></erp-product-manager>
                <erp-input-manager></erp-input-manager>
EOF

    view_layout_end
}
