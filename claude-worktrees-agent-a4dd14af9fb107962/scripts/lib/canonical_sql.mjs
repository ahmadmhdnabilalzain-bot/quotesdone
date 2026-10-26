// WHAT PRODUCTION RUNS, as a replayable SQL text (accountant, 21 Sep 2026).
//
// A check that replays whole historical scripts/sql files re-runs every routine those files EVER
// defined, including bodies a later file replaced. Measured 21 Sep 2026: payments_are_the_accountant
// failed on main with "column l.iban_doc_path does not exist" because it replayed
// the_it_engineer_knows_what_should_be_backed_up_and_closes_the_loop.sql, whose LANGUAGE SQL routine
// (validated at create) reads a column that
// the_last_traces_of_bank_details_negotiations_and_the_network_map_leave.sql dropped, redefining the
// routine without it (#777). The check was red on code production no longer runs.
//
// canonicalReplay(files) returns, for every routine the given files define, the CANONICAL definition:
// the last one in scripts/sql/MANIFEST.txt order (the order files are applied), skipping a definition
// scripts/sql/SUPERSEDED.txt retires. It is the rule scripts/checks/canonical_routine_manifest.mjs
// uses, with one difference: a pending file (scripts/sql/pending/) is included, because a pull request's own change is
// pending until the coordinator applies it and the replay exists to test that change before it is.
// Only CREATE FUNCTION statements are emitted, in MANIFEST order, a bare `create` made `create or
// replace`; tables, views and triggers are production's own (canonical_routine_manifest proves the
// repository's routines are what is live).
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const lines = (p) => (existsSync(join(REPO, p))
  ? read(p).split(/\r?\n/).map((s) => s.replace(/^﻿/, '').trim()) : []);
// A routine's identity is its name and argument TYPES: `(bigint, text)` and `(p_id bigint, p_note
// text default null)` are one routine (measured: fn_refund_decide, fn_ceo_seat_board and four others
// are spelled both ways across files), so names, defaults, OUT arguments and type aliases are dropped.
const ALIAS = { int: 'integer', int4: 'integer', int8: 'bigint', int2: 'smallint', bool: 'boolean',
  timestamptz: 'timestamp with time zone', varchar: 'character varying', float8: 'double precision', decimal: 'numeric' };
const TYPE_START = new Set(['timestamp', 'double', 'character', 'time', 'bit', 'interval']);
function argTypes(args) {
  const parts = []; let depth = 0, cur = '';
  for (const ch of args) {
    if (ch === '(') depth++; else if (ch === ')') depth--;
    if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; } else cur += ch;
  }
  parts.push(cur);
  return parts.map((a) => a.toLowerCase().replace(/\s+(default\b|=)[\s\S]*$/, '').replace(/\s+/g, ' ').trim())
    .filter((a) => a && !/^out\s/.test(a))
    .map((a) => {
      const w = a.replace(/^(in|inout|variadic)\s+/, '').split(' ');
      const t = (w.length > 1 && !TYPE_START.has(w[0]) ? w.slice(1) : w).join(' ').replace(/^public\./, '');
      return ALIAS[t] ?? t;
    }).join(',');
}

// Every CREATE FUNCTION public.<name>(...) statement in a SQL text, with its full source.
export function definitions(text) {
  const out = [];
  for (const m of text.matchAll(/create\s+(or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\s*\(/gi)) {
    if (text.slice(text.lastIndexOf('\n', m.index) + 1, m.index).includes('--')) continue;   // a comment
    const open = m.index + m[0].length - 1;
    let depth = 0, close = -1;
    for (let i = open; i < text.length; i++) {
      if (text[i] === '(') depth++;
      else if (text[i] === ')' && --depth === 0) { close = i; break; }
    }
    if (close < 0) continue;
    const tag = text.slice(close).match(/\bas\s+(\$[A-Za-z0-9_]*\$)/i);
    if (!tag) continue;
    const end = text.indexOf(tag[1], close + tag.index + tag[0].length);
    const semi = end < 0 ? -1 : text.indexOf(';', end + tag[1].length);
    if (semi < 0) continue;
    const stmt = text.slice(m.index, semi + 1);
    const name = m[2].toLowerCase();
    out.push({ name, key: `${name}(${argTypes(text.slice(open + 1, close))})`,
      stmt: m[1] ? stmt : stmt.replace(/^create\s+function/i, 'create or replace function') });
  }
  return out;
}

// The canonical definition of every routine `files` (scripts/sql basenames) define, as one SQL text.
export function canonicalReplay(files) {
  const retired = new Set(lines('scripts/sql/SUPERSEDED.txt').filter((l) => l && !l.startsWith('#'))
    .map((l) => l.split('::').map((s) => s.trim())).map(([f, r]) => `${f}::${(r || '').toLowerCase()}`));
  const wanted = new Set(files.flatMap((f) => definitions(read(`scripts/sql/${f}`)).map((d) => d.name)));
  const winner = new Map();   // name(args) -> the last definition in MANIFEST order
  lines('scripts/sql/MANIFEST.txt').forEach((p, pos) => {
    if (!/^scripts\/sql\/[^/]+\.sql$/.test(p) || !existsSync(join(REPO, p))) return;
    for (const d of definitions(read(p))) {
      if (wanted.has(d.name) && !retired.has(`${p}::${d.name}`)) winner.set(d.key, { pos, file: p, stmt: d.stmt });
    }
  });
  return [...winner.values()].sort((a, b) => a.pos - b.pos)
    .map((w) => `-- canonical: ${w.file}\n${w.stmt}`).join('\n\n');
}
