// apply_missing_objects.mjs — close the gap between staging and production, without a full rebuild.
//
// A full baseline replay takes ~50 minutes and drops the public schema to do it. When staging is
// already 95% correct and simply missing the tables that postdate the last baseline capture, that
// is the wrong tool. This computes the difference from the two live catalogues - Supabase is the
// source of truth, so the catalogue is the authority, not the repo - and applies only the
// statements that mention a missing table.
//
// It refuses to run against production.
//
//   node scripts/staging/apply_missing_objects.mjs [--apply]
import { readFileSync } from 'node:fs';
import { splitStatements, repairDumpSectionBreaks } from './sql_split.mjs';
import { mgmtRead, mgmtWrite, PROD_REF, assertNotProduction } from './qd_guard.mjs';

const SCHEMA_FILE = 'C:/Users/Opera/quotesdone/supabase/schema/full_schema.sql';
const REF = assertNotProduction(process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn', 'apply missing');
const APPLY = process.argv.includes('--apply');

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
if (!missing.length) { console.log('nothing to do'); process.exit(0); }
console.log('missing: ' + missing.join(', '));

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

const raw = repairDumpSectionBreaks(readFileSync(SCHEMA_FILE, 'utf8'));
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
const wanted = all.filter(s =>
  !s.includes(PROD_REF) &&
  missing.some(t => new RegExp(`\\b${t}\\b`).test(s)));

console.log(`statements parsed ${all.length}, referencing a missing table: ${wanted.length}`);
if (!APPLY) { console.log('\nDRY RUN - nothing applied. Re-run with --apply.'); process.exit(0); }

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
process.exitCode = stillMissing.length ? 1 : 0;
