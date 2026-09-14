// rebuild_staging.mjs — build a usable staging database from the committed baseline.
//
// WHY THIS EXISTS
// The Supabase branch replay failed after 31 of 712 migrations: the repo holds 285 migration
// files, the earliest dated 20260724, while production's recorded history starts far earlier.
// So "create_branch and you have staging" is false. The repo's documented route is
// baseline-then-increments (migration-set-cannot-rebuild.md).
//
// WHY IT IS NOT A STRAIGHT `psql -f full_schema.sql`
// That file contains a CRON JOBS section: 151 cron.schedule calls and 67 literal occurrences
// of the production ref. Applying it verbatim to a branch recreates the 3-4 Aug incident in
// which branch crons called production for eighteen hours. This script excises that section
// and refuses, via qd_guard, any remaining statement carrying the production literal.
//
//   node rebuild_staging.mjs <staging_ref> [--apply]
//
// Without --apply it is a dry run: it reports what it would do and changes nothing.
import { readFileSync, writeFileSync } from 'node:fs';
import { splitStatements } from './sql_split.mjs';
import { PROD_REF, resolveStagingRef, mgmtWrite, assertNoProductionLiteral } from './qd_guard.mjs';

const SCHEMA_FILE = 'C:/Users/Opera/quotesdone/supabase/schema/full_schema.sql';
const REF = resolveStagingRef(process.argv[2]);
const APPLY = process.argv.includes('--apply');
const log = [];
const say = (s) => { console.log(s); log.push(s); };

say(`rebuild_staging  target=${REF}  apply=${APPLY}  (production ${PROD_REF} is refused by qd_guard)`);

const raw = readFileSync(SCHEMA_FILE, 'utf8');
say(`baseline: ${SCHEMA_FILE}  ${raw.length} bytes`);
const captured = /Captured (\S+) from project (\w+)/.exec(raw);
say(`baseline captured ${captured?.[1]} from ${captured?.[2]}`);

// ---- 1. excise the CRON JOBS section -------------------------------------------------------
const SEC = /^-- ===== (.+?) =====/gm;
const bounds = [];
for (let m; (m = SEC.exec(raw)); ) bounds.push({ name: m[1], start: m.index });
for (let i = 0; i < bounds.length; i++) bounds[i].end = bounds[i + 1]?.start ?? raw.length;
say(`sections: ${bounds.map(b => b.name).join(' | ')}`);

const DROP_SECTIONS = new Set(['CRON JOBS']);
let body = '';
for (const b of bounds) {
  if (DROP_SECTIONS.has(b.name)) {
    const excised = raw.slice(b.start, b.end);
    say(`EXCISED section "${b.name}": ${excised.length} bytes, ` +
        `${(excised.match(/cron\.schedule/g) || []).length} cron.schedule, ` +
        `${(excised.match(new RegExp(PROD_REF, 'g')) || []).length} production-ref literals`);
    continue;
  }
  body += raw.slice(b.start, b.end);
}
// anything before the first section header (the file banner) is comments only
say(`body after excision: ${body.length} bytes`);

// ---- 2. split -------------------------------------------------------------------------------
const all = splitStatements(body);
say(`statements parsed: ${all.length}`);

// ---- 3. quarantine anything still carrying the production ref -------------------------------
const quarantined = [];
const stmts = [];
for (const s of all) {
  if (s.includes(PROD_REF)) quarantined.push(s); else stmts.push(s);
}
say(`quarantined (embed ${PROD_REF}): ${quarantined.length}`);
for (const q of quarantined.slice(0, 40)) {
  say(`  QUARANTINE: ${q.slice(0, 160).replace(/\s+/g, ' ')}`);
}
say(`to apply: ${stmts.length}`);

// ---- 4. schemas referenced but never created -------------------------------------------------
const schemas = new Set();
for (const s of stmts) {
  const m = /\b(?:CREATE\s+(?:TABLE|SEQUENCE|VIEW|MATERIALIZED\s+VIEW|FUNCTION|TYPE)(?:\s+IF\s+NOT\s+EXISTS)?)\s+([a-z_][a-z0-9_]*)\./i.exec(s);
  if (m) schemas.add(m[1].toLowerCase());
}
const SYSTEM = new Set(['public', 'auth', 'storage', 'extensions', 'vault', 'graphql', 'graphql_public',
  'realtime', 'supabase_functions', 'supabase_migrations', 'pg_catalog', 'information_schema', 'cron', 'net', 'pgbouncer']);
const appSchemas = [...schemas].filter(s => !SYSTEM.has(s)).sort();
say(`schemas referenced by DDL: ${[...schemas].sort().join(', ')}`);
say(`non-system schemas needing CREATE SCHEMA: ${appSchemas.join(', ') || '(none)'}`);
const hasCreateSchema = /\bCREATE\s+SCHEMA\b/i.test(body);
say(`baseline contains CREATE SCHEMA statements: ${hasCreateSchema}`);

if (!APPLY) {
  writeFileSync('C:/Users/Opera/qd-check/_rebuild_dryrun.txt', log.join('\n'), 'utf8');
  say('\nDRY RUN — nothing applied. Re-run with --apply.');
  process.exit(0);
}

// ---- 5. reset the branch --------------------------------------------------------------------
const prelude = [
  `drop schema if exists public cascade`,
  ...appSchemas.map(s => `drop schema if exists ${s} cascade`),
  `create schema public`,
  `grant usage on schema public to postgres, anon, authenticated, service_role`,
  `grant all on schema public to postgres, service_role`,
  ...appSchemas.map(s => `create schema if not exists ${s}`),
];
say('\n--- reset ---');
for (const p of prelude) {
  try { await mgmtWrite(REF, p, 'prelude'); say(`  ok   ${p}`); }
  catch (e) { say(`  FAIL ${p}\n       ${String(e.message).slice(0, 300)}`); }
}

// ---- 6. apply, in passes, until the failure count stops falling ------------------------------
// The dump's own header says ordering is best-effort. Rather than pretend to know the right
// order, apply repeatedly: a statement that failed only because its dependency had not been
// created yet will succeed on the next pass. When a pass fixes nothing, what remains is a real
// reproducibility defect, and that is the number worth reporting.
let pending = stmts.slice();
const passes = [];
for (let pass = 1; pass <= 6 && pending.length; pass++) {
  const failed = [];
  let ok = 0;
  let done = 0;
  const t0 = Date.now();
  for (const s of pending) {
    try { assertNoProductionLiteral(s, 'statement'); await mgmtWrite(REF, s, 'statement'); ok++; }
    catch (e) { failed.push({ sql: s, err: String(e.message).slice(0, 300) }); }
    // A job that prints only when a pass ends is indistinguishable from a job that has stopped.
    // The 4 Aug run hung at statement ~150 and looked identical to one making progress.
    if (++done % 50 === 0) {
      const rate = done / ((Date.now() - t0) / 1000);
      process.stdout.write(`    pass ${pass}: ${done}/${pending.length} ok=${ok} fail=${failed.length} ` +
        `${rate.toFixed(1)}/s eta=${Math.round((pending.length - done) / rate)}s\n`);
    }
  }
  passes.push({ pass, applied: ok, failed: failed.length });
  say(`pass ${pass}: applied ${ok}, failed ${failed.length}`);
  const noProgress = failed.length === pending.length;
  pending = failed.map(f => f.sql);
  if (!failed.length || noProgress) break;   // done, or a pass that fixed nothing
}

// ---- 7. final diagnostic pass: capture the error text of what genuinely will not apply -------
const residual = [];
for (const s of pending) {
  try { await mgmtWrite(REF, s, 'statement'); }
  catch (e) { residual.push({ sql: s, err: String(e.message).slice(0, 400) }); }
}
say(`\nresidual failures (real reproducibility defects): ${residual.length}`);
const byErr = new Map();
for (const r of residual) {
  const k = (/ERROR:\s+\w+:\s*([^\\"]{0,90})/.exec(r.err)?.[1] || r.err.slice(0, 90)).trim();
  byErr.set(k, (byErr.get(k) || 0) + 1);
}
for (const [k, v] of [...byErr.entries()].sort((a, b) => b[1] - a[1])) say(`  ${String(v).padStart(5)}  ${k}`);
for (const r of residual.slice(0, 30)) {
  say(`\n  STMT: ${r.sql.slice(0, 220).replace(/\s+/g, ' ')}\n  ERR : ${r.err.slice(0, 220).replace(/\s+/g, ' ')}`);
}

// ---- 8. what did we actually get? -----------------------------------------------------------
const census = await mgmtWrite(REF, `
  select
    (select count(*) from information_schema.tables where table_schema not in
      ('pg_catalog','information_schema','auth','storage','extensions','vault','graphql','graphql_public','realtime','supabase_functions','supabase_migrations','cron','net','pgbouncer')
      and table_type='BASE TABLE') as app_tables,
    (select count(*) from information_schema.views where table_schema='public') as public_views,
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') as public_routines,
    (select count(*) from information_schema.schemata where schema_name='kb_stage') as kb_stage,
    (select count(*) from cron.job) as cron_jobs`, 'census');
say(`\nBRANCH CENSUS: ${JSON.stringify(census)}`);
writeFileSync('C:/Users/Opera/qd-check/_rebuild_staging.txt', log.join('\n'), 'utf8');
writeFileSync('C:/Users/Opera/qd-check/_rebuild_residual.json', JSON.stringify(residual, null, 1), 'utf8');
say('\nwrote _rebuild_staging.txt and _rebuild_residual.json');
process.exit(residual.length ? 1 : 0);
