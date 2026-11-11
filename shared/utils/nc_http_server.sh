start_local_http_server() {
    local -n pid_ref=$1
    local -i port=${2:-8080}
    local html_file="$3"

    if (( pid_ref > 0 )) && kill -0 "$pid_ref" 2>/dev/null; then
        printf "\nEl servidor ya está activo (PID: %d).\n" "$pid_ref"
        return 1
    fi

    if [[ ! -f "$html_file" ]]; then
        printf "\nError: No se encontró el archivo %s para servir.\n\n" "$html_file"
        return 1
    fi

    fuser -k -9 "$port/tcp" >/dev/null 2>&1

    (
        trap 'pkill -P $$; exit 0' TERM INT EXIT
        while true; do
            {
                printf "HTTP/1.1 200 OK\r\n"
                printf "Content-Type: text/html; charset=UTF-8\r\n"
                printf "Content-Length: %d\r\n" "$(wc -c < "$html_file")"
                printf "Cache-Control: no-cache, no-store, must-revalidate\r\n"
                printf "Pragma: no-cache\r\n"
                printf "Expires: 0\r\n"
                printf "Connection: close\r\n\r\n"
                cat "$html_file"
            } | nc -l -p "$port" -q 1 >/dev/null 2>&1
        done
    ) &

    pid_ref=$!

    local local_ip
    local_ip=$(hostname -I | awk '{print $1}')
    
    printf "\nServidor HTTP iniciado (PID: %d).\n" "$pid_ref"
    printf "   ➜ Acceso local:   http://localhost:%d\n" "$port"
    printf "   ➜ Red Local (LAN): http://%s:%d\n\n" "$local_ip" "$port"
}

stop_local_http_server() {
    local -n pid_ref=$1
    local -i port=${2:-8080}

    set +m 2>/dev/null

    (
        pkill -9 -f "nc -l -p $port" 2>/dev/null

        if (( pid_ref > 0 )); then
            kill -9 "$pid_ref" 2>/dev/null
            kill -9 -"$pid_ref" 2>/dev/null
            wait "$pid_ref" 2>/dev/null
        fi

        fuser -k -9 "$port/tcp" 2>/dev/null
    ) >/dev/null 2>&1

    pid_ref=0
    printf "\nServidor detenido correctamente.\n\n"
}