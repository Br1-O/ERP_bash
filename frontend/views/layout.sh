#!/usr/bin/env bash
#
# Layout principal de la capa de presentación.

[[ -n "${_ERP_VIEW_LAYOUT_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_LAYOUT_LOADED=1

html_escape() {
    local value="${1:-}"
    value="${value//&/\&amp;}"
    value="${value//</\&lt;}"
    value="${value//>/\&gt;}"
    value="${value//\"/\&quot;}"
    value="${value//\'/\&#39;}"
    printf '%s' "${value}"
}

view_html_head() {
    local title="${1:-ERP de Licores Artesanales}"
    cat <<EOF
<!DOCTYPE html>
<html lang="es" data-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="ERP analítico para una tienda de licores artesanales">
    <title>${title} · Aurea ERP</title>
    <link rel="stylesheet" href="/assets/app.css">
    <script>
        (function () {
            try {
                var saved = localStorage.getItem('erp-theme');
                if (saved) document.documentElement.dataset.theme = saved;
            } catch (error) { /* almacenamiento no disponible */ }
        })();
    </script>
</head>
EOF
}

view_layout_start() {
    local title="${1:-Dashboard}"
    local active_nav="${2:-dashboard}"
    local active_tab="${3:-resumen}"
    local user="${4:-Usuario}"
    local role="${5:-admin}"
    local alert_count="${6:-0}"

    local dashboard_active="" contacts_active=""
    [[ "${active_nav}" == "dashboard" ]] && dashboard_active="active"
    [[ "${active_nav}" == "contacts" ]] && contacts_active="active"

    view_html_head "${title}"
    cat <<EOF
<body data-active-tab="${active_tab}">
    <div class="app-shell">
        <aside class="sidebar" id="sidebar">
            <div class="brand">
                <span class="brand-mark">A</span>
                <div>
                    <strong>Aurea</strong>
                    <small>ERP de licores artesanales</small>
                </div>
            </div>

            <nav class="sidebar-nav" aria-label="Navegación principal">
                <a class="nav-link ${dashboard_active}" href="/dashboard">
                    <span class="nav-icon">◫</span>
                    <span>Dashboard</span>
                </a>
                <a class="nav-link ${contacts_active}" href="/contactos">
                    <span class="nav-icon">☏</span>
                    <span>Agenda y contactos</span>
                </a>
                <a class="nav-link" href="/dashboard#stock">
                    <span class="nav-icon">◈</span>
                    <span>Stock y producción</span>
                </a>
                <a class="nav-link" href="/dashboard#catalogo">
                    <span class="nav-icon">◉</span>
                    <span>Catálogo y canasta</span>
                </a>
            </nav>

            <div class="sidebar-footer">
                <div class="user-chip">
                    <span class="avatar">$(html_escape "$(api_user_initials "${user}")")</span>
                    <div>
                        <strong>$(html_escape "${user}")</strong>
                        <small>$(html_escape "${role}")</small>
                    </div>
                </div>
                <a class="logout-link" href="/logout">Cerrar sesión</a>
            </div>
        </aside>

        <div class="main-shell">
            <header class="topbar">
                <button class="icon-button menu-toggle" id="menu-toggle" aria-label="Abrir menú">☰</button>
                <div class="topbar-title">
                    <h1 id="page-title">${title}</h1>
                    <p class="muted" id="page-subtitle">Gestión analítica de la destilería</p>
                </div>
                <div class="topbar-actions">
                    <a class="alert-pill" href="/dashboard#stock" title="Alertas de stock">
                        <span class="alert-dot"></span>
                        <span id="alert-count">${alert_count}</span>
                    </a>
                    <button class="icon-button" id="theme-toggle" aria-label="Cambiar tema">◐</button>
                </div>
            </header>

            <main class="content">
EOF
}

view_layout_end() {
    local data_json="${1:-}"
    local safe_json="${data_json//<\/script>/<\\/script>}"

    cat <<'EOF'
            </main>
        </div>
    </div>
    <div class="toast-stack" id="toast-stack" aria-live="polite"></div>
EOF

    if [[ -n "${safe_json}" ]]; then
        printf '    <script id="erp-data" type="application/json">%s</script>\n' "${safe_json}"
    fi

    cat <<'EOF'
    <script src="/assets/app.js"></script>
</body>
</html>
EOF
}

view_error_page() {
    local status="${1:-404}"
    local message="${2:-La página solicitada no existe.}"
    view_html_head "Error ${status}"
    cat <<EOF
<body class="centered-body">
    <main class="error-card">
        <span class="error-code">${status}</span>
        <h1>No pudimos completar la operación</h1>
        <p>$(html_escape "${message}")</p>
        <a class="btn primary" href="/dashboard">Volver al dashboard</a>
    </main>
</body>
</html>
EOF
}
