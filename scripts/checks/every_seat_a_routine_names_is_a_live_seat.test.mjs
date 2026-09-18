// EVERY SEAT A ROUTINE NAMES IS A LIVE SEAT — read out of org_agents, never out of a copy.
//
// WHY THIS EXISTS (18 Sep 2026). fn_supplier_sanctions_screen opened its two tasks on the assignees
// 'compliance_mgr' and 'bd'. Those were seats of the organisation chart the founder removed on
// 7 Sep 2026, and org_tasks.assigned_agent has a foreign key to org_agents, so the routine did not
// degrade on its first real sanctions hit — it raised 23503 and took the whole screening run with it.
// It looked healthy for eleven days only because it has never matched anybody: a screen that finds
// nothing never reaches the line that writes the seat name.
//
// That is the shape this file refuses to let happen again: code that addresses a colleague who does
// not exist, on a path that has not run yet.
//
// WHAT IT ASSERTS, AND HOW IT AVOIDS THE TWO WAYS A CHECK LIKE THIS GOES WRONG.
//   * The list of valid seats is READ FROM public.org_agents on every run. A hard-coded copy would
//     itself go stale the next time a seat is added or retired, which is the defect wearing a
//     different hat. The list of columns that carry a seat is read live too: every column with a
//     foreign key to org_agents, plus the seat-carrying columns that have no foreign key.
//   * It reads the LIVE bodies (pg_proc.prosrc) and the edge functions, not the history in
//     scripts/sql. A file that defined a routine which has since been dropped is history; it cannot
//     open a task on anybody.
//   * COMMENTS ARE STRIPPED BEFORE ANYTHING IS MATCHED. Twice in one session a check in this
//     repository failed against correct code because the comment explaining the fix quoted the
//     forbidden text. The two positive controls at the bottom prove both halves: a synthetic INSERT
//     naming a dead seat MUST be found, and the same text inside a comment MUST NOT be.
//   * It matches by POSITION, not by proximity. In `insert into t (a, b, c) values (x, y, z)` the
//     literal is only judged when it lands in a column that names a seat, so the 'assigned' and
//     'compliance_check' sitting beside it in the same tuple are not seat names and are not read as
//     any. A comparison (`where agent_key = 'bookkeeper'`) is NOT a finding: a lookup against
//     org_agents cannot orphan a row, and fn_receipt_hand_to_bookkeeper legitimately prefers a seat
//     that may not exist and falls back to the accountant.
//
// A finding here is not style. It is a row that will be refused, or a hand-off addressed to nobody.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// THE CI CHECKS JOB HAS NO MANAGEMENT TOKEN. Without one this would fail on the connection rather
// than on the subject, and a red run would say nothing about seats. The estate's convention is to
// skip loudly so that a green CI never reads as "verified against production" when it was not.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// Seat-carrying columns that have NO foreign key to org_agents and so fail silently instead of
// loudly. `to_role` is deliberately absent: measured on production it holds party roles (customer,
// supplier, founder, admin), not seats, so treating it as a seat column would flag correct code.
// `decided_by` is absent for the same reason — it holds the name of whatever resolved the row,
// routinely a routine name such as 'fn_receipt_hand_to_bookkeeper'.
const SEAT_COLUMNS_WITHOUT_A_FOREIGN_KEY = [
  'assigned_agent', 'raised_by', 'owner_seat', 'owner_role', 'from_seat', 'to_seat', 'messenger_seat',
];
// it_engineer_finding.raised_by is written as '<seat>.<topic>' (it_engineer.backup_gap), so only the
// part before the first dot is the seat.
const PREFIXED = new Set(['raised_by']);
const SEAT_SHAPED = /^[a-z][a-z0-9_]{1,40}$/;

function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ')
    .split('\n')
    .map(line => line.replace(/--.*$/, '').replace(/(^|[^:])\/\/.*$/, '$1'))
    .join('\n');
}

// Split a VALUES tuple on its top-level commas. Parentheses AND square brackets both nest — a body
// carrying `array['a','b']` shifted every column by one before the brackets were counted, which is
// how a positional matcher quietly starts judging the wrong column.
function splitTopLevel(body) {
  const out = [];
  let cur = '', depth = 0, quoted = false;
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (ch === "'") {
      if (quoted && body[i + 1] === "'") { cur += "''"; i++; continue; }
      quoted = !quoted; cur += ch; continue;
    }
    if (!quoted && (ch === '(' || ch === '[')) depth++;
    if (!quoted && (ch === ')' || ch === ']')) depth--;
    if (!quoted && depth === 0 && ch === ',') { out.push(cur); cur = ''; continue; }
    cur += ch;
  }
  out.push(cur);
  return out;
}

export function seatLiteralsWritten(raw, seatColumns) {
  const text = stripComments(raw);
  const found = [];
  const record = (column, literal, how) => {
    const value = PREFIXED.has(column) ? literal.split('.')[0] : literal;
    if (SEAT_SHAPED.test(value)) found.push({ column, value, how });
  };

  // Find the parenthesis that closes the one opening at `open`, ignoring quoted text.
  const closingParen = (s, open) => {
    let depth = 0, quoted = false;
    for (let i = open; i < s.length; i++) {
      const ch = s[i];
      if (ch === "'") { if (quoted && s[i + 1] === "'") { i++; continue; } quoted = !quoted; continue; }
      if (quoted) continue;
      if (ch === '(') depth++;
      else if (ch === ')') { depth--; if (depth === 0) return i; }
    }
    return -1;
  };

  // 1. insert into t (cols) values (vals), (vals), … — judged by position, EVERY tuple. A multi-row
  //    insert whose second tuple carried the dead seat used to be missed: the scan read the first
  //    tuple and the regex resumed just after the VALUES keyword.
  const insert = /insert\s+into\s+([a-z0-9_."]+)\s*\(([^()]*?)\)\s*values\s*/gis;
  let m;
  while ((m = insert.exec(text))) {
    const columns = m[2].split(',').map(s => s.trim().replace(/"/g, '').split('.').pop().toLowerCase());
    let cursor = m.index + m[0].length;
    if (!columns.some(c => seatColumns.has(c))) { insert.lastIndex = cursor; continue; }
    while (text[cursor] === '(') {
      const close = closingParen(text, cursor);
      if (close < 0) break;
      const values = splitTopLevel(text.slice(cursor + 1, close));
      columns.forEach((column, i) => {
        if (!seatColumns.has(column)) return;
        const literal = /^'([^']*)'(?:::text)?$/.exec((values[i] || '').trim());
        if (literal) record(column, literal[1], `insert ${m[1]}.${column}`);
      });
      const next = text.slice(close + 1).match(/^\s*,\s*/);   // the next tuple of the same insert
      if (!next) { cursor = close + 1; break; }
      cursor = close + 1 + next[0].length;
    }
    insert.lastIndex = cursor;
  }

  // 2. update … SET col = 'literal'. Only the SET clause is read, because `where agent_key = 'x'`
  //    is a lookup and a lookup cannot orphan anything. The clause ends at the first TOP-LEVEL
  //    where/returning/semicolon: a `where` inside a subquery in the SET list used to end it early
  //    and hide every assignment after it.
  const update = /\bupdate\s+[a-z0-9_."]+\s+set\b/gis;
  const assigned = new RegExp(`\\b(${[...seatColumns].join('|')})\\s*=\\s*'([^']*)'`, 'gi');
  while ((m = update.exec(text))) {
    let depth = 0, quoted = false, i = m.index + m[0].length;
    const start = i;
    for (; i < text.length; i++) {
      const ch = text[i];
      if (ch === "'") { if (quoted && text[i + 1] === "'") { i++; continue; } quoted = !quoted; continue; }
      if (quoted) continue;
      if (ch === '(') depth++;
      else if (ch === ')') depth--;
      else if (depth === 0 && (ch === ';' || /\s/.test(ch)) && /^\s*(where|returning)\b/i.test(text.slice(i))) break;
      else if (depth === 0 && ch === ';') break;
    }
    const clause = text.slice(start, i);
    let a;
    assigned.lastIndex = 0;
    while ((a = assigned.exec(clause))) record(a[1].toLowerCase(), a[2], `set ${a[1].toLowerCase()}`);
    update.lastIndex = i;
  }
  return found;
}

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (/\.(ts|mjs|js)$/.test(entry) && !/vendor/.test(full)) out.push(full);
  }
  return out;
}

test('every seat a live routine or edge function writes is a row in org_agents', { skip: SKIP }, async () => {
  const [row] = await sql(`
    select (select array_agg(agent_key order by agent_key) from public.org_agents) as seats,
           (select array_agg(distinct a.attname)
              from pg_constraint c
              join lateral unnest(c.conkey) k(attnum) on true
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
             where c.contype = 'f' and c.confrelid = 'public.org_agents'::regclass) as fk_columns,
           (select jsonb_agg(jsonb_build_object('sig', p.oid::regprocedure::text, 'src', p.prosrc))
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.prokind in ('f', 'p')) as routines`);

  // A management API array can arrive as a Postgres array literal rather than a JS array.
  const asArray = v => Array.isArray(v) ? v : String(v || '').replace(/^\{|\}$/g, '').split(',').filter(Boolean);
  const seats = asArray(row.seats);
  assert.ok(seats.length > 0, 'org_agents is empty, so this check cannot mean anything');
  const live = new Set(seats);
  const seatColumns = new Set([...asArray(row.fk_columns), ...SEAT_COLUMNS_WITHOUT_A_FOREIGN_KEY]);

  const sources = [
    ...row.routines.map(r => ({ where: `live routine ${r.sig}`, text: r.src })),
    ...walk(join(REPO, 'supabase', 'functions')).map(f => ({
      where: 'edge ' + f.slice(REPO.length + 1).replace(/\\/g, '/'), text: readFileSync(f, 'utf8'),
    })),
  ];

  const findings = [];
  for (const source of sources) {
    for (const hit of seatLiteralsWritten(source.text, seatColumns)) {
      if (!live.has(hit.value)) findings.push(`${source.where}: ${hit.how} = '${hit.value}'`);
    }
  }
  assert.deepEqual(findings, [],
    `these write a seat that is not in org_agents (${seats.join(', ')}); the row will be refused or ` +
    `the work addressed to nobody:\n  ${findings.join('\n  ')}`);
});

// POSITIVE CONTROLS. A check that has never been seen to fail is a claim, not a guard.
test('the matcher finds a dead seat written into a seat column', () => {
  const found = seatLiteralsWritten(
    `insert into public.org_tasks (dept_key, title, status, tier, action_class, assigned_agent)
     values ('legal', v_title, 'assigned', 'supervised', 'compliance_check', 'compliance_mgr');`,
    new Set(['assigned_agent']));
  assert.deepEqual(found.map(f => f.value), ['compliance_mgr']);
});

test('the matcher does not read a comment that describes the rule as code that breaks it', () => {
  const sqlComment = `-- never write assigned_agent = 'compliance_mgr': that seat does not exist
     /* insert into public.org_tasks (assigned_agent) values ('bd'); */`;
  assert.deepEqual(seatLiteralsWritten(sqlComment, new Set(['assigned_agent'])), []);
  const tsComment = `// owner_seat = 'compliance_mgr' was the old organisation chart\nconst x = 1;`;
  assert.deepEqual(seatLiteralsWritten(tsComment, new Set(['owner_seat'])), []);
});

test('the matcher finds a dead seat moved onto a row by an update', () => {
  const found = seatLiteralsWritten(
    `update public.org_tasks set assigned_agent = 'compliance_mgr', updated_at = now() where id = 7;`,
    new Set(['assigned_agent']));
  assert.deepEqual(found.map(f => f.value), ['compliance_mgr']);
});

test('the matcher reads every tuple of a multi-row insert, not just the first', () => {
  const found = seatLiteralsWritten(
    `insert into public.org_tasks (title, assigned_agent) values ('a', 'ceo'), ('b', 'compliance_mgr');`,
    new Set(['assigned_agent']));
  assert.deepEqual(found.map(f => f.value), ['ceo', 'compliance_mgr']);
});

test('a where inside a subquery does not end the SET clause early', () => {
  const found = seatLiteralsWritten(
    `update public.org_tasks set detail = (select x from y where z = 1), assigned_agent = 'bd' where id = 3;`,
    new Set(['assigned_agent']));
  assert.deepEqual(found.map(f => f.value), ['bd']);
});

test('a lookup against org_agents is not a finding', () => {
  const lookup = `select o.agent_key into v_owner from public.org_agents o
                   where o.agent_key in ('bookkeeper', 'accountant') and o.active;`;
  assert.deepEqual(seatLiteralsWritten(lookup, new Set(['agent_key'])), []);
});
