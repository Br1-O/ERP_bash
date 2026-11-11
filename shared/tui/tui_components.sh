#!/usr/bin/env bash

[[ -n "${_SHARED_TUI_COMPONENTS_LOADED:-}" ]] && return 0
declare -g _SHARED_TUI_COMPONENTS_LOADED=1

tui_require() {
    command -v whiptail >/dev/null 2>&1 || { 
        printf "Error: whiptail no está instalado (se requiere para la interfaz TUI).\n" >&2
        return 1
    }
    [[ -t 0 && -t 1 ]] || { 
        printf "Error: La interfaz TUI requiere una terminal interactiva (TTY).\n" >&2
        return 1
    }
}

tui_msg() {
    local title="$1"
    local text="$2"
    whiptail --title "$title" --msgbox "$text" 12 60 || true
}

tui_confirm() {
    local title="$1"
    local text="$2"
    whiptail --title "$title" --yesno "$text" 10 60
    return $?
}

tui_input() {
    local title="$1"
    local prompt="$2"
    local var_name="$3"
    
    # Validación defensiva para evitar el error de identificador vacío
    if [[ -z "$var_name" ]]; then
        return 1
    fi

    local -n _out="$var_name"
    local val
    if ! val="$(whiptail --title "$title" --inputbox "$prompt" 10 50 3>&1 1>&2 2>&3)"; then
        return 1
    fi
    _out="$val"
}

tui_pass() {
    local title="$1"
    local prompt="$2"
    local var_name="$3"

    if [[ -z "$var_name" ]]; then
        return 1
    fi

    local -n _out="$var_name"
    local val
    if ! val="$(whiptail --title "$title" --passwordbox "$prompt" 10 50 3>&1 1>&2 2>&3)"; then
        return 1
    fi
    _out="$val"
}

tui_run_show() {
    local title="$1"
    shift
    local tmp out
    tmp="$(mktemp)" || return 1
    "$@" >"$tmp" 2>&1 || true
    out="$(cat "$tmp")"
    rm -f "$tmp"
    [[ -z "$out" ]] && out="(Operación completada sin mensaje de salida)"
    whiptail --title "$title" --msgbox "$out" 14 65 || true
    return 0
}

tui_text_show() {
    local title="$1"
    local tmp lines
    shift
    tmp="$(mktemp)" || return 1
    "$@" >"$tmp" 2>&1 || true
    lines="$(wc -l <"$tmp")"
    if (( lines <= 12 )); then
        whiptail --title "$title" --scrolltext --msgbox "$(cat "$tmp")" 22 150 || true
    else
        whiptail --title "$title" --textbox "$tmp" 22 150 || true
    fi
    rm -f "$tmp"
}