// NO SCRIPT SENDS DDL, OR A ROLLED-BACK WRITE, TO PRODUCTION EXCEPT THROUGH THE GUARD (it_engineer, 13 Nov 2026). Offline.
//
// On 13 Nov 2026 rolled-back rehearsals held quotes and inquiries for 12-15 s at a time and live requests were cancelled at
// their 8 s limit (scripts/lib/replay_guard.mjs header). Independent review found the guard was one door among many: about
// forty scripts POSTed their own rolled-back probes (writes, DDL from a pending file) to the management API, and 29 of them
// (counted the same day: a send door, a `raise exception`, and DDL or a write in the same file) never went near it. They now
// go through scripts/lib/safe_replay.mjs replaySql(): the local database by default, production only with
// QD_REPLAY_ON_PRODUCTION=1, behind a 5 s transaction_timeout.
//
// This fails a file under scripts/ that can send to production (db.mjs sql(), qd_guard's mgmtFixture/mgmtWrite, a POST to
// the query endpoint, or a local function wrapping one of them) when a SQL text that takes a lock stopping writers (read by
// replay_guard's statedLocks), defines a routine, or writes inside a transaction that ends in `raise exception` is given to
// such a door: written into the call, or held in a name the call is given. replaySql() is the one door it accepts. A file
// whose job is to commit (an applier, an importer) is named below with its reason.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { statedLocks, STRONG_MODES } from '../lib/replay_guard.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));

// Each read on 13 Nov 2026. A new entry needs the same reading, and its reason here.
export const COMMITS_BY_DESIGN = new Map([
  ['scripts/apply_sql.mjs', 'the applier: commits a reviewed file, under its own 2 s lock_timeout and 60 s transaction_timeout'],
  ['scripts/qsql.mjs', 'the operator\'s runner for one file by hand; never called by a check'],
  ['scripts/lib/safe_replay.mjs', 'the door itself'],
  ['scripts/lib/db.mjs', 'the transport'],
  ['scripts/lib/qd_guard.mjs', 'the transport of the fixture and read doors'],
  ['scripts/sql/patch_founder_brief_truthful.mjs', 'a one-off routine patcher of Sep 2026 (CREATE OR REPLACE FUNCTION takes no table lock); its probe only reads'],
  ['scripts/eval/seat_qualification_exam.mjs', 'commits the exam items it loads (seat_exam_item); its retrieval probe goes through replaySql'],
  ['scripts/rehearsal/hvac_dress_rehearsal.mjs', 'arms and disarms the demo rehearsal switch on purpose (a committed decision_policy row); its guard probe goes through replaySql'],
  ['scripts/kb/purge_kb_bulk.mjs', 'the knowledge purge driver; commits batches by design'],
  ['scripts/kb/kb_chunks_copy_swap.mjs', 'the knowledge copy-and-swap driver; commits by design, operator only'],
  ['scripts/kb/drop_what_is_not_the_new_structure.mjs', 'the operator\'s one-off clean-up of the knowledge restructure: each DROP is its own autocommitted statement, held only for the drop'],
  ['scripts/kb/find_triggers_calling_deleted_routines.mjs', 'the operator\'s one-off clean-up of dead triggers: each DROP TRIGGER is its own autocommitted statement'],
  ['scripts/load/db_write_burst.mjs', 'a load generator, run by hand: concurrent rolled-back writes ARE its measurement, and one replay at a time would defeat it; never run by npm test or the gate'],
  ['scripts/checks/every_sql_replay_goes_through_safe_replay.test.mjs', 'its own proof replays through replaySql(); its sql() calls are readOnly reads'],
]);
// Directories of tools kept for history: not run by npm test or the gate (scripts/checks/run.mjs reads scripts/checks only).
const HISTORY = /^scripts\/(archive|staging)\//;

const DOOR = /lib\/db\.mjs['"]|database\/query|\bmgmtFixture\b|\bmgmtWrite\b/;
const GUARDED = /\breplaySql\s*\(|\brehearseChain\s*\(|\brehearse\s*\(/;
const ROUTINE_DDL = /\b(create\s+(or\s+replace\s+)?(function|procedure)\s+public\.|alter\s+(function|procedure)\s+public\.|drop\s+(function|procedure)\s)/i;
const PROBE_WRITE = (t) => /raise\s+exception/i.test(t) && /\b(insert\s+into\s+public\.|update\s+public\.[a-z_]+\s+set|delete\s+from\s+public\.)/i.test(t);

/** The string and template literals of a JS source, `${...}` holes replaced by a neutral name. [{ text, start }] */
export function literals(code) {
  const out = []; let i = 0;
  while (i < code.length) {
    const c = code[i];
    if (c === '/' && code[i + 1] === '/') { const e = code.indexOf('\n', i); i = e < 0 ? code.length : e; continue; }
    if (c === '/' && code[i + 1] === '*') { const e = code.indexOf('*/', i + 2); i = e < 0 ? code.length : e + 2; continue; }
    // a regular expression literal (/'/ would otherwise open a string): after an operator, a bracket or `return`
    if (c === '/') {
      const before = code.slice(Math.max(0, i - 12), i).replace(/\s+$/, '');
      if (!before || /[(,=:[!&|?{};+\-*%<>~^]$/.test(before) || /\b(return|typeof|case|of|in)$/.test(before)) {
        let j = i + 1; let cls = false;
        while (j < code.length && code[j] !== '\n') { if (code[j] === '\\') { j += 2; continue; } if (code[j] === '[') cls = true; else if (code[j] === ']') cls = false; else if (code[j] === '/' && !cls) break; j++; }
        if (code[j] === '/') { i = j + 1; continue; }
      }
    }
    if (c === "'" || c === '"' || c === '`') {
      const start = i; let text = ''; i++;
      while (i < code.length && code[i] !== c) {
        if (code[i] === '\\') { text += code[i + 1] === 'n' ? '\n' : (code[i + 1] ?? ''); i += 2; continue; }
        if (c === '`' && code[i] === '$' && code[i + 1] === '{') {
          let depth = 1; i += 2;
          while (i < code.length && depth) { if (code[i] === '{') depth++; else if (code[i] === '}') depth--; i++; }
          text += 'qd_hole'; continue;
        }
        text += code[i++];
      }
      i++; out.push({ text, start }); continue;
    }
    i++;
  }
  return out;
}

/** Why a SQL text must go through the guard, or null. */
export function dangerous(text) {
  if (text.length < 12 || !/\s/.test(text)) return null;
  const created = new Set([...text.matchAll(/create\s+(?:temp\s+|temporary\s+|unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?([a-z0-9_."]+)/gi)].map((m) => m[1].replace(/"/g, '').toLowerCase().replace(/^public\./, '')));
  let locks = [];
  try { locks = statedLocks(text); } catch { locks = []; }
  // a statement, not prose: a name qualified by its schema, or a text with a statement terminator
  const strong = locks.filter((l) => STRONG_MODES.has(l.mode) && (l.name.includes('.') || text.includes(';')) && !/^pg_temp\./.test(l.name)
    && !created.has(l.name.replace(/^public\./, '')) && !/^(public\.)?qd_hole$/.test(l.name));
  if (strong.length) return `${strong[0].kind} ${strong[0].name}`;
  if (ROUTINE_DDL.test(text) && /\$[a-z_]*\$/i.test(text)) return 'routine DDL';
  if (PROBE_WRITE(text)) return 'a write inside a rolled-back probe';
  // a routine run inside a transaction that ends in a raise: it writes and locks what it writes until the raise
  if (/raise\s+exception/i.test(text) && /(?::=|perform|select)\s+(?:\*\s+from\s+)?public\.(?:fn|qd|run|trg)_\w+\s*\(/i.test(text)) return 'a routine run inside a rolled-back probe';
  // a rolled-back DO block whose body is built at run time: nothing here can say it does not write
  if (/\bdo\s+\$\w*\$[\s\S]*qd_hole[\s\S]*\$\w*\$/i.test(text) && /raise\s+exception/i.test(text)) return 'a rolled-back DO block built at run time';
  return null;
}

const BASE_DOORS = ['sql', 'mgmtFixture', 'mgmtWrite'];
/** The names that send to production in this file: db.mjs sql() (and its aliases), the fixture doors, and any local function
 *  whose own body sends through one of them or POSTs to the query endpoint (a `probe(body)` wrapper). */
function doorsOf(src) {
  const doors = new Set(BASE_DOORS);
  for (const m of src.matchAll(/\b(?:sql|mgmtFixture|mgmtWrite)\s+as\s+([A-Za-z_$][\w$]*)/g)) doors.add(m[1]);
  // a wrapper is a door when its body hands its FIRST PARAMETER to a door: async function probe(body) { ... sql(`do $p$ ${body} $p$`) }
  const decl = /(?:async\s+)?function\s+([A-Za-z_][\w$]*)\s*\(\s*([A-Za-z_$][\w$]*)|(?:const|let)\s+([A-Za-z_][\w$]*)\s*=\s*(?:async\s*)?(?:\(\s*([A-Za-z_$][\w$]*)[^)]*\)|([A-Za-z_$][\w$]*))\s*=>/g;
  for (let grew = true; grew;) {
    grew = false;
    for (const m of src.matchAll(decl)) {
      const name = m[1] ?? m[3]; const param = m[2] ?? m[4] ?? m[5];
      if (!name || !param || doors.has(name) || name === 'replaySql') continue;
      const body = src.slice(m.index + m[0].length, m.index + m[0].length + 900);
      const end = body.search(/\n(?:async\s+)?function\s|\n(?:const|let|test|export)\b/);
      const own = end > 0 ? body.slice(0, end) : body;
      const sendsParam = [...doors].some((d) => new RegExp(`(?<![\\w.$])${d.replace(/\$/g, '\\$')}\\s*\\([^\\n]{0,200}?(?<![\\w.$])${param.replace(/\$/g, '\\$')}\\b`).test(own))
        || (/database\/query/.test(own) && new RegExp(`query:\\s*${param.replace(/\$/g, '\\$')}\\b`).test(own));
      if (sendsParam) { doors.add(name); grew = true; }
    }
  }
  return doors;
}

/** The findings of one source file (empty when it cannot send to production, or sends only through the guard). */
export function findings(src) {
  if (!DOOR.test(src)) return [];
  const lits = literals(src).map((l) => ({ ...l, why: dangerous(l.text) })).filter((l) => l.why);
  if (!lits.length) return [];
  const doors = [...doorsOf(src)];
  const call = `(?<![\\w.$])(?:${doors.join('|')})\\s*\\(`;
  const lineOf = (i) => src.slice(0, i).split('\n').length;
  const out = [];
  for (const l of lits) {
    const before = src.slice(Math.max(0, l.start - 160), l.start);
    // straight into a door: door(`...`), door(ref, `...`), door('begin;\n' + `...`)
    if (new RegExp(`${call}\\s*(?:[A-Za-z_$][\\w$]*\\s*,\\s*)?(?:'[^']*'\\s*\\+\\s*)?$`).test(before)) { out.push(`line ${lineOf(l.start)}: sends ${l.why} straight to a door that is not the guard`); continue; }
    // held in a name that a door is then given
    const v = /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:\([^)]*\)\s*=>\s*)?(?:String\.raw\s*)?$/.exec(before);
    if (v && !doors.includes(v[1]) && (new RegExp(`${call}[^\\n]{0,200}?(?<![\\w.$])${v[1]}\\b`).test(src) || (/database\/query/.test(src) && new RegExp(`query:\\s*${v[1]}\\b`).test(src)))) out.push(`line ${lineOf(l.start)}: ${v[1]} carries ${l.why} and a door that is not the guard sends it`);
    // the POST itself: a text inside a fetch to the query endpoint
    else if (/database\/query[\s\S]{0,300}$/.test(before)) out.push(`line ${lineOf(l.start)}: POSTs ${l.why} straight to the management API`);
  }
  return out;
}

function* files(dir) {
  for (const n of readdirSync(dir)) {
    if (n === 'node_modules' || n.startsWith('.')) continue;
    const p = join(dir, n);
    if (statSync(p).isDirectory()) yield* files(p);
    else if (/\.(mjs|js|cjs|ts)$/.test(n) && !/RETIRED/.test(n)) yield p;
  }
}

test('no file under scripts/ sends DDL or a rolled-back write to production except through the replay guard', () => {
  const found = [];
  for (const p of files(join(REPO, 'scripts'))) {
    const rel = relative(REPO, p).split('\\').join('/');
    if (COMMITS_BY_DESIGN.has(rel) || HISTORY.test(rel) || rel.startsWith('scripts/checks/retired/')) continue;
    if (rel === 'scripts/checks/no_script_sends_ddl_to_production_except_through_the_guard.test.mjs') continue;
    const f = findings(readFileSync(p, 'utf8'));
    if (f.length) found.push(`${rel}\n    ${f.join('\n    ')}`);
  }
  assert.deepEqual(found, [], `${found.length} file(s) send DDL or a rolled-back write around scripts/lib/safe_replay.mjs:\n  `
    + found.join('\n  ') + '\n  Send it with replaySql() (the local database by default; production only with QD_REPLAY_ON_PRODUCTION=1, cut at 5 s),'
    + ' or, for a tool whose job is to commit, name it in COMMITS_BY_DESIGN with the reason.');
});

test('the rule fails the shapes of 13 Nov and passes the same files through the guard', () => {
  const door = "import { sql } from '../lib/db.mjs';\n";
  const ddl = "await sql(`alter table public.quotes add column x int; do $p$ begin raise exception 'CHK<<1>>'; end $p$;`);";
  assert.equal(findings(door + ddl).length, 1, 'a literal ALTER sent with sql()');
  const viaGuard = "import { replaySql } from '../lib/safe_replay.mjs';\n" + ddl.replace('await sql(', 'await replaySql(');
  assert.deepEqual(findings(door + viaGuard), []);
  // a probe that writes and rolls back, held in a variable, in a file that never uses the guard
  const probe = door + "const PROBE = `do $p$ begin insert into public.notifications (type) values ('x'); raise exception 'CHK<<%>>', 1; end $p$;`;\nawait sql(PROBE);";
  assert.equal(findings(probe).length, 1);
  // the quoted name, the DO block, the drop index, the references: what the old regex missed is DDL here too
  for (const t of ['alter table "public"."quotes" add column y int', "do $d$ begin execute 'alter table quotes add column z int'; end $d$",
    'drop index public.quotes_pkey_x', 'create table public.zz_t (q bigint references public.quotes(id))']) {
    assert.ok(dangerous(t), t);
  }
  // reads, a temp table, a table the text creates itself: not DDL to production
  for (const t of ['select count(*) from public.quotes', 'create temp table qd_t as select 1; insert into qd_t values (2)',
    'create table public.zz_new (id int); create index on public.zz_new (id)']) assert.equal(dangerous(t), null, t);
  // a POST to the endpoint carrying a rolled-back write
  const post = "await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { body: JSON.stringify({ query: `do $p$ begin delete from public.leads where id = 1; raise exception 'x'; end $p$` }) });";
  assert.equal(findings(post).length, 1);
  // a wrapper: probe(body) sends do $p$ ${body} $p$ with sql(); the probe text given to it is the send
  const wrapped = door + "async function probe(body) {\n  try { await sql(`do $p$ ${body} $p$;`); } catch (e) { return e; }\n}\nawait probe(`insert into public.leads (id) values (1); raise exception 'CHK<<1>>';`);";
  assert.equal(findings(wrapped).length, 1, 'a probe wrapper around sql()');
  assert.deepEqual(findings(wrapped.replace('await sql(`do', 'await replaySql(`do')), []);
  // prose and regex sources are not statements
  assert.deepEqual(findings(door + "const msg = 'TRUNCATE empties a table whatever its RLS says';\nawait sql(`select 1`);"), []);
});
