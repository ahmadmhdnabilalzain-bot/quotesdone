// BRING STAGING UP TO WHAT PRODUCTION ACTUALLY RUNS.
//
// verify_prod_parity had been red at 5/8 on seven objects. Diffed character by character
// (scripts/diff_drifted_objects.mjs), three carry REAL fixes that only ever reached production:
//
//   enqueue_supplier_invites  production marks both CTEs MATERIALIZED, with a comment recording why:
//                             without the keyword Postgres inlines them into a correlated subquery
//                             and re-runs a 19,632-row aggregate once per candidate, ~220 s.
//   fn_control_mode_open      production declares v_reason / v_raw_len that staging's body lacks.
//   fn_invite_ramp            production ramps on v_sent_total / v_last_sent; staging still ramps on
//                             v_start / v_days — different logic, not different formatting.
//
// The other four (fn_schema_export, v_audit_coverage, v_department_health) are FORMATTING ONLY:
// staging carries a real newline where production has the two characters \n inside an E'' string,
// and staging's views spell out `::text AS text` where production's deparse omits the alias. Both
// forms produce identical results. They are synced anyway so the gate measures drift rather than
// punctuation.
//
// DIRECTION IS PRODUCTION -> STAGING, deliberately. Production is the live system and already holds
// the newer bodies; mirroring onto staging achieves parity with zero production risk. The project
// ref is rewritten as it travels — a staging routine that embedded the production ref would make
// branch code call production, which is what happened for eighteen hours on 3-4 Aug and is exactly
// what qd_guard's assertNoProductionLiteral exists to refuse.
//
//   node scripts/sync_routines_from_production.mjs [--dry-run]
import { mgmtRead, mgmtWrite, PROD_REF } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const DRY = process.argv.includes('--dry-run');
const ROUTINES = ['enqueue_supplier_invites', 'fn_control_mode_open', 'fn_invite_ramp',
                  'fn_schema_export', 'run_health_check'];
const VIEWS = ['v_audit_coverage', 'v_department_health'];

// The CREATE statement is assembled in JavaScript, not in the SELECT. qd_guard's mgmtRead refuses
// anything matching /\bcreate\b/ — correctly, since a read that builds DDL as a value is
// indistinguishable from one that runs it, and this is a production connection.
const prod = await mgmtRead(PROD_REF, `
  select p.proname n, 'routine' kind, pg_get_functiondef(p.oid) d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname='public' and p.proname in (${ROUTINES.map(r => `'${r}'`).join(',')})
  union all
  select viewname, 'view', definition
    from pg_views where schemaname='public' and viewname in (${VIEWS.map(v => `'${v}'`).join(',')})`);
for (const o of prod) {
  if (o.kind === 'view') o.d = `create or replace view public."${o.n}" as ${o.d}`;
}

const results = [];
for (const o of prod) {
  // The ref travels rewritten, never verbatim.
  const body = o.d.split(PROD_REF).join(STAGE);
  if (body.includes(PROD_REF)) throw new Error(`${o.n}: production ref survived the rewrite`);

  if (DRY) { results.push({ object: o.n, kind: o.kind, action: 'would apply', chars: body.length }); continue; }
  await mgmtWrite(STAGE, body, `sync ${o.n}`);
  results.push({ object: o.n, kind: o.kind, applied: true, chars: body.length });
}

if (!DRY) {
  // Assert equality the way the gate does: mask the ref, then compare. Anything still differing is
  // real drift this script did not resolve, and must be reported rather than assumed fixed.
  const after = await mgmtRead(STAGE, `
    select p.proname n, pg_get_functiondef(p.oid) d
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='public' and p.proname in (${ROUTINES.map(r => `'${r}'`).join(',')})
    union all
    select viewname, definition from pg_views
     where schemaname='public' and viewname in (${VIEWS.map(v => `'${v}'`).join(',')})`);
  const prodRaw = await mgmtRead(PROD_REF, `
    select p.proname n, pg_get_functiondef(p.oid) d
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='public' and p.proname in (${ROUTINES.map(r => `'${r}'`).join(',')})
    union all
    select viewname, definition from pg_views
     where schemaname='public' and viewname in (${VIEWS.map(v => `'${v}'`).join(',')})`);
  const mask = (s) => s.split(STAGE).join('<REF>').split(PROD_REF).join('<REF>');
  for (const r of results) {
    const a = after.find(x => x.n === r.object), b = prodRaw.find(x => x.n === r.object);
    r.matches = !!(a && b) && mask(a.d) === mask(b.d);
  }
}

console.table(results);
const bad = results.filter(r => !DRY && !r.matches);
if (bad.length) { console.error('STILL DIFFERENT: ' + bad.map(b => b.object).join(', ')); process.exit(1); }
console.log(DRY ? 'DRY RUN — nothing written'
  : `STAGING NOW MIRRORS PRODUCTION for ${results.length} object(s), project ref rewritten`);
