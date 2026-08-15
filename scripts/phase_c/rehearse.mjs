// Rehearse the exact committed Phase C migrations inside an ABORTED production transaction.
//
//   node scripts/phase_c/rehearse.mjs            # all files, one transaction, always rolls back
//   node scripts/phase_c/rehearse.mjs --from 05  # start at a file, for iterating on one of them
//
// A multi-statement file is ONE implicit transaction here, which is what makes this work: the
// files are concatenated in order, a block that reads the post-change counts and then RAISES is
// appended, and the raise aborts everything.  The numbers still come out.
//
// It refuses to report success if the migration does not raise — a rehearsal that committed is
// not a rehearsal, and "no error" would otherwise read as "it rolled back cleanly".
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { REPO } from './lib/package.mjs';
import { sql } from './lib/db.mjs';

// DEPLOY ORDER, not file order.  apply_sql refuses a file whose bindings name a routine that is
// not deployed yet, which caught two real ordering mistakes on the way in: 02 depends on
// fn_phase_c_reviewer_independent from 03, and the seven binding files depend on 08.  The list
// below is the order that actually applied cleanly, so the rehearsal and the deployment agree.
export const MIGRATION_FILES = [
  'phase_c_01_identity_and_registry_schema.sql',
  'phase_c_03_runtime_core.sql',
  'phase_c_02_authority_and_founder_boundary.sql',
  'phase_c_04_command_center.sql',
  'phase_c_08_runtime_writers.sql',
  'phase_c_09_invariants.sql',
  'phase_c_05_registry_load.sql',
  'phase_c_06_components_part01.sql',
  'phase_c_06_components_part02.sql',
  'phase_c_06_components_part03.sql',
  'phase_c_06_components_part04.sql',
  'phase_c_07_binding_01_role_binding.sql',
  'phase_c_07_binding_02_overlay_binding.sql',
  'phase_c_07_binding_03_workflow_binding.sql',
  'phase_c_07_binding_04_step_binding.sql',
  'phase_c_07_binding_05_handoff_binding.sql',
  'phase_c_07_binding_06_event_binding.sql',
  'phase_c_07_binding_07_gate_binding.sql',
  'phase_c_07_binding_08_rule_binding.sql',
];

const SQL_DIR = join(REPO, 'scripts', 'sql');
export const readMigration = f => readFileSync(join(SQL_DIR, f), 'utf8');
export const sha = s => createHash('sha256').update(s).digest('hex');

// What must be unchanged after an aborted rehearsal.
const FINGERPRINT_SQL = `
select
  (select count(*) from public.org_role)                                    as org_roles,
  (select count(*) from public.org_role_alias)                              as org_role_aliases,
  (select count(*) from public.org_department_alias)                        as org_dept_aliases,
  (select count(*) from public.org_departments)                             as org_departments,
  (select count(*) from public.fn_phase_a_baseline_drift())                 as phase_a_drift,
  (select count(*) from public.fn_phase_b_baseline_drift())                 as phase_b_drift,
  (select count(*) from cron.job)                                           as cron_jobs,
  (select count(*) from cron.job where active)                              as cron_active,
  (select count(*) from public.llm_route_health where open_until > now())   as llm_routes_held,
  (select count(*) from public.ai_cost_log)                                 as ai_cost_rows,
  (select count(*) from information_schema.tables
     where table_schema='public' and table_name like 'phase\\_c\\_%')        as phase_c_tables,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public')                                              as public_functions,
  (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
     join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and not t.tgisinternal)                       as public_triggers`;

async function fingerprint() {
  const r = (await sql(FINGERPRINT_SQL))[0];
  return { values: r, digest: sha(JSON.stringify(r)) };
}

const fromIdx = process.argv.includes('--from')
  ? MIGRATION_FILES.findIndex(f => f.includes(process.argv[process.argv.indexOf('--from') + 1]))
  : 0;
const files = MIGRATION_FILES.slice(Math.max(0, fromIdx));

const before = await fingerprint();
console.log('pre-rehearsal fingerprint:', JSON.stringify(before.values));
console.log('digest:', before.digest);
for (const f of files) {
  console.log(`  ${f}  ${(readMigration(f).length / 1024).toFixed(0)} KB  sha256=${sha(readMigration(f)).slice(0, 16)}`);
}

const body = files.map(f => `\n-- ===== ${f} =====\n${readMigration(f)}`).join('\n');
console.log(`total ${(body.length / 1024).toFixed(0)} KB across ${files.length} files`);

const abort = `
do $rehearsal$
declare
  v_components bigint; v_roles bigint; v_overlays bigint; v_steps bigint; v_handoffs bigint;
  v_events bigint; v_gates bigint; v_rules bigint; v_actions bigint; v_rules_cmd bigint;
  v_inv_total bigint; v_inv_failed bigint; v_failed text;
begin
  select count(*) into v_components from public.phase_c_component;
  select count(*) into v_roles      from public.phase_c_role_binding;
  select count(*) into v_overlays   from public.phase_c_overlay_binding;
  select count(*) into v_steps      from public.phase_c_step_binding;
  select count(*) into v_handoffs   from public.phase_c_handoff_binding;
  select count(*) into v_events     from public.phase_c_event_binding;
  select count(*) into v_gates      from public.phase_c_gate_binding;
  select count(*) into v_rules      from public.phase_c_rule_binding;
  select count(*) into v_actions    from public.phase_c_action_class;
  select count(*) into v_rules_cmd  from public.phase_c_command_rule;
  select count(*), count(*) filter (where not ok) into v_inv_total, v_inv_failed
    from public.fn_phase_c_invariants();
  select coalesce(string_agg(check_name || '(' || actual || '!=' || expected || ')', '; '), 'none')
    into v_failed from public.fn_phase_c_invariants() where not ok;
  raise exception 'REHEARSAL components=% roles=% overlays=% steps=% handoffs=% events=% gates=% rules=% action_classes=% command_rules=% invariants=%/% FAILED=[%]',
    v_components, v_roles, v_overlays, v_steps, v_handoffs, v_events, v_gates, v_rules,
    v_actions, v_rules_cmd, v_inv_total - v_inv_failed, v_inv_total, v_failed;
end $rehearsal$;`;

let message = null;
try {
  await sql(body + abort);
  console.error('\nFAIL: the rehearsal did NOT raise. Nothing proves it rolled back. Refusing.');
  process.exit(1);
} catch (e) {
  message = String(e.message);
}
const m = message.match(/REHEARSAL[^"\\]*/);
console.log('\n' + (m ? m[0] : message.slice(0, 6000)));

const after = await fingerprint();
console.log('\npost-rehearsal digest:', after.digest);
if (after.digest !== before.digest) {
  console.error('FAIL: production fingerprint CHANGED across an aborted rehearsal.');
  console.error('before:', JSON.stringify(before.values));
  console.error('after: ', JSON.stringify(after.values));
  process.exit(1);
}
console.log('production fingerprint unchanged across the abort.');
if (!m) { console.error('\nFAIL: could not read the rehearsal counts out of the raised message.'); process.exit(1); }
if (/FAILED=\[none\]/.test(m[0])) { console.log('\nREHEARSAL PASSED — every Phase C invariant held inside the transaction.'); process.exit(0); }
console.error('\nREHEARSAL FAILED — invariants did not hold. Refusing the real deployment.');
process.exit(1);
