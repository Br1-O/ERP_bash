#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_USERS_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_USERS_LOADED=1

view_users_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'HTML'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/user-manager/user-manager.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/erp-modal/erp-modal.js" defer></script>
    <script src="/components/user-manager/user-manager.js" defer></script>
HTML
)

    view_layout_start "Usuarios y permisos" "users" "usuarios" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'HTML'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Seguridad</span>
                        <h2>Cuentas, roles y autorizaciones</h2>
                        <p class="muted">Solo los administradores pueden crear vendedores y supervisores. Los supervisores pueden ver métricas y administrar stock según estos permisos, pero nunca crear usuarios.</p>
                    </div>
                </section>

                <erp-user-manager></erp-user-manager>
HTML

    view_layout_end
}
