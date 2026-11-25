#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_EVENTS_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_EVENTS_LOADED=1

view_events_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/erp-pagination/erp-pagination.css">
    <link rel="stylesheet" href="/components/event-manager/event-manager.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/erp-modal/erp-modal.js" defer></script>
    <script src="/components/erp-pagination/erp-pagination.js" defer></script>
    <script src="/components/event-manager/event-manager.js" defer></script>
EOF
)

    view_layout_start "Eventos y ferias" "events" "eventos" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'EOF'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Stock temporal</span>
                        <h2>Eventos, ferias y puntos de venta</h2>
                        <p class="muted">Asigne stock a cada evento, registre ventas de feria y cierre la operación devolviendo el remanente con sus pérdidas.</p>
                    </div>
                </section>

                <erp-event-manager></erp-event-manager>
EOF

    view_layout_end
}
