#!/usr/bin/env node
/*
 * Shell SQLite mínimo para el ERP cuando el binario sqlite3 no está
 * disponible. Usa node:sqlite (incluido en Node.js) y reproduce el protocolo
 * que espera db_singleton.sh: acumula SQL hasta un SELECT marcador y responde
 * las filas con el separador configurado.
 */

'use strict';

const { DatabaseSync } = require('node:sqlite');
const readline = require('node:readline');

function parseArgs(argv) {
    let database = ':memory:';
    let separator = '|';
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '-separator' && i + 1 < argv.length) {
            separator = argv[i + 1];
            i += 1;
            continue;
        }
        if (arg.startsWith('-separator=')) {
            separator = arg.slice('-separator='.length);
            continue;
        }
        if (['-batch', '-noheader', '-header', '-echo', '-bail'].includes(arg)) continue;
        if ((arg === '-cmd' || arg === '-init') && i + 1 < argv.length) {
            i += 1;
            continue;
        }
        if (arg.startsWith('-')) continue;
        database = arg;
    }
    return { database, separator };
}

function formatValue(value) {
    if (value === null || value === undefined) return '';
    if (value instanceof Uint8Array) return Buffer.from(value).toString('hex');
    return String(value);
}

function printRows(rows, separator) {
    return rows.map((row) => row.map(formatValue).join(separator)).join('\n');
}

function isQuery(sql) {
    const body = sql.replace(/^\s*(?:--[^\n]*\n|\/\*[\s\S]*?\*\/|\s)*/, '');
    return /^(SELECT|WITH|PRAGMA|EXPLAIN|VALUES)\b/i.test(body);
}

function hasMultipleStatements(sql) {
    let quote = '';
    let lineComment = false;
    let blockComment = false;
    let statements = 0;
    for (let i = 0; i < sql.length; i += 1) {
        const char = sql[i];
        const next = sql[i + 1];
        if (lineComment) {
            if (char === '\n') lineComment = false;
            continue;
        }
        if (blockComment) {
            if (char === '*' && next === '/') {
                blockComment = false;
                i += 1;
            }
            continue;
        }
        if (quote) {
            if (char === quote) {
                if (next === quote) i += 1;
                else quote = '';
            }
            continue;
        }
        if (char === '-' && next === '-') {
            lineComment = true;
            i += 1;
            continue;
        }
        if (char === '/' && next === '*') {
            blockComment = true;
            i += 1;
            continue;
        }
        if (char === '\'' || char === '"' || char === '`') {
            quote = char;
            continue;
        }
        if (char === ';' && sql.slice(i + 1).trim() !== '') statements += 1;
    }
    return statements > 0;
}

function execute(db, sql, separator) {
    const trimmed = sql.trim();
    if (!trimmed) return '';
    if (!isQuery(trimmed) || hasMultipleStatements(trimmed)) {
        db.exec(trimmed);
        return '';
    }
    const statement = db.prepare(trimmed);
    if (typeof statement.setReturnArrays === 'function') {
        statement.setReturnArrays(true);
        const rows = statement.all();
        if (!rows.length) return '';
        return printRows(rows, separator);
    }
    const rows = statement.all();
    if (!rows.length) return '';
    const columns = statement.columns().map((column) => column.name);
    return printRows(rows.map((row) => columns.map((column) => row[column])), separator);
}

function main() {
    const { database, separator } = parseArgs(process.argv.slice(2));
    const db = new DatabaseSync(database);
    let buffer = '';
    let separatorValue = separator;

    const reader = readline.createInterface({
        input: process.stdin,
        crlfDelay: Infinity
    });
    reader.on('line', handleLine);
    reader.on('close', () => {
        try {
            db.close();
        } catch (error) {
            process.stderr.write(`Error: ${error.message}\n`);
        }
    });

    function handleLine(line) {
        const trimmed = line.trim();
        if (!bufferStarted() && trimmed.startsWith('.')) {
            const command = trimmed.toLowerCase();
            if (command === '.quit' || command === '.exit') {
                db.close();
                process.exit(0);
            }
            if (command.startsWith('.separator ')) {
                const parts = trimmed.split(/\s+/, 2);
                if (parts.length === 2) separatorValue = parts[1].replace(/^["']|["']$/g, '');
            }
            return;
        }

        const markerMatch = trimmed.match(/^SELECT\s+'([^']+)';?$/);
        if (markerMatch) {
            const marker = markerMatch[1];
            let output = '';
            try {
                output = execute(db, buffer, separatorValue);
            } catch (error) {
                process.stderr.write(`Error: ${error.message}\n`);
            }
            buffer = '';
            if (output) process.stdout.write(`${output}\n`);
            process.stdout.write(`${marker}\n`);
            return;
        }

        buffer += `${line}\n`;
    }

    function bufferStarted() {
        return buffer.trim().length > 0;
    }
}

main();
