#!/usr/bin/env bash

SQLITE_USERS_PATH="shared/data/datos_usuarios.db"

init_users_storage() {
    mkdir -p "$(dirname "$SQLITE_USERS_PATH")"
    sqlite3 "$SQLITE_USERS_PATH" >/dev/null <<EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS Users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL CHECK (length(username) <= 50),
    password TEXT NOT NULL CHECK (length(password) <= 100)
);
EOF
}

db_insert_user() {
    local username="$1"
    local hashed_password="$2"
    init_users_storage
    
    local safe_username="${username//\'/\'\'}"
    sqlite3 "$SQLITE_USERS_PATH" "INSERT INTO Users (username, password) VALUES ('$safe_username', '$hashed_password');" 2>/dev/null
    return $?
}

db_username_exists() {
    local entered_username="$1"
    [[ ! -f "$SQLITE_USERS_PATH" ]] && return 2

    local safe_username="${entered_username//\'/\'\'}"
    local count=0
    read -r count < <(sqlite3 "$SQLITE_USERS_PATH" "SELECT COUNT(*) FROM Users WHERE username='$safe_username';")

    (( count > 0 )) && return 0 || return 1
}

db_find_password_by_username() {
    local entered_username="$1"
    local -n _out_pass_ref=$2
    [[ ! -f "$SQLITE_USERS_PATH" ]] && return 1

    local safe_username="${entered_username//\'/\'\'}"
    _out_pass_ref=""
    read -r _out_pass_ref < <(sqlite3 "$SQLITE_USERS_PATH" "SELECT password FROM Users WHERE username='$safe_username';")

    [[ -n "$_out_pass_ref" ]] && return 0 || return 1
}