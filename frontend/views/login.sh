#!/usr/bin/env bash
#
# Vista de autenticación.

[[ -n "${_ERP_VIEW_LOGIN_LOADED:-}" ]] && return 0
declare -g _ERP_VIEW_LOGIN_LOADED=1

view_login_page() {
    local error="${1:-}"
    local username="${2:-}"

    view_html_head "Acceso"
    cat <<'EOF'
<body class="login-body">
    <button class="icon-button login-theme" id="theme-toggle" aria-label="Cambiar tema">◐</button>
    <main class="login-shell">
        <section class="login-brand-panel">
            <div class="brand brand-large">
                <span class="brand-mark">A</span>
                <div>
                    <strong>Aurea</strong>
                    <small>ERP analítico de licores artesanales</small>
                </div>
            </div>

            <div class="login-copy">
                <span class="eyebrow">Destilería inteligente</span>
                <h1>Decisiones precisas para cada lote artesanal.</h1>
                <p>Inventario, producción, ventas y estadística aplicada en un único panel liviano, servido directamente desde Bash.</p>
            </div>

            <div class="login-metrics">
                <div class="glass-metric">
                    <span>Control</span>
                    <strong>6 módulos</strong>
                    <small>estadísticos integrados</small>
                </div>
                <div class="glass-metric">
                    <span>Auditoría</span>
                    <strong>Triggers</strong>
                    <small>trazabilidad automática</small>
                </div>
                <div class="glass-metric">
                    <span>Servidor</span>
                    <strong>socat</strong>
                    <small>HTTP sin dependencias pesadas</small>
                </div>
            </div>
        </section>

        <section class="login-card">
            <div class="login-card-head">
                <span class="eyebrow">Acceso seguro</span>
                <h2>Ingresar al ERP</h2>
                <p class="muted">Usuarios autorizados de la tienda y la destilería.</p>
            </div>
EOF

    if [[ -n "${error}" ]]; then
        printf '            <div class="form-error" role="alert">%s</div>\n' "$(html_escape "${error}")"
    fi

    cat <<EOF
            <form class="login-form" method="post" action="/login" autocomplete="on">
                <label class="field">
                    <span>Usuario</span>
                    <input type="text" name="username" value="$(html_escape "${username}")" placeholder="admin" required autofocus>
                </label>
                <label class="field">
                    <span>Contraseña</span>
                    <input type="password" name="password" placeholder="••••••••" required>
                </label>
                <button type="submit" class="btn primary btn-block">Ingresar al panel</button>
            </form>

            <div class="demo-hint">
                <strong>Acceso demo</strong>
                <span>Usuario <code>admin</code> · Contraseña <code>admin123</code></span>
            </div>
        </section>
    </main>
    <script src="/assets/app.js"></script>
</body>
</html>
EOF
}
