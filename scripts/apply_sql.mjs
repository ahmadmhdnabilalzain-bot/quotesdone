// Apply a .sql file to STAGING, then promote the VERIFIED definition to production byte-for-byte.
//
// The founder's promotion rule of 6 Aug 2026: qd_guard refuses production writes by design, so a
// routine reaches production by reading staging's verified definition back out and posting THAT
// verbatim — never by retyping a body. This script is that rule, executable.
//
//   node scripts/apply_sql.mjs scripts/sql/fn_task_approve.sql            # staging only
//   node scripts/apply_sql.mjs scripts/sql/fn_task_approve.sql --promote  # then production
//
// --promote posts pg_get_functiondef() read back FROM STAGING and asserts md5(prosrc) matches on
// both projects afterwards. A mismatch exits non-zero: the two projects then differ, and that is
// exactly the drift verify_prod_parity exists to catch.
import { readFileSync } from 'node:fs';
import { mgmtRead, mgmtWrite, PROD_REF } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const file = process.argv[2];
const PROMOTE = process.argv.includes('--promote');
// --ddl: the file also carries schema changes (columns, views, tables, indexes, cron rows) that
// pg_get_functiondef cannot express, so there is no "read the verified definition back" for them.
// The honest analogue is the identical text applied to both projects and the resulting SHAPE
// asserted equal — a column that lands with a different type or a view whose definition the planner
// rewrote differently shows up as a digest mismatch. Never use this to carry row DATA to
// production: that is promote_rows_to_production.mjs, which reads the verified value back.
const DDL = process.argv.includes('--ddl');
if (!file) { console.error('usage: node scripts/apply_sql.mjs <file.sql> [--promote] [--ddl]'); process.exit(2); }

const sql = readFileSync(file, 'utf8');
const one = (rows) => (rows && rows[0]) ? Object.values(rows[0])[0] : null;

await mgmtWrite(STAGE, sql, `apply ${file}`);
console.log(`applied to staging ${STAGE}`);

// Which routines did that file define? Parse the names, then read the REAL definitions back.
const names = [...sql.matchAll(/create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi)]
  .map(m => m[1]);
const uniq = [...new Set(names)];
if (!uniq.length && !DDL) { console.log('no functions defined in this file; nothing to promote'); process.exit(0); }

// PRODUCTION. qd_guard refuses this on purpose, so the post goes through the management API
// directly with the body read back from staging — never the file, never a retype.
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
// RETRIES, BECAUSE THE FAILURE MODE HERE IS A HALF-PROMOTED PRODUCTION. The management API
// rate-limits hard after a heavy session and this path had no backoff at all while qd_guard's
// mgmtWrite has had one for weeks — so a 429 arriving between two routines in the same file would
// deploy the first, throw on the second, and leave the two projects differing in a way the very
// next line of this script is supposed to prevent. Observed on the first promotion attempt of
// session 15. Slow is expected; a 9-second gate taking 102 seconds is normal, not a hang.
async function prodPost(q, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: q }),
  });
  const b = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 7) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.log(`  production ${r.status}; retrying in ${wait / 1000}s (attempt ${attempt + 1}/7)`);
    await new Promise(res => setTimeout(res, wait));
    return prodPost(q, attempt + 1);
  }
  if (!r.ok) throw new Error(`production ${r.status}: ${b.slice(0, 400)}`);
  return JSON.parse(b);
}

// The shape of every table column and view in public, as one digest per project. A column that
// lands with a different type, a default that did not carry, or a view the planner expanded
// differently all change this; a row of DATA does not, which is the point — this asserts SCHEMA
// parity and makes no claim about contents.
// THREE VIEWS RENDER DIFFERENTLY AND ARE SEMANTICALLY IDENTICAL — measured 6 Aug 2026, both
// projects on PostgreSQL 17.6. Staging's stored parse tree carries an explicit `AS text` alias on
// literal UNION columns where production's is implicit, and for `'x'::text` the inferred column
// name IS text, so both produce the same column names, types and rows. Recreating production's
// views to silence a cosmetic difference would touch three working views for no gain, and the
// standing rule is that a red parity check is a question about which side is RIGHT — here neither
// is wrong. They are baselined BY NAME so any FOURTH view that drifts still fails this gate.
const COSMETIC_VIEWS = ['v_audit_coverage', 'v_department_health', 'v_supplier_coi'];
const SHAPE = `select md5(string_agg(x, '|' order by x)) from (
  select 'c:'||table_name||'.'||column_name||':'||data_type||':'||is_nullable
         ||':'||coalesce(column_default,'-') x
    from information_schema.columns where table_schema='public'
  union all
  select 'v:'||viewname||':'||md5(definition) from pg_views where schemaname='public'
     and viewname not in (${COSMETIC_VIEWS.map(v => `'${v}'`).join(',')})
) s`;

const defsSql = (ref) => `select p.proname n, pg_get_function_identity_arguments(p.oid) a,
  pg_get_functiondef(p.oid) d, md5(p.prosrc) h
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname='public' and p.proname in (${uniq.map(n => `'${n}'`).join(',')})`;

const stageDefs = uniq.length ? await mgmtRead(STAGE, defsSql(STAGE)) : [];
if (uniq.length) console.log(`staging now defines: ${stageDefs.map(d => `${d.n}(${d.a})`).join(', ')}`);

if (!PROMOTE) { console.log('staging only — pass --promote to deploy to production'); process.exit(0); }

// A LITERAL PROJECT REF MUST NEVER BE PROMOTED (12 Aug 2026). This tool's whole premise is that the
// definition read back from staging is the definition production should have, byte for byte. That
// premise breaks for any routine carrying a hardcoded https://<ref>.supabase.co URL: promoting it
// silently repoints the PRODUCTION copy at STAGING, and nothing fails — production's trainer posts
// its work into the staging project and both sides keep reporting success.
//
// Nineteen routines carried one when this guard was written (fn_ai_trainer, fn_org_exec_knowledge_fill,
// fn_os_incident_open, fn_provision_category_call, fn_recert_rotate, fn_resilience_watch, fn_run_vt,
// fn_watch_failed_runs, fn_watch_health, qd_reveal_nudges, qd_sign_customer, qd_sign_supplier,
// run_agent, run_auto_deploy, run_doc_reminders, run_pending_digest, run_site_autodeploy,
// trg_autodispatch_inquiry, trg_enrich_capability). All pointed at their own project on both sides,
// so nothing was broken — the hazard was one --promote away, and I came one step from triggering it.
//
// There is no legitimate promote that carries a literal ref, so this refuses rather than warns. The
// fix is to derive the ref: `select value into v_ref from app_secrets where key = 'project_ref'`,
// with the cron.job fallback fn_action_invoke_dispatch, fn_rfq_redispatch_sweep and
// fn_capability_enrich_sweep all use.
const REF_LITERAL = /https:\/\/([a-z]{20})\.supabase\.co/g;
const offenders = stageDefs
  .map(d => ({ n: d.n, a: d.a, refs: [...new Set([...String(d.d).matchAll(REF_LITERAL)].map(m => m[1]))] }))
  .filter(x => x.refs.length);
if (offenders.length) {
  console.error('REFUSED: a routine in this file hardcodes a Supabase project ref, and promoting it');
  console.error('would write STAGING\'s URL into the PRODUCTION copy. Nothing would fail visibly.');
  for (const o of offenders) {
    console.error(`  ${o.n}(${o.a})  ->  ${o.refs.map(r => r === STAGE ? `${r} (STAGING)` : r === PROD_REF ? `${r} (production)` : r).join(', ')}`);
  }
  console.error("Fix: read app_secrets.project_ref inside the routine instead of writing the ref out.");
  process.exit(3);
}

// A BODY MAY NOT BE PROMOTED AHEAD OF THE ROUTINE IT CALLS (14 Aug 2026).
//
// Same asymmetry as the DDL rule below, one layer up. A routine that calls public.fn_x() compiles
// and promotes happily; plpgsql resolves the callee at RUN time, so if fn_x exists on staging and
// not on production, the promotion succeeds, every digest matches, and the function throws the
// first time production calls it.
//
// Nearly triggered on this very file: two sessions converged scripts/sql/org_reorg_04_runtime.sql,
// and the merged version had fn_agent_context_v3 calling a new helper fn_task_tsquery that existed
// on staging only. Promoting it would have made EVERY employee context assembly on production
// throw — the single hottest path in the company — while staging stayed green.
//
// project_parity would not have caught it either: that is a SHAPE check over columns and views, and
// a missing function is neither.
const CALLEE = /public\.((?:fn|trg|qd|run)_[a-z0-9_]+)\s*\(/g;
const selfDefined = new Set(uniq.map(n => n.toLowerCase()));
const called = new Set();
for (const d of stageDefs) for (const m of String(d.d).matchAll(CALLEE)) called.add(m[1].toLowerCase());
if (DDL) for (const m of sql.matchAll(CALLEE)) called.add(m[1].toLowerCase());
const wanted = [...called].filter(c => !selfDefined.has(c));
if (wanted.length) {
  const rows = await mgmtRead(PROD_REF, `select distinct lower(p.proname) n
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='public' and lower(p.proname) in (${wanted.map(w => `'${w}'`).join(',')})`);
  const have = new Set(rows.map(r => r.n));
  const missing = wanted.filter(w => !have.has(w));
  if (missing.length) {
    console.error('REFUSED: this file promotes a routine that calls something production does not have.');
    console.error('plpgsql resolves a callee at run time, so this would deploy cleanly, match every');
    console.error('digest, and then throw the first time production ran it.');
    for (const m of missing) console.error(`  missing on ${PROD_REF}: public.${m}()`);
    console.error('Fix: promote the file that DEFINES those routines first, then re-run this one.');
    process.exit(4);
  }
}

// DDL FIRST, ALWAYS. A function body promoted before the column it selects exists fails on
// production while reporting success on staging, which is the exact asymmetry this whole promotion
// rule exists to prevent.
if (DDL) {
  await prodPost(sql);
  console.log(`applied DDL to production ${PROD_REF}`);
}

for (const d of stageDefs) await prodPost(d.d);
const prodDefs = uniq.length ? await mgmtRead(PROD_REF, defsSql(PROD_REF)) : [];

let bad = 0;
for (const s of stageDefs) {
  const p = prodDefs.find(x => x.n === s.n && x.a === s.a);
  const ok = p && p.h === s.h;
  if (!ok) bad++;
  console.log(`${ok ? 'MATCH  ' : 'DIFFER '} ${s.n}(${s.a})  staging ${s.h}  production ${p ? p.h : '(absent)'}`);
}

if (DDL) {
  const sShape = one(await mgmtRead(STAGE, SHAPE));
  const pShape = one(await mgmtRead(PROD_REF, SHAPE));
  const ok = sShape === pShape;
  if (!ok) bad++;
  console.log(`${ok ? 'MATCH  ' : 'DIFFER '} public schema shape  staging ${sShape}  production ${pShape}`);
}

if (bad) { console.error(`${bad} object(s) differ after promotion`); process.exit(1); }
console.log(`PROMOTED ${stageDefs.length} routine(s)${DDL ? ' + DDL' : ''} to production ${PROD_REF}, identical`);
