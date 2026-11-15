#!/usr/bin/env bash

[[ -n "${_ERP_VIEW_CONTACTS_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_CONTACTS_LOADED=1

view_contacts_page() {
    local user="${1:-Usuario}"
    local role="${2:-admin}"
    local alerts_count="${3:-0}"

    local extra_head
    extra_head=$(cat <<'EOF'
    <link rel="stylesheet" href="/components/erp-modal/erp-modal.css">
    <link rel="stylesheet" href="/components/contact-manager/contact-manager.css">
    <script src="/assets/components.js" defer></script>
    <script src="/components/erp-modal/erp-modal.js" defer></script>
    <script src="/components/contact-manager/contact-manager.js" defer></script>
EOF
)

    view_layout_start "Agenda y contactos" "contacts" "contactos" "${user}" "${role}" "${alerts_count}" "${extra_head}"

    cat <<'EOF'
                <section class="section-heading">
                    <div>
                        <span class="eyebrow">Agenda comercial</span>
                        <h2>Proveedores, clientes y teléfonos</h2>
                        <p class="muted">Consulte qué vende cada proveedor, abra su ficha y copie el teléfono con un clic.</p>
                    </div>
                </section>

                <erp-contact-manager></erp-contact-manager>
EOF

    view_layout_end
}
