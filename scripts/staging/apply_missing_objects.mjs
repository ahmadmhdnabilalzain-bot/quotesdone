// apply_missing_objects.mjs — close the gap between staging and production, without a full rebuild.
//
// A full baseline replay takes ~50 minutes and drops the public schema to do it. When staging is
// already 95% correct and simply missing the tables that postdate the last baseline capture, that
// is the wrong tool. This computes the difference from the two live catalogues - Supabase is the
// source of truth, so the catalogue is the authority, not the repo - and applies only the
// statements that mention a missing table.
//
// REHOMED 15 AUG 2026, AND HALF OF IT WAS RETIRED RATHER THAN REPOINTED.
//
// It resolved 'pglpqrhvozwepymcuunn', deleted that morning. The DIFF half keeps all its value on
// one project and the question just changes owner: it used to ask "what does staging lack that
// production has", it now asks "what does the database lack that supabase/schema/full_schema.sql
// describes" — which is the drift this repo has been bitten by twice.
//
// The --apply half is gone. It was a second, unverified write path into what is now the only
// database: it posts dump statements and reports the HTTP result, with no read-back and none of the
// guards apply_sql.mjs carries (a dead project ref, a callee that does not exist yet, DDL ordering).
// Keeping it pointed at the live project would have made the riskiest tool in the repo the one with
// the least verification behind it. It now prints the statements and names the tool that applies
// them properly, which is the mandated deploy path anyway.
//
//   node scripts/staging/apply_missing_objects.mjs
import { readFileSync } from 'node:fs';
import { splitStatements } from './sql_split.mjs';
import { mgmtRead, mgmtWrite, PROD_REF } from '../lib/qd_guard.mjs';
import { REF } from '../lib/demo_factory.mjs';

const SCHEMA_FILE = 'C:/Users/Opera/quotesdone/supabase/schema/full_schema.sql';
if (process.argv.includes('--apply')) {
  console.error('--apply was retired on 15 Aug 2026 with the staging project. This reports the gap;');
  console.error('apply it with `node scripts/apply_sql.mjs <file.sql> --apply`, which reads the');
  console.error('definition back out of the database afterwards. This never did.');
  process.exit(2);
}
const APPLY = false;

// ---- enum types first ------------------------------------------------------------------------
// fn_schema_export() emits EXTENSIONS, SEQUENCES, TABLES, CONSTRAINTS, INDEXES, VIEWS, FUNCTIONS,
// TRIGGERS, RLS, POLICIES, CRON and APP_SECRETS - and no TYPES section at all. Zero CREATE TYPE
// statements in 1.7 MB. Any table with an enum column therefore cannot be created from the
// baseline at any point, ever: six of them failed with "type answer_precedence does not exist".
// The catalogue is the source of truth, so read the types from it directly.
const ENUM_Q = `select t.typname, string_agg(quote_literal(e.enumlabel), ',' order by e.enumsortorder) as labels
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'public' and t.typtype = 'e'
  group by t.typname order by t.typname`;

const prodEnums = await mgmtRead(PROD_REF, ENUM_Q);
const stageEnums = new Set((await mgmtRead(REF, ENUM_Q)).map(r => r.typname));
for (const e of prodEnums) {
  if (stageEnums.has(e.typname)) continue;
  if (!APPLY) { console.log(`would create enum public.${e.typname}`); continue; }
  try {
    await mgmtWrite(REF, `create type public.${e.typname} as enum (${e.labels})`, 'enum');
    console.log(`created enum public.${e.typname}`);
  } catch (err) {
    console.log(`FAILED enum ${e.typname}: ${String(err.message).slice(0, 140)}`);
  }
}

const q = "select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE'";
const prod = new Set((await mgmtRead(PROD_REF, q)).map(r => r.table_name));
const stage = new Set((await mgmtRead(REF, q)).map(r => r.table_name));
const missing = [...prod].filter(t => !stage.has(t)).sort();

console.log(`production ${prod.size} tables, staging ${stage.size}, missing ${missing.length}`);
// Do NOT exit here when tables are complete: views and routines are checked further down, and
// returning "nothing to do" on a full table set hid a 9-view, 25-routine gap.
if (missing.length) console.log('missing: ' + missing.join(', '));
else console.log('all tables present - continuing to views and routines');

// Sequences the dump omits entirely. workflow_step_run_id_seq is absent from its SEQUENCES
// section, so workflow_step_run's DEFAULT nextval() had nothing to point at.
const SEQ_Q = "select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='S'";
const prodSeq = (await mgmtRead(PROD_REF, SEQ_Q)).map(r => r.relname);
const stageSeq = new Set((await mgmtRead(REF, SEQ_Q)).map(r => r.relname));
for (const s of prodSeq) {
  if (stageSeq.has(s)) continue;
  if (!APPLY) { console.log(`would create sequence public.${s}`); continue; }
  try {
    await mgmtWrite(REF, `create sequence if not exists public.${s}`, 'sequence');
    console.log(`created sequence public.${s}`);
  } catch (err) { console.log(`FAILED sequence ${s}: ${String(err.message).slice(0, 140)}`); }
}

const raw = readFileSync(SCHEMA_FILE, 'utf8');
// The CRON JOBS section arms 151 schedules pointing at production. It is never applied to a branch.
const SEC = /^-- ===== (.+?) =====/gm;
const bounds = [];
for (let m; (m = SEC.exec(raw));) bounds.push({ name: m[1], start: m.index });
for (let i = 0; i < bounds.length; i++) bounds[i].end = bounds[i + 1]?.start ?? raw.length;
let body = '';
for (const b of bounds) if (b.name !== 'CRON JOBS') body += raw.slice(b.start, b.end);

const all = splitStatements(body);
// A statement is in scope when it names a missing table with a word boundary, so `quotes` does
// not drag in `quote_items`.
// Point the body at THIS project instead of dropping it. Twenty of the routines staging lacks -
// fn_ai_trainer, run_auto_deploy, trg_autodispatch_inquiry and friends - hardcode
// https://<production>.supabase.co/functions/v1/... in their bodies. Excluding them satisfies the
// letter of the guard (staging must never call production) while leaving staging without the
// function at all, so the behaviour can never be tested. Rewriting the ref satisfies the guard's
// intent: the function exists and calls STAGING's own endpoints. qd_guard still refuses anything
// that reaches it carrying the production literal, because the rewrite happens first and is
// asserted below.
// With one project the rewrite is the identity, and the assertion below would then fire on every
// statement that legitimately names this project's own ref — turning the safety check into a
// guaranteed throw. It stays armed for the day a second project exists again.
const SAME_PROJECT = REF === PROD_REF;
const localize = (sql) => (SAME_PROJECT ? sql : sql.split(PROD_REF).join(REF));
const assertLocalized = (sql) => {
  if (!SAME_PROJECT && sql.includes(PROD_REF)) throw new Error('localize() failed to remove the production ref');
  return sql;
};

const wanted = all.filter(s => missing.some(t => new RegExp(`\\b${t}\\b`).test(s)))
  .map(s => assertLocalized(localize(s)));

console.log(`statements parsed ${all.length}, referencing a missing table: ${wanted.length}`);
if (!APPLY) {
  console.log('\nREPORT ONLY — this tool no longer writes. Anything listed above belongs in a new');
  console.log('scripts/sql file applied with `node scripts/apply_sql.mjs <file> --apply`.');
  process.exit(0);
}

let pending = wanted.slice();
for (let pass = 1; pass <= 5 && pending.length; pass++) {
  const failed = [];
  let ok = 0;
  for (const s of pending) {
    try { await mgmtWrite(REF, s, 'statement'); ok++; }
    catch (e) { failed.push({ sql: s, err: String(e.message).slice(0, 200) }); }
  }
  console.log(`pass ${pass}: applied ${ok}, failed ${failed.length}`);
  const noProgress = failed.length === pending.length;
  // A pass that fixes nothing has told us everything it is going to. Print why, rather than
  // reporting a count and discarding the reason - the count alone cannot be acted on.
  if (noProgress || !failed.length) {
    const byErr = new Map();
    for (const f of failed) {
      const k = (/ERROR:\s+\w+:\s*([^"\\]{0,90})/.exec(f.err)?.[1] || f.err.slice(0, 90)).trim();
      byErr.set(k, (byErr.get(k) || 0) + 1);
    }
    for (const [k, v] of [...byErr.entries()].sort((a, b) => b[1] - a[1])) {
      console.log(`   ${String(v).padStart(4)}  ${k}`);
    }
    for (const f of failed.slice(0, 5)) {
      console.log(`   STMT: ${f.sql.slice(0, 150).replace(/\s+/g, ' ')}`);
    }
  }
  pending = failed.map(f => f.sql);
  if (!failed.length || noProgress) break;
}

const after = new Set((await mgmtRead(REF, q)).map(r => r.table_name));
const stillMissing = [...prod].filter(t => !after.has(t)).sort();
console.log(`\nstaging now ${after.size} tables; still missing ${stillMissing.length}` +
  (stillMissing.length ? ': ' + stillMissing.join(', ') : ''));

// ---- views and routines --------------------------------------------------------------------
// Tables are not the whole schema. The rebuild left staging 9 views and 25 routines short, and
// the missing views are precisely the instruments the later phases are measured with -
// v_executor_registry_gaps, v_llm_calls_without_task_class, v_model_policy_offcatalog,
// v_workflow_side_effects_without_executor. A phase whose measuring instrument does not exist
// cannot be reported on at all, so these are not cosmetic.
const VIEW_Q = "select table_name as name from information_schema.views where table_schema='public'";
const FUNC_Q = "select proname as name from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'";

// ---- column-level drift ------------------------------------------------------------------------
// A table can be present and still wrong. v_executor_registry_gaps failed with
// "column risk_tier does not exist" - the table was there, the column was not, and a table-level
// parity check reports 403/403 and calls that done.
const COL_Q = `select table_name, column_name, data_type, is_nullable, column_default
  from information_schema.columns where table_schema='public'`;
const pCols = await mgmtRead(PROD_REF, COL_Q);
const sCols = new Set((await mgmtRead(REF, COL_Q)).map(c => `${c.table_name}.${c.column_name}`));
const colGap = pCols.filter(c => !sCols.has(`${c.table_name}.${c.column_name}`) && after.has(c.table_name));
console.log(`\ncolumns missing from existing staging tables: ${colGap.length}`);
for (const c of colGap.slice(0, 20)) console.log(`   ${c.table_name}.${c.column_name} ${c.data_type}`);
if (APPLY) {
  let cok = 0, cbad = 0;
  for (const c of colGap) {
    const def = c.column_default ? ` default ${localize(c.column_default)}` : '';
    const sql = `alter table public.${c.table_name} add column if not exists ${c.column_name} ${c.data_type}${def}`;
    try { await mgmtWrite(REF, sql, 'column'); cok++; }
    catch (e) { cbad++; if (cbad <= 5) console.log(`   FAILED ${c.table_name}.${c.column_name}: ${String(e.message).slice(0, 120)}`); }
  }
  console.log(`   added ${cok}, failed ${cbad}`);
}

async function closeGap(label, listQ, defQ, build = (d) => d.ddl) {
  const want = new Set((await mgmtRead(PROD_REF, listQ)).map(r => r.name));
  const have = new Set((await mgmtRead(REF, listQ)).map(r => r.name));
  const gap = [...want].filter(x => !have.has(x)).sort();
  if (!gap.length) { console.log(`\n${label}: none missing`); return 0; }
  console.log(`\n${label}: ${gap.length} missing - ${gap.join(', ')}`);

  // Take the DEFINITION FROM THE CATALOGUE, not from the dump. pg_get_functiondef and
  // pg_get_viewdef emit canonical, complete DDL - no section headers, no literal escape damage,
  // no dependence on a splitter getting a 1.7 MB file exactly right. Supabase is the source of
  // truth, so ask Postgres what the object is rather than re-deriving it from a text export.
  const defs = await mgmtRead(PROD_REF, defQ(gap));
  const stmts = defs.map(d => assertLocalized(localize(build(d))));
  console.log(`${label}: ${stmts.length} definition(s) read from the catalogue`);
  if (!APPLY) return gap.length;

  let pending2 = stmts.slice();
  for (let pass = 1; pass <= 5 && pending2.length; pass++) {
    const failed = [];
    let ok = 0;
    for (const s of pending2) {
      try { await mgmtWrite(REF, s, 'statement'); ok++; }
      catch (e) { failed.push({ sql: s, err: String(e.message).slice(0, 200) }); }
    }
    console.log(`   pass ${pass}: applied ${ok}, failed ${failed.length}`);
    const noProgress = failed.length === pending2.length;
    if (noProgress || !failed.length) {
      const byErr = new Map();
      for (const f of failed) {
        const k = (/ERROR:\s+\w+:\s*([^"\\]{0,90})/.exec(f.err)?.[1] || f.err.slice(0, 90)).trim();
        byErr.set(k, (byErr.get(k) || 0) + 1);
      }
      for (const [k, v] of [...byErr.entries()].sort((a, b) => b[1] - a[1])) {
        console.log(`      ${String(v).padStart(3)}  ${k}`);
      }
    }
    pending2 = failed.map(f => f.sql);
    if (!failed.length || noProgress) break;
  }
  const left = (await mgmtRead(REF, listQ)).map(r => r.name);
  const stillGap = [...want].filter(x => !left.includes(x));
  console.log(`${label}: still missing ${stillGap.length}` + (stillGap.length ? ': ' + stillGap.join(', ') : ''));
  return stillGap.length;
}

const inList = (names) => names.map(n => `'${n.replace(/'/g, "''")}'`).join(',');

// The DDL keyword is assembled in JS, not in SQL: mgmtRead refuses any query whose TEXT contains
// a write verb, and a query that merely builds the string 'CREATE OR REPLACE VIEW' trips it. The
// guard cannot tell a literal from a statement, and it is right to fail closed.
const viewGap = await closeGap('views', VIEW_Q,
  (names) => `select viewname, definition from pg_views
              where schemaname='public' and viewname in (${inList(names)})`,
  (d) => `CREATE OR REPLACE VIEW public.${d.viewname} AS ${d.definition}`);

const funcGap = await closeGap('routines', FUNC_Q, (names) =>
  `select pg_get_functiondef(p.oid) as ddl
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname in (${inList(names)})`);

process.exitCode = (stillMissing.length + viewGap + funcGap) ? 1 : 0;
