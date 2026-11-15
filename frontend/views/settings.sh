#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_SETTINGS_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_SETTINGS_LOADED=1

view_settings_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/business-settings/business-settings.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/business-settings/business-settings.js" defer></script>
EOF
)

    view_layout_start "Configuración" "settings" "configuracion" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<EOF
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Identidad comercial</span>
                        <h2>Datos del negocio para facturas</h2>
                        <p class="muted">Estos datos aparecen en los comprobantes de compras y pedidos. Solo un administrador puede modificarlos.</p>
                    </div>
                </section>

                <erp-business-settings role="$(html_escape "${role}")"></erp-business-settings>
EOF

    view_layout_end
}
