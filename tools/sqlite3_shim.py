#!/usr/bin/env python3
"""Minimal sqlite3 shell used as a fallback when the CLI is unavailable.

The ERP keeps a persistent sqlite3 process and writes SQL statements followed
by a marker SELECT.  This shim implements just enough of the CLI protocol:
statements are accumulated until sqlite3.complete_statement() accepts them,
rows are printed with a configurable separator, and errors go to stderr.
"""

from __future__ import annotations

import os
import sqlite3
import sys


def parse_args(argv: list[str]) -> tuple[str, str]:
    separator = "|"
    database = ":memory:"
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "-separator" and i + 1 < len(argv):
            separator = argv[i + 1]
            i += 2
            continue
        if arg.startswith("-separator="):
            separator = arg.split("=", 1)[1]
            i += 1
            continue
        if arg in ("-batch", "-noheader", "-header", "-echo", "-bail"):
            i += 1
            continue
        if arg in ("-cmd", "-init") and i + 1 < len(argv):
            i += 2
            continue
        if arg.startswith("-"):
            i += 1
            continue
        database = arg
        i += 1
    return database, separator


def format_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.hex()
    return str(value)


def split_statements(buffer: str) -> tuple[list[str], str]:
    statements: list[str] = []
    current = ""
    for char in buffer:
        current += char
        if char == ";" and sqlite3.complete_statement(current):
            statement = current.strip()
            if statement:
                statements.append(statement)
            current = ""
    return statements, current


def execute_statement(cursor: sqlite3.Cursor, statement: str, separator: str) -> None:
    cursor.execute(statement)
    if cursor.description:
        for row in cursor.fetchall():
            sys.stdout.write(separator.join(format_value(value) for value in row) + "\n")
        sys.stdout.flush()


def main() -> int:
    database, separator = parse_args(sys.argv[1:])
    if database != ":memory:":
        parent = os.path.dirname(os.path.abspath(database))
        if parent:
            os.makedirs(parent, exist_ok=True)

    connection = sqlite3.connect(database, isolation_level=None)
    cursor = connection.cursor()
    buffer = ""

    for raw_line in sys.stdin:
        line = raw_line.rstrip("\n")
        stripped = line.strip()

        if not buffer.strip() and stripped.startswith("."):
            command = stripped.lower()
            if command in (".quit", ".exit"):
                break
            if command.startswith(".separator "):
                parts = stripped.split(None, 1)
                if len(parts) == 2:
                    separator = parts[1].strip("\"'")
            continue

        buffer += line + "\n"
        statements, buffer = split_statements(buffer)
        for statement in statements:
            try:
                execute_statement(cursor, statement, separator)
            except sqlite3.Error as exc:
                sys.stdout.flush()
                print(f"Error: {exc}", file=sys.stderr, flush=True)

    connection.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
