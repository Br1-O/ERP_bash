#!/usr/bin/env bash
#
# Motor analítico centralizado.
# Estadística descriptiva, probabilidad binomial, intervalos de confianza,
# pruebas de hipótesis, covarianza/regresión y alertas de reposición.

[[ -n "${_ERP_ANALYTICS_LOADED:-}" ]] && return 0
declare -g _ERP_ANALYTICS_LOADED=1

analytics_daily_json() {
    local raw
    raw=$(db_query "SELECT date(timestamp), SUM(total_amount), COUNT(*)
                    FROM Sales
                    GROUP BY date(timestamp)
                    ORDER BY date(timestamp);")

    LC_ALL=C awk -F'|' '
    function pct(p,    idx, lo, hi, frac) {
        if (n == 0) return 0;
        if (n == 1) return s[1];
        idx = (n - 1) * p;
        lo = int(idx) + 1;
        hi = lo + 1;
        if (hi > n) hi = n;
        frac = idx - int(idx);
        return s[lo] + (s[hi] - s[lo]) * frac;
    }
    {
        n++;
        d[n] = $1;
        v[n] = $2 + 0;
        c[n] = $3 + 0;
        total += v[n];
    }
    END {
        if (n == 0) {
            print "{\"labels\":[],\"values\":[],\"counts\":[],\"outliers\":[],\"stats\":{\"mean\":0,\"median\":0,\"q1\":0,\"q3\":0,\"iqr\":0,\"threshold\":0,\"total\":0,\"days\":0,\"sd\":0,\"cv\":0}}";
            exit;
        }
        for (i = 1; i <= n; i++) s[i] = v[i];
        for (i = 1; i <= n; i++)
            for (j = i + 1; j <= n; j++)
                if (s[j] < s[i]) { tmp = s[i]; s[i] = s[j]; s[j] = tmp; }
        q1 = pct(0.25); med = pct(0.5); q3 = pct(0.75);
        iqr = q3 - q1;
        thr = q3 + 1.5 * iqr;
        mean = total / n;
        ss = 0;
        for (i = 1; i <= n; i++) ss += (v[i] - mean) * (v[i] - mean);
        sd = (n > 1) ? sqrt(ss / (n - 1)) : 0;
        cv = (mean != 0) ? (sd / mean) * 100 : 0;

        printf "{\"labels\":[";
        for (i = 1; i <= n; i++) printf "%s\"%s\"", (i > 1 ? "," : ""), d[i];
        printf "],\"values\":[";
        for (i = 1; i <= n; i++) printf "%s%.2f", (i > 1 ? "," : ""), v[i];
        printf "],\"counts\":[";
        for (i = 1; i <= n; i++) printf "%s%d", (i > 1 ? "," : ""), c[i];
        printf "],\"outliers\":[";
        sep = "";
        for (i = 1; i <= n; i++) {
            if (v[i] > thr) {
                printf "%s{\"date\":\"%s\",\"value\":%.2f}", sep, d[i], v[i];
                sep = ",";
            }
        }
        printf "],\"stats\":{\"mean\":%.2f,\"median\":%.2f,\"q1\":%.2f,\"q3\":%.2f,\"iqr\":%.2f,\"threshold\":%.2f,\"total\":%.2f,\"days\":%d,\"sd\":%.2f,\"cv\":%.2f}}\n",
               mean, med, q1, q3, iqr, thr, total, n, sd, cv;
    }' <<< "${raw}"
}

analytics_binomial_json() {
    local peak_row peak_hour peak_count n k
    peak_row=$(db_query "SELECT strftime('%H', timestamp), COUNT(*)
                         FROM Sales
                         GROUP BY strftime('%H', timestamp)
                         ORDER BY 2 DESC
                         LIMIT 1;")
    peak_hour="--"
    peak_count=0
    if [[ -n "${peak_row}" ]]; then
        IFS='|' read -r peak_hour peak_count <<< "${peak_row}"
    fi
    [[ "${peak_count}" =~ ^[0-9]+$ ]] || peak_count=0

    n="${peak_count}"
    (( n < 6 )) && n=6
    k=$(( (n + 1) / 2 ))

    LC_ALL=C awk -v n="${n}" -v k="${k}" -v p="0.25" -v hour="${peak_hour}" -v peak="${peak_count}" '
    function comb(total, chosen,    i, r) {
        if (chosen < 0 || chosen > total) return 0;
        if (chosen > total - chosen) chosen = total - chosen;
        r = 1;
        for (i = 1; i <= chosen; i++) r = r * (total - chosen + i) / i;
        return r;
    }
    BEGIN {
        prob = 0;
        for (i = k; i <= n; i++) prob += comb(n, i) * (p ^ i) * ((1 - p) ^ (n - i));
        printf "{\"n\":%d,\"k\":%d,\"p\":0.25,\"probability\":%.4f,\"percent\":%.2f,\"peak_hour\":\"%s\",\"peak_sales\":%d}\n",
               n, k, prob, prob * 100, hour, peak;
    }'
}

_analytics_reorder_array() {
    local raw="$1"
    local period="${2:-30}"
    local lead="${3:-4}"

    LC_ALL=C awk -F'|' -v period="${period}" -v lead="${lead}" '
    function clamp(x) { return (x < 0 ? 0 : x); }
    {
        n++;
        id[n] = $1;
        name[n] = $2;
        stock[n] = $3 + 0;
        threshold[n] = $4 + 0;
        cost[n] = $5 + 0;
        total[n] = $6 + 0;
        sq[n] = $7 + 0;
        unit[n] = $9;
    }
    END {
        printf "[";
        for (i = 1; i <= n; i++) {
            mean = total[i] / period;
            variance = (sq[i] - 2 * mean * total[i] + period * mean * mean) / (period - 1);
            variance = clamp(variance);
            sd = sqrt(variance);
            cv = (mean > 0) ? (sd / mean) * 100 : 0;
            safety = 1.65 * sd * sqrt(lead);
            reorder = mean * lead + safety;
            risk = stock[i] - reorder;
            printf "%s{\"id\":%d,\"name\":\"%s\",\"stock\":%.2f,\"threshold\":%.2f,\"cost\":%.2f,\"mean\":%.3f,\"sd\":%.3f,\"cv\":%.2f,\"safety\":%.2f,\"reorder\":%.2f,\"risk\":%.2f,\"unit\":\"%s\",\"critical\":%s}",
                   (i > 1 ? "," : ""), id[i], name[i], stock[i], threshold[i], cost[i],
                   mean, sd, cv, safety, reorder, risk, unit[i],
                   ((stock[i] <= threshold[i] || stock[i] <= reorder) ? "true" : "false");
        }
        printf "]\n";
    }' <<< "${raw}"
}

analytics_reorder_products_json() {
    local raw
    raw=$(db_query "SELECT p.id, p.name, p.stock, p.min_production_threshold, p.cost,
                           COALESCE(d.total, 0), COALESCE(d.sq, 0), COALESCE(d.days, 0), 'unidades'
                    FROM Products p
                    LEFT JOIN (
                        SELECT product_id,
                               SUM(day_qty) AS total,
                               SUM(day_qty * day_qty) AS sq,
                               COUNT(*) AS days
                        FROM (
                            SELECT si.product_id, date(s.timestamp) AS sale_day,
                                   SUM(si.quantity) AS day_qty
                            FROM SaleItems si
                            JOIN Sales s ON s.id = si.sale_id
                            WHERE date(s.timestamp) >= date('now', '-29 days')
                            GROUP BY si.product_id, date(s.timestamp)
                        ) daily
                        GROUP BY product_id
                    ) d ON d.product_id = p.id
                    WHERE p.active = 1
                    ORDER BY p.name;")
    _analytics_reorder_array "${raw}" 30 4
}

analytics_reorder_inputs_json() {
    local raw
    raw=$(db_query "SELECT i.id, i.name, i.stock, i.min_stock_threshold, i.cost,
                           COALESCE(d.total, 0), COALESCE(d.sq, 0), COALESCE(d.days, 0), i.unit
                    FROM Inputs i
                    LEFT JOIN (
                        SELECT input_id,
                               SUM(day_qty) AS total,
                               SUM(day_qty * day_qty) AS sq,
                               COUNT(*) AS days
                        FROM (
                            SELECT pi.input_id, date(pb.timestamp) AS batch_day,
                                   SUM(pi.quantity) AS day_qty
                            FROM ProductionInputs pi
                            JOIN ProductionBatches pb ON pb.id = pi.batch_id
                            WHERE date(pb.timestamp) >= date('now', '-29 days')
                            GROUP BY pi.input_id, date(pb.timestamp)
                        ) daily
                        GROUP BY input_id
                    ) d ON d.input_id = i.id
                    ORDER BY i.name;")
    _analytics_reorder_array "${raw}" 30 7
}

analytics_cost_ci_json() {
    local raw
    raw=$(db_query "SELECT date(timestamp), unit_cost
                    FROM ProductionBatches
                    ORDER BY timestamp;")

    LC_ALL=C awk -F'|' '
    {
        n++;
        label[n] = $1;
        v[n] = $2 + 0;
        total += v[n];
    }
    END {
        if (n == 0) {
            print "{\"labels\":[],\"values\":[],\"n\":0,\"mean\":0,\"sd\":0,\"margin\":0,\"lower\":0,\"upper\":0,\"confidence\":0.95}";
            exit;
        }
        mean = total / n;
        ss = 0;
        for (i = 1; i <= n; i++) ss += (v[i] - mean) * (v[i] - mean);
        sd = (n > 1) ? sqrt(ss / (n - 1)) : 0;
        margin = (n > 0) ? 1.96 * sd / sqrt(n) : 0;
        lower = mean - margin;
        if (lower < 0) lower = 0;

        printf "{\"labels\":[";
        for (i = 1; i <= n; i++) printf "%s\"%s\"", (i > 1 ? "," : ""), label[i];
        printf "],\"values\":[";
        for (i = 1; i <= n; i++) printf "%s%.2f", (i > 1 ? "," : ""), v[i];
        printf "],\"n\":%d,\"mean\":%.2f,\"sd\":%.2f,\"margin\":%.2f,\"lower\":%.2f,\"upper\":%.2f,\"confidence\":0.95}\n",
               n, mean, sd, margin, lower, mean + margin;
    }' <<< "${raw}"
}

analytics_hypothesis_json() {
    local product_name="Sabor estacional"
    local successes=0 trials=0

    product_name=$(db_scalar "SELECT name FROM Products WHERE is_seasonal = 1 ORDER BY id LIMIT 1;" 2>/dev/null || printf 'Sabor estacional')
    local feedback
    feedback=$(db_query "SELECT COALESCE(SUM(accepted), 0), COUNT(*)
                         FROM TastingFeedback
                         WHERE product_id = (SELECT id FROM Products WHERE is_seasonal = 1 ORDER BY id LIMIT 1);")
    if [[ -n "${feedback}" ]]; then
        IFS='|' read -r successes trials <<< "${feedback}"
    fi

    if [[ -z "${trials}" || "${trials}" == "0" ]]; then
        feedback=$(db_query "SELECT COALESCE(SUM(CASE WHEN p.is_seasonal = 1 THEN si.quantity ELSE 0 END), 0),
                                    COALESCE(SUM(si.quantity), 0)
                             FROM SaleItems si
                             JOIN Sales s ON s.id = si.sale_id
                             JOIN Products p ON p.id = si.product_id
                             WHERE date(s.timestamp) >= date('now', '-30 days');")
        [[ -n "${feedback}" ]] && IFS='|' read -r successes trials <<< "${feedback}"
    fi

    [[ "${successes}" =~ ^[0-9]+$ ]] || successes=0
    [[ "${trials}" =~ ^[0-9]+$ ]] || trials=0

    LC_ALL=C awk -v s="${successes}" -v n="${trials}" -v p0="0.40" -v product="${product_name}" '
    function erfc(x,    z, t) {
        z = (x < 0 ? -x : x);
        t = 1 / (1 + z / 2);
        t = t * exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
        return (x >= 0 ? t : 2 - t);
    }
    function normcdf(x) { return 0.5 * erfc(-x / sqrt(2)); }
    BEGIN {
        if (n <= 0) {
            printf "{\"product\":\"%s\",\"p0\":0.40,\"successes\":0,\"n\":0,\"phat\":0,\"z\":0,\"pvalue\":1,\"alpha\":0.05,\"verdict\":\"SIN DATOS\",\"approved\":false}\n", product;
            exit;
        }
        phat = s / n;
        se = sqrt(p0 * (1 - p0) / n);
        z = (se > 0) ? (phat - p0) / se : 0;
        pvalue = 1 - normcdf(z);
        approved = (pvalue < 0.05 && phat > p0);
        printf "{\"product\":\"%s\",\"p0\":0.40,\"successes\":%d,\"n\":%d,\"phat\":%.4f,\"z\":%.4f,\"pvalue\":%.6f,\"alpha\":0.05,\"verdict\":\"%s\",\"approved\":%s}\n",
               product, s, n, phat, z, pvalue,
               (approved ? "APROBAR PRODUCCIÓN MASIVA" : "MANTENER EN PRUEBA"),
               (approved ? "true" : "false");
    }'
}

analytics_basket_json() {
    local top_rows
    top_rows=$(db_query "SELECT p.id, p.name, COALESCE(SUM(si.quantity), 0) AS units
                         FROM Products p
                         JOIN SaleItems si ON si.product_id = p.id
                         JOIN Sales s ON s.id = si.sale_id
                         WHERE p.active = 1 AND date(s.timestamp) >= date('now', '-59 days')
                         GROUP BY p.id
                         ORDER BY units DESC, p.id
                         LIMIT 6;")

    if [[ -z "${top_rows}" ]]; then
        printf '{"products":[],"matrix":[],"pairs":[],"combos":[],"substitutes":[],"sales_count":0}\n'
        return
    fi

    local ids="" names="" id name units
    while IFS='|' read -r id name units; do
        [[ -z "${id}" ]] && continue
        ids+="${ids:+,}${id}"
        names+="${names:+|}${name}"
    done <<< "${top_rows}"

    local items
    items=$(db_query "SELECT si.sale_id, si.product_id, SUM(si.quantity)
                      FROM SaleItems si
                      JOIN Sales s ON s.id = si.sale_id
                      WHERE si.product_id IN (${ids})
                        AND date(s.timestamp) >= date('now', '-59 days')
                      GROUP BY si.sale_id, si.product_id
                      ORDER BY si.sale_id;")

    LC_ALL=C awk -F'|' -v ids="${ids}" -v names="${names}" '
    function esc(x) { gsub(/\\/, "\\\\", x); gsub(/"/, "\\\"", x); return x; }
    {
        sale = $1; prod = $2; qty = $3 + 0;
        if (!(sale in seen)) { seen[sale] = 1; sales[++nsales] = sale; }
        q[sale SUBSEP prod] = qty;
    }
    END {
        split(ids, id, ",");
        split(names, nm, "|");
        m = length(id);

        for (i = 1; i <= m; i++) nm[i] = esc(nm[i]);

        pc = 0;
        for (i = 1; i <= m; i++) {
            corr[i,i] = 1;
            for (j = i + 1; j <= m; j++) {
                sx = sy = sxx = syy = sxy = co = 0;
                if (nsales > 0) {
                    for (k = 1; k <= nsales; k++) {
                        x = q[sales[k] SUBSEP id[i]] + 0;
                        y = q[sales[k] SUBSEP id[j]] + 0;
                        sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y;
                        if (x > 0 && y > 0) co++;
                    }
                }
                den = (nsales > 1 ? nsales - 1 : 1);
                cov = (nsales > 0) ? (sxy - sx * sy / nsales) / den : 0;
                varx = (nsales > 0) ? (sxx - sx * sx / nsales) / den : 0;
                vary = (nsales > 0) ? (syy - sy * sy / nsales) / den : 0;
                corrval = (varx > 0 && vary > 0) ? cov / sqrt(varx * vary) : 0;
                b1 = (nsales > 0 && (sxx - sx * sx / nsales) != 0) ? (sxy - sx * sy / nsales) / (sxx - sx * sx / nsales) : 0;
                b0 = (nsales > 0) ? sy / nsales - b1 * (sx / nsales) : 0;

                corr[i,j] = corrval; corr[j,i] = corrval;
                pc++;
                pa[pc] = i; pb[pc] = j; pcorr[pc] = corrval; pcov[pc] = cov;
                pb0[pc] = b0; pb1[pc] = b1; pco[pc] = co;
            }
        }

        printf "{\"products\":[";
        for (i = 1; i <= m; i++) {
            printf "%s{\"id\":%d,\"name\":\"%s\"}", (i > 1 ? "," : ""), id[i], nm[i];
        }
        printf "],\"matrix\":[";
        for (i = 1; i <= m; i++) {
            printf "%s[", (i > 1 ? "," : "");
            for (j = 1; j <= m; j++) {
                printf "%s%.2f", (j > 1 ? "," : ""), corr[i,j];
            }
            printf "]";
        }
        printf "],\"pairs\":[";

        for (p = 1; p <= pc; p++) {
            printf "%s{\"a_id\":%d,\"a_name\":\"%s\",\"b_id\":%d,\"b_name\":\"%s\",\"corr\":%.4f,\"cov\":%.4f,\"slope\":%.4f,\"intercept\":%.4f,\"cooccurrence\":%d}",
                   (p > 1 ? "," : ""), id[pa[p]], nm[pa[p]], id[pb[p]], nm[pb[p]],
                   pcorr[p], pcov[p], pb1[p], pb0[p], pco[p];
        }
        printf "],\"sales_count\":%d,", nsales;

        for (p = 1; p <= pc; p++) ord[p] = p;
        for (i = 2; i <= pc; i++) {
            key = ord[i];
            j = i - 1;
            while (j >= 1 && pcorr[ord[j]] < pcorr[key]) { ord[j + 1] = ord[j]; j--; }
            ord[j + 1] = key;
        }

        printf "\"combos\":[";
        c = 0;
        for (i = 1; i <= pc && c < 3; i++) {
            p = ord[i];
            if (pcorr[p] <= 0 || pco[p] <= 0) continue;
            c++;
            printf "%s{\"a_name\":\"%s\",\"b_name\":\"%s\",\"corr\":%.4f,\"slope\":%.4f,\"intercept\":%.4f,\"cooccurrence\":%d}",
                   (c > 1 ? "," : ""), nm[pa[p]], nm[pb[p]], pcorr[p], pb1[p], pb0[p], pco[p];
        }
        printf "],\"substitutes\":[";

        for (p = 1; p <= pc; p++) ord[p] = p;
        for (i = 2; i <= pc; i++) {
            key = ord[i];
            j = i - 1;
            while (j >= 1 && pcorr[ord[j]] > pcorr[key]) { ord[j + 1] = ord[j]; j--; }
            ord[j + 1] = key;
        }
        c = 0;
        for (i = 1; i <= pc && c < 3; i++) {
            p = ord[i];
            if (pcorr[p] >= 0) continue;
            c++;
            printf "%s{\"a_name\":\"%s\",\"b_name\":\"%s\",\"corr\":%.4f,\"cov\":%.4f}",
                   (c > 1 ? "," : ""), nm[pa[p]], nm[pb[p]], pcorr[p], pcov[p];
        }
        printf "]}\n";
    }' <<< "${items}"
}

analytics_categories_json() {
    local raw
    raw=$(db_query "SELECT c.name, COALESCE(SUM(si.quantity * si.unit_price), 0)
                    FROM SaleItems si
                    JOIN Sales s ON s.id = si.sale_id
                    JOIN Products p ON p.id = si.product_id
                    JOIN Categories c ON c.id = p.category_id
                    GROUP BY c.id
                    ORDER BY 2 DESC;")

    LC_ALL=C awk -F'|' '
    {
        n++;
        label[n] = $1;
        value[n] = $2 + 0;
    }
    END {
        printf "{\"labels\":[";
        for (i = 1; i <= n; i++) printf "%s\"%s\"", (i > 1 ? "," : ""), label[i];
        printf "],\"values\":[";
        for (i = 1; i <= n; i++) printf "%s%.2f", (i > 1 ? "," : ""), value[i];
        printf "]}\n";
    }' <<< "${raw}"
}

analytics_low_inputs_json() {
    local rows row id name stock unit threshold deficit item out=""
    rows=$(db_query "SELECT id, name, stock, unit, min_stock_threshold,
                            ROUND(min_stock_threshold - stock, 2)
                     FROM Inputs
                     WHERE stock <= min_stock_threshold
                     ORDER BY (min_stock_threshold - stock) DESC;")
    while IFS='|' read -r id name stock unit threshold deficit; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"stock":%s,"unit":%s,"threshold":%s,"deficit":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_number "${stock}")" \
            "$(json_quote "${unit}")" "$(json_number "${threshold}")" "$(json_number "${deficit}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"
    printf '[%s]' "${out}"
}

analytics_low_products_json() {
    local rows row id name stock threshold deficit item out=""
    rows=$(db_query "SELECT id, name, stock, min_production_threshold,
                            (min_production_threshold - stock)
                     FROM Products
                     WHERE active = 1 AND stock <= min_production_threshold
                     ORDER BY (min_production_threshold - stock) DESC;")
    while IFS='|' read -r id name stock threshold deficit; do
        [[ -z "${id}" ]] && continue
        item=$(printf '{"id":%d,"name":%s,"stock":%s,"threshold":%s,"deficit":%s}' \
            "${id}" "$(json_quote "${name}")" "$(json_number "${stock}")" \
            "$(json_number "${threshold}")" "$(json_number "${deficit}")")
        out+="${out:+,}${item}"
    done <<< "${rows}"
    printf '[%s]' "${out}"
}

analytics_alerts_json() {
    local inputs products count
    inputs=$(analytics_low_inputs_json)
    products=$(analytics_low_products_json)
    count=$(db_scalar "SELECT (SELECT COUNT(*) FROM Inputs WHERE stock <= min_stock_threshold) +
                              (SELECT COUNT(*) FROM Products WHERE active = 1 AND stock <= min_production_threshold);" 2>/dev/null || printf '0')
    printf '{"inputs":%s,"products":%s,"count":%s}' "${inputs}" "${products}" "$(json_number "${count:-0}")"
}

analytics_kpis_json() {
    local revenue sales_count units avg_ticket active_products inventory_value customers low_count
    revenue=$(db_scalar "SELECT COALESCE(SUM(total_amount), 0) FROM Sales WHERE date(timestamp) >= date('now', '-29 days');" 2>/dev/null || printf '0')
    sales_count=$(db_scalar "SELECT COUNT(*) FROM Sales WHERE date(timestamp) >= date('now', '-29 days');" 2>/dev/null || printf '0')
    units=$(db_scalar "SELECT COALESCE(SUM(si.quantity), 0)
                       FROM SaleItems si JOIN Sales s ON s.id = si.sale_id
                       WHERE date(s.timestamp) >= date('now', '-29 days');" 2>/dev/null || printf '0')
    active_products=$(db_scalar "SELECT COUNT(*) FROM Products WHERE active = 1;" 2>/dev/null || printf '0')
    inventory_value=$(db_scalar "SELECT COALESCE(SUM(stock * cost), 0) FROM Products WHERE active = 1;" 2>/dev/null || printf '0')
    customers=$(db_scalar "SELECT COUNT(*) FROM Customers;" 2>/dev/null || printf '0')
    low_count=$(db_scalar "SELECT (SELECT COUNT(*) FROM Inputs WHERE stock <= min_stock_threshold) +
                                  (SELECT COUNT(*) FROM Products WHERE active = 1 AND stock <= min_production_threshold);" 2>/dev/null || printf '0')

    revenue="${revenue:-0}"
    sales_count="${sales_count:-0}"
    units="${units:-0}"
    avg_ticket=$(LC_ALL=C awk -v r="${revenue}" -v n="${sales_count}" 'BEGIN { printf "%.2f", (n > 0 ? r / n : 0) }')

    local revenue_fmt inventory_fmt
    revenue_fmt=$(LC_ALL=C awk -v v="${revenue}" 'BEGIN { printf "%.2f", v + 0 }')
    inventory_fmt=$(LC_ALL=C awk -v v="${inventory_value}" 'BEGIN { printf "%.2f", v + 0 }')

    printf '{"revenue":%s,"sales_count":%s,"units":%s,"avg_ticket":%s,"active_products":%s,"inventory_value":%s,"customers":%s,"low_stock_count":%s}' \
        "$(json_number "${revenue_fmt}")" "$(json_number "${sales_count}")" \
        "$(json_number "${units}")" "$(json_number "${avg_ticket}")" \
        "$(json_number "${active_products}")" "$(json_number "${inventory_fmt}")" \
        "$(json_number "${customers}")" "$(json_number "${low_count:-0}")"
}

analytics_dashboard_json() {
    local daily binomial kpis alerts reorder_products reorder_inputs cost_ci hypothesis basket categories
    local products customers suppliers categories_options inputs recent_sales journal

    daily=$(analytics_daily_json)
    binomial=$(analytics_binomial_json)
    kpis=$(analytics_kpis_json)
    alerts=$(analytics_alerts_json)
    reorder_products=$(analytics_reorder_products_json)
    reorder_inputs=$(analytics_reorder_inputs_json)
    cost_ci=$(analytics_cost_ci_json)
    hypothesis=$(analytics_hypothesis_json)
    basket=$(analytics_basket_json)
    categories=$(analytics_categories_json)

    products=$(api_list_products_json 1)
    customers=$(api_list_customers_json)
    suppliers=$(api_list_suppliers_json)
    categories_options=$(api_list_categories_json)
    inputs=$(api_list_inputs_json)
    recent_sales=$(api_recent_sales_json 8)
    journal=$(api_journal_json 10)

    printf '{"generated_at":%s,"daily":%s,"binomial":%s,"kpis":%s,"alerts":%s,"reorder_products":%s,"reorder_inputs":%s,"cost_ci":%s,"hypothesis":%s,"basket":%s,"categories":%s,"products":%s,"customers":%s,"suppliers":%s,"categories_options":%s,"inputs":%s,"recent_sales":%s,"journal":%s}\n' \
        "$(json_quote "$(date '+%Y-%m-%d %H:%M:%S')")" \
        "${daily}" "${binomial}" "${kpis}" "${alerts}" \
        "${reorder_products}" "${reorder_inputs}" "${cost_ci}" \
        "${hypothesis}" "${basket}" "${categories}" \
        "${products}" "${customers}" "${suppliers}" "${categories_options}" "${inputs}" \
        "${recent_sales}" "${journal}"
}
