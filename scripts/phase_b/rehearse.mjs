// Rehearse the exact committed Phase B migration inside an ABORTED production transaction.
//
//   node scripts/phase_b/rehearse.mjs
//
// It concatenates the committed files in order, appends a block that reads the post-change
// counts and then RAISES, so the numbers come out and nothing commits.  A multi-statement file
// is one implicit transaction here, which is what makes that work.
//
// It then re-reads the production fingerprint and refuses to report success unless the
// fingerprint is byte-identical to the one taken before the rehearsal.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { REPO } from './lib/package.mjs';
import { sql } from './lib/db.mjs';

export const MIGRATION_FILES = [
  'phase_b_01_workflow_registry_schema.sql',
  'phase_b_02_identity_aliases.sql',
  'phase_b_03_registry_core.sql',
  'phase_b_04_steps.sql',
  'phase_b_05_handoffs_and_exceptions.sql',
  'phase_b_06_events.sql',
  'phase_b_07_crosswalk.sql',
  'phase_b_08_validators.sql',
];

const SQL_DIR = join(REPO, 'scripts', 'sql');
export const readMigration = f => readFileSync(join(SQL_DIR, f), 'utf8');
export const sha = s => createHash('sha256').update(s).digest('hex');

// The production fingerprint: what must be unchanged after an aborted rehearsal.
const FINGERPRINT_SQL = `
select
  (select count(*) from public.org_role)                                              as org_roles,
  (select count(*) from public.org_role_alias)                                        as org_role_aliases,
  (select count(*) from public.org_departments)                                       as org_departments,
  (select count(*) from public.org_workflow_ownership)                                as org_workflow_ownership,
  (select count(*) from public.fn_phase_a_baseline_drift())                           as phase_a_drift,
  (select count(*) from public.fn_phase_a_organization_violations())                  as phase_a_violations,
  (select count(*) from cron.job)                                                     as cron_jobs,
  (select count(*) from cron.job where active)                                        as cron_active,
  (select count(*) from public.llm_route_health where open_until > now())             as llm_routes_held,
  (select count(*) from information_schema.tables
     where table_schema='public' and table_name like 'phase\\_b\\_%')                  as phase_b_tables,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public')                                                        as public_functions,
  (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
     join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and not t.tgisinternal)                                 as public_triggers`;

async function fingerprint() {
  const r = (await sql(FINGERPRINT_SQL))[0];
  return { values: r, digest: sha(JSON.stringify(r)) };
}

if (import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/'))) {
  const before = await fingerprint();
  console.log('pre-rehearsal fingerprint:', JSON.stringify(before.values));
  console.log('digest:', before.digest);

  const body = MIGRATION_FILES.map(f => `\n-- ===== ${f} =====\n${readMigration(f)}`).join('\n');
  for (const f of MIGRATION_FILES) {
    console.log(`  ${f}  ${(readMigration(f).length / 1024).toFixed(0)} KB  sha256=${sha(readMigration(f)).slice(0, 16)}`);
  }
  console.log(`total ${(body.length / 1024).toFixed(0)} KB`);

  // Read the post-change counts, then raise so the whole implicit transaction rolls back.
  const abort = `
do $rehearsal$
declare
  v_workflows bigint; v_steps bigint; v_handoffs bigint; v_events bigint;
  v_crosswalk bigint; v_aliases bigint; v_inv_total bigint; v_inv_failed bigint;
  v_failed text;
begin
  select count(*) into v_workflows from public.phase_b_workflow;
  select count(*) into v_steps     from public.phase_b_workflow_step;
  select count(*) into v_handoffs  from public.phase_b_handoff;
  select count(*) into v_events    from public.phase_b_event;
  select count(*) into v_crosswalk from public.phase_b_crosswalk;
  select count(*) into v_aliases   from public.org_role_alias;
  select count(*), count(*) filter (where not ok) into v_inv_total, v_inv_failed
    from public.fn_phase_b_invariants();
  select coalesce(string_agg(check_name || '(' || actual || '!=' || expected || ')', '; '), 'none')
    into v_failed from public.fn_phase_b_invariants() where not ok;
  raise exception 'REHEARSAL workflows=% steps=% handoffs=% events=% crosswalk=% aliases=% invariants=%/% FAILED=[%]',
    v_workflows, v_steps, v_handoffs, v_events, v_crosswalk, v_aliases,
    v_inv_total - v_inv_failed, v_inv_total, v_failed;
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
  console.log('\n' + (m ? m[0] : message.slice(0, 3000)));

  const after = await fingerprint();
  console.log('\npost-rehearsal digest:', after.digest);
  if (after.digest !== before.digest) {
    console.error('FAIL: production fingerprint CHANGED across an aborted rehearsal.');
    console.error('before:', JSON.stringify(before.values));
    console.error('after: ', JSON.stringify(after.values));
    process.exit(1);
  }
  console.log('production fingerprint unchanged across the abort.');
  if (!m) { console.error('FAIL: could not read the rehearsal counts out of the raised message.'); process.exit(1); }
  if (/FAILED=\[none\]/.test(m[0])) { console.log('\nREHEARSAL PASSED — every invariant held inside the transaction.'); process.exit(0); }
  console.error('\nREHEARSAL FAILED — invariants did not hold. Refusing the real deployment.');
  process.exit(1);
}
